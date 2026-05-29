# UniCampus+ — Maquette vulnérable opérationnelle

Document de présentation synthétique du projet : architecture, services, vulnérabilités modélisées, et choix d'ingénierie. Sert de support de soutenance.

> Documents de référence approfondis : [architecture-technique.md](architecture-technique.md), [justification-choix-maquette.md](justification-choix-maquette.md), [mapping-analyse-risque.md](mapping-analyse-risque.md), [scenarios-attaque.md](scenarios-attaque.md).

---

## 1. Le projet en chiffres

| Indicateur | Valeur |
|---|---|
| VMs déployées | **11** (1 firewall + 1 VPN + 6 serveurs + 3 postes clients) |
| Réseaux Neutron | **2** (campus + DMZ) |
| Floating IPs publiques | **5** (toutes pointées sur fw-legacy) |
| Comptes Unix nominatifs | **6** (jdupont, lmartin, sleblanc, cfournier, dsi, pa1) |
| Vulnérabilités volontaires modélisées | **17** (cf. §5) |
| Scénarios opérationnels démontrables | **6 (SO1–SO6)** |
| Lignes de Terraform | ~600 |
| Scripts cloud-init | 11 (1 par VM) |
| Provider IaC | terraform-provider-openstack v3.4 |
| Backend state | GitLab managed HTTP backend |
| CI/CD | GitLab (`check → plan → apply` manuel) |

**Toute la stack est reproductible** : `terraform apply` reconstruit l'intégralité de la maquette en ~15 min, sans intervention manuelle, sur l'OpenStack mutualisé de l'école.

---

## 2. Architecture déployée

### 2.1 Topologie réseau

```
                          Internet
                              │
                         ext-net (provider)
                              │
                  ┌───────────┴──────────┐
                  │  Routeur Neutron     │
                  │     10.0.0.1         │
                  └───────────┬──────────┘
                              │   DMZ 10.0.0.0/24
                          5 FIPs publiques
                          attachées sur :
                              │
                  10.0.0.2 ─ fw-legacy DMZ ─ 10.0.0.3 .4 .5 .6
                       │
                  fw-legacy (Debian 10 EOL)
                       │ iptables DNAT vers VMs internes
                       │ iptables MASQUERADE egress
                       │ ip_forward=1
                       │
                  192.168.107.2 (gateway DHCP du subnet campus)
                       │
                  campus 192.168.107.0/24
                       │
   ┌──────┬───────┬────┴──────┬───────┬──────────┬────────┬──────┐
  .3     .10     .11         .12    .14         .15      .20    DHCP
  vpn  srv-mail srv-ldap  srv-moodle web-rh  calc-recherche db-rh postes
```

### 2.2 Caractéristiques clés

- **Subnet campus sans router_interface Neutron** : aucune Floating IP ne peut DNAT directement vers une VM interne. Seule sortie = fw-legacy.
- **fw-legacy périmétrique** : voit 100 % de l'egress des VMs (gateway DHCP `.2`) et 100 % de l'ingress des services exposés (DNAT depuis ses 5 IPs DMZ aliasées).
- **Pas de cloisonnement intra-campus** : toutes les VMs partagent le même subnet L2 (modélise "pas de segmentation interne", règle ANSSI 22 volontairement violée).
- **`port_security_enabled = false`** sur tous les ports campus + DMZ : OVS firewall désactivé côté OpenStack, pour que fw-legacy soit l'unique point de filtrage (et puisse réellement forwarder pour le compte d'autres VMs).

---

## 3. Conformité à l'énoncé

Chaque "faiblesse" listée dans [Enonce.md](Enonce.md) est concrètement matérialisée dans la maquette.

