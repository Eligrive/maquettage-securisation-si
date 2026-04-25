# Justification des choix — maquette UniCampus+ v1

Ce document explique chaque décision de conception de la maquette v1. Pour les détails purement techniques (IP, ports, packages, configurations), se référer à `architecture-technique-v1.md`.

## 1. Démarche

L'énoncé du projet impose deux maquettes successives : une v1 sensible aux attaques décrites dans `Projet_07_UniCampus.md`, puis une v2 corrigée selon les résultats de l'analyse de risque. La v1 vise donc la **fidélité à la description** du SI dégradé, pas la sécurité. Chaque faiblesse listée doit pouvoir être démontrée concrètement par un scénario d'attaque sans ambiguïté pour les auditeurs.

Trois principes ont guidé la conception :

1. **Reproduire fidèlement** les vulnérabilités décrites dans le projet, sans en inventer ni en omettre.
2. **Permettre des démonstrations concrètes** : chaque menace listée correspond à un chemin d'attaque exécutable depuis une VM de la maquette.
3. **Rester déployable** sur l'OpenStack mutualisé sans interférer avec les autres groupes.

## 2. IAM en v1 : analyse du modèle DAC

### 2.1 Modèle d'accès dominant

Le contrôle d'accès de la v1 relève du **Discretionary Access Control** (DAC) : chaque service est propriétaire de ses ressources et de ses comptes, et décide localement qui peut accéder à quoi. Aucune vue centrale n'existe.

| Caractéristique DAC | Mise en œuvre dans la maquette |
|---|---|
| Propriété locale des comptes | Bases MariaDB sur Moodle, Synapses, RH ; comptes Unix sur calc-recherche et mail ; fichier `chap-secrets` sur le VPN |
| Droits attribués ressource par ressource | Permissions Unix, GRANT MariaDB, ACL NFS, exports Samba |
| Aucune autorité centrale | LDAP déployé mais aucun service applicatif ne s'y connecte |
| Pas d'attribut contextuel | Aucune décision basée sur département, horaires, localisation ou appareil |

### 2.2 Ce qui est absent par rapport à RBAC et ABAC

| Mécanisme IAM | Présence v1 | Description de l'absence |
|---|---|---|
| RBAC (rôles) | absent | Aucun rôle défini : un enseignant-chercheur a N comptes locaux indépendants, sans rattachement à un profil unique |
| ABAC (attributs) | absent | Aucun attribut utilisateur exploitable pour conditionner l'accès (ex. accès R&D uniquement depuis le réseau interne en heures ouvrées) |
| SSO | absent | Un couple login/mdp par service, dérive vers la réutilisation des mots de passe |
| MFA | absent | Aucun second facteur, même pour la DSI |
| Provisioning centralisé | absent | Création/révocation manuelle dans chaque service |
| Bastion d'administration | absent | Le poste DSI se connecte en SSH direct partout |

Cette absence est **la vulnérabilité IAM centrale** de la v1 : impossibilité de révoquer un accès de manière fiable, traçabilité éclatée, surface d'attaque démultipliée par la duplication des identités.

### 2.3 Cible IAM pour la v2

La v2 introduira un Keycloak en SSO fédéré au LDAP, avec un modèle **RBAC** sur les rôles `etudiant`, `enseignant`, `chercheur`, `ens-chercheur`, `admin`, `dsi`, plus une dimension **ABAC** sur les accès R&D (MFA obligatoire hors réseau interne, fenêtre horaire). Un bastion (Teleport ou Apache Guacamole) journalisera les sessions admin.

## 3. Choix de l'architecture réseau

### 3.1 VLAN plat unique

L'énoncé décrit explicitement un WiFi étudiants connecté au réseau interne et des serveurs pédagogiques dans le même VLAN que la recherche. La maquette modélise littéralement cette absence de segmentation par un unique subnet `uc-net-campus` accueillant à la fois les serveurs sensibles, les bases, les postes administratifs et les postes étudiants. C'est la condition pour que les scénarios d'attaque latérale (ARP spoof, scan, accès direct aux DB) restent crédibles.

