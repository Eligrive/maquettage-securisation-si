Ce document rassemble le descriptif de la nouvelle configuration et les raisons des choix effectués 

On répartit les machines de la V1 : 

| `uc-vpn-legacy` | .3 | m1.tiny | Ubuntu 22.04 | Concentrateur PPTP |

| `uc-srv-moodle` | .12 | m1.small | Ubuntu 22.04 | Moodle (Apache+PHP+MariaDB) | 



| `uc-srv-mail` | .10 | m1.tiny | Ubuntu 22.04 | Postfix + Dovecot |

| `uc-srv-ldap` | .11 | m1.tiny | Ubuntu 22.04 | OpenLDAP (slapd) |
| `uc-web-rh` | .14 | m1.tiny | Ubuntu 22.04 | Portail RH (Apache+PHP) |
| `uc-db-rh` | .20 | m1.tiny | Ubuntu 22.04 | MariaDB RH |

| `uc-calc-recherche` | .15 | m1.small | Ubuntu 22.04 | NFS+Samba+Jupyter+PostgreSQL |
| `uc-poste-etu` | DHCP | Ubuntu 22.04 | Poste étudiant / attaquant |
| `uc-poste-prof` | DHCP | Ubuntu 22.04 | Poste enseignant-chercheur |
| `uc-poste-dsi` | DHCP | Ubuntu 22.04 | Poste DSI / admin |


| Réseau | CIDR | Hôtes |
|---|---|---|
| `uc-net-user` | 192.168.101.0/24 | étudiant : `uc-poste-etu` et Profs : `uc-poste-prof` |
| `uc-net-recherche` | 192.168.102.0/24 | Recherche : `uc-calc-recherche` |
| `uc-net-admin`| 192.168.103.0/24 |  DSI : `uc-poste-dsi` |
| `uc-net-rh` |  192.168.104.0/24 | `uc-srv-ldap` `uc-web-rh` `uc-db-rh` |
| `uc-net-mail`| 192.168.105.0/24 | `uc-srv-mail` |
| `uc-net-vpn` | 192.168.106.0/24 | `uc-vpn-legacy` | 
| `uc-net-dmz`| 192.168.107.0/24 | `uc-srv-moodle` |



# TO DO : 
- Ajouter les modifs réseaux dû à Keycloak 
- Configurer le Reverse Proxy pour que web-rh soit accessible 

Il va falloir installer un reverse Proxy nginx et des certificats SSL : 

Ressources : 

https://slash-root.fr/nginx-installation-dun-reverse-proxy/

https://slash-root.fr/nginx-ajouter-un-certificat-ssl-lets-encrypt-pour-passer-en-https/