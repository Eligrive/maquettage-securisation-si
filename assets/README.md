# Assets — documents leurres de la maquette UniCampus+

Documents factices (« loot ») déposés sur les VMs de la maquette vulnérable pour
les scénarios d'exfiltration de données. **Tout le contenu est fictif.**

## Organisation

Un sous-dossier **par VM cible**, nommé d'après la clé d'instance Terraform
(`local.vms_fixed` / `local.vms_dhcp` dans `terraform/instances.tf`). Le
provisioning (cloud-init / scp / ansible) copie `assets/<vm>/*` vers la VM
correspondante.

| Dossier | VM (`uc-<dossier>`) | IP fixe | Service hôte | Documents |
|---|---|---|---|---|
| `srv-moodle` | uc-srv-moodle | .12 | Moodle (Apache/PHP) | cours, TD, sujet d'examen, relevé de notes, dossier d'inscription |
| `web-rh` | uc-web-rh | .14 | Application RH (Apache/PHP → db-rh) | fiche RH, bulletin de paie |
| `calc-recherche` | uc-calc-recherche | .15 | Calcul recherche (NFS/Samba/Jupyter) | article, notebook, rapport labo, rapport ANR |
| `poste-dsi` | uc-poste-dsi | DHCP | Poste admin/DSI/direction | budget prévisionnel, délibération CA, export annuaire LDAP |
| `srv-mail` | uc-srv-mail | .10 | Messagerie (Postfix/Dovecot) | email DSI (identifiants VPN) |

## Notes de mapping

- **`dossier_inscription_etudiant`** → `srv-moodle` : faute de serveur scolarité
  dédié dans la maquette, les données étudiantes sont regroupées sur le serveur
  Moodle (avec les relevés de notes).
- **`export_annuaire_ldap`** → `poste-dsi` : c'est un export généré par la DSI,
  pas la base LDAP vivante. La donnée LDAP « live » de `uc-srv-ldap` est
  provisionnée séparément (slapd / LDIF), pas sous forme de fichier.
- **`email_dsi_acces_vpn_CONFIDENTIEL.pdf`** → `srv-mail` : **leurre ajouté**
  (aucun document mail n'existait). Il contient les identifiants VPN partagés
  (`campus` / `unicampus2024`, cf. architecture §5.3), créant une chaîne
  d'attaque pédagogique **mail → VPN**.

## VMs sans asset fichier

`uc-fw-legacy`, `uc-vpn-legacy` (infra, pas de données), `uc-srv-ldap` (données
dans l'annuaire vivant), `uc-db-rh` (données dans MariaDB, peuplées par SQL),
`uc-poste-etu` (poste attaquant Kali), `uc-poste-prof` (accède aux données via
Moodle).
