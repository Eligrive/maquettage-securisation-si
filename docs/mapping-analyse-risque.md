# Mapping analyse de risque ↔ maquette technique

Document de traçabilité entre les éléments de l'analyse de risque EBIOS RM
(fichier `analyse-risque/EBIOS_RM_UniCampus.xlsx`) et leur matérialisation
concrète dans la maquette déployée par Terraform.

Codes EBIOS utilisés ci-dessous :
- **VM** : Valeur métier (atelier 1)
- **BS** : Bien support (atelier 1)
- **ER** : Évènement redouté (atelier 1)
- **SR** : Source de risque (atelier 2)
- **OV** : Objectif visé (atelier 2)
- **SS** : Scénario stratégique (atelier 3)
- **SO** : Scénario opérationnel (atelier 4)
- **R / RR / M** : Risque / Risque résiduel / Mesure de traitement (atelier 5)

---

## 1. Missions et valeurs métier (A1.1)

| Mission | Valeur métier | Modélisation dans la maquette |
|---|---|---|
| M1 Enseignement | VM1.1 Diffusion des contenus pédagogiques | `uc-srv-moodle` (Moodle) + données pédagogiques leurres dans `/var/www/html/moodle/uc-docs/` |
| | VM1.2 Évaluation et notation | Tables `mdl_grade_*` de la base MariaDB locale de `uc-srv-moodle` |
| | VM1.3 Résultats académiques | Idem VM1.2 (notes stockées dans `mdl_grade_grades`) |
| | VM1.4 Communication pédagogique | `uc-srv-mail` (Postfix + Dovecot), comptes nominatifs `jdupont`, `lmartin` |
| | VM1.5 Accès aux ressources documentaires | **Non modélisé** (déclaré pour complétude du périmètre, considéré comme géré par un prestataire) |
| M2 Recherche | VM2.1 Conduite des activités de recherche | `uc-calc-recherche` (Jupyter, PostgreSQL local, NFS, Samba) |
| | VM2.2 Patrimoine scientifique | Données leurres dans `/srv/recherche/` (article, notebook ANR, rapport labo) |
| | VM2.3 Collaboration et diffusion scientifique | Compte partenaire `pa1` sur `uc-calc-recherche` + partage Samba `[partenaires]` |
| M3 Administration | VM3.1 Gestion des ressources humaines | `uc-web-rh` (front PHP) + `uc-db-rh` (MariaDB) |
| | VM3.2 Données personnelles et contractuelles | Table `employes` sur `uc-db-rh` (login, nom, poste, salaire, **rib**, hash SHA1) |
| | VM3.3 Gestion administrative étudiants (scolarité) | **Fusionnée dans Moodle** (faute de serveur scolarité dédié) |
| | VM3.4 Gestion financière et comptable | **Non modélisée séparément** (compte `cfournier VP Finances` sur uc-web-rh comme proxy) |

## 2. Biens supports (A1.2) — mapping officiel

Les codes BS suivants reprennent **strictement** ceux de la feuille A1.2 de
l'EBIOS_RM_UniCampus.xlsx. ⚠️ Le script `analyse-risque/build_a4_v3.py`
utilise une numérotation BS différente dans les feuilles A4.1 — c'est une
inconsistance à corriger côté analyse (cf. §6).

