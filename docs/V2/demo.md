commandes pour se connecter à différents postes (admin, élève, prof)

connexion ssh impossible même depuis une machine d'un même sous-réseau

tests à montrer/vérifier : 
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
```

* tests de SSO depuis une machine (connexion à différents services avec une seule session)
```
Connexion depuis un poste sur le moodle et le mail : 
- mail.unicampus.fr/roundcube
- moodle.unicampus.fr
```
* SSH depuis les machines ne doivent pas fonctionner -> les ports SSH des machines sont fermés

Moodle a une IP flottante publique -> accessible depuis l'extérieur

* Connexion aux DB impossible SAUF par le bastion

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