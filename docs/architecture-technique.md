# Architecture technique — maquette UniCampus+ v1

Document de référence décrivant **exhaustivement** la maquette telle qu'elle est
déployée par Terraform (`terraform/`). Sert de support à la traçabilité avec
l'analyse de risque (cf. [mapping-analyse-risque.md](mapping-analyse-risque.md))
et de référence pour la démonstration des attaques
(cf. [scenarios-attaque.md](scenarios-attaque.md)).

> ⚠️ Cette maquette est **volontairement vulnérable**. Toutes les "anomalies"
> décrites ici (mots de passe faibles, comptes partagés, services en clair,
> partages ouverts) sont **intentionnelles** et reproduisent fidèlement les
> faiblesses listées dans l'énoncé. Voir [justification-choix-maquette.md](justification-choix-maquette.md).

---

## 1. Vue d'ensemble

11 instances déployées sur OpenStack, toutes dans le même réseau privé
`uc-net-campus` (192.168.107.0/24), reproduisant l'absence de segmentation
réseau décrite par l'énoncé.

| Élément | Valeur |
|---|---|
| Plateforme | OpenStack mutualisé (Télécom Paris) |
| Orchestration | Terraform (provider `terraform-provider-openstack`) |
| Backend Terraform | HTTP managé GitLab (state name `default`) |
| Pipeline | `.gitlab-ci.yml` (check → plan → apply manuel) |
| Préfixe ressources | `uc-` |
| CIDR interne | 192.168.107.0/24 |
| Réseau externe | `provider` (variable `external_network_name`) |
| Nombre de VMs | 11 (1 firewall + 1 VPN + 6 serveurs + 3 postes) |
| Floating IPs | 5 (fw, vpn, mail, moodle, web-rh) |
| Security groups | 1 (`uc-sg-allow-all`) |

## 2. Réseau et exposition externe

### 2.1 Sous-réseau interne

