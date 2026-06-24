commandes pour se connecter à différents postes (admin, élève, prof)

connexion ssh impossible même depuis une machine d'un même sous-réseau

tests à montrer/vérifier : 
* connexion au LDAP en anonyme -> impossible ou en authentifié -> profil dsi, connexion en ??? -> port spécial ?

* nmap depuis le poste étudiant pour montrer l'efficacité du firewall et de la segmentation

* tests de SSO depuis une machine (connexion à différents services avec une seule session)

* SSH depuis les machines ne doivent pas fonctionner -> les ports SSH des machines sont fermés

Moodle a une IP flottante publique -> accessible depuis l'extérieur

* Connexion aux DB impossible SAUF par le bastion

* Checker le bastion (Teleport ?)

* Accès au SIEM, voir le dashboard, les logs, les alertes

* Passage automatique de HTTP à HTTPS par le DNS