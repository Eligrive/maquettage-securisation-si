# Guide de vérification fonctionnelle — maquette UniCampus+

Ce document sert de checklist opérationnelle pour confirmer que la maquette
UniCampus+ est bien en état de démonstration. Il complète
[architecture-technique.md](architecture-technique.md) et
[assets/README.md](../assets/README.md), sans remplacer le détail des
scénarios d'attaque documentés dans
[scenarios-attaque.md](scenarios-attaque.md).

L'objectif est simple : pour chaque composant, savoir quoi vérifier, avec quel
endpoint, quelles commandes lancer, et quel résultat considérer comme "OK".

## 1. Ce qu'il faut vérifier en premier

Avant de tester les services, valider que le provisioning cloud-init est bien
terminé, surtout sur `uc-srv-moodle`.

```bash
sudo cloud-init status --wait
sudo systemctl status cloud-final --no-pager -l
sudo tail -n 200 /var/log/uc-provision.log
```

Critère attendu : `cloud-final` doit être terminé et le log ne doit plus
montrer un script bloqué sur une étape de provisioning.

## 2. Cartographie rapide des points de contrôle

| Service | VM | Adresse / port | Ce que l'on valide |
|---|---|---|---|
| Administration firewall | `uc-fw-legacy` | `10.0.0.2:22` | alias DMZ, NAT, routage, IP forwarding |
| VPN PPTP | `uc-vpn-legacy` | `10.0.0.3:1723` + GRE 47 | service PPTP et accès au réseau campus |
| Messagerie | `uc-srv-mail` | `10.0.0.4:25/110/143` | Postfix, Dovecot, accès texte clair |
| Moodle | `uc-srv-moodle` | `10.0.0.5:80` | Apache, MariaDB locale, site Moodle |
| Portail RH | `uc-web-rh` | `10.0.0.6:80` | application web RH et accès base RH |
| Base RH | `uc-db-rh` | `192.168.107.20:3306` | MariaDB, comptes `rhapp` et `root` |
| Calcul / recherche | `uc-calc-recherche` | `192.168.107.15:2049/445/8888/5432` | NFS, Samba, Jupyter, PostgreSQL |
| Poste DSI | `uc-poste-dsi` | DHCP | outils, documents sensibles, accès admin |
| Poste prof | `uc-poste-prof` | DHCP | accès aux comptes de référence |
| Poste étudiant | `uc-poste-etu` | DHCP | outils d'audit / attaque pédagogique |

## 3. Ordre de vérification recommandé

1. Vérifier que le provisioning est fini.
2. Vérifier `fw-legacy`, car il porte les alias DMZ et le DNAT.
3. Vérifier les services exposés : VPN, mail, Moodle, RH.
4. Vérifier les services de données : LDAP, MariaDB RH, PostgreSQL, NFS.
5. Vérifier les postes clients et les documents leurres.
6. Vérifier les journaux si quelque chose ne répond pas.

## 4. Rappels de credentials utiles

