Ce document rassemble la documentation et les démarches effectuées et à effectuer pour un bon setup d'OpenStack avec Terraform.

[[_TOC_]]

# Terraform

Dans notre maquette il va nous falloir les `.tf` suivants :

- **`provider.tf`** : Configure le moteur Terraform pour qu'il sache comment discuter avec votre OpenStack (tout en attendant que GitLab CI lui donne les clés secrètes). Contient aussi la configuration du **backend distant** qui héberge le state.
- **`data.tf`** : Fait l'inventaire de ce qui existe déjà sur le cloud (vos images Ubuntu et Debian, ainsi que le réseau externe `ext-net`) pour pouvoir s'en servir.
- **`network.tf`** : Construit votre réseau privé isolé (`uc-net-campus`), son plan d'adressage (192.168.107.0/24) et le routeur qui le connecte à internet. Contient aussi les `port` Neutron pour les IPs fixes.
- **`security.tf`** : Met en place votre groupe de sécurité (`uc-sg-allow-all`) pour définir les règles d'ouverture des ports réseau.
- **`keypair.tf`** : Enregistre votre clé SSH personnelle dans OpenStack pour vous garantir un accès administrateur sécurisé à toutes vos futures machines.
- **`instances.tf`** : Le cœur de l'usine : c'est ici que l'on commande la création de vos serveurs et postes clients (incluant les instructions automatiques pour installer l'interface graphique des postes DSI et Prof).
- **`floating_ips.tf`** : Demande des adresses IP publiques au réseau externe et "tire les câbles" pour les brancher sur vos 4 machines exposées (Firewall, VPN, Mail, Moodle).
- **`variables.tf`** : Le panneau de contrôle qui centralise vos réglages (comme le préfixe `uc-`), vous permettant de renommer ou modifier tout le projet en changeant juste une ligne.

> Note : tous les `.tf` d'un même dossier sont lus comme un seul ensemble par Terraform. Le découpage en plusieurs fichiers est purement organisationnel — l'ordre des fichiers n'a aucune importance, c'est le graphe de dépendances entre ressources qui détermine l'ordre de création.

Dans l'ordre de conception, on procède comme suit :

### Phase 1 : Les variables et la connexion

1. **`variables.tf`**
2. **`provider.tf`** (avec le backend de state)
3. **`data.tf`**

### Phase 2 : L'environnement

1. **`network.tf`** (réseau, subnet, routeur, ports)
2. **`security.tf`**
3. **`keypair.tf`**

### Phase 3 : Les machines

1. **`instances.tf`**

### Phase 4 : L'ouverture au public

1. **`floating_ips.tf`**

---

## Gestion de la cohabitation

Pour utiliser un réseau OpenStack déjà en place, on n'utilise pas le mot-clé `resource`, mais le mot-clé `data`.

Exemple dans votre fichier `network.tf` :

```hcl
# On demande à OpenStack de trouver le réseau nommé "shared-net"
data "openstack_networking_network_v2" "reseau_existant" {
  name = "nom-du-reseau-partage" # Remplacez par le vrai nom visible sur Horizon
}

# On récupère aussi le sous-réseau associé si nécessaire
data "openstack_networking_subnet_v2" "subnet_existant" {
  network_id = data.openstack_networking_network_v2.reseau_existant.id
}
```

### Connecter votre VM à ce réseau

Une fois que Terraform a "lu" l'ID de ce réseau existant, il vous suffit de le passer en paramètre dans votre fichier `instances.tf` :

```hcl
resource "openstack_compute_instance_v2" "ma_vm" {
  name        = "jdupont-vm-01"
  image_id    = data.openstack_images_image_v2.ubuntu_2204.id
  flavor_name = "m1.small"
  key_pair    = openstack_compute_keypair_v2.uc_keypair.name

  # On branche la VM sur l'ID qu'on a récupéré via le bloc 'data'
  network {
    uuid = data.openstack_networking_network_v2.reseau_existant.id
  }
}
```

---

## Identification et `provider.tf`

URL d'authentification : `http://137.194.208.23:5000/v3/`

### Étape 1 : Générer les identifiants côté OpenStack