| Code BS | Dénomination officielle | Ressource Terraform | IP | Floating |
|---|---|---|---|---|
| BS01 | Plateforme Moodle (`uc-srv-moodle`) | [scripts/srv-moodle.sh](../terraform/scripts/srv-moodle.sh) | .12 | oui |
| BS02 | Base de données Moodle (intégrée à `uc-srv-moodle`) | idem (MariaDB locale 127.0.0.1) | .12 | non (bind local) |
| BS03 | Serveur de messagerie (`uc-srv-mail`) | [scripts/srv-mail.sh](../terraform/scripts/srv-mail.sh) | .10 | oui |
| BS04 | Annuaire d'identité LDAP (`uc-srv-ldap`) | [scripts/srv-ldap.sh](../terraform/scripts/srv-ldap.sh) | .11 | non |
| BS05 | Serveur de calcul et stockage de recherche (`uc-calc-recherche`) | [scripts/calc-recherche.sh](../terraform/scripts/calc-recherche.sh) | .15 | non |
| BS06 | Application web RH (`uc-web-rh`) | [scripts/web-rh.sh](../terraform/scripts/web-rh.sh) | .14 | **oui** (changement v1) |
| BS07 | Base de données RH (`uc-db-rh`) | [scripts/db-rh.sh](../terraform/scripts/db-rh.sh) | .20 | non (mais bind 0.0.0.0) |
| BS08 | Poste étudiant (`uc-poste-etu`) | [scripts/poste-etu.sh](../terraform/scripts/poste-etu.sh) | DHCP | non |
| BS09 | Poste enseignant et enseignant-chercheur (`uc-poste-prof`) | [scripts/poste-prof.sh](../terraform/scripts/poste-prof.sh) | DHCP | non |
| BS10 | Poste administratif et DSI (`uc-poste-dsi`) | [scripts/poste-dsi.sh](../terraform/scripts/poste-dsi.sh) | DHCP | non |
| BS11 | Passerelle périmétrique (`uc-fw-legacy`) | [scripts/fw-legacy.sh](../terraform/scripts/fw-legacy.sh) | .2 | oui |
| BS12 | Accès distant VPN (`uc-vpn-legacy`) | [scripts/vpn-legacy.sh](../terraform/scripts/vpn-legacy.sh) | .3 | oui |
| BS13 | Réseau campus (`uc-net-campus`) | [network.tf](../terraform/network.tf) | 192.168.107.0/24 | — |

## 3. Évènements redoutés (A1.4) — couverture par la maquette

| Code ER | Intitulé (synthèse) | Gravité | Biens supports impactés | Démontrabilité maquette |
|---|---|---|---|---|
| ER01 | Fuite massive données personnelles | G4 | BS06, BS07, BS04 | ✅ SO3 (exfiltration RH + LDAP) |
| ER02 | Fuite données / résultats de recherche | G3 | BS05 | ✅ SO4 (exfiltration via partage partenaire) |
| ER03 | Altération frauduleuse des notes / diplômes | G3 | BS01, BS02 | ✅ SO1 (compromission Moodle) |
| ER04 | Interruption services pédagogiques > 24h | G3 (G4 en examens) | BS01, BS03, BS13 | ✅ SO2 (effet de bord du rançongiciel) |
| ER05 | Altération frauduleuse de la paie | G3 | BS06, BS07 | ✅ SO5 (modification RIB + salaire) |
| ER06 | Interruption massive simultanée tous services | G4 | tous | ✅ SO2 (rançongiciel multi-VMs) |
| ER08 | Détournement de la messagerie | G2 | BS03 | ⚠️ Démontrable (relais ouvert) mais aucun SO retenu |
| ER09 | Perte / destruction définitive recherche | G3 | BS05 | ✅ SO6 (suppression depuis compte insider) |

## 4. Sources de risque (A2.1) — modélisation dans la maquette

| Code SR | Profil | VM "exécutante" | Capacités modélisées |
|---|---|---|---|
| SR-A | Étudiant malveillant | `uc-poste-etu` (Ubuntu + nmap/hydra/ldap-utils/smbclient) | Connexion légitime au VLAN, outillage offensif, position interne |
| SR-B | Cybercriminel organisé | Attaquant externe via Internet | Accès aux floating IPs (fw, vpn, mail, moodle, **web-rh**), capacité phishing simulée |
| SR-C | Acteur étatique / APT | Attaquant externe disposant de **credentials applicatifs partenaire compromis** (`pa1/partenaire2024`) | Accès Samba `[partenaires]` + SSH sur `uc-calc-recherche`, persistance, exfiltration discrète |
| SR-D | Hacktiviste | (non retenu en SO, surveillance uniquement) | — |
| SR-E | Personnel mécontent / ex-personnel | Tout compte Unix nominatif (`jdupont`, `cfournier`, `dsi`) | SSH avec creds légitimes, accès direct BDD avec creds connus, accès au web-rh sans auth |