### 3.2 Multi-bâtiments absorbés

UniCampus+ est décrit comme réparti sur plusieurs bâtiments. Une modélisation fidèle à la sécurité absente passe par l'**absorption des bâtiments dans le même VLAN** : pas de VPN site-à-site, pas de séparation L2 inter-sites. Cela évite d'introduire artificiellement de la segmentation que l'énoncé ne mentionne pas, et illustre la conséquence — un poste compromis dans le bâtiment A voit immédiatement les serveurs du bâtiment B.

### 3.3 VPN d'accès distant legacy

Pour les personnels nomades, un concentrateur PPTP/L2TP sans MFA est ajouté (`uc-vpn-legacy`). Le PPTP est volontairement déprécié, l'authentification CHAP utilise un compte partagé entre tous les personnels. Ce choix introduit un vecteur d'attaque externe crédible (brute-force depuis Internet, phishing du compte partagé) sans alourdir la maquette.

## 4. Choix concernant les services et leur isolation

### 4.1 Front-end et back-end séparés pour les services sensibles

Pour la RH et la recherche, le front (web) et la base sont déployés sur deux VMs distinctes (`uc-web-rh` / `uc-db-rh`, `uc-calc-recherche` / `uc-db-recherche`). Cette séparation est l'état de l'art même dans les SI anciens et permet de démontrer le **pivot inter-VM dans le même VLAN** : un étudiant peut, depuis son poste, atteindre directement `uc-db-rh:3306` en TCP sans avoir besoin de compromettre le front.

Pour Moodle et Synapses, le front et la base sont colocalisés. La duplication n'apporterait pas de valeur démonstrative supplémentaire et alourdirait la maquette.

### 4.2 LDAP présent mais inutilisé

L'énoncé décrit « pas de SSO, mots de passe multiples ». Pour rendre tangible cette dérive, un serveur LDAP est déployé mais aucune appli ne s'y connecte — ce qui modélise une organisation qui possède l'outil sans s'en servir, situation très fréquente dans les SI universitaires.

### 4.3 Synapses distinct de la RH

Le portail scolarité (Synapses : notes, emplois du temps) est séparé de la RH/finances. Ces deux services ont des publics et des données différents (étudiants et enseignants pour Synapses, personnels pour la RH) et seraient dans la réalité gérés par deux applications distinctes. Cela permet aussi de multiplier les bases de comptes (chacune sa propre table `users`) et donc d'illustrer plus visiblement la prolifération des identités.

### 4.4 Postes clients distincts par profil