| Faiblesse énoncée | Matérialisation technique | Composant |
|---|---|---|
| "Pas de SSO, mots de passe multiples" | Bases auth séparées (Moodle DB, OpenLDAP, MariaDB RH, comptes Unix nominatifs) | tous serveurs |
| Dérive opérationnelle : même mdp partout | `jdupont/unicampus2024` accepté sur SSH + IMAP + Moodle + LDAP + Samba (cred reuse cross-services) | [_bootstrap.sh](../terraform/scripts/_bootstrap.sh) + scripts/vm |
| "WiFi étudiants connecté au réseau interne" | `uc-poste-etu` (DHCP) dans le même VLAN que les serveurs | [network.tf](../terraform/network.tf) |
| "Pédago + recherche dans le même VLAN" | Tous serveurs dans `192.168.107.0/24` | [network.tf](../terraform/network.tf) |
| "Firewall obsolète, règles incohérentes" | Debian 10 EOL + iptables `policy ACCEPT` + règle vestige `tcp dpt:8080` | [fw-legacy.sh](../terraform/scripts/fw-legacy.sh) |
| "Pas de supervision centralisée des logs" | Aucune VM rsyslog/ELK/SIEM, logs locaux uniquement | absence dans `instances.tf` |
| Règle ANSSI 7 (accès maîtrisé) | Floating IP RH exposée sans auth → SQLi sur Internet | [web-rh.sh](../terraform/scripts/web-rh.sh) |
| Règle ANSSI 8 (comptes nominatifs) | Compte `dsi` partagé sur 7 VMs avec NOPASSWD | scripts/srv-* + poste-dsi |
| Règle ANSSI 10 (politique mdp) | `unicampus2024`, `admin2024`, `recherche2024` (mots du dictionnaire + année) | tous scripts |
| Règle ANSSI 13 (auth forte) | PPTP MS-CHAP-v2 + MPPE-128 (RC4 déprécié), pas de MFA | [vpn-legacy.sh](../terraform/scripts/vpn-legacy.sh) |
| Règle ANSSI 25 (filtrage) | iptables `ACCEPT/ACCEPT/ACCEPT`, pas de SG OpenStack | [fw-legacy.sh](../terraform/scripts/fw-legacy.sh) |
| Règle ANSSI 31 (protocoles sécurisés) | HTTP en clair (Moodle + web-rh), SMTP/IMAP sans TLS, LDAP 389 plain | scripts services |

---

## 4. Catalogue des services

### 4.1 Synthèse — endpoints publics

| Service | Floating IP | Port | Auth | Vulns clés |
|---|---|---|---|---|
| **uc-fw-legacy** SSH admin | `137.194.211.13` | 22 | clé `uc-keypair-admin` | OS EOL |
| **uc-vpn-legacy** PPTP | `137.194.211.236` | TCP 1723 + GRE | `campus/unicampus2024` | MS-CHAP-v2, MPPE-128 (RC4), pas de MFA |
| **uc-srv-mail** SMTP/IMAP/POP3 | `137.194.210.120` | 25 / 143 / 110 | LOGIN/PLAIN sans TLS | relais ouvert (`mynetworks=0.0.0.0/0`), AUTH plain |
| **uc-srv-moodle** HTTP | `137.194.210.214` | 80 | `admin/Admin2024` | HTTP clair, pas de politique mdp |
| **uc-web-rh** HTTP | `137.194.210.76` | 80 | **aucune** | SQLi sur `?login=`, UPDATE direct salaire/RIB |

### 4.2 Synthèse — services internes (depuis le subnet campus)

