# Terraform — maquette UniCampus+ (volontairement vulnérable)

Déploiement OpenStack de la maquette : réseau, 11 VMs, security group permissif,
floating IPs. Le **provisioning logiciel des services est désormais fait par
Ansible** (cf. [`../ansible/`](../ansible/)) ; Terraform ne fournit plus qu'un
**cloud-init minimal** (hostname, python3, et pour fw-legacy le bring-up réseau).

> ⚠️ Cette maquette est **volontairement vulnérable** (services en clair, mots de
> passe faibles, partages ouverts…) à des fins pédagogiques d'analyse de risques.
> À déployer uniquement sur le sous-réseau isolé du groupe.

## Structure

| Fichier | Rôle |
|---|---|
| `provider.tf` | Providers (openstack, cloudinit) + backend HTTP GitLab |
| `variables.tf` | Variables paramétrables |
| `data.tf` | Images, flavors, réseau externe |
| `network.tf` | Réseau, subnet, routeur, ports Neutron à IP fixe |
| `security.tf` | Security group `uc-sg-allow-all` |
| `keypair.tf` | Keypair admin (clé publique du groupe) |
| `instances.tf` | 11 instances (8 IP fixe + 3 postes DHCP), `user_data` minimal |
| `floating_ips.tf` | 4 floating IPs (fw, vpn, mail, moodle) + outputs (FIP moodle/fw-legacy) |
| `cloudinit.tf` | `user_data` **minimal** par VM (hostname + python3 ; bring-up réseau fw-legacy) |
| `siem.tf` | Réseau SOC + VM SIEM (lot Supervision v2) |

## Provisioning

Le provisioning logiciel (paquets, config des services, comptes, leurres) est
réalisé par **Ansible** — cf. [`../ansible/README.md`](../ansible/README.md). Le
`user_data` construit dans `cloudinit.tf` est réduit au strict nécessaire pour
qu'Ansible puisse se connecter :

- **VMs Ubuntu** : hostname (`uc-<vm>`) + garantie d'un `python3`.
- **fw-legacy (Debian 10)** : bring-up réseau minimal (route par défaut côté DMZ
  + persistance dhclient), pour que sa Floating IP réponde et que les VMs internes
  soient atteintes par rebond. La politique pare-feu complète (forwarding, NAT,
  DNAT, alias DMZ) est jouée par le rôle Ansible `fw_legacy`.

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