⚠️ Note de cohérence : le script `build_a4_v3.py` libelle les SOs comme
"SR-D Personnel mécontent / insider". Conformément à A2.1, c'est **SR-E**.
À corriger côté analyse.

## 5. Couples SR/OV retenus (A2.2) → Scénarios stratégiques (A3.3)

| Couple | SR | Objectif visé | ER ciblé(s) | SS | SO |
|---|---|---|---|---|---|
| C01 | SR-A Étudiant | Compromettre les résultats académiques | ER03 | SS1 | SO1 |
| C03 | SR-B Cybercriminel | Extorquer une rançon par chiffrement | ER06, ER04 | SS2 | SO2 |
| C04 | SR-B Cybercriminel | Revendre les données personnelles | ER01 | SS3 | SO3 |
| C05 | SR-C Acteur étatique | Exfiltrer le patrimoine scientifique | ER02 | SS4 | SO4 |
| C08 | SR-E Personnel mécontent | Détourner la paie | ER05 | SS5 | SO5 |
| C09 | SR-E Personnel mécontent | Détruire les données par vengeance | ER05, ER09 | SS6 | SO6 |

Couples écartés (Surveillance) : C02 SR-A Sabotage, C06 SR-D Publication
données, C07 SR-D Défacement Moodle.

## 6. Scénarios opérationnels (A4.1 / A4.2) — démontrabilité

Pour chaque SO, on liste les **vulnérabilités exploitées** d'après l'analyse,
le **chemin retenu**, et la **démonstrabilité actuelle** (post-modifications).

| Code | Chemin retenu (synthèse) | Gravité × Vraisemblance | Démo |
|---|---|---|---|
| SO1 | Scan VLAN → phishing enseignant → connexion Moodle → modif `mdl_grade_*` | G3 × V3 = Modéré (9) | ✅ Pas-à-pas dans [scenarios-attaque.md §SO1](scenarios-attaque.md) |
| SO2 | OSINT → phishing → cred reuse jdupont → email DSI → SSH `dsi@<servers>` → chiffrement multi-VMs | G4 × V4 = Élevé (16) | ✅ §SO2 |
| SO3 | Port scan externe web-rh → SQLi login bypass → lecture directe `uc-db-rh:3306` → exfiltration | G4 × V3 = Élevé (12) | ✅ §SO3 |
| SO4 | Creds applicatifs partenaire (PA1) compromis → Samba `[partenaires]` → exfiltration discrète | G3 × V2 = Modéré (6) | ✅ §SO4 (chemin reformulé : "cred partenaire fuité" remplace "compromission labo partenaire") |
| SO5 | Compte légitime (cfournier ou jdupont) → formulaire modification web-rh OU UPDATE direct db-rh → modif RIB | G3 × V2 = Modéré (6) | ✅ §SO5 |
| SO6 | Compte légitime insider → SSH serveurs + NFS → suppression données critiques | G3 × V2 = Modéré (6) | ✅ §SO6 |

### Vulnérabilités spécifiques par SO → preuve dans la maquette