| Service | IP | Port | Auth | Vulns clés |
|---|---|---|---|---|
| **uc-srv-ldap** | 192.168.107.11 | 389 | `cn=admin,dc=unicampus,dc=local / unicampus2024` | bind anonyme OK, pas de TLS, `userPassword` en clair |
| **uc-db-rh** | 192.168.107.20 | 3306 | `rhapp/rh2024` ou `root/root` | bind 0.0.0.0, hashs SHA1 sans sel |
| **uc-calc-recherche** NFS | 192.168.107.15 | 2049 | **aucune** | export `*`, `no_root_squash` |
| **uc-calc-recherche** Samba | 192.168.107.15 | 445 | invité OK | `[recherche] guest ok, force user=root` |
| **uc-calc-recherche** Jupyter | 192.168.107.15 | 8888 | **aucune** | `--NotebookApp.token=''`, exécution Python arbitraire |
| **uc-calc-recherche** PostgreSQL | 192.168.107.15 | 5432 | `recherche/recherche2024` | bind localhost (légère atténuation) |

### 4.3 Comment se servir des services

#### Moodle (depuis Internet)
```
URL    : http://137.194.210.214/login/
Login  : admin
Mdp    : Admin2024
```
Une fois logué : pas de politique de mot de passe, comptes potentiels via LDAP (à créer dans Moodle ou via API).

#### Portail RH (depuis Internet)
```
URL : http://137.194.210.76/
```
Aucune authentification. **PoC SQLi en une ligne** :
```bash
curl -G "http://137.194.210.76/" --data-urlencode "login=' OR '1'='1"
# Retourne 4 employés avec leurs RIBs et salaires
```

#### Mail (SMTP/IMAP)
```
Server : 137.194.210.120
Ports  : 25 (SMTP), 143 (IMAP plain), 110 (POP3)
Users  : jdupont/unicampus2024, lmartin/Printemps2024, sleblanc/recherche2024,
         cfournier/finance2024, dsi/admin2024
```

#### VPN PPTP
```
Serveur : 137.194.211.236 (PPTP)
Login   : campus
Mdp     : unicampus2024
```
> **Important** : PPTP nécessite que le GRE (protocole IP 47) passe. Si tu es derrière un VPN commercial type NordVPN, GRE est typiquement filtré → erreur 619/807. Sur le LAN/Wifi école, ça passe.

Une fois connecté, on récupère une IP `192.168.107.210-220` dans le subnet campus → accès direct aux services internes (LDAP, DB-RH, NFS, Samba, Jupyter…).

#### SSH admin (fw-legacy)
```bash
ssh debian@137.194.211.13   # clé uc-keypair-admin
```

#### SSH vers VMs internes (via ProxyJump)
```bash
ssh -J debian@137.194.211.13 ubuntu@192.168.107.12    # srv-moodle
ssh -J debian@137.194.211.13 ubuntu@192.168.107.20    # db-rh
# etc.
```

#### LDAP (depuis poste-etu après compromission initiale)
```bash
# Bind anonyme (autorisé par défaut)
ldapsearch -x -H ldap://192.168.107.11 -b 'dc=unicampus,dc=local'

# Bind admin (mot de passe connu)
ldapsearch -x -H ldap://192.168.107.11 \
  -D 'cn=admin,dc=unicampus,dc=local' -w unicampus2024 \
  -b 'dc=unicampus,dc=local' '(uid=*)'
```

#### NFS (depuis poste-etu)
```bash
showmount -e 192.168.107.15
sudo mount -t nfs 192.168.107.15:/srv/recherche /mnt
# no_root_squash → on lit/écrit en tant que root sur le serveur
```

#### Samba (depuis poste-etu)
```bash
# Anonyme
smbclient //192.168.107.15/recherche -N

# Authentifié (compte partenaire)
smbclient //192.168.107.15/partenaires -U pa1%partenaire2024
```

#### Jupyter (depuis poste-etu)
```
URL : http://192.168.107.15:8888/
```
Aucun token, aucun password → terminal Python distant, exécution de code arbitraire sur le serveur recherche.

---

## 5. Vulnérabilités volontaires modélisées

Synthèse des 17 anti-patterns implémentés (détails dans [architecture-technique.md §6](architecture-technique.md)).

