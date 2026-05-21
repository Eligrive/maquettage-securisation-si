# Terraform — maquette UniCampus+ (volontairement vulnérable)

Déploiement OpenStack de la maquette : réseau, 11 VMs, security group permissif,
floating IPs, et **provisioning des services via cloud-init**.

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
| `instances.tf` | 11 instances (8 IP fixe + 3 postes DHCP), `user_data` cloud-init |
| `floating_ips.tf` | 4 floating IPs (fw, vpn, mail, moodle) |
| `cloudinit.tf` | Assemble par VM : assets (`/opt/loot`) + `scripts/<vm>.sh` |
| `scripts/<vm>.sh` | Script de configuration isolé, un par VM |

## Provisioning (cloud-init)

Chaque instance reçoit un `user_data` multipart construit dans `cloudinit.tf` :

1. **Assets** — les PDF leurres de `../assets/<vm>/` sont déposés dans `/opt/loot`
   sur la VM (cloud-config `write_files`, base64, sans dépendance réseau).
2. **Configuration** — le script `scripts/<vm>.sh` installe et configure les
   services (cf. `docs/architecture-technique.md` §4–§6).

Pour modifier la conf d'un service, éditer son `scripts/<vm>.sh` : aucun autre
fichier Terraform à toucher.

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