| SO | Vulnérabilité listée dans A4.1 | Localisation dans la maquette |
|---|---|---|
| SO1 | Bind LDAP anonyme | [srv-ldap.sh](../terraform/scripts/srv-ldap.sh) (slapd sans ACL) |
| SO1 | WiFi étudiant + serveurs même VLAN | [network.tf](../terraform/network.tf) (subnet unique) |
| SO1 | Pas de MFA / rate-limit Moodle | [srv-moodle.sh](../terraform/scripts/srv-moodle.sh) (install par défaut) |
| SO1 | Aucun log centralisé | absence volontaire |
| SO2 | Compte d'admin partagé en clair sur srv-mail/poste-dsi | [srv-mail.sh](../terraform/scripts/srv-mail.sh) (mail DSI), [poste-dsi.sh](../terraform/scripts/poste-dsi.sh) (credentials-admin.txt) |
| SO2 | Sudo NOPASSWD pour `dsi` et `ubuntu` partout | tous les scripts |
| SO2 | VPN PPTP compte partagé MPPE-128 | [vpn-legacy.sh](../terraform/scripts/vpn-legacy.sh) |
| SO2 | Aucun cloisonnement réseau | [network.tf](../terraform/network.tf) |
| SO2 | Pas de sauvegarde immuable | absence volontaire |
| SO3 | SQLi sur uc-web-rh | [web-rh.sh:21](../terraform/scripts/web-rh.sh#L21) (requête concaténée) |
| SO3 | uc-db-rh exposée `0.0.0.0:3306` + hashs SHA1 | [db-rh.sh:12,39-41](../terraform/scripts/db-rh.sh) |
| SO3 | HTTP en clair sur web-rh | [web-rh.sh](../terraform/scripts/web-rh.sh) |
| SO3 | Bind LDAP anonyme | idem SO1 |
| SO3 | Pas de détection d'exfiltration | absence volontaire |
| SO4 | NFS et Samba sans auth sur calc-recherche | [calc-recherche.sh](../terraform/scripts/calc-recherche.sh) |
| SO4 | Jupyter sans token 0.0.0.0:8888 | idem |
| SO4 | Pas de cloisonnement VLAN partenaires | modélisé via creds applicatifs PA1 (cf. §4 SR-C) |
| SO4 | Données scientifiques en clair | `/srv/recherche/` (assets PDF) |
| SO5 | Pas de séparation des privilèges côté web-rh | [web-rh.sh](../terraform/scripts/web-rh.sh) (un seul rôle implicite, aucune auth) |
| SO5 | Comptes non révoqués au départ | modélisé (creds `jdupont` actifs sur toutes les VMs) |
| SO5 | Aucune validation à 4 yeux RIB / salaire | [web-rh.sh](../terraform/scripts/web-rh.sh) (formulaire UPDATE direct) |
| SO5 | Pas de journal d'audit applicatif | absence volontaire |
| SO6 | Sudo NOPASSWD partout | idem SO2 |
| SO6 | Compte VPN partagé jamais changé | leurre PDF + mail DSI |
| SO6 | Aucune sauvegarde immuable | absence volontaire |
| SO6 | Pas de contrôle d'accès NFS recherche | [calc-recherche.sh](../terraform/scripts/calc-recherche.sh) (export `*`) |

## 7. Plan de traitement (A5.3) — état dans la maquette v1

La maquette v1 implémente **délibérément zéro mesure** du plan A5.3 — c'est
le SI dégradé. Le tableau ci-dessous indique, pour chaque mesure prioritaire,
ce qu'il faudra modifier dans Terraform pour passer à la v2.

### 7.1 Mesures P1 (T0+3 mois) — non implémentées en v1

| Code | Mesure | Action v2 dans Terraform |
|---|---|---|
| M01 | PSSI + politique de mots de passe | Ajouter PAM `pam_pwquality` + rotation, supprimer comptes faibles |
| M02 | Cycle de vie des comptes | Provisionnement central (LDAP comme source) au lieu de `useradd` par script |
| M05 | Sensibilisation phishing | Hors scope Terraform |
| M07 | Cloisonnement réseau (VLANs) | Découper en `uc-net-etudiants`, `uc-net-admin`, `uc-net-recherche`, `uc-net-dmz`, ajouter SG par VLAN |
| M08 | Suppression bind LDAP anonyme + LDAPS | Modifier slapd config (ACL + TLS) |
| M09 | Migration hashs SHA1 → bcrypt | Remplacer `SHA1(...)` dans db-rh.sh par bcrypt |
| M10 | Suppression sudo NOPASSWD | Retirer `/etc/sudoers.d/90-uc-nopasswd` + `91-uc-dsi`, exiger mot de passe |
| M11 | HTTPS partout | Ajouter Let's Encrypt / cert PKI sur moodle, web-rh, mail |
| M12 | Restriction écoute db-rh sur localhost | Changer `bind-address` de 0.0.0.0 vers 127.0.0.1 ou IP web-rh |
| M14 | Comptes VPN individuels | Remplacer le compte unique de chap-secrets par un compte par utilisateur, ou migrer vers WireGuard (M13) |
| M15 | MFA applications critiques | Plugin Moodle MFA, MFA web-rh, MFA VPN |
| M17 | Logs centralisés | Ajouter VM rsyslog/Graylog + forwarder sur chaque VM |
| M22 | Sauvegardes immuables | Hors scope Terraform direct (stockage S3 Object Lock) |
| M24 | Snapshots automatiques | À configurer côté hyperviseur OpenStack |

### 7.2 Mesures P2/P3 (T0+6 à +18 mois) — non implémentées

M03, M04, M06, M13, M16, M18, M19, M20, M21, M23, M25, M26 — détails dans
A5.3.

## 8. Risques résiduels (A5.4) — référence

Les six risques résiduels RR01–RR06 sont décrits dans A5.4 de l'EBIOS. Ils
s'appliquent **à la maquette v2** (après remédiation) et ne sont pas
matérialisés dans la maquette v1.

| Code | Risque | Niveau initial → résiduel |
|---|---|---|
| RR01 | Compromission notes (résiduel) | Moyen (9) → Moyen (6) |
| RR02 | Rançongiciel (résiduel) | Élevé (16) → Moyen (6) |
| RR03 | Exfiltration données personnelles (résiduel) | Élevé (12) → Moyen (8) |
| RR04 | Exfiltration recherche (résiduel) | Moyen (6) → Faible (3) |
| RR05 | Détournement paie (résiduel) | Moyen (6) → Faible (3) |
| RR06 | Destruction par vengeance (résiduel) | Moyen (6) → Faible (2) |

## 9. Inconsistances détectées dans `build_a4_v3.py`

Lors de la vérification, les écarts suivants ont été constatés entre les
feuilles A1/A2 (source de vérité) et le script de génération A4 :

| Élément | Dans `build_a4_v3.py` | Correct (A1/A2 EBIOS) |
|---|---|---|
| BS Mail | "BS08 Mail" (SO2) | **BS03** Mail |
| BS Web RH | "BS05 Web RH" | **BS06** Web RH |
| BS BDD RH | "BS07 BDD RH" ✓ | BS07 ✓ |
| BS calc-recherche | "BS09 calc-recherche" | **BS05** calc-recherche |
| BS NFS recherche | "BS10 NFS recherche" | absorbé dans **BS05** (un seul bien support pour calc-recherche) |
| BS Postes recherche | "BS12 Postes recherche" | **BS09** poste-prof |
| BS Réseau campus | "BS13 Réseau campus" ✓ | BS13 ✓ |
| Source de risque insider | "SR-D Personnel mécontent" (SO5, SO6) | **SR-E** Personnel mécontent (SR-D = Hacktiviste) |
| ER ciblé SO2 | "ER01" | **ER06, ER04** |
| ER ciblé SO4 | "ER04" | **ER02** |
| ER ciblé SO6 | "ER01" | **ER05, ER09** |

Ces écarts n'invalident pas l'analyse de risque elle-même (les feuilles A1
et A2 sont cohérentes), mais ils brouillent la lecture des graphes A4.1.
À corriger dans une prochaine itération du script.