### Réseau / infrastructure (5)
1. Pas de cloisonnement intra-campus (un seul subnet pour tous les serveurs et postes)
2. Wifi étudiants (poste-etu) dans le même VLAN que les serveurs sensibles
3. Firewall obsolète Debian 10 EOL avec `policy ACCEPT` partout
4. Règle iptables résiduelle `tcp dpt:8080` sans justification (vestige conf historique)
5. Pas de logging centralisé

### Authentification / IAM (4)
6. Pas de SSO (chaque service gère ses propres comptes)
7. Dérive opérationnelle : même mot de passe par utilisateur sur tous les services (cred reuse)
8. Compte d'urgence `dsi/admin2024` partagé entre admins, NOPASSWD sudo sur 7 VMs
9. Politique de mot de passe inexistante (mots du dictionnaire + année)

### Services exposés (5)
10. Floating IP web-rh exposée sur Internet (appli RH interne sur le web public)
11. Moodle en HTTP clair, sans politique mdp côté admin
12. Postfix relais ouvert (`mynetworks=0.0.0.0/0`)
13. Dovecot IMAP `AUTH=PLAIN LOGIN` sans TLS
14. PPTP : MS-CHAP-v2 + MPPE-128 (RC4 déprécié), pas de MFA

### Code applicatif (3)
15. **SQLi** dans `web-rh/index.php` sur le paramètre `login` (concaténation directe)
16. **Modification sans auth** sur web-rh : `UPDATE employes SET salaire=…, rib=…` accessible à tous
17. Hashs `SHA1` sans sel dans `db-rh.employes.password_sha1`

### Données / leurres
- LDAP : entrées `userPassword: unicampus2024` en clair
- srv-mail : mail DSI "à tout le personnel" leakant `dsi/admin2024` dans la Maildir de jdupont
- poste-dsi : `/home/dsi/credentials-admin.txt` en clair listant tous les creds admin
- poste-prof : `/home/ubuntu/identifiants.txt` (anti-pattern "mémo perso")
- calc-recherche : PDF "résultats expérimentaux confidentiels" accessibles sans auth

---

## 6. Démonstration des SO (scénarios opérationnels)

Tous les **6 scénarios opérationnels** retenus dans l'analyse EBIOS RM sont **techniquement démontrables** sur la maquette. Détails pas-à-pas dans [scenarios-attaque.md](scenarios-attaque.md).

| # | Source de risque (SR) | Chemin technique | Démo rapide |
|---|---|---|---|
| SO1 | Étudiant frustré → DoS plateforme pédagogique | nmap depuis poste-etu → Moodle → SYN flood ou auth brute force | `hydra -L users -P pass moodle login` |
| SO2 | Étudiant → vol sujet d'examen | SSH cred reuse jdupont → srv-moodle → `find /var/moodledata -name "sujet*"` ou DB Moodle | `mysql -u moodle moodle -e 'SELECT * FROM mdl_files'` |
| SO3 | Cybercriminel ext → exfil RH + chantage | Port scan Internet → web-rh SQLi → exfil base employés → modif RIB (SO5 chaining) | `curl -G ".../?login=' OR 1=1"` |
| SO4 | Acteur étatique → exfil données recherche | Phishing PA1 → Samba `[partenaires]` (creds pa1/partenaire2024) → exfil `/srv/recherche` | `smbclient -U pa1%partenaire2024` |
| SO5 | Cybercriminel → détournement RIB versements | Suite SO3 : UPDATE direct salaire/RIB sans auth | formulaire POST `/` |
| SO6 | Atteinte image / vandalisme Moodle | SSH cred reuse → admin Moodle → modif site, suppression cours | login web `admin/Admin2024` |

**Chaîne d'attaque centrale** (commune à SO1/SO2/SO3) :

```
poste-etu (attaquant) 
   └─> nmap 192.168.107.0/24
       └─> SSH 192.168.107.12 jdupont/unicampus2024  ← cred reuse
           └─> sudo (mot de passe inconnu, mais...)
               └─> /home/jdupont/Maildir/cur/*.mail  ← leurre DSI
                   └─> dsi/admin2024 récupéré
                       └─> SSH n'importe quelle VM → root NOPASSWD
                           └─> compromission complète
```