Les six profils utilisateurs (étudiant, enseignant, chercheur, ens-chercheur, admin, DSI) sont matérialisés par six VMs distinctes. Deux VMs étudiants (au lieu d'une seule) renforcent la crédibilité de la masse 12 000 et permettent de simuler la propagation latérale entre postes utilisateurs.

## 5. Absence volontaire de bastion pour la DSI

Le poste DSI se connecte en SSH direct à chaque serveur, avec sa clé privée stockée en clair dans `~/.ssh/`. Ce choix illustre une mauvaise pratique d'administration extrêmement courante dans les SI peu matures et ouvre un scénario d'escalade privilégié : un phishing réussi sur le compte DSI compromet l'ensemble du SI. Pas de journalisation des sessions admin, pas de point de contrôle unique — exactement ce que la v2 corrigera avec un bastion.

## 6. Composants volontairement absents

| Composant | Faiblesse SI correspondante |
|---|---|
| SSO (Keycloak, SAML, OIDC) | « Multiplicité de services non intégrés : pas de SSO » |
| Fournisseur d'identité centralisé exploité | Absence de RBAC / ABAC |
| LDAPS (TLS sur LDAP) | « Protocoles non sécurisés » (règle ANSSI 31) |
| HTTPS sur Moodle, RH, Synapses | Idem |
| STARTTLS sur SMTP/IMAP | Idem |
| Kerberos sur NFS | Idem |
| Segmentation WiFi étudiants | « WiFi étudiants connecté au réseau interne » |
| VLAN dédié recherche / RH | « Serveurs pédago et recherche dans le même VLAN » |
| VPN site-à-site inter-bâtiments | Absence de segmentation inter-sites |
| MFA sur VPN d'accès distant | Authentification forte absente (règle ANSSI 13) |
| Serveur de logs central (rsyslog, ELK, SIEM) | « Pas de supervision centralisée des logs » |
| Bastion SSH pour la DSI | Mauvaise pratique d'administration |
| Pare-feu moderne / NGFW | « Firewall obsolète, règles incohérentes » |
| Politique de mots de passe | Règle ANSSI 10 |
| Antivirus / EDR sur les postes | Hors scope énoncé mais aggravation supplémentaire |

## 7. Mapping faiblesses SI → choix de maquette

### 7.1 Multiplicité de services non intégrés

| Choix | Justification |
|---|---|
| Bases de comptes locales par appli (Moodle, Synapses, RH, mail) | Modélise la prolifération des identités |
| LDAP déployé mais non branché | Reproduit l'annuaire présent mais ignoré |
| Algorithmes de hash hétérogènes (bcrypt, MD5, SHA1, crypt) | Reflète des applis acquises à des époques différentes |

### 7.2 WiFi étudiants connecté au réseau interne

| Choix | Justification |
|---|---|
| Postes étudiants dans `uc-net-campus` | Visibilité L2/L3 complète sur l'infra |
| Aucune ACL ni SG restrictif | Pas de filtrage entre étudiants et serveurs |
| Pas de portail captif, pas de 802.1X | WiFi modélisé comme un branchement direct au VLAN |

### 7.3 Serveurs pédago et recherche dans le même VLAN

| Choix | Justification |
|---|---|
| Moodle, calc-recherche, db-recherche dans le même subnet | Reproduit littéralement l'absence de séparation |
| db-rh dans le même subnet que les postes étudiants | Base RH directement exposée |
| NFS sans Kerberos avec export `*` | Partage R&D accessible à toute machine du VLAN |

### 7.4 Firewall obsolète, règles incohérentes

| Choix | Justification |
|---|---|
| Image Debian 10 pour `uc-fw-legacy` | Représente une distribution non maintenue |
| iptables en `ACCEPT` par défaut | Modélise les règles permissives |
| Règle fantôme port 8080 | Illustre les règles oubliées « héritées d'un ancien projet » |
| `uc-sg-allow-all` sur toutes les VMs | Court-circuite tout filtrage au niveau OpenStack |

### 7.5 Pas de supervision centralisée des logs

| Choix | Justification |
|---|---|
| Aucune instance rsyslog/ELK/Graylog/Wazuh | Reproduit l'absence de SOC |
| Logs locaux uniquement | Pas de corrélation possible |
| Pas de netflow sur firewall | Pas de détection de latéralisation |

## 8. Scénarios d'attaque démontrables

| Menace de l'énoncé | Chemin d'attaque sur la maquette |
|---|---|
| Accès non autorisé étudiant → serveurs | Depuis `uc-poste-etu-01` : `nmap 192.168.107.0/24`, puis `ldapsearch -x -h 192.168.107.11`, puis `mount -t nfs 192.168.107.15:/data/rd /mnt` |
| Vol compte enseignant → données R&D | Phishing via `uc-srv-mail` vers `uc-poste-ens-chercheur`, capture des creds Moodle, réutilisation sur `uc-calc-recherche`, pivot vers `uc-db-recherche` en PostgreSQL |
| Attaques internes via WiFi | ARP spoof entre `uc-poste-etu-01` et serveurs, capture des creds Moodle/RH en HTTP via Wireshark, replay sur Synapses |
| Phishing personnels | Envoi de mail depuis `uc-srv-mail` sans SPF/DKIM/DMARC, lien vers fausse mire Moodle |
| Compromission accès distant | Brute-force PPTP sur l'IP publique du VPN depuis Internet, accès direct au VLAN interne |
| Escalade root | Compromission de `uc-poste-dsi`, récupération de `~/.ssh/id_rsa`, SSH sur tous les serveurs |
| Accès direct base sensible | Depuis `uc-poste-etu-01`, connexion `mysql -h 192.168.107.20 -u rh -prh2024` |

## 9. Règles ANSSI volontairement enfreintes

| Règle | Intitulé | Enfreinte par |
|---|---|---|
| 7 | Accès réseau aux seuls équipements maîtrisés | WiFi étudiants dans le VLAN interne |
| 9 | Droits strictement nécessaires | NFS ouvert, LDAP anonyme, SG allow-all, GRANT MariaDB sur `%` |
| 10 | Politique de mots de passe | Comptes locaux faibles, creds VPN partagés |
| 13 | Authentification forte | Absence de MFA partout, VPN sans second facteur |
| 22 | Segmentation réseau | VLAN unique, pas de séparation inter-bâtiments |
| 25 | Filtrage réseau | iptables permissif, SG allow-all, règle fantôme |
| 31 | Protocoles sécurisés | HTTP, LDAP 389, SMTP/IMAP en clair, NFSv3, PPTP |
| 35 | Journalisation | Pas de collecte centralisée |
| 40 | Gestion d'incident | Pas de SOC, pas de procédure, pas de bastion |

Règles **conservées** dès la v1 : règle 4 (actifs sensibles identifiés par nomenclature `uc-srv-recherche`, `uc-db-recherche`, `uc-db-rh`) et règle 8 (comptes système nominatifs sur les postes, seul le partage des credentials applicatifs est modélisé).

## 10. Contrainte OpenStack mutualisé

| Contrainte | Choix de maquette correspondant |
|---|---|
| OpenStack partagé entre ~10 groupes admin | Isolation par convention de nommage, pas par tenant |
| Ne pas modifier le réseau principal | `ext-net` jamais créé, référencé en paramètre |
| Éviter les collisions avec les autres groupes | Préfixe `uc-` sur toutes les ressources |
| CIDR non collisionnel | 192.168.107.0/24 (à valider avant déploiement) |
| Ne pas toucher aux routeurs des autres | Un unique routeur `uc-router-campus` sous le contrôle du groupe |
| Suppression propre | Stack Heat auto-contenu, supprimable en une commande |

## 11. Table de traçabilité globale

| Élément SI d'origine | Choix maquette | Ressource Heat |
|---|---|---|
| « pas de SSO » | Bases de comptes locales par appli | `srv_moodle`, `srv_synapses`, `web_rh`, `srv_mail` |
| « WiFi étudiants sur réseau interne » | Postes étudiants dans `uc-net-campus` | `poste_etu_01`, `poste_etu_02` |
| « pédago et recherche même VLAN » | Tous serveurs dans `uc-subnet-campus` | `subnet_campus` + tous les ports |
| « firewall obsolète » | Debian 10 + iptables ACCEPT + SG allow-all | `fw_legacy`, `sg_allow_all` |
| « règles incohérentes » | Règle fantôme port 8080 | user_data de `fw_legacy` |
| « multi-bâtiments sans segmentation » | VLAN unique + VPN PPTP | `net_campus`, `vpn_legacy` |
| « phishing personnels » | Postfix sans SPF/DKIM/DMARC | `srv_mail` |
| « pas de bastion » | SSH direct depuis `uc-poste-dsi` | `poste_dsi` |
| « IAM = DAC » | Comptes locaux + LDAP non branché | `srv_ldap` + user_data des serveurs |
| « pas de supervision » | Aucune instance de collecte | absence volontaire |

## 12. Limites assumées de la maquette

| Limite | Commentaire |
|---|---|
| 16 VMs au lieu de 12 000 + 500 utilisateurs réels | Échantillonnage représentatif des profils, pas de simulation de charge |
| Bâtiments absorbés dans un seul VLAN | Choix qui simplifie la topologie sans masquer la vulnérabilité de fond |
| Pas de WiFi physique simulé | Connexion modélisée comme branchement direct au VLAN, suffisant pour les scénarios |
| Pas d'antivirus / EDR | Hors scope énoncé mais à mentionner en analyse de risque |
| Configurations applicatives partielles | Installation des paquets via cloud-init, peuplement des comptes manuel |
