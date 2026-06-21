# Lot Supervision — Provisioning Ansible (SIEM Wazuh + IDS/IPS Suricata)

Ce dossier provisionne la **supervision** de la maquette V2 :

| Composant | Hôte | Rôle Ansible |
|---|---|---|
| Wazuh all-in-one (manager + indexer + dashboard) | `uc-srv-siem` (VLAN SOC) | `wazuh_manager` |
| Sonde réseau Suricata (IDS/IPS inline) | firewall central | `suricata_ids` |
| Agents Wazuh (HIDS + collecte de logs) | tous les serveurs & postes | `wazuh_agent` |

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

```bash
cd ansible/

# 1. Générer l'inventaire avec la vraie Floating IP du SIEM (depuis Terraform)
TF_DIR=../terraform scripts/gen-inventory.sh \
    inventory/hosts.ini inventory/hosts.generated.ini

# 2. Lancer le déploiement complet (topologie segmentée)
ansible-playbook -i inventory/hosts.generated.ini site.yml \
    -e ssh_jump_host="ubuntu@<FIP_bastion>"

# Variante topologie « flat » (develop, avant segmentation) :
#   - déployer le SIEM avec siem_attach_campus=true (terraform)
#   - utiliser l'inventaire flat et le rebond via fw-legacy
ansible-playbook -i inventory/hosts.flat.ini site.yml \
    -e ssh_jump_host="ubuntu@<FIP_fw-legacy>"
```

Jouer une partie seulement :

```bash
ansible-playbook -i inventory/hosts.generated.ini site.yml --tags siem
ansible-playbook -i inventory/hosts.generated.ini site.yml --tags ids
ansible-playbook -i inventory/hosts.generated.ini site.yml --tags agents
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
