
# Projet 07 – UniCampus+
**Mots clés : IAM, SSO, firewalling, segmentation réseau, accès étudiants/enseignants**

## Société : UniCampus+
UniCampus+ est une université accueillant environ **12 000 étudiants** et **500 personnels** (enseignants, administratifs, chercheurs, techniciens). Le campus est réparti sur plusieurs bâtiments, accueillant salles de cours, laboratoires de recherche, infrastructures IT, bibliothèques numériques et services administratifs.

## Organisation interne
- **Enseignants / chercheurs** : besoins d’accès aux ressources pédagogiques et scientifiques.
- **Étudiants** : accès Moodle, messagerie, ressources documentaires.
- **Services administratifs** : gestion RH, scolarité, finances.
- **Équipe DSI** : réseau, IAM, systèmes, sécurité.

## Contexte du système d'information
- Multiplicité de services non intégrés : pas de SSO, mots de passe multiples.
- Réseau WiFi étudiants connecté au réseau interne (!).
- Serveurs pédagogiques et serveurs sensibles de recherche dans le même VLAN.
- Firewall obsolète, règles incohérentes.
- Pas de supervision centralisée des logs.

## Menaces
- Accès non autorisé aux serveurs par un étudiant.
- Vol de compte enseignant → accès données recherche.
- Attaques internes via WiFi non segmenté.
- Phishing ciblant les personnels.

## Règles d’hygiène ANSSI pertinentes
- Règle 4 : Identification des actifs sensibles.
- Règle 7 : Accès réseau aux seuls équipements maîtrisés.
- Règle 8 : Comptes nominatifs.
- Règle 9 : Droits strictement nécessaires.
- Règle 10 : Politique de mots de passe.
- Règle 13 : Authentification forte.
- Règle 22 : Segmentation réseau.
- Règle 25 : Filtrage réseau.
- Règle 31 : Protocoles sécurisés.
- Règle 35 : Journalisation.
- Règle 40 : Gestion d’incident.
