    Ce document va rassembler les choses importantes concernant la migration
Comme on part du paradygme que l'on fait une migration d'une V1 déjà existante on ex^plique dans ce document certaines problématique et scénario rencontrés pour les documenter et expliquer nos choix 

## Migration du provisioning : cloud-init → Ansible

### Pourquoi

La V1 provisionnait ses VM via des **scripts cloud-init bruts** injectés en
`user_data` (`terraform/scripts/*.sh`). Limites : exécution **one-shot** au
premier boot, **non idempotents**, **non rejouables** sans recréer la VM, aucune
**vue d'inventaire**. Pour gérer des systèmes plus complexes (et préparer la V2),
on bascule le modèle de gestion vers **Ansible**.

### Cadrage

Ansible est ici l'outil de **déploiement de la modélisation** (construction de la
maquette pédagogique), **pas** l'outil d'administration du SI modélisé. Il déploie
donc **tous** les éléments V1 — y compris les **postes BYOD** : le caractère « non
administré » de ces postes reste *modélisé* dans la config produite (pas d'agent
Wazuh, cf. `[postes_byod]`), mais l'outil de déploiement de la maquette les
provisionne quand même.

Répartition des responsabilités :

- **Terraform** = infrastructure (VM, réseau, FIP) + cloud-init **minimal**
  (hostname/python ; route par défaut de fw-legacy).
- **Ansible** = provisioning logiciel **idempotent** et rejouable (cf.
  [`../../ansible/README.md`](../../ansible/README.md)).

### Correspondance script → rôle

| Script V1 (`terraform/scripts/`) | Rôle Ansible (`ansible/roles/`) |
|---|---|
| `_bootstrap.sh` (SSH password auth) | `common` |
| blocs `useradd`/`chpasswd`/sudoers (dupliqués) | `maquette_accounts` (data-driven) |
| dépôt PDF base64 en `user_data` | `loot` (data-driven, `copy` depuis `assets/`) |
| `fw-legacy.sh` | `fw_legacy` |
| `vpn-legacy.sh` | `vpn_legacy` |
| `srv-ldap.sh` | `srv_ldap` |
| `srv-mail.sh` | `srv_mail` |
| `srv-moodle.sh` | `srv_moodle` |
| `web-rh.sh` | `web_rh` |
| `db-rh.sh` | `db_rh` |
| `calc-recherche.sh` | `calc_recherche` |
| `poste-{etu,prof,dsi}.sh` | `poste` (paramétré par host_vars) |

Les **vulnérabilités volontaires** sont préservées à l'identique (LDAP bind
anonyme, MariaDB `0.0.0.0` + root distant, SQLi du portail RH, relais SMTP ouvert,
NFS `no_root_squash`, Samba guest, Jupyter sans token, PPTP/MPPE, cred-reuse).

### Problématique d'ordonnancement (chicken-and-egg fw-legacy)

Toutes les VM ont **fw-legacy comme passerelle** : tant qu'il n'a pas activé le
forwarding + NAT, les autres VM n'ont pas d'accès Internet (leurs `apt-get`
échouent). Le playbook `provision.yml` provisionne donc **fw-legacy en premier**,
puis les services, puis les postes. Le rebond SSH (`ProxyJump`) des VM internes se
fait via la Floating IP de fw-legacy (topologie flat).