Les identifiants complets sont aussi rappelés dans
[architecture-technique.md](architecture-technique.md#7-authentification--récapitulatif-des-credentials).

| Service | Identifiants |
|---|---|
| VPN PPTP | `campus / unicampus2024` |
| Moodle | `admin / Admin2024` |
| LDAP admin | `cn=admin,dc=unicampus,dc=local / unicampus2024` |
| LDAP users | `jdupont / unicampus2024`, `lmartin / Printemps2024` |
| Mail | `jdupont / unicampus2024`, `lmartin / Printemps2024`, `sleblanc / recherche2024`, `cfournier / finance2024`, `dsi / admin2024` |
| RH MariaDB | `rhapp / rh2024`, `root / root` |
| Samba partenaires | `pa1 / partenaire2024`, `sleblanc / recherche2024`, `jdupont / unicampus2024` |
| PostgreSQL recherche | `recherche / recherche2024` |

## 5. Vérification par composant

### 5.1 `uc-fw-legacy` — firewall périmétrique

Ce qu'il faut voir :

- l'alias DMZ `10.0.0.2` est présent sur l'interface DMZ ;
- `net.ipv4.ip_forward = 1` ;
- les règles NAT existent ;
- les FIPs sont relayées vers VPN, mail, Moodle et RH ;
- l'accès SSH d'administration fonctionne sur la FIP associée au firewall.

Commandes :

```bash
sudo systemctl status uc-fw-aliases --no-pager -l
sudo sysctl net.ipv4.ip_forward
sudo ip addr show eth1
sudo iptables -S
sudo iptables -t nat -S
```

Critère OK : les alias `10.0.0.3` à `10.0.0.6` apparaissent, le forwarding est
actif et les règles DNAT/MASQUERADE attendues sont présentes.

### 5.2 `uc-vpn-legacy` — accès distant PPTP

Ce qu'il faut voir :

- `pptpd` est démarré ;
- le port TCP 1723 est à l'écoute ;
- la connexion client attribue une adresse dans `192.168.107.210-220` ;
- une fois connecté, on atteint les services internes du campus.

### 5.2.1 Création du VPN sous Windows 10/11

La procédure ci-dessous crée le client VPN sur un poste Windows avec le client
intégré de l'OS.

1. Ouvrir **Settings** > **Network & Internet** > **VPN**.
2. Cliquer sur **Add a VPN connection**.
3. Renseigner **VPN provider** = `Windows (built-in)`.
4. Renseigner **Connection name** = `UniCampus VPN`.
5. Renseigner **Server name or address** = `137.194.211.236`.
6. Renseigner **VPN type** = `Point to Point Tunneling Protocol (PPTP)`.
7. Renseigner **Type of sign-in info** = `User name and password`.
8. Renseigner **User name** = `campus`.
9. Renseigner **Password** = `unicampus2024`.
10. Cliquer sur **Save**, puis sur **Connect**.

Vérification après connexion :

```powershell
ipconfig
ping 192.168.107.12
ping 192.168.107.15
```

Variante PowerShell si tu préfères créer le profil par commande :

```powershell
Add-VpnConnection -Name 'UniCampus VPN' -ServerAddress '137.194.211.236' -TunnelType Pptp -AuthenticationMethod MSChapv2 -RememberCredential -Force
rasdial 'UniCampus VPN' campus unicampus2024
```

Commandes côté serveur :

```bash
sudo systemctl status pptpd --no-pager -l
sudo ss -ltnp | grep 1723
sudo journalctl -u pptpd -e --no-pager
```

Validation fonctionnelle côté client VPN :

```bash
ip a
ping -c 3 192.168.107.12
ping -c 3 192.168.107.15
```

Critère OK : le tunnel se monte avec `campus / unicampus2024` et donne accès au
réseau `192.168.107.0/24`.

### 5.2.2 Commandes SSH par machine

Une fois le VPN créé et connecté, les VMs du campus s'atteignent directement sur
leurs IP internes. Sans VPN, le firewall `fw-legacy` sert de rebond via
`ssh -J`.

Le firewall est une VM Debian, donc le rebond SSH utilise l'utilisateur
`debian`. Les autres VMs restent accessibles avec `ubuntu`.

| Machine | SSH après VPN | SSH via rebond `fw-legacy` |
|---|---|---|
| `fw-legacy` | `ssh debian@137.194.211.13` | `ssh debian@137.194.211.13` |
| `vpn-legacy` | `ssh ubuntu@192.168.107.3` | `ssh -J debian@137.194.211.13 ubuntu@192.168.107.3` |
| `srv-mail` | `ssh ubuntu@192.168.107.10` | `ssh -J debian@137.194.211.13 ubuntu@192.168.107.10` |
| `srv-ldap` | `ssh ubuntu@192.168.107.11` | `ssh -J debian@137.194.211.13 ubuntu@192.168.107.11` |
| `srv-moodle` | `ssh ubuntu@192.168.107.12` | `ssh -J debian@137.194.211.13 ubuntu@192.168.107.12` |
| `web-rh` | `ssh ubuntu@192.168.107.14` | `ssh -J debian@137.194.211.13 ubuntu@192.168.107.14` |
| `calc-recherche` | `ssh ubuntu@192.168.107.15` | `ssh -J debian@137.194.211.13 ubuntu@192.168.107.15` |
| `db-rh` | `ssh ubuntu@192.168.107.20` | `ssh -J debian@137.194.211.13 ubuntu@192.168.107.20` |
| `poste-dsi` | `ssh ubuntu@<IP-DHCP-poste-dsi>` | `ssh -J debian@137.194.211.13 ubuntu@<IP-DHCP-poste-dsi>` |
| `poste-prof` | `ssh ubuntu@<IP-DHCP-poste-prof>` | `ssh -J debian@137.194.211.13 ubuntu@<IP-DHCP-poste-prof>` |
| `poste-etu` | `ssh ubuntu@<IP-DHCP-poste-etu>` | `ssh -J debian@137.194.211.13 ubuntu@<IP-DHCP-poste-etu>` |

Pour les VMs DHCP, l'adresse exacte se récupère dans Horizon ou via la commande
`openstack server list` avant de lancer SSH.

### 5.3 `uc-srv-mail` — messagerie Postfix / Dovecot

Ce qu'il faut voir :

- `postfix` et `dovecot` sont actifs ;
- les ports 25, 110 et 143 répondent ;
- la configuration est volontairement en clair ;
- les comptes Unix nominatifs existent ;
- le document leurre DSI est présent dans la boîte mail de `jdupont`.

Commandes :

```bash
sudo systemctl status postfix dovecot --no-pager -l
sudo ss -ltnp | grep -E ':(25|110|143)\b'
sudo postconf -n | grep -E 'inet_interfaces|mynetworks|tls_security_level'
```

Tests de bannière depuis un poste client :

```bash
printf 'EHLO test\r\nQUIT\r\n' | nc -v 192.168.107.10 25
printf 'a1 CAPABILITY\r\nQUIT\r\n' | nc -v 192.168.107.10 143
printf 'QUIT\r\n' | nc -v 192.168.107.10 110
```

Critère OK : les trois services répondent en texte clair et acceptent les
comptes listés dans le tableau des identifiants.

### 5.4 `uc-srv-ldap` — annuaire OpenLDAP

Ce qu'il faut voir :

- `slapd` est actif ;
- le port 389 répond ;
- un bind anonyme fonctionne ;
- les entrées `people` et `groups` existent ;
- les comptes `jdupont` et `lmartin` sont présents.

Commandes :

```bash
sudo systemctl status slapd --no-pager -l
sudo ss -ltnp | grep 389
ldapwhoami -x -H ldap://192.168.107.11
ldapsearch -x -H ldap://192.168.107.11 -b dc=unicampus,dc=local '(uid=jdupont)' dn uid cn
ldapsearch -x -D 'cn=admin,dc=unicampus,dc=local' -W -H ldap://192.168.107.11 -b dc=unicampus,dc=local '(objectClass=*)' | head -n 40
```

Critère OK : la base `dc=unicampus,dc=local` est interrogeable sans TLS et les
comptes attendus remontent dans les résultats.

### 5.5 `uc-srv-moodle` — plateforme Moodle

Ce qu'il faut voir :

- `cloud-init` est terminé ;
- `apache2` et `mariadb` sont actifs ;
- le port 80 répond ;
- la base Moodle `moodle` existe ;
- les fichiers `uc-docs/` sont bien copiés ;
- l'interface web permet la connexion avec `admin / Admin2024`.

Commandes :

```bash
sudo cloud-init status --long
sudo systemctl status apache2 mariadb --no-pager -l
sudo ss -ltnp | grep -E ':(80|3306)\b'
sudo tail -n 200 /var/log/uc-provision.log
ls -l /var/www/html/moodle/uc-docs/
mysql -u moodle -p -h 127.0.0.1 -e 'SHOW DATABASES;'
```

Validation fonctionnelle :

- ouvrir `http://10.0.0.5` depuis l'extérieur, ou `http://192.168.107.12` depuis le campus ;
- se connecter avec `admin / Admin2024` ;
- vérifier que la page d'accueil Moodle s'affiche et que les documents leurres sont accessibles ;
- vérifier que la base locale répond avec l'utilisateur `moodle`.

Critère OK : Moodle se charge sans erreur PHP, la page d'administration est
accessible et la base MariaDB locale répond.

### 5.6 `uc-web-rh` — portail RH

Ce qu'il faut voir :

- `apache2` est actif ;
- le port 80 répond ;
- la page unique `index.php` est accessible ;
- la recherche et la modification se comportent comme décrit dans
  `scenarios-attaque.md` ;
- les documents RH leurres sont présents.

Commandes :

```bash
sudo systemctl status apache2 --no-pager -l
sudo ss -ltnp | grep ':80\b'
curl -I http://192.168.107.14
ls -l /var/www/html/rh-docs/
```

Validation fonctionnelle :

- ouvrir `http://10.0.0.6` depuis l'extérieur, ou `http://192.168.107.14` depuis le campus ;
- vérifier que la page RH s'affiche ;
- vérifier que le formulaire de recherche retourne des employés ;
- vérifier que le formulaire de modification met bien à jour salaire et RIB ;
- pour les détails d'exploitation de la vulnérabilité, se reporter à
  [scenarios-attaque.md](scenarios-attaque.md).

Critère OK : la page est accessible sans authentification et les deux formulaires
répondent comme attendu.

### 5.7 `uc-db-rh` — base RH MariaDB

Ce qu'il faut voir :

- `mariadb` écoute sur `0.0.0.0:3306` ;
- la base `rh` existe ;
- la table `employes` est peuplée ;
- les comptes `rhapp` et `root` fonctionnent comme prévu.

Commandes :

```bash
sudo systemctl status mariadb --no-pager -l
sudo ss -ltnp | grep 3306
mysql -h 192.168.107.20 -u rhapp -p -e 'SHOW DATABASES; USE rh; SHOW TABLES; SELECT login, salaire, rib FROM employes;'
```

Critère OK : la base répond à distance et la table `employes` contient les
entrées de démonstration.

### 5.8 `uc-calc-recherche` — NFS, Samba, Jupyter et PostgreSQL

Ce qu'il faut voir :

- `nfs-kernel-server`, `smbd`, `jupyter` et `postgresql` sont actifs ;
- NFS exporte `/srv/recherche` sans authentification ;
- Samba propose un partage invité et un partage authentifié ;
- Jupyter écoute sur `0.0.0.0:8888` sans token ;
- PostgreSQL répond localement.

Commandes :

```bash
sudo systemctl status nfs-kernel-server smbd jupyter postgresql --no-pager -l
sudo ss -ltnp | grep -E ':(2049|139|445|8888|5432)\b'
showmount -e 192.168.107.15
smbclient -L //192.168.107.15 -N
curl -I http://192.168.107.15:8888
```

Validation fonctionnelle NFS :

```bash
sudo mkdir -p /mnt/recherche
sudo mount -t nfs 192.168.107.15:/srv/recherche /mnt/recherche
ls -l /mnt/recherche
```

Validation fonctionnelle Samba :

```bash
smbclient //192.168.107.15/recherche -N -c 'ls'
smbclient //192.168.107.15/partenaires -U pa1 -c 'ls'
```

Validation fonctionnelle PostgreSQL :

```bash
psql -h 127.0.0.1 -U recherche -d lrid_results -c '\dt'
```

Critère OK : les partages sont lisibles, Jupyter est atteignable sans token et
la base PostgreSQL locale est accessible avec `recherche / recherche2024`.

### 5.9 `uc-poste-dsi` — poste d'administration

Ce qu'il faut voir :

- les outils d'accès réseau sont installés ;
- les documents de démonstration sont présents ;
- le fichier `credentials-admin.txt` existe ;
- le poste peut servir de point de rebond pour les accès administratifs.

Commandes :

```bash
command -v openssh-client nfs-common smbclient
test -f /home/dsi/credentials-admin.txt && echo OK
ls -l /home/ubuntu/Documents/
ls -l /home/dsi/Documents/
```

Critère OK : les documents leurres sont présents et le poste est prêt pour une
démo d'administration.

### 5.10 `uc-poste-prof` — poste enseignant-chercheur

Ce qu'il faut voir :

- les outils de consultation sont installés ;
- le fichier `identifiants.txt` existe ;
- les identifiants réutilisables sont accessibles dans le cadre de la démo.

Commandes :

```bash
command -v nfs-common smbclient firefox
test -f /home/ubuntu/identifiants.txt && echo OK
```

Critère OK : le poste contient les documents pédagogiques et les identifiants de
démonstration pour les services `jdupont`.

### 5.11 `uc-poste-etu` — poste étudiant / attaquant

Ce qu'il faut voir :

- les outils offensifs sont présents ;
- le poste n'a pas de compte nominatif ;
- il peut servir de machine d'audit et de démonstration.

Commandes :

```bash
command -v nmap netcat hydra ldapsearch smbclient curl python3 git
```

Critère OK : les outils de test réseau et applicatif sont installés.

## 6. Vérifications transverses utiles

### Réseau et ports

```bash
ss -ltnp
ip route
ping -c 3 192.168.107.10
ping -c 3 192.168.107.12
ping -c 3 192.168.107.15
```

### Journaux

```bash
sudo journalctl -u apache2 -e --no-pager
sudo journalctl -u mariadb -e --no-pager
sudo journalctl -u slapd -e --no-pager
sudo tail -n 200 /var/log/syslog
```

### Problèmes fréquents

- `cloud-init` encore en cours : attendre la fin de `cloud-final`.
- Page Moodle vide ou lente : vérifier que le clone GitHub a terminé et que
  `/var/log/uc-provision.log` ne montre plus d'erreur.
- Port 3306 non joignable depuis l'extérieur : vérifier si le service écoute
  bien sur `0.0.0.0` ou seulement sur `127.0.0.1` selon la VM ciblée.
- VPN qui monte mais pas d'accès interne : vérifier les routes du client VPN et
  les règles DNAT sur `fw-legacy`.

## 7. Résultat attendu d'une démo "tout est OK"

Quand la maquette est prête, on doit pouvoir constater simultanément :

- le firewall relaye bien les services publiés ;
- le VPN fournit un accès au réseau campus ;
- le mail répond en clair sur les ports 25/110/143 ;
- LDAP accepte les recherches anonymes ;
- Moodle affiche la page d'accueil et accepte `admin / Admin2024` ;
- le portail RH répond sans authentification ;
- la base RH est peuplée ;
- NFS, Samba, Jupyter et PostgreSQL sont joignables ;
- les postes clients contiennent leurs documents leurres.

Si tu veux aller plus loin, le document suivant à consulter est
[scenarios-attaque.md](scenarios-attaque.md), qui enchaîne les vérifications de
fonctionnement avec les démonstrations de vulnérabilités.