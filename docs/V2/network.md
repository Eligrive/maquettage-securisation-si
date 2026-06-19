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


On ajoute les machines de la V2 : 
| `uc-srv-roundcube` | m1.small | Ubuntu 22.04 | Mail  (Roundcube) | 
| `uc-srv-sso` | m1.small | Ubuntu 22.04 | keycloak | 
| `uc-srv-bastion`| m1.small |  Ubuntu 22.04 | teleport |

| Réseau | CIDR | Hôtes |
|---|---|---|
| `uc-net-user` | 192.168.101.0/24 | étudiant : `uc-poste-etu` et Profs : `uc-poste-prof` |
| `uc-net-recherche` | 192.168.102.0/24 | Recherche : `uc-calc-recherche` |
| `uc-net-admin`| 192.168.103.0/24 |  DSI : `uc-poste-dsi`, `uc-srv-bastion` |
| `uc-net-rh` |  192.168.104.0/24 | `uc-srv-ldap` `uc-web-rh` `uc-db-rh` |
| `uc-net-mail`| 192.168.105.0/24 | `uc-srv-mail` |
| `uc-net-vpn` | 192.168.106.0/24 | `uc-vpn-legacy` | 
| `uc-net-dmz`| 192.168.107.0/24 | `uc-srv-moodle` , `uc-srv-roundcube`, `uc-srv-sso` |


Ce qui donne pour les IP : 
`uc-poste-etu`  : 192.168.101.1
`uc-poste-prof` : 192.168.101.2

`uc-calc-recherche` : 192.168.102.1

`uc-poste-dsi` : 192.168.103.1
`uc-srv-bastion` : 192.168.103.2

`uc-srv-ldap` : 192.168.104.1
`uc-web-rh` : 192.168.104.2
`uc-db-rh`  : 192.168.104.3

`uc-srv-mail` : 192.168.105.1

`uc-vpn-legacy` : 192.168.106.1

`uc-srv-moodle` : 192.168.107.1
`uc-srv-roundcube` : 192.168.107.2
`uc-srv-sso` : 192.168.107.3    

Et le firewall qui est tout seul 
`uc-srv-firewall`: 192.168.108.1


# TO DO : 
- Ajouter les modifs réseaux dû à Keycloak 
- Configurer le Reverse Proxy pour que web-rh soit accessible 

Il va falloir installer un reverse Proxy nginx et des certificats SSL : 

Ressources : 

https://slash-root.fr/nginx-installation-dun-reverse-proxy/

https://slash-root.fr/nginx-ajouter-un-certificat-ssl-lets-encrypt-pour-passer-en-https/