Comme on utilise un SSO passant par GitLab il faut setup des **Application Credentials**. C'est l'approche recommandée pour la CI : pas de mot de passe utilisateur stocké dans GitLab, et révocation possible sans casser le compte humain.

Dans Horizon : **Identity > Application Credentials**.

Remplissez les informations :

- **Name** : Donnez un nom clair pour vous en souvenir (ex: `gitlab-ci-terraform-gita`).
- **Expiration Date** : (Optionnel) C'est une bonne pratique de sécurité de mettre une date de fin, mais si vous le faites, notez bien de le renouveler dans GitLab quand il expirera.
- Laissez le reste vide/par défaut.

⚠️ **TRÈS IMPORTANT** : une fenêtre va s'afficher avec l'ID et le Secret. Gardez cette fenêtre ouverte ou copiez immédiatement le **Secret** dans un bloc-notes temporaire. Une fois cette fenêtre fermée, **vous ne pourrez plus jamais récupérer le Secret** (il faudra supprimer l'identifiant et en recréer un autre).

### Étape 2 : Ajouter les variables dans GitLab

**Settings** (Paramètres) > **CI/CD** > **Variables** > **Expand** (Développer) > **Add variable**.

| Clé (Key) | Valeur (Value) | Paramètres à cocher |
| :--- | :--- | :--- |
| `OS_AUTH_TYPE` | `v3applicationcredential` | Rien de spécial. |
| `OS_AUTH_URL` | L'URL de votre API OpenStack (ex: `http://137.194.208.23:5000/v3/`) | Rien de spécial. |
| `OS_APPLICATION_CREDENTIAL_ID` | L'ID généré à l'étape 1 | Rien de spécial. |
| `OS_APPLICATION_CREDENTIAL_SECRET` | Le Secret généré à l'étape 1 | 🚨 **Cochez impérativement "Mask variable"** (Masquer). Cochez "Protect variable" si la CI tourne sur une branche protégée (comme `main`). |

### Étape 3 : Le fichier `provider.tf`

Pour que la magie opère, il faut s'assurer que votre code Terraform ne tente pas de forcer une autre méthode de connexion. Le bloc `provider "openstack"` doit être vide : Terraform va alors lire les variables d'environnement `OS_*` injectées par GitLab CI.

```hcl
terraform {
  required_version = ">= 1.6"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4"
    }
  }

  # Backend distant pour le state — voir section dédiée
  backend "http" {}
}

# Bloc vide : Terraform lit les variables d'environnement OS_* de GitLab CI
provider "openstack" {
}
```

> **Important** : la version `~> 3.4` cible le provider de novembre 2025. Les versions 1.x sont obsolètes et ne sont plus maintenues. Une montée majeure (1 → 2 → 3) introduit des breaking changes, donc on pin sur une majeure stable.

---

## Backend de state distant

**C'est le point le plus important à régler avant de mettre la CI en route.** Sans backend distant, le fichier `terraform.tfstate` est créé sur le runner GitLab et **détruit à la fin du job**. Au deuxième `apply`, Terraform considère que rien n'existe et retente de tout créer — qui plante avec des erreurs « ressource already exists ».

Trois options possibles. Pour ce projet, **GitLab Managed Terraform State** est le plus simple : intégré, gratuit, pas de service externe à configurer.

### Option recommandée : GitLab Managed State

Dans `provider.tf`, on déclare un backend `http` qui pointera vers GitLab :

```hcl
terraform {
  backend "http" {}
}
```

Le détail de la connexion est passé via des arguments au `terraform init` dans le pipeline (voir section pipeline plus bas).

### Option alternative : backend Swift (OpenStack)

Si vous préférez héberger le state dans OpenStack lui-même :

```hcl
terraform {
  backend "swift" {
    container = "tfstate-unicampus"
    archive_container = "tfstate-unicampus-archive"
  }
}
```

L'authentification Swift utilise les mêmes variables `OS_*` que le provider, donc rien à reconfigurer côté credentials.

---

## `data.tf`

`data.tf` permet de récupérer les ressources qui existent déjà sur OpenStack.

### A. Le réseau externe (Internet / IPs publiques)

**Pourquoi** : 4 « Floating IPs » (pour le Firewall, VPN, Mail, Moodle).

```hcl
# On cherche le réseau public par son nom
data "openstack_networking_network_v2" "ext_net" {
  name = var.external_network_name
}
```

### B. Images

**Pourquoi** : pour dire à Terraform sur quoi installer vos 11 machines.

```hcl
# Image Ubuntu Serveur (nom exact à vérifier avec `openstack image list`)
data "openstack_images_image_v2" "ubuntu_2204" {
  name = "jammy-2022-12-29"
}

# Image Debian pour le firewall legacy
data "openstack_images_image_v2" "debian_10" {
  name = "debian-10"
}
```

> **Note** : `most_recent = true` n'est utile que quand le nom est partiel ou est un pattern. Avec un nom exact comme `"jammy-2022-12-29"`, il n'y a qu'une image qui matche, donc l'argument est inutile.

### C. Flavors

```hcl
data "openstack_compute_flavor_v2" "flavor_tiny" {
  name = "m1.tiny"
}

data "openstack_compute_flavor_v2" "flavor_small" {
  name = "m1.small"
}
```

### D. Réseau interne partagé (option « réseau existant »)

Si vous décidez de ne pas créer votre bulle `uc-net-campus` isolée et de vous brancher sur un réseau déjà créé par l'administrateur, ajoutez ces blocs.

```hcl
data "openstack_networking_network_v2" "reseau_partage" {
  name = "nom-du-reseau-fourni-par-admin"
}

# Sous-réseau partagé — nécessaire si on veut fixer des IPs précises
data "openstack_networking_subnet_v2" "subnet_partage" {
  name       = "nom-du-sous-reseau-fourni"
  network_id = data.openstack_networking_network_v2.reseau_partage.id
}
```

---

## `network.tf` — option « créer le réseau de zéro »

### 1. Créer le réseau

```hcl
resource "openstack_networking_network_v2" "uc_net" {
  name           = "${var.prefix}net-campus"
  admin_state_up = true
}
```

> ⚠️ `admin_state_up = true` (booléen, sans guillemets) — pas `"true"` comme une string.

### 2. Définir la plage d'adresses (le sous-réseau)

```hcl
resource "openstack_networking_subnet_v2" "uc_subnet" {
  name            = "${var.prefix}subnet-campus"
  network_id      = openstack_networking_network_v2.uc_net.id
  cidr            = var.subnet_cidr
  ip_version      = 4
  dns_nameservers = ["8.8.8.8", "1.1.1.1"]

  # Pool DHCP pour les postes clients (.100 à .200)
  # Les IPs en dehors du pool (.2 à .29) restent libres pour les ports fixes
  allocation_pool {
    start = "192.168.107.100"
    end   = "192.168.107.200"
  }
}
```

> **Pourquoi le `allocation_pool`** : sans ça, OpenStack peut allouer en DHCP n'importe quelle IP du subnet, y compris celles que vous voulez réserver pour vos serveurs. Restreindre le pool DHCP à `.100-.200` garantit que les IPs basses (`.2` à `.29`) restent disponibles pour vos `port` fixes.

### 3. Créer le routeur

```hcl
resource "openstack_networking_router_v2" "uc_router" {
  name                = "${var.prefix}router-campus"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.ext_net.id
}
```

### 4. Brancher le routeur sur le subnet

```hcl
resource "openstack_networking_router_interface_v2" "uc_router_interface" {
  router_id = openstack_networking_router_v2.uc_router.id
  subnet_id = openstack_networking_subnet_v2.uc_subnet.id
}
```

---

## `network.tf` — option « réseau existant »

Dans ce scénario, vous ne créez **aucun** réseau ni routeur. Votre fichier `network.tf` ne servira qu'à réserver des adresses IP fixes via des `port` Neutron.

*(Rappel : cela nécessite que votre `data.tf` ait déjà trouvé le `reseau_partage` et le `subnet_partage`.)*

### Réserver une IP fixe (le `port`)

Un `port` Neutron est l'équivalent virtuel d'une carte réseau. En le créant explicitement avec une IP, on fixe l'adresse au lieu de subir le DHCP.

À répéter pour chaque serveur nécessitant une IP précise (Mail, DB, etc.).

```hcl
resource "openstack_networking_port_v2" "port_mail" {
  name           = "${var.prefix}port-mail"
  network_id     = data.openstack_networking_network_v2.reseau_partage.id
  admin_state_up = true

  # ⚠️ Le security group s'applique sur le PORT, pas sur l'instance
  # (voir explication dans la section security.tf)
  security_group_ids = [openstack_networking_secgroup_v2.uc_sg_allow_all.id]

  fixed_ip {
    subnet_id  = data.openstack_networking_subnet_v2.subnet_partage.id
    ip_address = "192.168.107.10"
  }
}
```

> **Note importante sur le placement du security group** : quand on utilise un `port` explicite, le SG **doit** être déclaré sur le port via `security_group_ids` (et **pas** sur l'instance via `security_groups`). Si vous mettez les deux, le provider Terraform peut renvoyer un warning et le comportement effectif dépend de la version.

---

## `security.tf`

Ce fichier définit les Security Groups d'OpenStack : les règles de pare-feu qu'OpenStack applique directement aux machines virtuelles. Dans notre cas on veut que ce soit notre pare-feu créé (`uc-fw-legacy`) qui agisse, donc on doit faire en sorte que le pare-feu d'OpenStack laisse tout passer.

### 1. Création du groupe de sécurité

```hcl
resource "openstack_networking_secgroup_v2" "uc_sg_allow_all" {
  name        = "${var.prefix}sg-allow-all"
  description = "Groupe de securite permissif pour delegation au fw-legacy"
}
```

### 2. Définir les règles entrantes (Ingress)

Par défaut, OpenStack bloque tout ce qui entre. Il faut donc explicitement créer des règles pour ouvrir les portes : TCP, UDP et ICMP.

```hcl
# Tout TCP entrant
resource "openstack_networking_secgroup_rule_v2" "allow_all_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.uc_sg_allow_all.id
}

# Tout UDP entrant
resource "openstack_networking_secgroup_rule_v2" "allow_all_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.uc_sg_allow_all.id
}

# ICMP (ping)
resource "openstack_networking_secgroup_rule_v2" "allow_icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.uc_sg_allow_all.id
}
```

> **Note sur l'Egress** : OpenStack autorise nativement tout le trafic sortant par défaut lors de la création d'un security group. Pas besoin de règle explicite.

### 3. Comment appliquer le SG : règle d'or

Il y a **deux endroits possibles** pour attacher un security group, et il faut en choisir **un seul** par VM :

**Cas A : VM avec port explicite** → SG sur le port
```hcl
resource "openstack_networking_port_v2" "port_mail" {
  # ...
  security_group_ids = [openstack_networking_secgroup_v2.uc_sg_allow_all.id]
}

resource "openstack_compute_instance_v2" "uc_srv_mail" {
  # PAS de security_groups ici quand on utilise un port
  network {
    port = openstack_networking_port_v2.port_mail.id
  }
}
```

**Cas B : VM en DHCP (sans port explicite)** → SG sur l'instance
```hcl
resource "openstack_compute_instance_v2" "uc_poste_etu" {
  # ...
  security_groups = [openstack_networking_secgroup_v2.uc_sg_allow_all.name]

  network {
    uuid = openstack_networking_network_v2.uc_net.id
  }
}
```

Dans la maquette UniCampus+, les **serveurs** ont des IPs fixes (donc cas A), les **postes clients** sont en DHCP (donc cas B).

---

## `keypair.tf`

### 1. Déclaration de la clé

```hcl
resource "openstack_compute_keypair_v2" "uc_keypair" {
  name       = "${var.prefix}keypair-admin"
  public_key = var.ssh_public_key
}
```

> **Pourquoi via une variable et pas `file("~/.ssh/id_rsa.pub")`** : le runner GitLab CI n'a pas de `~/.ssh/`. La clé publique doit être passée via la variable `TF_VAR_ssh_public_key` configurée dans GitLab CI/CD > Variables. En local sur votre poste, vous pouvez la mettre dans un fichier `terraform.tfvars` ignoré par Git.

### 2. Variante : utiliser une clé déjà présente

Si vous avez déjà importé votre clé manuellement via Horizon et que vous voulez juste que Terraform l'utilise sans la gérer :

```hcl
data "openstack_compute_keypair_v2" "kp_existante" {
  name = "mon-access-sso"
}
```

### 3. Comment l'utiliser (dans `instances.tf`)

Dans la définition de vos VMs, vous indiquez le nom de la clé à injecter au démarrage :

```hcl
resource "openstack_compute_instance_v2" "uc_srv_mail" {
  # ...
  key_pair = openstack_compute_keypair_v2.uc_keypair.name
}
```

---

## `instances.tf`

Une instance Terraform OpenStack se décompose en 4 blocs logiques.

### 1. Identité (nom, OS, puissance)

Donner un nom unique (avec votre préfixe `uc-`), une taille (flavor) et une image système.

```hcl
resource "openstack_compute_instance_v2" "uc_srv_moodle" {
  name        = "${var.prefix}srv-moodle"
  flavor_name = "m1.small"
  image_id    = data.openstack_images_image_v2.ubuntu_2204.id
```

> **Cohérence `image_id` vs `image_name`** : une fois qu'un data source existe, on utilise systématiquement son `.id`. Le `name` peut matcher plusieurs images si l'admin met à jour la liste.

### 2. Sécurité et accès

Injecter la clé SSH. Pour le SG, voir la règle d'or de la section `security.tf` : sur le port si on en utilise un, sur l'instance sinon.

```hcl
  key_pair = openstack_compute_keypair_v2.uc_keypair.name
```

### 3. Branchement réseau

**Cas A : IP fixe via un port** (pour les serveurs)
```hcl
  network {
    port = openstack_networking_port_v2.port_moodle.id
  }
}
```

**Cas B : IP dynamique en DHCP** (pour les postes clients)
```hcl
  security_groups = [openstack_networking_secgroup_v2.uc_sg_allow_all.name]

  network {
    uuid = openstack_networking_network_v2.uc_net.id
  }
}
```

### 4. Automatisation au boot (cloud-init)

Pour les postes Prof et DSI, vous partez d'une image Ubuntu Serveur et installez l'environnement graphique au premier boot via `user_data`.

```hcl
resource "openstack_compute_instance_v2" "uc_poste_prof" {
  name        = "${var.prefix}poste-prof"
  flavor_name = "m1.small"  # m1.tiny (1 Go RAM) trop juste pour un desktop
  image_id    = data.openstack_images_image_v2.ubuntu_2204.id
  key_pair    = openstack_compute_keypair_v2.uc_keypair.name

  security_groups = [openstack_networking_secgroup_v2.uc_sg_allow_all.name]

  network {
    uuid = openstack_networking_network_v2.uc_net.id
  }

  # Format cloud-config (YAML) — plus déclaratif que du shell brut
  user_data = <<-EOF
    #cloud-config
    package_update: true
    package_upgrade: false
    packages:
      - xfce4
      - xfce4-goodies
      - lightdm
    runcmd:
      - systemctl set-default graphical.target
      - systemctl enable lightdm
  EOF
}
```

> **Choix de l'environnement graphique** : `ubuntu-desktop` complet pèse plusieurs Go et prend 10-15 minutes à installer, ce qui peut faire timeout cloud-init. Sur une `m1.tiny` (1 Go RAM), ça plante. Solutions : passer en `m1.small` (2 Go), ou utiliser un environnement léger comme XFCE/LXQt comme ci-dessus.

### Astuce : factorisation avec `for_each`

Vu qu'il y a 11 VMs avec des paramètres similaires, copier-coller le bloc 11 fois est pénible à maintenir. Une `local` map + un seul bloc `for_each` permet d'ajouter/retirer une VM en une ligne :

```hcl
locals {
  servers = {
    "srv-mail"   = { flavor = "m1.tiny",  ip = "192.168.107.10", floating = true }
    "srv-ldap"   = { flavor = "m1.tiny",  ip = "192.168.107.11", floating = false }
    "srv-moodle" = { flavor = "m1.small", ip = "192.168.107.12", floating = true }
    "web-rh"     = { flavor = "m1.tiny",  ip = "192.168.107.14", floating = false }
    "db-rh"      = { flavor = "m1.tiny",  ip = "192.168.107.20", floating = false }
    # ... etc
  }
}

resource "openstack_networking_port_v2" "server" {
  for_each = local.servers

  name               = "${var.prefix}port-${each.key}"
  network_id         = openstack_networking_network_v2.uc_net.id
  security_group_ids = [openstack_networking_secgroup_v2.uc_sg_allow_all.id]

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.uc_subnet.id
    ip_address = each.value.ip
  }
}

resource "openstack_compute_instance_v2" "server" {
  for_each = local.servers

  name        = "${var.prefix}${each.key}"
  flavor_name = each.value.flavor
  image_id    = data.openstack_images_image_v2.ubuntu_2204.id
  key_pair    = openstack_compute_keypair_v2.uc_keypair.name

  network {
    port = openstack_networking_port_v2.server[each.key].id
  }
}
```

À considérer si vous avez le temps : c'est un investissement initial qui paie vite.

---

## `floating_ips.tf`

On cherche à donner des adresses publiques à 4 machines : firewall, VPN, mail, Moodle.

### 1. L'allocation (réserver l'adresse)

```hcl
resource "openstack_networking_floatingip_v2" "fip_mail" {
  pool = data.openstack_networking_network_v2.ext_net.name
}
```

À ce stade, l'IP est réservée mais ne va nulle part. Elle « flotte » dans votre projet.

### 2. L'association (brancher l'IP sur le port)

Quand on utilise des ports explicites (cas typique de la maquette), il est plus précis d'associer la floating IP au **port** plutôt qu'à l'instance. Le port est plus stable que l'instance et survit à un remplacement.

```hcl
resource "openstack_networking_floatingip_associate_v2" "fip_assoc_mail" {
  floating_ip = openstack_networking_floatingip_v2.fip_mail.address
  port_id     = openstack_networking_port_v2.port_mail.id
}
```

### Variante : association à l'instance

Si la VM n'utilise pas de port explicite (cas DHCP), on peut associer à l'instance :

```hcl
resource "openstack_compute_floatingip_associate_v2" "fip_assoc_mail" {
  floating_ip = openstack_networking_floatingip_v2.fip_mail.address
  instance_id = openstack_compute_instance_v2.uc_srv_mail.id
}
```

> Note : ce sont **deux ressources différentes**. `openstack_networking_floatingip_associate_v2` (sur port) et `openstack_compute_floatingip_associate_v2` (sur instance). Choisir selon le cas.

---

## `variables.tf`

Le fichier `variables.tf` permet de centraliser les réglages comme le préfixe, le nom du réseau externe ou les plages d'IP.

### 1. Déclarer les variables

```hcl
variable "prefix" {
  type        = string
  description = "Préfixe à ajouter devant le nom de chaque ressource"
  default     = "uc-"
}

variable "external_network_name" {
  type        = string
  description = "Nom du réseau public pour les IPs flottantes"
  default     = "ext-net"
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR du sous-réseau interne"
  default     = "192.168.107.0/24"
}

variable "ssh_public_key" {
  type        = string
  description = "Clé SSH publique injectée dans les VMs"
  sensitive   = false
  # Pas de default : injectée via TF_VAR_ssh_public_key dans la CI
  # ou via terraform.tfvars en local
}
```

### 2. Utiliser les variables

Syntaxe : `var.nom_de_la_variable`.

```hcl
resource "openstack_networking_network_v2" "uc_net" {
  name = "${var.prefix}net-campus"
}

resource "openstack_networking_subnet_v2" "uc_subnet" {
  name       = "${var.prefix}subnet-campus"
  network_id = openstack_networking_network_v2.uc_net.id
  cidr       = var.subnet_cidr
  ip_version = 4
}
```

### 3. Surcharger les variables

Sans toucher au code, vous pouvez créer une variable d'environnement `TF_VAR_prefix` dans GitLab CI avec la valeur `examen-`. Au prochain pipeline, toutes vos machines seront nommées `examen-srv-mail`, `examen-fw-legacy`, etc.

C'est aussi le mécanisme pour passer la clé SSH : variable GitLab `TF_VAR_ssh_public_key` avec votre clé publique en valeur.

---

## Bonnes pratiques de versioning Git

### `.gitignore`

À créer **dès le début**, sinon le state local et les caches finissent dans Git :

```
# State Terraform — ne JAMAIS commiter (contient des secrets)
*.tfstate
*.tfstate.backup
*.tfstate.*.backup

# Cache local du init
.terraform/

# Plans sauvegardés
*.tfplan

# Variables avec valeurs secrètes
*.auto.tfvars
secrets.tfvars
terraform.tfvars
```

### `.terraform.lock.hcl` : à commiter

Ce fichier est généré par `terraform init` et fige les versions exactes de providers téléchargées. **Il doit être commité** pour que toute l'équipe et la CI utilisent les mêmes versions. C'est l'équivalent du `package-lock.json` en Node.

---

## Pipeline GitLab

Référence : https://spacelift.io/blog/gitlab-terraform

On crée un fichier `.gitlab-ci.yml` qui définit le pipeline. Le pattern recommandé est de séparer `validate`, `plan` et `apply`, avec :

- `validate` et `plan` qui tournent automatiquement à chaque MR pour permettre la revue
- `apply` manuel sur la branche `main` après merge

### Fichier `.gitlab-ci.yml` complet

```yaml
image:
  name: hashicorp/terraform:1.9
  entrypoint: [""]

variables:
  TF_ROOT: ${CI_PROJECT_DIR}/terraform
  TF_STATE_NAME: unicampus-prod
  # URL pour le backend GitLab Managed State
  TF_ADDRESS: ${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${TF_STATE_NAME}

cache:
  key: "${TF_STATE_NAME}"
  paths:
    - ${TF_ROOT}/.terraform/

before_script:
  - cd ${TF_ROOT}
  - terraform --version
  - terraform init
      -backend-config="address=${TF_ADDRESS}"
      -backend-config="lock_address=${TF_ADDRESS}/lock"
      -backend-config="unlock_address=${TF_ADDRESS}/lock"
      -backend-config="username=gitlab-ci-token"
      -backend-config="password=${CI_JOB_TOKEN}"
      -backend-config="lock_method=POST"
      -backend-config="unlock_method=DELETE"
      -backend-config="retry_wait_min=5"

stages:
  - validate
  - plan
  - apply

validate:
  stage: validate
  script:
    - terraform fmt -check
    - terraform validate

plan:
  stage: plan
  script:
    - terraform plan -out=plan.tfplan
  artifacts:
    paths:
      - ${TF_ROOT}/plan.tfplan
    expire_in: 1 week

apply:
  stage: apply
  script:
    - terraform apply -auto-approve plan.tfplan
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
      changes:
        - "terraform/**/*"
      when: manual
  dependencies:
    - plan
```

### Pourquoi cette structure

- **`validate`** vérifie le formatage et la syntaxe — rapide, sans contact avec OpenStack.
- **`plan`** génère et sauvegarde le plan en artefact. Vous (ou un relecteur) pouvez le télécharger et le relire avant validation.
- **`apply`** consomme l'artefact `plan.tfplan` produit par le job précédent. Garantit qu'on applique exactement ce qui a été revu, pas une version recalculée.
- **`when: manual`** sur `apply` impose un clic humain sur GitLab avant le déploiement. Sécurité de base contre les apply accidentels.
- **`changes`** limite le déclenchement aux modifications du dossier `terraform/`.

### Variables GitLab à configurer

Dans **Settings > CI/CD > Variables** :

| Clé | Valeur | Cocher |
|---|---|---|
| `OS_AUTH_TYPE` | `v3applicationcredential` | — |
| `OS_AUTH_URL` | `http://137.194.208.23:5000/v3/` | — |
| `OS_APPLICATION_CREDENTIAL_ID` | (depuis Horizon) | — |
| `OS_APPLICATION_CREDENTIAL_SECRET` | (depuis Horizon) | 🚨 Mask + Protect |
| `TF_VAR_ssh_public_key` | Votre clé publique SSH (`ssh-ed25519 AAAA…`) | — |