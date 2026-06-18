Ce document rassemble la documentation, les implémentations techniques et les raisons de la mise en place de keycloak 

# KEYCLOAK 
Implémentation :

https://blog.stephane-robert.info/docs/services/identite/keycloak/

Pattern recommandé

    Créez des groupes basés sur l'organisation (équipes, départements)
    Assignez des rôles aux groupes
    Ajoutez des utilisateurs aux groupes
    Les applications lisent les rôles dans le token


__Stratégie 2 : Fédération LDAP/Active Directory__


<img src="https://blog.stephane-robert.info/_astro/keycloak-federation-ldap.D8aWfdun_Z4k5eJ.svg">



Fédération LDAP : Keycloak synchronise les utilisateurs depuis un annuaire LDAP ou Active Directory

Cas d'usage : entreprise avec Active Directory existant, vous voulez réutiliser les identités.

Où sont les users : dans LDAP/AD. Keycloak les synchronise (import complet ou à la demande).

Avantages : pas de double gestion des mots de passe, intégration avec l'existant.


Break glass

Prévoyez un accès d'urgence au realm master :

    Compte admin avec MFA
    Procédure de récupération documentée
    Accès via réseau restreint (VPN, bastion)


Il faut a priori avoir 2 serveurs Keycloak : un de prod et un de test 


## Keycloak dans le réseau 
On doit ajouter une machine pour héberger keycloak dans la DMZ \
Il faut configurer une règle pare-feu pour que Keycloak puisse interroger le LDAP \
Il va falloir rajouter un DNS probablement  pour que le nom de domaine sso.unicampus.fr pointe directement vers l'IP privée de Keycloak dans la DMZ 

Keycloak va probablement s'installer derrière un réseau donc il va falloir utiliser une option précise 


https://blog.stephane-robert.info/docs/services/identite/keycloak/administration/

## Realm
- Realm master
- Realm net

## Groups 
Puisque tes rôles sont globaux (etudiant, externe, etc.), tes groupes doivent simplement refléter ton organigramme ou ta scolarité. Tu auras besoin d'environ 7 groupes principaux.

Groupe Etudiants

    Rôle assigné automatiquement : etudiant

    Mécanique : L'API Gateway et les firewalls liront ce rôle pour ouvrir le VPN et Moodle en mode utilisateur.

Groupe Professeurs

    Rôle assigné automatiquement : professeur

Groupe Chercheurs

    Rôle assigné automatiquement : chercheur

Groupe Equipe_DSI

    Rôles assignés automatiquement : admin_dsi

Groupe Equipe_DBA

    Rôles assignés automatiquement : admin_dba

Groupe Equipe_RH

    Rôles assignés automatiquement : admin_rh

Groupe Intervenants_Externes

    Rôle assigné automatiquement : externe

Il faudra : Configurer les Events pour le SIEM 

## Installation avec Docker

On utilise les images docker de keycloak, pour ça on va devoir installer docker sur la machine qui va héberger keycloak 

On suit le guide suivant https://blog.stephane-robert.info/docs/services/identite/keycloak/installation/ ( à adapté à notre environnement )

### Installation de Docker 
https://blog.stephane-robert.info/docs/conteneurs/moteurs-conteneurs/docker/installation/

### Installation de Keycloak 

https://blog.stephane-robert.info/docs/services/identite/keycloak/installation/ 
## Connexion au LDAP 

## Check List : Check-list avant d'installer
On répond à une check list pour définir ses besoins 

1. Configuration des Realms

    Combien de realms ? \
    2 realms au total sur l'instance : le realm master (strictement réservé à l'administration technique du serveur Keycloak par la DSI) et 1 seul realm applicatif (ex: unicampus ou net) pour l'ensemble des populations de l'université.

    1 realm par environnement (prod, staging) ? \
    Non. L'isolation des environnements est physique. Le serveur Keycloak de Test et le serveur Keycloak de Production sont deux VM distinctes exécutant leurs propres conteneurs, garantissant qu'aucune modification ou test de charge n'impacte la production. (on peut soit tout mettre sur la même soit juste un de Prod )

    1 realm par tenant (multi-tenant) ? \
    Non. L'établissement utilise un périmètre unique où les utilisateurs sont cloisonnés par rôles globaux et non par étanchéité de realms.

2. Protocoles Applicatifs

    Quel protocole pour vos applications ? \
    OIDC (OpenID Connect). Les applications cibles de la migration (uc-srv-moodle et uc-web-rh) seront configurées comme des clients OIDC standards utilisant des flux d'autorisation sécurisés avec échange de jetons JWT.

3. Source des Identités (User Federation)

    D'où viennent les identités ? \
    Fédération LDAP. Keycloak se connecte via le pare-feu central au serveur uc-srv-ldap (situé dans le VLAN protégé uc-net-rh : 192.168.104.11).

    Gestion des mots de passe : Les identifiants et attributs (nom, prénom, mail) sont synchronisés depuis le LDAP. En revanche, pour assainir les mots de passe faibles ou en clair de la V1, la colonne userPassword n'est pas importée. Une politique de Forced Reset est configurée via l'action requise UPDATE_PASSWORD dans Keycloak au premier login de l'utilisateur.