---

## 7. Réalisations techniques notables

### 7.1 Infrastructure as Code intégrale

Aucune action manuelle requise pour reconstruire la maquette. Tout est dans le repo :
- `terraform/*.tf` (réseau, ports, instances, FIPs, keypair, cloudinit)
- `terraform/scripts/<vm>.sh` (un script par VM, isolé)
- `assets/<vm>/*.pdf` (leurres déposés via cloud-init)
- `.gitlab-ci.yml` (`check → plan → apply` manuel)
- State managé GitLab HTTP backend (verrouillage natif, multi-utilisateurs)

### 7.2 Topologie périmétrique vraie (DMZ + campus)

Architecture rare sur Neutron, choisie pour fidélité au narratif "pare-feu obsolète périmétrique" :
- Routeur Neutron sur la **DMZ uniquement** (pas d'interface campus)
- 5 Floating IPs publiques toutes attachées au **même port DMZ** de fw-legacy (multi `fixed_ip` + association via `fixed_ip` field)
- fw-legacy fait du **vrai DNAT iptables** (control + GRE pour PPTP) vers les IPs internes
- Egress des VMs internes obligatoirement via fw-legacy (gateway DHCP forcée à `.2`)

### 7.3 Bypass intelligent des bugs cloud-init

Découvert au déploiement : cloud-init (sur Debian 10 ET Ubuntu 24.04) plante silencieusement sur le multipart MIME généré par le data source Terraform `cloudinit_config` (`ShellScriptPartHandler: Failed calling handler`). Conséquence : aucun script n'était exécuté, les VMs bootaient vanilla.

**Solution adoptée** : on bypass entièrement le multipart, on assemble un **shellscript bash brut** combinant (1) assets base64 (2) bootstrap commun (3) script setup, et on l'envoie en `user_data`. Cloud-init détecte le shebang `#!/bin/bash` et exécute directement. Plus aucun problème. Cf. [cloudinit.tf](../terraform/cloudinit.tf).

### 7.4 OVS firewall : contournement nécessaire pour faire de la VM-routeur

Découverte clé du projet : Neutron OVS firewall avec `port_security_enabled=True` drop les paquets dont la destination IP ne matche pas le port, **avant même que netfilter ne les voie** dans la VM. C'est ce qui empêchait fw-legacy de forwarder pour le compte des autres VMs.

**Solution** : `port_security_enabled = false` sur tous les ports campus + DMZ, défini à la fois au niveau réseau (défaut pour les ports DHCP auto-créés) et au niveau port (override explicite). Documenté dans [network.tf](../terraform/network.tf) avec commentaire détaillé pour expliquer pourquoi.

### 7.5 Injection dynamique des FIPs dans le provisioning

Les Floating IPs sont auto-attribuées par Neutron au `terraform apply` — leur valeur n'est connue qu'à ce moment-là. Pour que Moodle se configure avec son URL externe correcte (sinon redirige les visiteurs vers son IP interne inaccessible), on injecte les FIPs comme variables d'environnement au début du `user_data` :

```hcl
fip_exports = join("\n", [
  for k, v in openstack_networking_floatingip_v2.public :
  "export FIP_${replace(upper(k), "-", "_")}=\"${v.address}\""
])
```

Les scripts cloud-init peuvent ensuite référencer `${FIP_SRV_MOODLE}`, `${FIP_WEB_RH}`, etc.

### 7.6 Résolution du conflit slapd

Sur les installs récentes, `dpkg-reconfigure -f noninteractive slapd` ignore le preseed du mot de passe admin → mot de passe aléatoire généré au premier install → `ldapadd` planait avec `Invalid credentials`. La base restait vide. Fix : on force le `olcRootPW` via `ldapmodify EXTERNAL` sur `slapd-config` après l'install. Reproductible.

### 7.7 Jupyter dans un venv pour éviter le conflit pip / PEP 668

Sur Ubuntu 24.04, `pip3 install notebook` plante (PEP 668 + conflit `traitlets` apt sans `RECORD`). On installe dans un venv isolé `/opt/jupyter-venv/`, le systemd unit pointe dessus. Aucun conflit avec les paquets système.

---

## 8. Limitations connues et choix assumés

### Volontaires (modélisent l'énoncé)
- VM ↔ VM intra-campus en L2 direct, contournant fw-legacy → modélise l'absence de cloisonnement réseau interne
- Pas de TLS sur LDAP / HTTP / IMAP / SMTP → modélise "protocoles non sécurisés"
- Compte `dsi` partagé sur 7 VMs → modélise le "compte d'urgence" anti-pattern

### Techniques (contournements OpenStack)
- `port_security_enabled = false` partout : nécessaire pour que fw-legacy puisse forwarder (cf. §7.4). Side-effect : un attaquant pourrait spoofer MAC/IP côté Neutron — mais c'est cohérent avec le narratif "pas de sécurité OpenStack-level".
- Le SG `uc-sg-allow-all` est gardé défini en Terraform sans être attaché à nos ports : un autre groupe du projet partagé (artvisio) y a attaché 2 de ses ports → Neutron refuse de le détruire → on le préserve dans la conf pour ne pas casser leur travail.

### Hors-périmètre
- PPTP non testable depuis l'extérieur derrière un VPN commercial (GRE filtré par NordVPN, etc.) → testable depuis le LAN école ou un poste interne (validé).
- Pas de simulation Wifi : `uc-poste-etu` représente le réseau Wifi étudiant en L2-équivalence.
- Pas de SIEM/SOC simulé : conforme à l'énoncé "pas de supervision centralisée".

---

## 9. Pour rejouer la démo en partant de zéro

```bash
# 1. Cloner
git clone <repo>
cd Projet/terraform

# 2. Sourcer les credentials OpenStack (application credential école)
source ../app-cred-gitlab-ci-unicampus-openrc.sh   # avec les secrets

# 3. Apply (déploiement complet ~15 min)
terraform init
terraform plan
terraform apply

# 4. Récupérer les FIPs
openstack floating ip list -c "Floating IP Address" -c Description

# 5. Vérifier que tout est UP
curl -I http://<FIP_moodle>/login/   # Moodle
curl -I http://<FIP_webrh>/          # web-rh
nc -zv <FIP_mail> 25                 # SMTP
# etc.
```

Le pipeline GitLab CI/CD est la voie alternative : `Pipelines → Run → bouton ▶️ sur le job manuel `terraform_apply`. Le state distant est managé, deux développeurs peuvent travailler en parallèle.

---

## 10. Synthèse

**Ce que la maquette démontre concrètement** :
- Un SI dégradé conforme à l'énoncé, où **chaque faiblesse de l'analyse de risque est matérialisée techniquement et exploitable**
- Une chaîne d'attaque centrale (cred reuse + absence de SSO + absence de cloisonnement) qui traverse 6 services en cascade
- Les 6 SOs de l'analyse EBIOS RM, tous démontrables et rejouables en quelques commandes

**Ce que le déploiement démontre opérationnellement** :
- Une infrastructure 100 % code, reproductible en 15 min sur OpenStack mutualisé
- Une topologie périmétrique réelle (DMZ + campus) avec DNAT inline sur fw-legacy
- Un débuggage approfondi des spécificités OpenStack Neutron (OVS firewall, multi-FIP, port_security)
- 6 patches de correction (cloud-init, slapd, jupyter, Moodle, fw-legacy, OVS) tous tracés en commits et documentés

La maquette est **prête à être présentée et démontrée**.
