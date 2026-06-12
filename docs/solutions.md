# Récapitulatif des failles — Maquette UniCampus+ v1
## et solutions à mettre en place pour la v2

> Ce document recense l'ensemble des vulnérabilités volontairement implémentées dans la maquette v1, organisées par nature d'intervention. Chaque faille est associée à la solution à déployer pour la v2, au(x) scénario(s) qu'elle rend possible, et à la règle ANSSI concernée.

---

## Catégorie 1 — Architecture réseau et segmentation

> Ces failles portent sur la topologie réseau. Leur remédiation passe par des modifications de l'infrastructure (Terraform/OpenStack) et non par des reconfigurations applicatives.

---

### 1.1 VLAN unique — absence totale de segmentation interne

**Faille implémentée**  
Tous les équipements (postes étudiants, serveurs pédagogiques, serveurs de recherche, bases de données RH, postes DSI) sont dans un seul et même subnet `uc-net-campus` (192.168.107.0/24). Un poste étudiant dispose d'une visibilité L2/L3 directe sur `uc-db-rh` (3306), `uc-calc-recherche` (NFS, Samba, Jupyter), `uc-srv-ldap` (389), etc.

**Scénarios activés** : SO1, SO2, SO3, SO4, SO5, SO6

**Règles ANSSI enfreintes** : Règle 22 (Segmentation réseau), Règle 7 (Accès réseau aux seuls équipements maîtrisés)

**Solution v2**  
Découper le réseau en VLANs dédiés dans Terraform :

| Réseau | CIDR | Hôtes |
|---|---|---|
| `uc-net-etudiants` | 192.168.101.0/24 | Postes étudiants + portail WiFi captif |
| `uc-net-enseignants` | 192.168.102.0/24 | Postes enseignants et enseignants-chercheurs |
| `uc-net-admin` | 192.168.103.0/24 | Postes DSI + postes administratifs |
| `uc-net-pedago` | 192.168.104.0/24 | Moodle, serveur mail, LDAP |
| `uc-net-recherche` | 192.168.105.0/24 | calc-recherche, PostgreSQL |
| `uc-net-rh` | 192.168.106.0/24 | web-rh, db-rh |
| `uc-net-dmz` | 10.0.0.0/24 | Services exposés sur Internet |

Créer les `openstack_networking_router_interface_v2` entre les VLANs et définir des Security Groups restrictifs par VLAN (règle de moindre privilège).

---

### 1.2 Firewall périmétrique avec politique ACCEPT totale

**Faille implémentée**  
`uc-fw-legacy` tourne sous Debian 10 (fin de support). Sa politique iptables est `INPUT/FORWARD/OUTPUT ACCEPT` — aucun filtrage effectif. Une règle fantôme sur le port 8080 est présente sans documentation ni utilité. Le Security Group OpenStack `uc-sg-allow-all` court-circuite toute tentative de filtrage au niveau de la plateforme.

**Scénarios activés** : SO2, SO3 (accès direct depuis Internet)

**Règles ANSSI enfreintes** : Règle 25 (Filtrage réseau), Règle 31 (Protocoles sécurisés)

**Solution v2**  
Remplacer `uc-fw-legacy` (Debian 10 + iptables permissif) par une instance sous Ubuntu 22.04 avec `nftables` configuré en whitelist stricte. Exemple de politique cible :

- Bloquer tout trafic entre `uc-net-etudiants` et `uc-net-rh`/`uc-net-recherche`
- Autoriser uniquement HTTPS (443) depuis DMZ vers Moodle et web-rh
- Autoriser SSH uniquement depuis `uc-net-admin` vers les serveurs, via bastion

---

### 1.3 Application RH exposée directement sur Internet

**Faille implémentée**  
`uc-web-rh` dispose d'une Floating IP directement joignable depuis Internet (via DNAT fw-legacy port 80). Une application RH interne contenant des données personnelles (salaires, IBAN) n'a aucune raison d'être exposée publiquement.