4. Architecture Réseau et Terminaison TLS

    Où termine le TLS ? \
    Au reverse proxy, déployé aux côtés de Moodle dans la zone uc-net-dmz (192.168.107.0/24). Le pare-feu central intercepte le flux HTTPS externe (port 443) et le redirige vers ce proxy, qui valide le certificat et transmet la requête HTTP en interne vers le conteneur Keycloak.

    Quel est le hostname public ? \
    sso.unicampus.fr.

    Cohérence avec les certificats TLS : Le certificat (généré via la PKI interne ou une autorité publique) est porté par le reverse proxy. Pour éviter les erreurs de bouclage réseau (Hairpin NAT), le pare-feu central utilise une configuration de Split DNS permettant aux machines internes (uc-web-rh) de résoudre sso.unicampus.fr directement avec l'IP privée de la DMZ. Keycloak est configuré avec le mode KC_PROXY=edge pour interpréter correctement les en-têtes de redirection (X-Forwarded-*).

5. Disponibilité et Sauvegardes

    Besoin de haute disponibilité ?\
    Une single instance s'appuyant sur Docker Compose (Keycloak + base PostgreSQL dédiée) est configurée pour la phase de maquettage et de validation. Pour la mise en production finale, cette configuration sera migrée vers un cluster de 2 répliques avec cache distribué (Infinispan).

    Backup ? \
    La sauvegarde (Backup) sera gérée par une tâche planifiée (cron) directement sur la machine virtuelle Keycloak, qui exécutera :

    Un export de la base de données (pg_dump).

    Un export JSON des configurations de Keycloak via l'outil en ligne de commande local.

6. Sécurisation des Accès Administration

    Accès admin restreint ?\
     Oui. Le pare-feu central applique des règles strictes sur la chaîne FORWARD. L'accès aux endpoints d'administration de Keycloak (la console web du realm master) est bloqué pour tout le réseau, sauf s'il provient du VLAN d'administration DSI (uc-net-admin : 192.168.103.0/24) ou à travers le bastion de gestion.

    MFA pour les admins : L'activation d'un second facteur d'authentification (MFA via TOTP/Google Authenticator) est configurée comme une politique obligatoire pour l'ensemble des comptes du realm master et des comptes dotés de privilèges d'administration dans le realm applicatif.


## Le lien avec l'applicatif 
Pour OIDC : 
La mise en place se fait en deux étapes, sans infrastructure supplémentaire :

Côté Keycloak : Dans l'interface d'administration, tu crées un "Client". Tu lui donnes un nom (ex: moodle-app) et Keycloak va te générer un "Client ID" et un "Client Secret" (un mot de passe technique).

Côté Application : * Pour Moodle, tu n'as rien à coder. Tu installes simplement le plugin officiel "OpenID Connect" depuis le panel Moodle, et tu y colles le Client ID et le Client Secret fournis par Keycloak.

Pour le Web RH (PHP), tu ajoutes une petite librairie PHP standard (comme jumbojett/openid-connect-php) dans ton code pour que l'application sache "parler" OIDC et rediriger l'utilisateur vers Keycloak.

Pour les bases de données et le ssh on passe par un bastion 

Pour le mail on va ajouter une machine qui héberge Zimbra , c'est une app web on a un OIDC 

### Le bastion 

TO DO 



## Keycloak et LDAP 

https://slash-root.fr/keycloak-integration-ldap-externe/ 

Option A (Lecture Seule - La plus simple) : \
  Tu dis à Keycloak que le LDAP est en "Read-Only". Lorsque l'utilisateur crée son nouveau mot de passe fort, Keycloak le garde pour lui, haché de manière sécurisée (Argon2/PBKDF2) dans sa propre base PostgreSQL. Le LDAP V1 reste tel quel (avec ses vieux mots de passe inutilisés), il ne sert plus qu'à fournir les noms et les adresses e-mail.


## MFA 

L'activation du MFA pour les administrateurs (ou tout autre profil) est très simple et entièrement native :

Tu te connectes sur la console d'administration de Keycloak avec ton compte admin.

Tu vas dans le menu Authentication > onglet Required Actions. Tu t'assures que l'action Configure OTP (One Time Password) est activée.

Tu vas dans la gestion de tes Groupes (ex: le groupe Equipe_DSI), tu ouvres les paramètres du groupe et tu ajoutes Configure OTP dans les Required Actions par défaut du groupe.

Côté Utilisateur : La prochaine fois qu'un administrateur (ex: le compte de ton DSI) tentera de se connecter, Keycloak bloquera l'accès après la saisie du mot de passe. Un écran s'affichera avec un QR Code. L'administrateur devra le scanner avec son téléphone (via l'application Google Authenticator ou FreeOTP), entrer le code à 6 chiffres pour valider, et son compte sera définitivement protégé par le MFA.


## Keycloak et Reverse Proxy : 
https://slash-root.fr/keycloak-installation-avec-docker-et-reverse-proxy-ssl-nginx/


