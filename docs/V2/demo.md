Tests à montrer/vérifier : 

* connexion au LDAP en anonyme -> impossible ou en authentifié -> profil dsi, connexion en ??? -> port spécial ?
```bash
# Test en anonyme
ldapsearch -x -H ldaps://uc-srv-ldap:636 -b "dc=unicampus,dc=fr"

# Test en authentifié
ldapsearch -x -H ldaps://uc-srv-ldap:636 -b "dc=unicampus,dc=fr" -D "cn=dsi,ou=admin,dc=unicampus,dc=fr" -W
``` 

* nmap depuis le poste étudiant pour montrer l'efficacité du firewall et de la segmentation
```bash
# Pour étu / prof
nmap nmap -sP 192.168.101.0/24
nmap -Pn 192.168.104.0/24
```

* tests de SSO depuis une machine (connexion à différents services avec une seule session)
```
Connexion depuis un poste sur le moodle et le mail : 
- mail.unicampus.fr/roundcube
- moodle.unicampus.fr
```Connexion aux différentes ressources 

* SSH depuis les machines ne doivent pas fonctionner

```bash 
# Pour la connexion au ldap 
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no root@192.168.104.1
```

Moodle a une IP flottante publique -> accessible depuis l'extérieur

* Connexion aux DB impossible SAUF par le bastion
```bash
# rh 
mysql -h 192.168.104.3 -u root -p

#base recherche
psql -h 192.168.102.1 -U postgres -d lrid_results
```

* Checker le bastion (Teleport ?)

* Accès au SIEM, voir le dashboard, les logs, les alertes

```
Connection Par le navigateur depuis des postes dans le reseau admin ou par la machine directement. 
port : 443
Dashboard : https://192.168.109.1, 
ou https://localhost
utilisateur admin
```

* Passage automatique de HTTP à HTTPS par le DNS
  
* Test RBAC : 
Il faut tenter la connexion a web rh avec un compte étudiant 