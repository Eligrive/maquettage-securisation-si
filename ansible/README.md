# Provisioning Ansible — maquette UniCampus+

Ansible est l'outil de **déploiement de la modélisation** (construction de la
maquette pédagogique volontairement vulnérable), **pas** l'outil d'administration
du SI modélisé. Ce dossier couvre **deux lots** :

1. **Base maquette v1** (`provision.yml`) — provisioning applicatif des éléments
   V1, migré des anciens scripts cloud-init (`terraform/scripts/*.sh`) :

   | Composant | Hôte | Rôle Ansible |
   |---|---|---|
   | Pare-feu périmétrique (iptables NAT/DNAT) | `uc-fw-legacy` | `fw_legacy` |
   | Annuaire OpenLDAP | `uc-srv-ldap` | `srv_ldap` |
   | Messagerie Postfix/Dovecot | `uc-srv-mail` | `srv_mail` |
   | LMS Moodle (Apache/PHP/MariaDB) | `uc-srv-moodle` | `srv_moodle` |
   | Portail RH (Apache/PHP, SQLi) | `uc-web-rh` | `web_rh` |
   | Base RH MariaDB | `uc-db-rh` | `db_rh` |
   | Calcul recherche (NFS/Samba/PostgreSQL/Jupyter) | `uc-calc-recherche` | `calc_recherche` |
   | VPN PPTP | `uc-vpn-legacy` | `vpn_legacy` |
   | Postes étudiant / prof / DSI | `uc-poste-*` | `poste` |
   | Comptes cred-reuse + leurres PDF (transverses) | (selon hôte) | `common`, `maquette_accounts`, `loot` |

2. **Supervision v2** (`supervision.yml`) — SIEM Wazuh + IDS/IPS Suricata :

   | Composant | Hôte | Rôle Ansible |
   |---|---|---|
   | Wazuh all-in-one (manager + indexer + dashboard) | `uc-srv-siem` (VLAN SOC) | `wazuh_manager` |
   | Sonde réseau Suricata (IDS/IPS inline) | firewall central | `suricata_ids` |
   | Agents Wazuh (HIDS + collecte de logs) | tous les serveurs & postes | `wazuh_agent` |

`site.yml` enchaîne les deux : **`provision.yml` puis `supervision.yml`** (la
maquette doit exister avant qu'on y installe les agents).

> Rappel : les **postes BYOD** sont *déployés* par Ansible (outil de construction
> de la maquette) mais restent *modélisés* comme « non administrés » dans le SI
> simulé — aucun agent Wazuh ne s'y exécute (cf. groupe `[postes_byod]`).

## Pourquoi Ansible plutôt que les scripts cloud-init ?

Les scripts `terraform/scripts/*.sh` injectés en `user_data` ont des limites : ils
ne tournent **qu'une fois au premier boot**, ne sont **pas idempotents**, ne se
**réexécutent pas** sans recréer la VM, et n'ont aucune **vue d'inventaire**
(impossible de dire « installe l'agent partout sauf X »). Ansible corrige tout
ça : exécution répétable, pilotée par l'inventaire, fan-out multi-hôtes, et
reconfiguration sans redéploiement. Terraform reste responsable de
**l'infrastructure** (VM, réseau SOC, FIP) ; Ansible du **provisioning logiciel**.

## Pré-requis

- `ansible-core` ≥ 2.14 sur le control node (Linux/WSL/macOS — pas Windows natif).
- La **clé privée SSH** correspondant à `var.ssh_public_key` (Terraform) chargée
  dans l'agent SSH (ou via `--private-key`).
- Accès réseau aux VMs :
  - le **SIEM** est joint par sa **Floating IP** ;
  - les autres VMs (sans FIP) sont atteintes par **rebond SSH** via le bastion
    (segmenté) ou la FIP de `fw-legacy` (flat) → variable `ssh_jump_host`.

## Exécution locale

Topologie déployable aujourd'hui = **flat** (campus 192.168.107.0/24, fw-legacy
périmétrique). Le rebond SSH se fait par la Floating IP de fw-legacy.

```bash
cd ansible/

# 1. Générer l'inventaire avec la vraie Floating IP du SIEM (depuis Terraform)
TF_DIR=../terraform scripts/gen-inventory.sh \
    inventory/hosts.flat.ini inventory/hosts.generated.ini

# 2. Déploiement COMPLET : base maquette v1 puis supervision (site.yml)
ansible-playbook -i inventory/hosts.generated.ini site.yml \
    -e ssh_jump_host="ubuntu@<FIP_fw-legacy>" \
    -e moodle_wwwroot="http://<FIP_moodle>"
#   (FIP via `terraform -chdir=../terraform output -raw fw_legacy_floating_ip`
#    et `... moodle_floating_ip`. En flat, déployer le SIEM avec
#    siem_attach_campus=true pour qu'il écoute côté campus.)
```

Jouer un seul lot, ou un seul service (tags) :

```bash
# Lots
ansible-playbook -i inventory/hosts.generated.ini provision.yml   ...   # base v1
ansible-playbook -i inventory/hosts.generated.ini supervision.yml ...   # SIEM/IDS

# Services de la base v1
ansible-playbook ... site.yml --tags fw       # pare-feu fw-legacy
ansible-playbook ... site.yml --tags ldap     # (idem : mail|db-rh|web-rh|moodle|calc|vpn|postes)

# Supervision
ansible-playbook ... site.yml --tags siem     # (idem : ids|agents)
```

## Accès au dashboard

Après le rôle `wazuh_manager`, les identifiants générés sont rapatriés dans
`ansible/.wazuh-credentials/uc-srv-siem-wazuh-passwords.txt` (ignoré par git).
Dashboard : `https://<FIP_SIEM>` — utilisateur `admin`.

> En cible V2, le dashboard ne doit PAS être exposé sur Internet : l'accès se
> fait depuis le VLAN admin / via le bastion ou le VPN. La Floating IP sert au
> bootstrap et à la démo (cf. `siem_expose_fip` dans `terraform/siem.tf`).

## Choix agent vs syslog

- **Agent Wazuh** partout où l'on maîtrise l'hôte (toutes les VMs Linux) : il
  apporte la collecte de logs **et** l'intégrité de fichiers (FIM), le contrôle
  de configuration (SCA), la détection de rootkits et la réponse active. C'est
  supérieur au simple syslog.
- **Syslog distant** (port 514 sur le manager) : conservé comme **filet** pour
  les équipements qui ne peuvent pas héberger d'agent (appliances réseau).

## Règles firewall requises

Le forwarding des logs traverse le firewall central. Les règles à ajouter dans
le lot pare-feu sont décrites dans [`docs/V2/Supervision.md`](../docs/V2/Supervision.md)
et fournies prêtes à l'emploi dans
[`docs/V2/firewall-siem.rules.sh`](../docs/V2/firewall-siem.rules.sh).