| Élément | Valeur | Code Terraform |
|---|---|---|
| Network Neutron | `uc-net-campus` | [network.tf:20-23](../terraform/network.tf#L20-L23) |
| Subnet CIDR | `192.168.107.0/24` | [network.tf:25-40](../terraform/network.tf#L25-L40) |
| Gateway | `192.168.107.1` | calculé via `cidrhost(cidr, 1)` |
| Pool DHCP | `192.168.107.100–200` | calculé via `cidrhost` |
| DNS forwarders | `8.8.8.8`, `1.1.1.1` | [network.tf:39](../terraform/network.tf#L39) |
| Routeur | `uc-router-campus` (attaché au `provider`) | [network.tf:42-51](../terraform/network.tf#L42-L51) |

### 2.2 Plan d'adressage IP fixe

| Plage | Usage |
|---|---|
| .1 | Gateway Neutron |
| .2 – .9 | Infrastructure réseau (firewall, VPN) |
| .10 – .19 | Serveurs applicatifs |
| .20 – .29 | Serveurs back-end (bases) |
| .100 – .200 | Pool DHCP (postes clients) |

### 2.3 Security group

Une seule politique `uc-sg-allow-all` appliquée à toutes les interfaces — la
maquette **n'utilise pas** OpenStack pour filtrer les flux (modélise l'absence
de pare-feu interne, cf. énoncé "firewall obsolète, règles incohérentes").

| Direction | Protocole | Ports | Source/Dest |
|---|---|---|---|
| ingress | TCP | 1-65535 | 0.0.0.0/0 |
| ingress | UDP | 1-65535 | 0.0.0.0/0 |
| ingress | ICMP | — | 0.0.0.0/0 |
| egress  | tout | — | 0.0.0.0/0 |

Cf. [security.tf](../terraform/security.tf).

### 2.4 Floating IPs (exposition externe)

5 VMs sont accessibles depuis Internet via floating IP du pool `provider`
([floating_ips.tf:13](../terraform/floating_ips.tf#L13)) :

| VM | Floating | Services exposés | Pourquoi exposé |
|---|---|---|---|
| `uc-fw-legacy` | oui | SSH 22 | Administration "legacy" |
| `uc-vpn-legacy` | oui | PPTP 1723/tcp + GRE 47 | Accès distant utilisateurs |
| `uc-srv-mail` | oui | SMTP 25, IMAP 143, POP3 110 | Messagerie institutionnelle |
| `uc-srv-moodle` | oui | HTTP 80 | Plateforme pédagogique publique |
| `uc-web-rh` | oui | HTTP 80 | **Vulnérabilité** : une appli RH interne ne devrait pas être sur Internet — nécessaire pour démontrer SO3 |

## 3. Inventaire des VMs

### 3.1 VMs à IP fixe

| Code Terraform | Hostname | IP fixe | Flavor | Image | Rôle |
|---|---|---|---|---|---|
| `fw-legacy` | `uc-fw-legacy` | .2 | m1.tiny | Debian 10 | Pare-feu legacy |
| `vpn-legacy` | `uc-vpn-legacy` | .3 | m1.tiny | Ubuntu 22.04 | Concentrateur PPTP |
| `srv-mail` | `uc-srv-mail` | .10 | m1.tiny | Ubuntu 22.04 | Postfix + Dovecot |
| `srv-ldap` | `uc-srv-ldap` | .11 | m1.tiny | Ubuntu 22.04 | OpenLDAP (slapd) |
| `srv-moodle` | `uc-srv-moodle` | .12 | m1.small | Ubuntu 22.04 | Moodle (Apache+PHP+MariaDB) |
| `web-rh` | `uc-web-rh` | .14 | m1.tiny | Ubuntu 22.04 | Portail RH (Apache+PHP) |
| `calc-recherche` | `uc-calc-recherche` | .15 | m1.small | Ubuntu 22.04 | NFS+Samba+Jupyter+PostgreSQL |
| `db-rh` | `uc-db-rh` | .20 | m1.tiny | Ubuntu 22.04 | MariaDB RH |

### 3.2 VMs DHCP

| Code Terraform | Hostname | IP | Image | Rôle |
|---|---|---|---|---|
| `poste-etu` | `uc-poste-etu` | DHCP | Ubuntu 22.04 | Poste étudiant / attaquant |
| `poste-prof` | `uc-poste-prof` | DHCP | Ubuntu 22.04 | Poste enseignant-chercheur |
| `poste-dsi` | `uc-poste-dsi` | DHCP | Ubuntu 22.04 | Poste DSI / admin |

Note : l'énoncé décrit aussi des postes administratifs et un poste recherche
distinct. La maquette **fusionne** :
- `poste-admin` ⊂ `poste-dsi` (rôles administration + DSI cumulés)
- `poste-rech` ⊂ `poste-prof` (rôle enseignant-chercheur, mêmes creds)

### 3.3 Allocation des ressources

| Flavor | Spécif. | VMs |
|---|---|---|
| m1.tiny | 1 vCPU / 1 Go RAM / 10 Go disque | 9 |
| m1.small | 1 vCPU / 2 Go RAM / 20 Go disque | 2 |
| **Total** | **11 vCPU / 13 Go RAM / 130 Go disque** | 11 |

## 4. Provisioning (cloud-init multipart)

Chaque VM reçoit, au premier boot, un `user_data` multipart construit par
[cloudinit.tf](../terraform/cloudinit.tf) :

1. **Assets (si applicable)** — dépôt des PDF leurres de `assets/<vm>/` dans
   `/opt/loot/` via cloud-config `write_files` base64 (pas de dépendance réseau).
2. **Bootstrap commun** ([_bootstrap.sh](../terraform/scripts/_bootstrap.sh)) —
   active `PasswordAuthentication yes` dans `sshd_config.d/`. Skippé pour
   `fw-legacy` (Debian 10, géré par son propre script).
3. **Script spécifique** ([scripts/<vm>.sh](../terraform/scripts/)) — installe
   et configure les services, crée les comptes Unix, dépose les leurres texte.

## 5. Comptes Unix locaux — le mécanisme central de latéralisation

**Principe directeur** : l'énoncé décrit *« pas de SSO, mots de passe
multiples »*. Plutôt qu'un mot de passe différent par service, la maquette
modélise la dérive **inverse mais équivalente** documentée par l'ANSSI :
**les utilisateurs utilisent le même mot de passe sur tous les services**.
Conséquence opérationnelle : un mot de passe compromis sur n'importe quel
service ouvre l'accès à tous les autres.

Combiné à l'absence de cloisonnement réseau (un seul VLAN) et à
`PasswordAuthentication=yes` sur tous les serveurs ([_bootstrap.sh](../terraform/scripts/_bootstrap.sh)),
ce choix rend la **latéralisation SSH par réutilisation de credentials**
triviale et démontrable, ce qui est la chaîne d'attaque centrale de la
plupart des scénarios opérationnels.

### 5.1 Matrice utilisateurs × VMs

| Utilisateur | Mot de passe | Rôle métier | VMs où le compte existe |
|---|---|---|---|
| `jdupont` | `unicampus2024` | Enseignant-chercheur | srv-mail, srv-moodle, srv-ldap, calc-recherche, poste-prof |
| `lmartin` | `Printemps2024` | Étudiante | srv-mail, srv-moodle, srv-ldap |
| `sleblanc` | `recherche2024` | Chercheuse | srv-mail, calc-recherche |
| `cfournier` | `finance2024` | VP Finances | srv-mail, web-rh |
| `dsi` | `admin2024` | Compte admin "de secours" partagé par la DSI | srv-mail, srv-ldap, srv-moodle, web-rh, db-rh, calc-recherche, poste-dsi |
| `pa1` | `partenaire2024` | Compte applicatif partenaire (PA1) | calc-recherche (SSH + Samba) |
| `ubuntu` | (clé SSH) | Compte cloud-init par défaut | toutes les VMs Ubuntu |

### 5.2 Privilèges

- `ubuntu` : sudo NOPASSWD sur **toutes** les VMs Ubuntu (default cloud-init,
  `/etc/sudoers.d/90-cloud-init-users`).
- `dsi` : sudo NOPASSWD sur **toutes** les VMs où il existe
  (`/etc/sudoers.d/91-uc-dsi`).
- `ubuntu` sur `poste-dsi` : sudoers explicite supplémentaire
  (`/etc/sudoers.d/90-uc-nopasswd`).
- Autres comptes : aucun privilège élevé (utilisateurs standards).

### 5.3 Leurres "credentials en clair"

| Localisation | Contenu | Modélise |
|---|---|---|
| `srv-mail:/home/jdupont/Maildir/cur/1700000000.uc.mail:2,S` | Email DSI diffusé "à tout le personnel" avec `dsi/admin2024` et la liste des serveurs concernés | DSI distribuant un compte d'urgence par mail |
| `srv-mail:/home/jdupont/email_dsi_acces_vpn_CONFIDENTIEL.pdf` | Email DSI contenant les creds VPN `campus/unicampus2024` (PDF leurre) | Distribution insouciante de creds VPN |
| `poste-dsi:/home/dsi/credentials-admin.txt` | Compte dsi, VPN, root MariaDB, admin LDAP en clair | DSI conservant ses creds en clair sur son poste |
| `poste-dsi:/home/ubuntu/Documents/export_annuaire_ldap_unicampus_CONFIDENTIEL.pdf` | Export annuaire | Exfiltration possible si poste compromis |
| `poste-prof:/home/ubuntu/identifiants.txt` | Identifiants jdupont sur tous les services + connexions SSH | Anti-pattern "mémo perso" |

## 6. Détail des services par VM

### 6.1 `uc-fw-legacy` (.2) — Pare-feu Debian 10

[scripts/fw-legacy.sh](../terraform/scripts/fw-legacy.sh)

- `net.ipv4.ip_forward=1` (routage activé)
- iptables : `INPUT/FORWARD/OUTPUT ACCEPT`, toutes les tables vidées
- Règle résiduelle : `INPUT -p tcp --dport 8080 -j ACCEPT` (vestige d'un projet)
- Floating IP : SSH 22 admin (clé `uc-keypair-admin`)
- `iptables-persistent` pour la persistance au reboot
- **Pas de bootstrap SSH-password** : géré séparément (Debian 10)

### 6.2 `uc-vpn-legacy` (.3) — VPN PPTP

[scripts/vpn-legacy.sh](../terraform/scripts/vpn-legacy.sh)

- `pptpd` : `localip 192.168.107.3`, `remoteip 192.168.107.210-220`
- `pptpd-options` : MS-CHAP-v2 obligatoire, MPPE-128 (RC4 déprécié), pas de MFA
- `chap-secrets` : un seul compte partagé `campus / unicampus2024 / *`
- Floating IP : PPTP 1723/tcp + GRE proto 47
- Pas de comptes Unix nominatifs (les utilisateurs VPN sont CHAP, pas SSH)

### 6.3 `uc-srv-mail` (.10) — Messagerie Postfix/Dovecot

[scripts/srv-mail.sh](../terraform/scripts/srv-mail.sh)

- Postfix : `inet_interfaces=all`, `mynetworks=0.0.0.0/0` (**relais ouvert**),
  `smtpd_tls_security_level=none`, Maildir
- Dovecot : `disable_plaintext_auth=no`, `auth_mechanisms=plain login`, `ssl=no`
- Comptes Unix créés : `jdupont`, `lmartin`, `sleblanc`, `cfournier`, `dsi` (NOPASSWD)
- Floating IP : SMTP 25, IMAP 143, POP3 110
- Leurres :
  - PDF email VPN (`email_dsi_acces_vpn_CONFIDENTIEL.pdf`) dans `/home/jdupont/`
  - Mail texte DSI dans la Maildir de jdupont (compte `dsi/admin2024` partagé)

### 6.4 `uc-srv-ldap` (.11) — OpenLDAP

[scripts/srv-ldap.sh](../terraform/scripts/srv-ldap.sh)

- `slapd` : suffix `dc=unicampus,dc=local`, écoute `ldap:///` (port 389 en clair, pas de TLS)
- Mot de passe admin : `cn=admin,dc=unicampus,dc=local / unicampus2024`
- **Bind anonyme autorisé** par défaut (pas d'ACL custom)
- Entrées peuplées : OUs `people` + `groups`, comptes `lmartin` / `jdupont`
  avec `userPassword: unicampus2024`
- Comptes Unix créés : `dsi` (NOPASSWD)

### 6.5 `uc-srv-moodle` (.12) — Moodle

[scripts/srv-moodle.sh](../terraform/scripts/srv-moodle.sh)

- Apache + PHP 8 + MariaDB locale (bind `127.0.0.1`)
- Moodle branch `MOODLE_404_STABLE` cloné depuis GitHub
- Compte admin Moodle : `admin / Admin2024` (pas de politique de mdp)
- Base `moodle` / user MariaDB `moodle/unicampus2024` (localhost only)
- Docs leurres copiés dans `/var/www/html/moodle/uc-docs/`
- `chmod 0777` sur `/var/moodledata` (permissif volontaire)
- HTTP en clair (pas de TLS)
- Floating IP : HTTP 80
- Comptes Unix créés : `jdupont`, `lmartin`, `dsi` (NOPASSWD)

### 6.6 `uc-web-rh` (.14) — Portail RH

[scripts/web-rh.sh](../terraform/scripts/web-rh.sh)

- Apache + PHP, **aucune authentification** (un seul rôle implicite)
- Page unique `index.php` :
  - Connexion à `uc-db-rh` via mysqli (creds `rhapp/rh2024` en dur dans le code)
  - **Formulaire de recherche** : SQLi sur le paramètre `login` (concaténation,
    cf. SO3)
  - **Formulaire de modification** (sans auth, sans validation, sans audit) :
    `UPDATE employes SET salaire=..., rib=... WHERE login=...` → SO5
- Floating IP : HTTP 80 (exposition externe → SO3)
- Comptes Unix créés : `cfournier`, `dsi` (NOPASSWD)
- Docs RH leurres dans `/var/www/html/rh-docs/`

### 6.7 `uc-db-rh` (.20) — Base RH MariaDB

[scripts/db-rh.sh](../terraform/scripts/db-rh.sh)

- MariaDB : `bind-address = 0.0.0.0` (écoute sur toutes les interfaces)
- Comptes MariaDB :
  - `rhapp@'%' / rh2024` (GRANT ALL sur `rh.*`)
  - `root@'%' / root` (GRANT ALL ON \*.\* WITH GRANT OPTION)
- Table `employes` (id, login, nom, poste, salaire, **rib**, password_sha1) :
  - `jdupont` (3200 €, RIB IBAN FR fictif)
  - `lmartin` (étudiante, 0 €)
  - `cfournier` (5400 €, VP Finances)
  - `sleblanc` (3800 €, Chercheuse)
- Hashs `SHA1` sans sel (cassables instantanément avec hashcat / rainbow tables)
- Comptes Unix créés : `dsi` (NOPASSWD)

### 6.8 `uc-calc-recherche` (.15) — Calcul recherche

[scripts/calc-recherche.sh](../terraform/scripts/calc-recherche.sh)

- **NFS** : export `/srv/recherche *(rw,sync,no_root_squash,no_subtree_check)`
  → accessible **sans authentification**, **root remote** autorisé
- **Samba** :
  - Partage `[recherche]` : `guest ok = yes`, `force user = root`
  - Partage `[partenaires]` : `valid users = pa1, sleblanc, jdupont`,
    authentification par mot de passe (creds réutilisés)
- **Jupyter** : service systemd, écoute `0.0.0.0:8888`, `--NotebookApp.token=''`
  (pas de token, pas de password)
- **PostgreSQL** : base `lrid_results`, user `recherche / recherche2024`
  (bind localhost par défaut)
- Comptes Unix créés : `jdupont`, `sleblanc`, `dsi` (NOPASSWD), `pa1` (partenaire),
  `recherche` (compte d'exécution Jupyter)
- Données leurres : PDF recherche dans `/srv/recherche/`

### 6.9 `uc-poste-dsi` (DHCP) — Poste admin DSI

[scripts/poste-dsi.sh](../terraform/scripts/poste-dsi.sh)

- Outils : `openssh-client`, `nfs-common`, `smbclient`
- `/etc/sudoers.d/90-uc-nopasswd` : `ubuntu ALL=(ALL) NOPASSWD:ALL`
- `/etc/sudoers.d/91-uc-dsi` : `dsi ALL=(ALL) NOPASSWD:ALL`
- Compte Unix créé : `dsi / admin2024`
- Leurres : documents administratifs PDF (budget, délibération, export LDAP)
  dans `/home/ubuntu/Documents/` et `/home/dsi/Documents/`
- **Fichier `/home/dsi/credentials-admin.txt`** en clair (anti-pattern volontaire) :
  liste l'ensemble des credentials administratifs (dsi, VPN, root MariaDB, admin LDAP)
- Note `/home/ubuntu/NOTE-cle-admin.txt` : la maquette utilise désormais la
  latéralisation par credentials (compte `dsi`), le dépôt d'une clé SSH
  privée n'est plus requis

### 6.10 `uc-poste-etu` (DHCP) — Poste étudiant / attaquant

[scripts/poste-etu.sh](../terraform/scripts/poste-etu.sh)

- Outils offensifs : `nmap`, `netcat-openbsd`, `hydra`, `nfs-common`, `smbclient`,
  `ldap-utils`, `curl`, `python3`, `git`
- README dans `/home/ubuntu/`
- **Pas de compte nominatif** (c'est la machine attaquante)

### 6.11 `uc-poste-prof` (DHCP) — Poste enseignant-chercheur

[scripts/poste-prof.sh](../terraform/scripts/poste-prof.sh)

- Outils : `nfs-common`, `smbclient`, `firefox`
- Fichier `/home/ubuntu/identifiants.txt` : tous les creds jdupont
  (Moodle, Mail, LDAP, Samba, Jupyter, SSH)
- Compte Unix créé : `jdupont / unicampus2024`

## 7. Authentification — récapitulatif des credentials

| Service | Endpoint | Credentials | Source |
|---|---|---|---|
| SSH (tous serveurs) | port 22 | `ubuntu` (clé) + comptes nominatifs (mot de passe) | cloud-init + `_bootstrap.sh` |
| Moodle web | http://192.168.107.12 | `admin/Admin2024`, comptes utilisateurs (à créer dans Moodle) | srv-moodle.sh |
| Moodle DB | localhost:3306 | `moodle/unicampus2024` | srv-moodle.sh |
| LDAP | ldap://192.168.107.11 | bind anonyme OK, `cn=admin/unicampus2024`, `uid=jdupont/unicampus2024`, `uid=lmartin/unicampus2024` | srv-ldap.sh |
| MariaDB RH | 192.168.107.20:3306 | `rhapp/rh2024`, `root/root` | db-rh.sh |
| Web RH | http://\<floating\>/ | aucune authentification | web-rh.sh |
| SMTP/IMAP | 192.168.107.10 | `jdupont/unicampus2024`, `lmartin/Printemps2024`, `sleblanc/recherche2024`, `cfournier/finance2024`, `dsi/admin2024` | srv-mail.sh |
| VPN PPTP | \<floating-vpn\>:1723 | `campus/unicampus2024` | vpn-legacy.sh |
| Samba [recherche] | //192.168.107.15/recherche | guest | calc-recherche.sh |
| Samba [partenaires] | //192.168.107.15/partenaires | `pa1/partenaire2024`, `sleblanc/recherche2024`, `jdupont/unicampus2024` | calc-recherche.sh |
| NFS recherche | 192.168.107.15:/srv/recherche | aucune (export `*`) | calc-recherche.sh |
| Jupyter | http://192.168.107.15:8888 | aucune (token vide) | calc-recherche.sh |
| PostgreSQL recherche | 127.0.0.1:5432 | `recherche/recherche2024` | calc-recherche.sh |

## 8. Logging

| Composant | Cible | Centralisation |
|---|---|---|
| Tous services | `/var/log/` local de chaque VM | aucune |
| `uc-fw-legacy` | `/var/log/syslog` local | aucune |
| `uc-vpn-legacy` | `/var/log/syslog` local | aucune |
| Bases de données | logs locaux MariaDB / PostgreSQL | aucune |

Aucun rsyslog forwarder, aucun agent Wazuh / Filebeat / Fluentd. C'est la
modélisation littérale de l'énoncé "Pas de supervision centralisée des logs".

## 9. Conformité avec l'énoncé

Mapping des faiblesses listées dans l'énoncé → modélisation dans la maquette :

| Faiblesse énoncée | Modélisation dans la maquette |
|---|---|
| "Multiplicité de services non intégrés : pas de SSO" | Bases de comptes locales (Moodle DB, LDAP, MariaDB RH, comptes Unix), credentials hétérogènes par nature |
| "Mots de passe multiples" → réutilisation | Mêmes mots de passe sur SSH/IMAP/Moodle/LDAP par utilisateur, compte `dsi/admin2024` partout |
| "WiFi étudiants connecté au réseau interne" | Postes étudiants dans le même VLAN `uc-net-campus` que les serveurs |
| "Serveurs pédago + recherche dans le même VLAN" | Tous les serveurs dans `192.168.107.0/24`, security group "allow all" |
| "Firewall obsolète, règles incohérentes" | Debian 10 + iptables `ACCEPT` + règle 8080 résiduelle (cf. §6.1) |
| "Pas de supervision centralisée des logs" | Aucune VM de log (rsyslog/ELK/SIEM), logs locaux uniquement |

## 10. Évolutions par rapport à la version initiale

Cette version intègre les modifications suivantes pour rendre tous les SOs
techniquement démontrables :

| # | Changement | Raison | Fichier |
|---|---|---|---|
| 1 | Activation de `PasswordAuthentication yes` sur tous les serveurs Ubuntu | Permettre la latéralisation SSH par cred reuse | [_bootstrap.sh](../terraform/scripts/_bootstrap.sh) |
| 2 | Comptes Unix nominatifs (`jdupont`, `lmartin`, `sleblanc`, `cfournier`) sur les serveurs où l'utilisateur a une activité métier | Modéliser le cred reuse cross-services | scripts/srv-*, scripts/web-rh, scripts/calc-recherche, scripts/poste-prof |
| 3 | Compte `dsi/admin2024` (sudo NOPASSWD) sur tous les serveurs Ubuntu | Modéliser un compte d'admin "de secours" partagé par la DSI | scripts/srv-*, scripts/web-rh, scripts/db-rh, scripts/calc-recherche, scripts/poste-dsi |
| 4 | Email texte "DSI" déposé dans `/home/jdupont/Maildir/` sur srv-mail | Leurre divulguant les creds `dsi/admin2024` après compromission de jdupont | [scripts/srv-mail.sh](../terraform/scripts/srv-mail.sh) |
| 5 | Fichier `/home/dsi/credentials-admin.txt` sur poste-dsi | Anti-pattern "DSI conserve ses creds en clair sur son poste" | [scripts/poste-dsi.sh](../terraform/scripts/poste-dsi.sh) |
| 6 | Compte `pa1/partenaire2024` (Unix + Samba) sur calc-recherche | Modéliser un compte applicatif partenaire dont les creds peuvent fuiter (SO4) | [scripts/calc-recherche.sh](../terraform/scripts/calc-recherche.sh) |
| 7 | Partage Samba `[partenaires]` authentifié | Donner un canal d'accès distinct pour SO4 (partenaire) | [scripts/calc-recherche.sh](../terraform/scripts/calc-recherche.sh) |
| 8 | Colonne `rib` (IBAN) dans la table `employes` + formulaire de modification sur web-rh | Permettre la démo SO5 (détournement de RIB de versement) | [scripts/db-rh.sh](../terraform/scripts/db-rh.sh), [scripts/web-rh.sh](../terraform/scripts/web-rh.sh) |
| 9 | Floating IP attachée à `uc-web-rh` | Permettre le "port scan externe" du chemin retenu SO3 | [floating_ips.tf](../terraform/floating_ips.tf) |
| 10 | Note dans `/home/ubuntu/NOTE-cle-admin.txt` sur poste-dsi rendant le dépôt de clé optionnel | SO2 ne dépend plus d'une opération manuelle post-deploy | [scripts/poste-dsi.sh](../terraform/scripts/poste-dsi.sh) |

Aucune mesure de réduction du risque n'a été introduite — toutes ces
modifications **conservent ou aggravent** les vulnérabilités. La maquette
reste pleinement représentative du SI dégradé décrit dans l'énoncé.