**Scénario activé** : SO3

**Règle ANSSI enfreinte** : Règle 25 (Filtrage réseau)

**Solution v2**  
Supprimer la Floating IP de `uc-web-rh` dans `floating_ips.tf`. L'accès doit se faire uniquement depuis `uc-net-admin` ou via le bastion. Si un accès distant est nécessaire, il passe obligatoirement par le VPN.

---

### 1.4 VPN PPTP avec compte partagé

**Faille implémentée**  
`uc-vpn-legacy` utilise le protocole PPTP/MPPE-128 (RC4, déprécié et cassable). Un seul compte VPN partagé entre tous les personnels (`campus / unicampus2024`) est défini dans `chap-secrets`. Aucun MFA. En cas de compromission du compte, tout le SI est accessible depuis Internet.

**Scénario activé** : SO2

**Règles ANSSI enfreintes** : Règle 13 (Authentification forte), Règle 10 (Politique de mots de passe)

**Solution v2**  
Remplacer PPTP par **WireGuard** (ou OpenVPN/IPsec). Créer un compte VPN individuel par utilisateur. ~~Activer le MFA (TOTP via FreeOTP ou YubiKey)~~. Révoquer les accès à la déconnexion de l'employé.

---

## Catégorie 2 — Gestion des identités et des accès (IAM)

> Ces failles portent sur la gouvernance des identités. Leur remédiation implique le déploiement ou la reconfiguration de composants IAM (Keycloak, LDAP, PAM, bastion) — des changements d'architecture logicielle, pas de simples modifications de fichiers de configuration.

---

### 2.1 Absence de SSO — prolifération des bases de comptes locales

**Faille implémentée**  
Chaque service gère sa propre base d'utilisateurs : MariaDB sur Moodle, tables `users` sur Synapses, `chap-secrets` sur le VPN, comptes Unix sur chaque serveur. Un utilisateur comme `jdupont` possède des identifiants distincts sur au moins 5 services. Cette fragmentation mène inévitablement à la réutilisation des mots de passe, mécanisme central de latéralisation dans la maquette.

**Scénarios activés** : SO1, SO2, SO4

**Règles ANSSI enfreintes** : Règle 8 (Comptes nominatifs), Règle 9 (Droits strictement nécessaires)

**Solution v2**  
Déployer un SSO : Kerberos 

---

### 2.2 Serveur LDAP déployé mais non utilisé — DAC par défaut

**Faille implémentée**  
`uc-srv-ldap` (OpenLDAP) est présent mais aucune application ne s'y connecte pour l'authentification. Il modélise un annuaire acquis mais ignoré. Le modèle d'accès effectif est un DAC (Discretionary Access Control) pur : chaque service est seul maître de ses ressources, sans vue centrale.

**Scénario activé** : SO1 (reconnaissance LDAP anonyme)

**Règle ANSSI enfreinte** : Règle 8 (Comptes nominatifs)

**Solution v2**  
Faire du LDAP la source d'autorité unique (source of truth) pour les identités. Tous les services s'authentifient via LDAP/Kerberos. Mettre en place un modèle **RBAC** avec les rôles `etudiant`, `enseignant`, `chercheur`, `ens-chercheur`, `admin`, `dsi`. 

~~Ajouter une dimension **ABAC** pour les accès R&D (accès conditionné par le réseau source et la plage horaire)~~

---


Pas de MFA : Trop contraignant à la connexion, on a le SSO ( peut être MFA sur vpn)


### 2.4 Absence de bastion d'administration SSH

**Faille implémentée**  
Le poste DSI se connecte en SSH direct (`PasswordAuthentication yes`) sur tous les serveurs avec les credentials `dsi/admin2024`. Aucune journalisation des sessions admin, aucun point de contrôle unique. La compromission du poste DSI ou de ses credentials compromet l'ensemble du SI en une étape.

**Scénario activé** : SO2 (escalade root via pivot DSI)

