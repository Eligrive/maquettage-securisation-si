MaquetteV1.md


12 000 etudiant -> 20 VM -> plutôt 3 
500 personnels -> (DSI,Enseignants, Enseignant-Chercheurs,Chercheurs,Admnistratif,) 5 VM    On peut aussi penser aux intervenants extérieurs 
VM pour Database, Server Mail, Web Service (combien ? ) 
Serveur Pédagogique Enseignant
Serveur de Recherche 
Serveur Mail 
Ressource Pédagogique Elève
(est ce que pour les 3 serveurs 
On peut peut être augmenté le nombre d'étudiants pour que ce soit proportionnel


Organisation réseau : 
A priori pas de segmentation réseau 
Comment représenter le fait que le wifi soit dans le réseau interne ? doit être vulnérable à : Attaques internes via WiFi non segmenté. -> Un seul Réseau et un seul sous-réseau
Serveur Pédagogique et de recherche dans le même VLAN 
Firewall obsolète (qu'est ce que ça veut dire ici obsolète) ? Règles incohérentes (par exemple ? )
Obsolète : En maquette, utilisez une VM avec une vieille version de Debian ou un script iptables mal maintenu.
Incohérentes : Par exemple, une règle qui autorise tout le trafic sortant (Any/Any),des règles "fantômes" qui ouvrent des ports oubliés


Service et SSO : 
Multiplicité de services non intégrés : pas de SSO, mots de passe multiples. -> Créer plusieurs services tous gérer par une database de mdp différents (est ce la bonne représentation ? ) : Mail,Synapses,Moodle 
Il faut aussi ajouter les services pour l'admin (Synapses, Mail, RH/finance, database données élèves peut être - on va faire large et dire database pédagogique) 
Pour les enseignants (Mail, Synapses, database pédagogique , Moodle )
POur les chercheurs (Mail, database chercheur, accès service pédago - gpu etc) 
POur la dsi( Mail, Synapse,Moodle, all database pour certains, - servie dsi) 

Est ce que pour les service dsi il faut spécifier ou alors on laisse le service dsi comme nom général ? 
Les différents services où est ce que je les stocke ? tous sur la même machine ? qu'est ce qui est le plus commun dans la vraie vie ? 

Phishing ciblant les personnels. -> mail service 


Pas de supervision centralisée des logs. -> on peut faire le choix de mettre des logs par service, mais de ne pas les centraliser dans un SIEM, on peut même dire qu'on mets des logs que sur certains services mais pas tout pour l'analyse de risque 



Première proposition : 
1. Les Postes Utilisateurs (La zone "WiFi" et Bureautique)
Dans cette V1, ces postes sont sur le même réseau (VLAN) que les serveurs critiques. C'est la vulnérabilité majeure.

vm-client-etu-01 à 03 (3 VMs) : Représentent les étudiants sur le WiFi. L'une d'elles pourra servir de point de départ pour l'attaque interne.

vm-client-prof-01 (1 VM) : Poste enseignant.

vm-client-chercheur-01 (1 VM) : Poste chercheur.

vm-client-admin-01 (1 VM) : Poste du personnel administratif (Scolarité/RH).

vm-client-dsi-01 (1 VM) : Poste de l'administrateur système. Faille V1 : Il n'y a pas de serveur "Bastion". Ce poste se connecte en SSH directement à tous les serveurs, ce qui est une mauvaise pratique.

2. Les Serveurs Front-End (Les Applications Web)
Ce sont les services avec lesquels les utilisateurs interagissent. Chaque service gère ses propres mots de passe (pas de SSO).

vm-srv-mail : Le serveur de messagerie (Postfix/Dovecot). Faille V1 : Cible idéale pour simuler le phishing.

vm-web-moodle : Le portail de cours en ligne.

vm-web-synapses : Le portail de scolarité (notes, emplois du temps).

vm-web-rh : Le portail des ressources humaines et finances.

vm-calc-recherche : Le serveur de calcul/traitement pour les chercheurs.

3. Les Serveurs Back-End (Les Bases de Données)
Pour répondre à votre question : "tous sur la même machine ?" -> Non, dans l'industrie, même ancienne, on sépare généralement le service Web de sa base de données. Cependant, dans la V1, ces bases de données sont vulnérables car elles sont sur le même sous-réseau que les étudiants.

vm-db-moodle : Contient les cours et les mots de passe locaux Moodle.

vm-db-synapses : Contient les dossiers et notes des étudiants.

vm-db-rh : Contient les données financières (salaires, budgets). Faille V1 : Totalement exposée au réseau étudiant.

vm-db-recherche : Contient les brevets et résultats de recherche sensibles.

4. Le Composant Réseau & Sécurité (L'illusion de sécurité)
vm-fw-legacy : Une vieille machine Debian faisant office de routeur/pare-feu pour sortir sur Internet. Faille V1 : Ses règles iptables sont permissives (Any/Any). Alternativement, vous pouvez utiliser le routeur par défaut d'OpenStack mais configurer des "Security Groups" qui laissent passer tout le trafic interne (Ingress TCP 1-65535 autorisé depuis tout le sous-réseau).






 
