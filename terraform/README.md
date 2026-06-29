# Terraform — maquette UniCampus+ (V2 segmentée)

Déploiement OpenStack de la maquette : **réseau segmenté en VLAN** (cf.
[`../docs/V2/network.md`](../docs/V2/network.md)), VMs, floating IPs. Le
**provisioning logiciel des services est fait par Ansible**
(cf. [`../ansible/`](../ansible/)) ; Terraform ne fournit qu'un **cloud-init
minimal** (hostname, python3, et pour le firewall le bring-up réseau).

> ⚠️ Les **services** restent **volontairement vulnérables** (clair, mots de
> passe faibles, partages ouverts…) à des fins pédagogiques. La V2 ajoute la
> **segmentation réseau + un firewall central filtrant** comme remédiation.
> À déployer uniquement sur le sous-réseau isolé du groupe (préfixe `uc-`).

## Topologie segmentée

7 VLAN internes, un par zone métier ; le **firewall central `uc-srv-firewall`**
en est la **gateway** (`.254`) — tout l'inter-VLAN le traverse (filtrage). Un
réseau de **transit** (`192.168.108.0/24`) le relie au routeur Neutron (egress +
FIP). Le SOC (`uc-net-soc`, cf. `siem.tf`) est joint via des routes statiques.

| VLAN | CIDR | Hôtes |
|---|---|---|
| `uc-net-user` | 192.168.101.0/24 | poste-etu `.1`, poste-prof `.2` |
| `uc-net-recherche` | 192.168.102.0/24 | calc-recherche `.1` |
| `uc-net-admin` | 192.168.103.0/24 | poste-dsi `.1` (bastion `.2`, V2/IAM) |
| `uc-net-rh` | 192.168.104.0/24 | ldap `.1`, web-rh `.2`, db-rh `.3` |
| `uc-net-mail` | 192.168.105.0/24 | srv-mail `.1` |
| `uc-net-vpn` | 192.168.106.0/24 | vpn-legacy `.1` |
| `uc-net-dmz` | 192.168.107.0/24 | moodle `.1` (roundcube `.2`, sso `.3`, V2/IAM) |
| `uc-net-transit` | 192.168.108.0/24 | firewall `.1`, routeur Neutron `.254` |
| `uc-net-soc` | 192.168.109.0/24 | SIEM `.1` (cf. `siem.tf`) |

## Structure

| Fichier | Rôle |
|---|---|
| `provider.tf` | Providers (openstack, cloudinit) + backend HTTP GitLab |
| `variables.tf` | Variables paramétrables |
| `data.tf` | Images, flavors, réseau externe |
| `network.tf` | VLAN segmentés + transit + routeur Neutron (routes statiques) + ports |
| `security.tf` | Security group `uc-sg-allow-all` (non attaché) |
| `keypair.tf` | Keypair admin (clé publique du groupe) |
| `instances.tf` | 10 VMs métier + firewall central multi-homed, `user_data` minimal |
| `floating_ips.tf` | FIP firewall + services (DNAT) + outputs (FIP moodle/firewall) |
| `cloudinit.tf` | `user_data` **minimal** par VM (hostname + python3 ; route transit du firewall) |
| `siem.tf` | Réseau SOC + VM SIEM (lot Supervision v2) |

## Provisioning

Le provisioning logiciel (paquets, config des services, comptes, leurres,
politique pare-feu) est réalisé par **Ansible** — cf.
[`../ansible/README.md`](../ansible/README.md). Le `user_data` (`cloudinit.tf`)
est réduit au strict nécessaire pour qu'Ansible se connecte :

- **VMs Ubuntu** : hostname (`uc-<vm>`) + garantie d'un `python3`.
- **firewall central** : bring-up réseau minimal (route par défaut côté transit
  + persistance), pour que sa Floating IP réponde et que les VMs internes soient
  atteintes par rebond. Forwarding, NAT, DNAT et **politique inter-VLAN** (DROP
  par défaut, conforme RBAC IAM) sont joués par le rôle Ansible `fw_central`.

Pour modifier la conf d'un service, éditer son rôle sous `../ansible/roles/` et
rejouer le playbook (idempotent) — sans recréer la VM.

## Variables CI/CD à définir dans GitLab

*(Settings → CI/CD → Variables. Cocher « Masked » pour les secrets. Les variables
« Protected » ne sont visibles que sur les branches protégées : décocher
« Protected » si `develop` ne l'est pas.)*

### Authentification OpenStack (lue automatiquement par le provider)

Option mot de passe :

| Variable | Exemple |
|---|---|
| `OS_AUTH_URL` | `https://openstack.exemple.fr:5000/v3` |
| `OS_USERNAME` | login |
| `OS_PASSWORD` | *(masked)* |
| `OS_PROJECT_NAME` | nom du projet |
| `OS_USER_DOMAIN_NAME` | `Default` |
| `OS_PROJECT_DOMAIN_NAME` | `Default` |
| `OS_REGION_NAME` | `RegionOne` |

Option Application Credentials (recommandé) : `OS_AUTH_URL`,
`OS_AUTH_TYPE=v3applicationcredential`, `OS_APPLICATION_CREDENTIAL_ID`,
`OS_APPLICATION_CREDENTIAL_SECRET` *(masked)*, `OS_REGION_NAME`.

### Variables Terraform

| Variable | Rôle |
|---|---|
| `TF_VAR_ssh_public_key` | Clé publique SSH du groupe (injectée dans la keypair admin) |
| `TF_VAR_external_network_name` | Nom réel du réseau externe (défaut `provider`, à vérifier sur Horizon) |

## Pipeline

- `terraform_check` (toutes branches) : `init -backend=false`, `fmt -check`, `validate`
- `terraform_plan` (develop/main/MR) : `plan` (nécessite les variables ci-dessus)
- `terraform_apply` (develop/main, **manuel**) : `apply`

## Usage local

```sh
cd terraform
terraform init -backend=false   # validation hors-ligne
terraform fmt -check
terraform validate
```