**Règles ANSSI enfreintes** : Règle 35 (Journalisation), Règle 40 (Gestion d'incident)

**Solution v2**  
Déployer un **bastion SSH** (Teleport ou Apache Guacamole) dans `uc-net-admin`. Toutes les connexions SSH admin passent obligatoirement par le bastion. Le bastion enregistre les sessions (audit trail), intègre le MFA, et centralise la gestion des autorisations. Les connexions SSH directes depuis les postes clients vers les serveurs sont bloquées par les Security Groups.

En gros c'est des logs sur la connexion ssh 

---

### 2.5 Compte d'administration partagé `dsi` sur tous les serveurs

**Faille implémentée**  
Le compte Unix `dsi/admin2024` avec `sudo NOPASSWD` est créé sur l'ensemble des serveurs. Ce compte partagé n'est pas nominatif, ses credentials sont stockés en clair dans `/home/dsi/credentials-admin.txt` sur le poste DSI, et distribués par mail aux personnels. Sa compromission est totale et irréversible sans intervention sur chaque VM.

**Scénario activé** : SO2

**Règles ANSSI enfreintes** : Règle 8 (Comptes nominatifs), Règle 9 (Droits strictement nécessaires)

**Solution v2**  
Supprimer le compte `dsi` partagé. Les administrateurs système utilisent leurs comptes nominatifs (`prenom.nom`). Les privilèges sudo sont accordés nominativement et avec authentification par mot de passe (supprimer `/etc/sudoers.d/90-uc-nopasswd` et `91-uc-dsi`). La gestion centralisée des sudo est assurée par le bastion ou un outil PAM.

En gros Setup un PAM 

---

## Catégorie 3 — Sécurité des protocoles et des communications

> Ces failles portent sur le choix des protocoles réseau. Leur correction implique la reconfiguration des services applicatifs (certificats TLS, changement de protocole), distincte des modifications d'infrastructure réseau ou d'IAM.

---

### 3.1 LDAP en clair sur le port 389 — bind anonyme autorisé

**Faille implémentée**  
`uc-srv-ldap` écoute sur `ldap:///` (port 389, sans TLS). Le bind anonyme est autorisé par défaut (aucune ACL slapd). N'importe quel hôte du VLAN peut lister les entrées de l'annuaire (OUs, UIDs, userPasswords en clair) sans s'authentifier. Utilisé en reconnaissance dans SO1 et SO3.

**Scénarios activés** : SO1, SO3

**Règle ANSSI enfreinte** : Règle 31 (Protocoles sécurisés)

**Solution v2**  
Activer **LDAPS** (port 636) avec un certificat PKI interne. Désactiver le port 389 ou forcer STARTTLS. Configurer les ACL slapd pour interdire le bind anonyme — seuls les services authentifiés (Keycloak) peuvent interroger l'annuaire. Les `userPassword` sont stockés en bcrypt.

---

### 3.2 HTTP en clair sur Moodle, portail RH et messagerie

**Faille implémentée**  
`uc-srv-moodle`, `uc-web-rh` et `uc-srv-mail` (SMTP/IMAP/POP3) communiquent en clair. Les credentials transitent en plaintext sur le réseau campus. Dans le contexte du VLAN unique, un ARP spoof permet de capturer toutes les sessions en quelques secondes.

**Scénarios activés** : SO1, SO3 (capture de credentials via ARP spoof)

**Règle ANSSI enfreinte** : Règle 31 (Protocoles sécurisés)

**Solution v2**  
Déployer des certificats TLS (PKI interne ou Let's Encrypt) sur l'ensemble des services web. Configurer Apache avec `SSLEngine on`, redirection automatique HTTP → HTTPS, HSTS. Pour la messagerie : activer `smtpd_tls_security_level=encrypt` (Postfix) et `ssl=required` (Dovecot). Désactiver POP3/IMAP en clair (ports 110/143), n'exposer que les ports TLS (993/995/587).

---

### 3.3 NFS sans authentification — export ouvert `*`

**Faille implémentée**  
`uc-calc-recherche` exporte `/srv/recherche` avec les options `*(rw,sync,no_root_squash,no_subtree_check)`. N'importe quelle machine du VLAN peut monter le partage en lecture/écriture avec les droits root. Les données scientifiques (notebooks ANR, rapports labo) sont directement accessibles.

**Scénarios activés** : SO4, SO6

**Règles ANSSI enfreintes** : Règle 9 (Droits strictement nécessaires), Règle 31 (Protocoles sécurisés)

**Solution v2**  
Migrer vers **NFSv4 avec Kerberos** (sec=krb5p). Restreindre les exports aux seules machines autorisées par IP (remplacer `*` par la liste explicite des clients). Supprimer `no_root_squash`. En complément de la segmentation réseau (catégorie 1), le partage NFS ne sera accessible que depuis `uc-net-recherche`.

modifier les fichiers de conf, principe du moindre privilège 

---

### 3.4 Samba avec accès invité et `force user = root`

**Faille implémentée**  
Le partage Samba `[recherche]` est configuré avec `guest ok = yes` et `force user = root` : tout accès invité s'exécute avec les droits root sur le système de fichiers.

**Scénario activé** : SO4

**Règle ANSSI enfreinte** : Règle 9 (Droits strictement nécessaires)

**Solution v2**  
Supprimer le partage `[recherche]` en accès invité. Configurer Samba avec authentification obligatoire intégrée à Kerberos/LDAP. Supprimer `force user = root` et définir un compte de service dédié avec droits minimaux. Les accès partenaires (`pa1`) sont gérés via un compte nominatif à durée de vie limitée, révocable depuis Kerberos .


modifier les fichiers de conf, principe du moindre privilège 
---

### 3.5 Jupyter Notebook exposé sans token sur 0.0.0.0:8888

**Faille implémentée**  
Le service Jupyter tourne avec `--NotebookApp.token=''` et écoute sur toutes les interfaces (`0.0.0.0:8888`). N'importe quel hôte du VLAN peut accéder à l'environnement de calcul (et exécuter du code arbitraire sur le serveur) sans aucune authentification.

**Scénario activé** : SO4

**Règle ANSSI enfreinte** : Règle 9 (Droits strictement nécessaires)

**Solution v2**  
Configurer Jupyter avec un token fort ou authentification par mot de passe hashé. Restreindre l'écoute à `127.0.0.1` (accès uniquement via tunnel SSH ou reverse proxy local). Exposer Jupyter via un reverse proxy Apache/Nginx avec authentification Kerberos si un accès réseau est nécessaire.

---

### 3.6 Serveur mail — relais ouvert et absence de SPF/DKIM/DMARC

**Faille implémentée**  
Postfix est configuré avec `mynetworks=0.0.0.0/0` (relais ouvert depuis n'importe quelle source) et `smtpd_tls_security_level=none`. Aucun enregistrement SPF/DKIM/DMARC n'est en place. `uc-srv-mail` peut donc être utilisé pour envoyer des mails de phishing au nom de `@unicampus.fr` sans authentification.

**Scénario activé** : SO2 (phishing personnels via relais ouvert)

**Règles ANSSI enfreintes** : Règle 31 (Protocoles sécurisés), Règle 40 (Gestion d'incident)

**Solution v2**  
Restreindre `mynetworks` aux seuls réseaux internes légitimes. Activer TLS (`smtpd_tls_security_level=encrypt`). Publier les enregistrements DNS SPF, signer les mails avec DKIM, et définir une politique DMARC en `reject`. Activer l'authentification SMTP (SASL) pour les envois utilisateurs.

---

## Catégorie 4 — Sécurité des applications et des données

> Ces failles portent sur le code applicatif, la configuration des bases de données et le stockage des données sensibles. Leur correction s'effectue au niveau de chaque application ou script de déploiement.

---

### 4.1 Injection SQL sur le portail RH (`uc-web-rh`)

**Faille implémentée**  
Le formulaire de recherche de `index.php` construit sa requête par concaténation directe du paramètre `login` sans aucune sanitisation. Une injection SQL sur ce formulaire permet de contourner l'authentification, d'exfiltrer la table `employes` (salaires, IBAN, hashs), voire d'exécuter des commandes via `INTO OUTFILE`.

**Scénario activé** : SO3

**Règle ANSSI enfreinte** : Règle 9 (Droits strictement nécessaires)

**Solution v2**  
Réécrire toutes les requêtes SQL en utilisant des **requêtes préparées** (PDO avec `prepare()` / `bindParam()`). Valider et filtrer tous les paramètres en entrée. Mettre en place un WAF (ModSecurity) devant le portail RH. Restreindre les privilèges du compte MariaDB applicatif aux seules opérations nécessaires (suppression du GRANT ALL).

Modifier le code de index.php 

---

### 4.2 Portail RH sans authentification

**Faille implémentée**  
`uc-web-rh` ne demande aucune authentification. N'importe qui ayant accès à l'URL (interne ou externe via la Floating IP) peut consulter et modifier les données RH (salaires, IBAN, données personnelles). Le formulaire `UPDATE` sur les RIBs et salaires est directement accessible.

**Scénarios activés** : SO3, SO5

**Règles ANSSI enfreintes** : Règle 8 (Comptes nominatifs), Règle 9 (Droits strictement nécessaires)

**Solution v2**  
Implémenter une authentification SSO. Mettre en place une séparation des rôles applicatifs : consultation RH (lecture), modification salaires (droits restreints), validation RIB (double validation à 4 yeux). Journaliser toutes les actions de modification avec horodatage et identité de l'auteur.

En gros Utilisation du SSO et principe du moindre privilège

---

### 4.3 Base RH (`uc-db-rh`) exposée sur `0.0.0.0:3306` avec comptes root ouverts

**Faille implémentée**  
MariaDB écoute sur toutes les interfaces (`bind-address = 0.0.0.0`). Les comptes `rhapp@'%'/rh2024` et `root@'%'/root` autorisent les connexions depuis n'importe quelle IP du VLAN. Un étudiant peut se connecter directement à la base RH depuis son poste (`mysql -h 192.168.107.20 -u root -proot`) sans passer par l'application.

**Scénarios activés** : SO3, SO5

**Règles ANSSI enfreintes** : Règle 9 (Droits strictement nécessaires), Règle 22 (Segmentation réseau)

**Solution v2**  
Restreindre `bind-address` à l'IP de `uc-web-rh` (ou `127.0.0.1` si colocalisation). Remplacer les GRANT `@'%'` par des GRANT limités à l'IP de l'applicatif front-end. Supprimer le compte `root@'%'`. Combiner avec la segmentation réseau (catégorie 1) pour n'autoriser le port 3306 que depuis `uc-net-rh`.

A vérifier mais a priori firewall + segementation réseua = plus de problème 
---

### 4.4 Hashs de mots de passe SHA1 sans sel dans la base RH

**Faille implémentée**  
La table `employes` stocke les mots de passe sous forme de hashs `SHA1` sans sel. Ces hashs sont cassables quasi-instantanément par tables arc-en-ciel (hashcat, CrackStation). Les mots de passe récupérés permettent ensuite la réutilisation sur d'autres services (latéralisation).

**Scénario activé** : SO3 (post-exfiltration)

**Règle ANSSI enfreinte** : Règle 10 (Politique de mots de passe)

**Solution v2**  
Remplacer `SHA1(password)` par **bcrypt** (cost factor ≥ 12) ou Argon2id dans le code PHP et dans `db-rh.sh`. Migrer les hashs existants au prochain login de chaque utilisateur (double hashing temporaire ou invalidation forcée). En parallèle, mettre en place une politique de mots de passe via PAM `pam_pwquality` (longueur minimale, complexité, historique).

Ou alors SHA256 , faire attention fait partie de la migration et de la conservation de la donnée
---

### 4.5 Credentials stockés en clair sur les postes et dans la messagerie

**Faille implémentée**  
Plusieurs fichiers en clair exposent l'ensemble des secrets du SI :
- `/home/dsi/credentials-admin.txt` (poste-dsi) : credentials DSI, VPN, root MariaDB, admin LDAP
- `/home/ubuntu/identifiants.txt` (poste-prof) : tous les credentials de `jdupont`
- Mail DSI dans la Maildir de `jdupont` : compte `dsi/admin2024` distribué à tous les personnels
- PDF VPN dans `/home/jdupont/` : credentials VPN partagés

**Scénarios activés** : SO2, SO4

**Règles ANSSI enfreintes** : Règle 8 (Comptes nominatifs), Règle 10 (Politique de mots de passe)

**Solution v2**  
Supprimer tous les fichiers de credentials en clair. Les secrets d'infrastructure sont gérés dans un **coffre-fort de secrets** (HashiCorp Vault ou équivalent). Les accès sont délivrés dynamiquement et révocables. Les personnels s'authentifient via le SSO (pas de partage de credentials par mail). Les comptes partagés sont interdits.

---

### 4.6 `chmod 0777` sur le répertoire Moodle data

**Faille implémentée**  
Le répertoire `/var/moodledata` est provisonné avec les permissions `0777`, permettant à tout utilisateur du système (et a fortiori à tout processus web compromis) d'écrire, modifier ou supprimer des données pédagogiques (notes, devoirs, fichiers cours).

**Scénario activé** : SO1 (post-compromission Moodle)

**Règle ANSSI enfreinte** : Règle 9 (Droits strictement nécessaires)

**Solution v2**  
Appliquer les permissions recommandées par Moodle : propriétaire `www-data:www-data`, permissions `0750` sur les répertoires et `0640` sur les fichiers. Le processus web ne doit avoir accès qu'aux ressources strictement nécessaires à son fonctionnement.

Toujours le principe du moindre privilège, ici on modifie la config de moodle 

---

## Catégorie 5 — Supervision, journalisation et réponse à incident

> Ces failles portent sur la capacité à détecter les attaques et à y répondre. Leur remédiation implique le déploiement de composants de supervision centralisée (SIEM, SOC).

---

### 5.1 Absence de centralisation des logs

**Faille implémentée**  
Aucun serveur de logs centralisé n'est déployé (pas de rsyslog forwarder, Graylog, ELK, ou Wazuh). Les logs de chaque VM restent locaux dans `/var/log/`. En cas d'intrusion, les logs peuvent être effacés par l'attaquant sur la machine compromise. Il est impossible de corréler des événements entre services (ex. : connexion LDAP → Moodle → SSH → db-rh dans la même session).

**Scénarios concernés** : tous (absence de détection)

**Règles ANSSI enfreintes** : Règle 35 (Journalisation), Règle 40 (Gestion d'incident)

**Solution v2**  
Déployer une VM de collecte centralisée avec **Graylog** ou la stack **Elastic (ELK)**. Configurer un agent rsyslog/Filebeat/Fluentd sur chaque VM pour forwarder les logs vers le collecteur central. Définir des alertes sur les événements critiques : authentifications échouées répétées, connexions SSH hors heures ouvrées, requêtes SQL anormales, modifications de fichiers sensibles (auditd).

EN gros centralisation des logs --> setup d'un SIEM 
---

### 5.2 Absence de procédure et d'outillage de réponse à incident

**Faille implémentée**  
Aucun SOC, aucune procédure de gestion d'incident, aucun système de détection (IDS/IPS, EDR). En cas d'attaque réussie (rançongiciel SO2, exfiltration SO3), aucun mécanisme ne permet de détecter, contenir ou remonter l'incident.

**Scénario concerné** : SO2, SO6 (destruction sans détection)

**Règle ANSSI enfreinte** : Règle 40 (Gestion d'incident)

**Solution v2**  
Rédiger une Politique de Sécurité du Système d'Information (PSSI) avec procédures de réponse à incident. Déployer un IDS réseau (Suricata ou Zeek) sur le firewall périmétrique. Mettre en place des sauvegardes immuables (stockage objet S3 avec Object Lock). Définir un plan de continuité d'activité (PCA) et tester les procédures de restauration.

SETUP SOC , IDS, IPS , SIEM

---

## Tableau de synthèse — Traçabilité failles ↔ solutions ↔ ANSSI

| # | Faille | Catégorie | SO impactés | Règles ANSSI | Solution principale |
|---|---|---|---|---|---|
| 1.1 | VLAN unique | Réseau | SO1–SO6 | R22, R7 | Segmentation en 6 VLANs |
| 1.2 | Firewall ACCEPT total | Réseau | SO2, SO3 | R25, R31 | nftables whitelist + SG restrictifs |
| 1.3 | Web-RH sur Internet | Réseau | SO3 | R25 | Supprimer la Floating IP RH |
| 1.4 | VPN PPTP compte partagé | Réseau | SO2 | R13, R10 | WireGuard + comptes individuels + MFA |
| 2.1 | Pas de SSO | IAM | SO1, SO2, SO4 | R8, R9 | Keycloak OIDC/SAML |
| 2.2 | LDAP non branché / DAC | IAM | SO1, SO3 | R8 | LDAP source d'autorité + RBAC/ABAC |
| 2.3 | Pas de MFA | IAM | SO1–SO3, SO5 | R13 | MFA Keycloak (TOTP/WebAuthn) |
| 2.4 | Pas de bastion SSH | IAM | SO2 | R35, R40 | Teleport / Guacamole |
| 2.5 | Compte `dsi` partagé NOPASSWD | IAM | SO2 | R8, R9 | Comptes nominatifs + sudo avec mdp |
| 3.1 | LDAP en clair / bind anonyme | Protocoles | SO1, SO3 | R31 | LDAPS + ACL slapd |
| 3.2 | HTTP en clair (tous services) | Protocoles | SO1, SO3 | R31 | TLS partout + HSTS |
| 3.3 | NFS sans auth, export `*` | Protocoles | SO4, SO6 | R9, R31 | NFSv4 + Kerberos |
| 3.4 | Samba invité + `force user=root` | Protocoles | SO4 | R9 | Auth Kerberos + compte dédié |
| 3.5 | Jupyter sans token, 0.0.0.0 | Protocoles | SO4 | R9 | Token + écoute localhost |
| 3.6 | Relais mail ouvert, pas de SPF/DKIM | Protocoles | SO2 | R31, R40 | TLS + mynetworks + SPF/DKIM/DMARC |
| 4.1 | Injection SQL portail RH | Applications | SO3 | R9 | Requêtes préparées + WAF |
| 4.2 | Portail RH sans authentification | Applications | SO3, SO5 | R8, R9 | SSO Keycloak + RBAC applicatif |
| 4.3 | MariaDB RH exposée `0.0.0.0:3306` | Applications | SO3, SO5 | R9, R22 | bind-address restreint + GRANT limités |
| 4.4 | Hashs SHA1 sans sel | Applications | SO3 | R10 | bcrypt / Argon2id |
| 4.5 | Credentials en clair sur postes | Applications | SO2, SO4 | R8, R10 | Vault + interdiction comptes partagés |
| 4.6 | chmod 0777 Moodle data | Applications | SO1 | R9 | Permissions 0750/0640 www-data |
| 5.1 | Pas de logs centralisés | Supervision | Tous | R35, R40 | Graylog/ELK + agents forwarders |
| 5.2 | Pas de SOC ni procédure incident | Supervision | SO2, SO6 | R40 | PSSI + IDS + sauvegardes immuables |
