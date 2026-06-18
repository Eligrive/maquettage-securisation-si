    Ce document va rassembler la description de la solution utilisé pour la gestion IAM 


En gros : comment on va gérer SSO et LDAP , leurs connexions, leurs configurations, comment l'ajouter à l'applicatif 

Inventaire : 

Identité :

- étudiant 
- prof
- chercheur 
- dsi
- admin 
- intervenant extérieur 

Les identités sont stockés dans le LDAP :  
on y retrouve dans la V1 

uid : L'identifiant unique (ex: jdupont). Souvent généré automatiquement (1ère lettre du prénom + nom).

sn (Surname) : Le nom de famille.

givenName : Le prénom.

mail : L'adresse email institutionnelle (vitale pour la récupération de compte).

title : Le poste (ex: "Enseignant-Chercheur").

endscol : La date de fin de scolarité 

Dans la V2 on rajoute la catégorie : 
userPassword : Le hash du mot de passe 


Ressources : 
- DB recherche 
- Mails 
- DB Rh
- Moodle 
- VPN
- SSH 
- WEB Rh
- LDAP 


# Matrice Globale de Contrôle d'Accès (RBAC) - UniCampus+ V2

Ce document cartographie l'ensemble des droits d'accès aux ressources du système d'information en fonction des rôles métiers, conformément au principe du moindre privilège.

# Matrice Globale de Contrôle d'Accès (RBAC) - UniCampus+ V2

Ce document cartographie l'ensemble des droits d'accès aux ressources du système d'information en fonction des rôles métiers, conformément au principe du moindre privilège.

| Rôle (Qui ?) | Ressource (Quoi ?) | Action (Quel droit ?) | Commentaire | 
| ----- | ----- | ----- | ----- | 
| **Etudiant** | `Serveur_Mail` | Accès | Accès au serveur mail étudiant. | 
| **Etudiant** | `Moodle` | Accès (User) | Consultation des cours et rendu des devoirs. | 
| **Etudiant** | `VPN` | Accès | Accès distant au réseau campus. | 
| **Professeur** | `Serveur_Mail` | Accès | Messagerie institutionnelle. | 
| **Professeur** | `Moodle` | Accès (Prof) | Création et gestion des cours pédagogiques. | 
| **Professeur** | `VPN` | Accès | Accès distant au réseau campus. | 
| **Chercheur** | `Serveur_Mail` | Accès | Messagerie institutionnelle. | 
| **Chercheur** | `VPN` | Accès | Accès distant au réseau campus. | 
| **Chercheur** | `DB_Recherche` | Accès | Lecture et écriture sur la base de données de recherche. | 
| **Admin_DSI** | `Serveur_Mail` | Accès | Messagerie institutionnelle. | 
| **Admin_DSI** | `Moodle` | Accès (DSI) | Maintenance et configuration technique de la plateforme. | 
| **Admin_DSI** | `VPN` | Accès | Accès distant au réseau campus. | 
| **Admin_DSI** | `Serveurs_Infrastructure` | `ssh_login` | Le `ssh_login` est associé à un compte unix limité à l'administration système (n'a pas les permissions de lire les données métiers). | 
| **Admin_DBA** | `DB_Recherche` | Accès / Modification | Administration du schéma et des données de recherche. | 
| **Admin_DBA** | `DB_RH` | Accès | Maintenance de la base de données des ressources humaines. | 
| **Admin_RH** | `Serveur_Mail` | Accès | Messagerie institutionnelle. | 
| **Admin_RH** | `Moodle` | Accès (RH) | Consultation globale pour les dossiers ou extractions. | 
| **Admin_RH** | `VPN` | Accès | Accès distant au réseau campus. | 
| **Admin_RH** | `DB_RH` | Accès | Accès direct interdit (passe par l'application Web RH). | 
| **Admin_RH** | `Web_RH` | Accès | Droit de lire et modifier les informations des employés (RIB, Salaires). | 
| **Externe / Partenaire** | `Moodle` | Accès (Externe) | Accès restreint en tant qu'invité ou auditeur libre. | 
| **Externe / Partenaire** | `VPN` | Accès | Accès distant très restreint et temporaire. |