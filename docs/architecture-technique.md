# Architecture technique : maquette UniCampus+ v1

Document descriptif de l'architecture déployée.

## 1. Vue d'ensemble

| Élément | Valeur |
|---|---|
| Plateforme | OpenStack (utilisation d'un sous-réseau par groupe) |
| Orchestration | Terraform - `unicampus-vuln.yaml` |
| Préfixe ressources | `uc-` |
| CIDR interne | 192.168.107.0/24 (temp : à changer quand l'OpenStack sera pret) |
| Réseau externe | `ext-net` (existant, référencé en paramètre) |
| Nombre de VMs | 11 (1 firewall + 1 VPN + 6 serveurs + 3 postes) |

## 2. Architecture réseau

### 2.1 Réseaux et sous-réseaux

| Réseau | CIDR | Gateway | DHCP | Pool DHCP | DNS |
|---|---|---|---|---|---|
| `uc-net-campus` | 192.168.107.0/24 | 192.168.107.1 | activé | 192.168.107.100 - .200 | 8.8.8.8, 1.1.1.1 |

### 2.2 Routeur

| Nom | Interface interne | Gateway externe |
|---|---|---|
| `uc-router-campus` | 192.168.107.1 sur `uc-subnet-campus` | `ext-net` |

### 2.3 Plan d'adressage IP fixe

| Plage | Usage |
|---|---|
| 192.168.107.1 | Gateway Neutron |
| 192.168.107.2 - .9 | Infrastructure réseau (firewall, VPN) |
| 192.168.107.10 - .19 | Serveurs applicatifs |
| 192.168.107.20 - .29 | Serveurs back-end (bases) |
| 192.168.107.100 - .200 | Pool DHCP (postes clients) |

## 3. Inventaire des instances

### 3.1 Infrastructure réseau

| Nom | Flavor | Image OS | IP fixe | Floating IP |
|---|---|---|---|---|
| `uc-fw-legacy` | m1.tiny | Debian 10 | 192.168.107.2 | oui |
| `uc-vpn-legacy` | m1.tiny | Ubuntu 22.04 | 192.168.107.3 | oui |

### 3.2 Serveurs applicatifs

| Nom | Flavor | Image OS | IP fixe | Floating IP |
|---|---|---|---|---|
| `uc-srv-mail` | m1.tiny | Ubuntu 22.04 | 192.168.107.10 | oui |
| `uc-srv-ldap` | m1.tiny | Ubuntu 22.04 | 192.168.107.11 | non |
| `uc-srv-moodle` | m1.small | Ubuntu 22.04 | 192.168.107.12 | oui |
| `uc-web-rh` | m1.tiny | Ubuntu 22.04 | 192.168.107.14 | non |
| `uc-calc-recherche` | m1.small | Ubuntu 22.04 | 192.168.107.15 | non |

### 3.3 Serveurs back-end

| Nom | Flavor | Image OS | IP fixe | Floating IP |
|---|---|---|---|---|
| `uc-db-rh` | m1.tiny | Ubuntu 22.04 | 192.168.107.20 | non |

Note : `uc-db-recherche` est fusionné dans `uc-calc-recherche` pour réduire le nombre de VMs. Le pivot front -> back sensible reste démontrable côté RH (`uc-web-rh` -> `uc-db-rh`).

### 3.4 Postes clients

| Nom | Flavor | Image OS | IP | Floating IP |
|---|---|---|---|---|
| `uc-poste-etu` | m1.tiny | Kali Linux | DHCP | non |
| `uc-poste-prof` | m1.tiny | Ubuntu Desktop 22.04 | DHCP | non |
| `uc-poste-dsi` | m1.tiny | Ubuntu Desktop 22.04 | DHCP | non |

Note : `uc-poste-prof` cumule les rôles enseignant et enseignant-chercheur (mêmes creds Moodle + recherche). `uc-poste-admin` est fusionné avec `uc-poste-dsi` pour les démonstrations administratives.

### 3.5 Allocation des ressources

#### Spécifications des flavors OpenStack utilisés

| Flavor | vCPU | RAM | Disque |
|---|---|---|---|
| m1.tiny | 1 | 1 Go | 10 Go |
| m1.small | 1 | 2 Go | 20 Go |

#### Allocation par VM

| VM | Flavor | vCPU | RAM | Disque |
|---|---|---|---|---|
| `uc-fw-legacy` | m1.tiny | 1 | 1 Go | 10 Go |
| `uc-vpn-legacy` | m1.tiny | 1 | 1 Go | 10 Go |
| `uc-srv-mail` | m1.tiny | 1 | 1 Go | 10 Go |
| `uc-srv-ldap` | m1.tiny | 1 | 1 Go | 10 Go |
| `uc-srv-moodle` | m1.small | 1 | 2 Go | 20 Go |
| `uc-web-rh` | m1.tiny | 1 | 1 Go | 10 Go |
| `uc-calc-recherche` | m1.small | 1 | 2 Go | 20 Go |
| `uc-db-rh` | m1.tiny | 1 | 1 Go | 10 Go |
| `uc-poste-etu` | m1.tiny | 1 | 1 Go | 10 Go |
| `uc-poste-prof` | m1.tiny | 1 | 1 Go | 10 Go |
| `uc-poste-dsi` | m1.tiny | 1 | 1 Go | 10 Go |

#### Récapitulatif par flavor

| Flavor | Nombre de VMs | vCPU cumulés | RAM cumulée | Disque cumulé |
|---|---|---|---|---|
| m1.tiny | 9 | 9 | 9 Go | 90 Go |
| m1.small | 2 | 2 | 4 Go | 40 Go |

#### Total ressources requises

| Ressource | Quantité |
|---|---|
| vCPU | 11 |
| RAM | 13 Go |
| Disque éphémère | 130 Go |
| Floating IPs | 4 |
| Security groups | 1 |
| Ports Neutron avec IP fixe | 9 |
| Réseaux | 1 |
| Sous-réseaux | 1 |
| Routeurs | 1 |

## 4. Catalogue des services

### 4.1 Services réseau

| VM | Service | Daemon | Port | Protocole | Bind |
|---|---|---|---|---|---|
| `uc-fw-legacy` | Routage | `iptables` + `net.ipv4.ip_forward=1` | - | - | - |
| `uc-fw-legacy` | Administration | `openssh-server` | 22 | TCP | 0.0.0.0 |
| `uc-vpn-legacy` | VPN distant | `pptpd` | 1723 | TCP + GRE (proto 47) | 0.0.0.0 |
| `uc-vpn-legacy` | Administration | `openssh-server` | 22 | TCP | 0.0.0.0 |

### 4.2 Services applicatifs

| VM | Service | Daemon | Port | Protocole | Bind |
|---|---|---|---|---|---|
| `uc-srv-mail` | SMTP | `postfix` | 25 | TCP en clair | 0.0.0.0 |
| `uc-srv-mail` | IMAP | `dovecot-imapd` | 143 | TCP en clair | 0.0.0.0 |
| `uc-srv-mail` | POP3 | `dovecot-pop3d` | 110 | TCP en clair | 0.0.0.0 |
| `uc-srv-ldap` | Annuaire | `slapd` | 389 | LDAP en clair | 0.0.0.0 |
| `uc-srv-moodle` | Web | `apache2` + `php` | 80 | HTTP en clair | 0.0.0.0 |
| `uc-srv-moodle` | Base locale | `mariadb-server` | 3306 | TCP | 127.0.0.1 |
| `uc-web-rh` | Web | `apache2` + `php` | 80 | HTTP en clair | 0.0.0.0 |
| `uc-calc-recherche` | NFS | `nfs-kernel-server` | 2049 + 111 (rpcbind) | TCP/UDP | 0.0.0.0 |
| `uc-calc-recherche` | Samba | `smbd` | 445, 139 | TCP | 0.0.0.0 |
| `uc-calc-recherche` | Notebook | `jupyter` | 8888 | HTTP | 0.0.0.0 |
| `uc-calc-recherche` | Base locale | `postgresql` | 5432 | TCP | 127.0.0.1 |

### 4.3 Services back-end

| VM | Service | Daemon | Port | Protocole | Bind |
|---|---|---|---|---|---|
| `uc-db-rh` | SGBD | `mariadb-server` | 3306 | TCP | 0.0.0.0 |

### 4.4 Dépendances inter-services

| Source | Destination | Port | Usage |
|---|---|---|---|
| `uc-web-rh` | `uc-db-rh:3306` | TCP | Stockage données RH |

## 5. Configuration réseau et sécurité

### 5.1 Security group OpenStack

| Nom | Direction | Protocole | Ports | Source/Destination |
|---|---|---|---|---|
| `uc-sg-allow-all` | Ingress | TCP | 1 - 65535 | 0.0.0.0/0 |
| `uc-sg-allow-all` | Ingress | UDP | 1 - 65535 | 0.0.0.0/0 |
| `uc-sg-allow-all` | Ingress | ICMP | - | 0.0.0.0/0 |
| `uc-sg-allow-all` | Egress | tous | tous | 0.0.0.0/0 |

Appliqué à toutes les instances.

### 5.2 Configuration `uc-fw-legacy`

| Élément | Valeur |
|---|---|
| Politique INPUT | ACCEPT |
| Politique FORWARD | ACCEPT |
| Politique OUTPUT | ACCEPT |
| Tables | toutes vidées |
| Règle résiduelle | `iptables -A INPUT -p tcp --dport 8080 -j ACCEPT` |
| Persistence | `iptables-persistent` |
| IP forwarding | `net.ipv4.ip_forward=1` |

### 5.3 Configuration `uc-vpn-legacy` (PPTP)

| Élément | Valeur |
|---|---|
| Daemon | `pptpd` |
| `localip` | 192.168.107.3 |
| `remoteip` | 192.168.107.210 - .220 |
| Authentification | CHAP, fichier `/etc/ppp/chap-secrets` |
| Compte | `campus` / `unicampus2024` (partagé) |
| MFA | aucun |
| Chiffrement | MPPE-128 (RC4, déprécié) |

## 6. Configuration IAM

### 6.1 Annuaire LDAP `uc-srv-ldap`

| Élément | Valeur |
|---|---|
| Suffix | `dc=unicampus,dc=local` |
| OUs | `ou=people`, `ou=groups` |
| Admin DN | `cn=admin,dc=unicampus,dc=local` |
| Bind anonyme | autorisé |
| TLS | non configuré |
| Consommateurs applicatifs | aucun |

Schéma de comptes prévu (à peupler manuellement) : étudiants, enseignants, chercheurs, ens-chercheurs, admin, DSI.

### 6.2 Bases de comptes locales par service

| Service | Stockage des comptes | Hash | Politique de mot de passe |
|---|---|---|---|
| `uc-srv-moodle` | Table `mdl_user` (MariaDB local) | bcrypt | aucune |
| `uc-web-rh` | Table sur `uc-db-rh` | SHA1 | aucune |
| `uc-srv-mail` | Comptes Unix locaux + Dovecot | crypt | aucune |
| `uc-vpn-legacy` | `/etc/ppp/chap-secrets` | clair | aucune |
| `uc-calc-recherche` | Comptes Unix locaux + NFS UID/GID | crypt | aucune |
| Postes Linux | `/etc/shadow` local | sha512crypt | aucune |

### 6.3 Administration

| Élément | Valeur |
|---|---|
| Bastion SSH | aucun |
| Méthode admin | SSH direct depuis `uc-poste-dsi` vers chaque serveur |
| Stockage des clés | `/home/ubuntu/.ssh/` sur `uc-poste-dsi` (clé privée en clair) |
| Sudo | NOPASSWD pour `ubuntu` sur chaque VM |
| Journalisation des sessions | aucune |

## 7. Exposition externe

### 7.1 Floating IPs allouées

| Instance | Port d'attache | IP fixe interne | Service exposé |
|---|---|---|---|
| `uc-fw-legacy` | `uc-port-fw` | 192.168.107.2 | SSH admin |
| `uc-vpn-legacy` | `uc-port-vpn` | 192.168.107.3 | PPTP 1723/tcp + GRE |
| `uc-srv-mail` | `uc-port-mail` | 192.168.107.10 | SMTP 25, IMAP 143 |
| `uc-srv-moodle` | `uc-port-moodle` | 192.168.107.12 | HTTP 80 |

### 7.2 Pool de floating IPs

Alloué depuis `ext-net` (réseau partagé non géré par le template).

## 8. Logging

| Composant | Cible | Centralisation |
|---|---|---|
| Tous services | `/var/log/` local de chaque VM | aucune |
| `uc-fw-legacy` | `/var/log/syslog` local | aucune |
| `uc-vpn-legacy` | `/var/log/syslog` local | aucune |
| Bases de données | logs locaux MariaDB / PostgreSQL | aucune |

Aucun rsyslog forwarder, aucun agent Wazuh / Filebeat / Fluentd.
