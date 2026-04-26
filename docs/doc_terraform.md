    Ce document rassemble la documentation et les démarches effectuées et à effectuer pour un bon setup d'openstack avec terraform 

# Terraform
Dans notre maquette il va nous falloir les .tf suivants : 


* **`provider.tf`** : Configure le moteur Terraform pour qu'il sache comment discuter avec votre OpenStack (tout en attendant que GitLab CI lui donne les clés secrètes).
* **`data.tf`** : Fait l'inventaire de ce qui existe déjà sur le cloud (vos images Ubuntu et Debian, ainsi que le réseau externe `ext-net`) pour pouvoir s'en servir.
* **`network.tf`** : Construit votre réseau privé isolé (`uc-net-campus`), son plan d'adressage (192.168.107.0/24) et le routeur qui le connecte à internet.
* **`security.tf`** : Met en place votre groupe de sécurité (`uc-sg-allow-all`) pour définir les règles d'ouverture des ports réseau.
* **`keypair.tf`** : Enregistre votre clé SSH personnelle dans OpenStack pour vous garantir un accès administrateur sécurisé à toutes vos futures machines.
* **`instances.tf`** : Le cœur de l'usine : c'est ici que l'on commande la création de vos serveurs et postes clients (incluant les instructions automatiques pour installer l'interface graphique des postes DSI et Prof).
* **`floating_ips.tf`** : Demande des adresses IP publiques au réseau externe et "tire les câbles" pour les brancher sur vos 4 machines exposées (Firewall, VPN, Mail, Moodle).
* **`variables.tf`** : Le panneau de contrôle qui centralise vos réglages (comme le préfixe `uc-`), vous permettant de renommer ou modifier tout le projet en changeant juste une ligne.



## Gestion de la cohabitation 

Pour utiliser un réseau OpenStack déjà en place, on n'utilise pas le mot-clé resource , mais le mot-clé data 

Exemple dans votre fichier network.tf :
```terraform
# On demande à OpenStack de trouver le réseau nommé "shared-net"
data "openstack_networking_network_v2" "reseau_existant" {
  name = "nom-du-reseau-partage" # Remplacez par le vrai nom visible sur Horizon
}

# On récupère aussi le sous-réseau associé si nécessaire
data "openstack_networking_subnet_v2" "subnet_existant" {
  network_id = data.openstack_networking_network_v2.reseau_existant.id
}
``` 

Connecter votre VM à ce réseau
Une fois que Terraform a "lu" l'ID de ce réseau existant, il vous suffit de le passer en paramètre dans votre fichier instance.tf

```terraform

resource "openstack_compute_instance_v2" "ma_vm" {
  name            = "jdupont-vm-01"
  image_name      = "Ubuntu 22.04"
  flavor_name     = "m1.small"
  key_pair        = "ma-cle-ssh"

  # On branche la VM sur l'ID qu'on a récupéré via le bloc 'data'
  network {
    uuid = data.openstack_networking_network_v2.reseau_existant.id
  }
}
```
## Identification et provider.tf



URL d'authentification : http://137.194.208.23:5000/v3/

### Étape 1 : Générer les identifiants côté OpenStack

Comme on utilise un SSO passant par Gitlab il faut setup des credentials d'applications
Identity > Application Credentials

Remplissez les informations :
   * **Name :** Donnez un nom clair pour vous en souvenir (ex: `gitlab-ci-terraform-gita`).
   * **Expiration Date :** (Optionnel) C'est une bonne pratique de sécurité de mettre une date de fin, mais si vous le faites, notez bien de le renouveler dans GitLab quand il expirera.
   * Laissez le reste vide/par défaut.
1. ⚠️ **TRÈS IMPORTANT :** Une fenêtre va s'afficher avec l'ID et le Secret. Gardez cette fenêtre ouverte ou copiez immédiatement le **Secret** dans un bloc-notes temporaire. Une fois cette fenêtre fermée, **vous ne pourrez plus jamais récupérer le Secret** (il faudra supprimer l'identifiant et en recréer un autre). 

### Étape 2 : Ajouter les variables dans GitLab 

1. **Settings** (Paramètres) > **CI/CD** > **Variables** > **Expand** (Développer) > **Add variable**
2. 
| Clé (Key) | Valeur (Value) | Paramètres à cocher |
| :--- | :--- | :--- |
| `OS_AUTH_TYPE` | `v3applicationcredential` | Rien de spécial. |
| `OS_AUTH_URL` | L'URL de votre API OpenStack (ex: `https://api.cloud.votre-entreprise.com:5000/v3`) | Rien de spécial. |
| `OS_APPLICATION_CREDENTIAL_ID` | L'ID généré à l'étape 1 | Rien de spécial. |
| `OS_APPLICATION_CREDENTIAL_SECRET` | Le Secret généré à l'étape 1 | 🚨 **Cochez impérativement "Mask variable"** (Masquer). Cochez "Protect variable" si la CI tourne sur une branche protégée (comme `main`). |

### Étape 3 : Nettoyer votre code Terraform

Pour que la magie opère, il faut s'assurer que votre code Terraform ne tente pas de forcer une autre méthode de connexion. 

Ouvrez le fichier où vous avez déclaré votre provider (souvent `provider.tf` ou au début de `main.tf`) et assurez-vous que le bloc est vide de toute information d'authentification :

```hcl
terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53.0" # Adaptez à la version que vous utilisez
    }
  }
}

# Laisser ce bloc vide demande à Terraform de regarder
# les variables d'environnement OS_ de GitLab CI
provider "openstack" {
  
}
```

## data.tf
`data.tf`permet de récupérer les ressources qui existent déjà sur openstack \


### 1. Peu importe le choix du réseau

#### A. Le Réseau Externe (Internet / IP Publiques)
* **Pourquoi :** 4 "Floating IPs" (pour le Firewall, VPN, Mail, Moodle).
* **Le Template :**
```hcl
# On cherche le réseau public par son nom
data "openstack_networking_network_v2" "ext_net" {
  name = "ext-net" 
}
```

#### B. Images
* **Pourquoi :** Pour dire à Terraform sur quoi installer vos 11 machines.
* **Le Template :**
```hcl
# On cherche la dernière version de l'image Ubuntu Serveur
data "openstack_images_image_v2" "ubuntu_2204" {
  name        = "jammy-2022-12-29"
  most_recent = true
}

# On cherche l'image Debian pour le Firewall
data "openstack_images_image_v2" "debian_10" {
  name        = "debian-10"
  most_recent = true
}
```

#### C. Flavors
* **Le Template :**
```hcl
# On vérifie l'existence du petit gabarit
data "openstack_compute_flavor_v2" "flavor_tiny" {
  name = "m1.tiny"
}

# On vérifie l'existence du gabarit moyen
data "openstack_compute_flavor_v2" "flavor_small" {
  name = "m1.small"
}
```

---

### 2. Option "Réseau Existant"

Si vous décidez de ne pas créer votre bulle `uc-net-campus` isolée et de vous brancher sur un réseau déjà créé par l'administrateur, vous devez ajouter ces blocs à votre `data.tf`.

#### D. Le Réseau Interne Partagé
* **Pourquoi :** Pour trouver le gros "switch" virtuel sur lequel vous allez brancher vos 11 machines.
* **Le Template :**
```hcl
data "openstack_networking_network_v2" "reseau_partage" {
  name = "nom-du-reseau-fourni-par-admin"
}
```

#### E. Le Sous-réseau Partagé (Optionnel mais recommandé)
* **Pourquoi :** Si vous devez fixer des IPs précises (ex: 192.168.107.10 pour le serveur mail), Terraform a besoin de connaître l'ID exact du sous-réseau pour réserver la place.
* **Le Template :**
```hcl
data "openstack_networking_subnet_v2" "subnet_partage" {
  name       = "nom-du-sous-reseau-fourni"
  # On s'assure de chercher dans le bon réseau parent
  network_id = data.openstack_networking_network_v2.reseau_partage.id
}
```
## network.tf
Si on décide de créer le réseau de 0 : 


---

### On crée notre réseau

Tout ce code ira dans votre fichier **`network.tf`**.

**1. Créer le "Switch" virtuel (Le Réseau)**
Ici on crée le nom du réseau
```hcl
resource "openstack_networking_network_v2" "uc_net" {
  name           = "uc-net-campus"
  admin_state_up = "true"
}
```

**2. Définir la plage d'adresses (Le Sous-réseau)**
Ici on crée le sous réseau
```hcl
resource "openstack_networking_subnet_v2" "uc_subnet" {
  name       = "uc-subnet-campus"
  network_id = openstack_networking_network_v2.uc_net.id
  cidr       = "192.168.107.0/24"
  ip_version = 4
  # Les DNS de Google et Cloudflare pour que vos VMs aient accès à internet
  dns_nameservers = ["8.8.8.8", "1.1.1.1"] 
}
```

**3. Créer la passerelle de sortie (Le Routeur)**
Ici on crée le routeur. Il utilise l'information de votre fichier `data.tf`.
```hcl
resource "openstack_networking_router_v2" "uc_router" {
  name                = "uc-router-campus"
  # On dit au routeur de pointer vers le réseau de l'université
  external_network_id = data.openstack_networking_network_v2.ext_net.id 
}
```

**4. Brancher le câble (L'Interface du Routeur)**
Sans ça, le routeur ne sert à rien. On relie le routeur (étape 3) au sous-réseau (étape 2).
```hcl
resource "openstack_networking_router_interface_v2" "uc_router_interface" {
  router_id = openstack_networking_router_v2.uc_router.id
  subnet_id = openstack_networking_subnet_v2.uc_subnet.id
}
```

---

### On utilise le réseau déjà crée

Dans ce scénario, vous ne créez **aucun** réseau ni routeur. Votre fichier **`network.tf`** ne servira qu'à réserver des adresses IP fixes.

*(Rappel : cela nécessite que votre fichier `data.tf` ait déjà trouvé le `reseau_partage` et le `subnet_partage`).*

**1. Réserver une IP fixe (Le Port)**
À répéter pour chaque serveur nécessitant une IP précise (Mail, DB, etc.). Code à mettre dans **`network.tf`**.
```hcl
resource "openstack_networking_port_v2" "port_mail" {
  name           = "uc-port-mail"
  network_id     = data.openstack_networking_network_v2.reseau_partage.id

  fixed_ip {
    subnet_id  = data.openstack_networking_subnet_v2.subnet_partage.id
    ip_address = "192.168.107.10" # L'IP exacte souhaitée
  }
}
```

**2. Brancher la VM sur cette IP fixe**
Ce bout de code se mettra plus tard dans votre fichier **`instances.tf`**, à l'intérieur de la configuration de votre serveur Mail.
```hcl
  network {
    port = openstack_networking_port_v2.port_mail.id
  }
```

**3. Brancher une VM avec une IP aléatoire (DHCP)**
Pour vos postes clients (`uc-poste-etu`, etc.), pas besoin de créer de port. Dans **`instances.tf`**, vous vous branchez directement sur le réseau.
```hcl
  network {
    uuid = data.openstack_networking_network_v2.reseau_partage.id
  }
```

---
## security.tf
Ce fichier définit les Security Groups d'Openstack : les règles de pare feu qu'Openstack applique direct aux machines virtuelles. Dans notre cas on veut que ce soit notre pare feu crée qui agisse, donc on doit faire en sorte que le pare feu d'openstack laisse tout passer

### 1. Création du groupe de sécurité

Ce groupe contiendra toutes vos règles.

```hcl
# Création du groupe de sécurité principal
resource "openstack_networking_secgroup_v2" "uc_sg_allow_all" {
  name        = "uc-sg-allow-all"
  description = "Groupe de securite permissif pour delegation au fw-legacy"
}
```

### 2. Définir les Règles Entrantes (Ingress)

Par défaut, OpenStack bloque tout ce qui entre. Il faut donc explicitement créer des règles pour ouvrir les portes. Selon votre architecture, il faut ouvrir le TCP, l'UDP et l'ICMP (le protocole utilisé pour la commande `ping`).

```hcl
# Autoriser TOUT le trafic TCP (Ports 1 à 65535) depuis n'importe quelle IP (0.0.0.0/0)
resource "openstack_networking_secgroup_rule_v2" "allow_all_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.uc_sg_allow_all.id
}

# Autoriser TOUT le trafic UDP (Ports 1 à 65535)
resource "openstack_networking_secgroup_rule_v2" "allow_all_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.uc_sg_allow_all.id
}

# Autoriser le protocole ICMP (indispensable pour les tests de ping)
resource "openstack_networking_secgroup_rule_v2" "allow_icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.uc_sg_allow_all.id
}
```

*Note sur l'Egress (Trafic sortant) : Dans OpenStack, les groupes de sécurité autorisent nativement tout le trafic sortant par défaut lors de leur création. Vous n'avez donc pas besoin d'écrire de règle spécifique pour l'Egress.*

### 3. Comment appliquer ce groupe (Dans `instances.tf`)

Ce code ne va pas dans `security.tf`, mais sera ajouté dans la configuration de chacune de vos instances :

```hcl
resource "openstack_compute_instance_v2" "uc_fw_legacy" {
  name        = "uc-fw-legacy"
  # ... (flavor, image, network)

  # On attache le groupe de sécurité défini dans security.tf
  security_groups = [openstack_networking_secgroup_v2.uc_sg_allow_all.name]
}
```
## keypair.tf


###  Ce qu'il faut mettre dans le fichier
Il n'y a généralement qu'une seule ressource à déclarer.

```hcl
# On envoie votre clé publique vers OpenStack
resource "openstack_compute_keypair_v2" "uc_keypair" {
  name       = "uc-keypair-admin"
  # On demande à Terraform de lire le contenu de votre fichier de clé publique
  # Remplacez le chemin par le vôtre (ex: ~/.ssh/id_ed25519.pub)
  public_key = file("~/.ssh/id_rsa.pub")
}
```

### 3. Variante : Utiliser une clé déjà présente sur OpenStack
Si vous avez déjà importé votre clé manuellement via l'interface Web (Horizon) et que vous voulez juste que Terraform l'utilise sans la gérer, on utilise un bloc **`data`** (dans `data.tf` ou `keypair.tf`).

```hcl
# On cherche la clé qui s'appelle "mon-access-sso" déjà sur Horizon
data "openstack_compute_keypair_v2" "kp_existante" {
  name = "mon-access-sso"
}
```

### 4. Comment l'utiliser (Dans `instances.tf`)
C'est l'étape finale. Dans la définition de vos 11 VMs, vous indiquez quelle clé doit être injectée dans l'image au démarrage.

```hcl
resource "openstack_compute_instance_v2" "uc_srv_mail" {
  name            = "uc-srv-mail"
  # ... (image, flavor, etc.)

  # On indique le NOM de la clé à utiliser
  key_pair        = openstack_compute_keypair_v2.uc_keypair.name
}
```
## instances.tf

Pour que ce soit digeste, on peut diviser la création d'une machine (une `resource "openstack_compute_instance_v2"`) en 4 blocs logiques. Voici ce que vous devez y mettre.

### 1. (Nom, OS, Puissance)
**Ce qu'il faut faire :** Donner un nom unique à la VM (avec votre préfixe `uc-`), lui attribuer sa taille (Flavor) et pointer vers l'ID de l'image système récupérée dans votre `data.tf`.

**L'exemple de code :**
```hcl
resource "openstack_compute_instance_v2" "uc_srv_moodle" {
  name        = "uc-srv-moodle"
  flavor_name = "m1.small"
  # On utilise l'ID de l'image trouvée par le data.tf
  image_id    = data.openstack_images_image_v2.ubuntu_2204.id
```

### 2. La Sécurité et l'Accès
**Ce qu'il faut faire :** Indiquer à OpenStack d'injecter votre clé SSH pour que vous puissiez vous y connecter, et appliquer le groupe de sécurité permissif pour que votre firewall applicatif (`uc-fw-legacy`) puisse faire son travail.

**L'exemple de code (suite de la VM Moodle) :**
```hcl
  # On utilise le nom de la clé créée dans keypair.tf
  key_pair        = openstack_compute_keypair_v2.uc_keypair.name
  
  # On applique le groupe de sécurité créé dans security.tf
  security_groups = [openstack_networking_secgroup_v2.uc_sg_allow_all.name]
```

### 3. Le Branchement Réseau (Deux méthodes)
C'est ici que vous appliquez votre choix réseau. Vous avez deux cas de figure dans votre architecture.

**Cas A : Branchement avec une IP dynamique (DHCP)**
Pour vos postes clients (`uc-poste-etu`, etc.), vous branchez simplement la machine sur le réseau global.
```hcl
  # Pour un poste client sans IP fixe
  network {
    # UUID du réseau créé dans network.tf (ou trouvé dans data.tf)
    uuid = openstack_networking_network_v2.uc_net.id
  }
```

**Cas B : Branchement avec une IP Fixe exigée**
Pour vos serveurs (`uc-srv-mail` en `.10`, etc.), vous ne branchez pas le réseau directement, vous branchez le **Port** que vous avez créé dans `network.tf`.
```hcl
  # Pour un serveur nécessitant une IP précise
  network {
    # ID du port réservé spécifiquement pour ce serveur
    port = openstack_networking_port_v2.port_mail.id
  }
```

### 4. L'Automatisation (Le Cloud-init / User Data)
**Ce qu'il faut faire :** C'est le bloc magique. Pour vos postes "Prof" et "DSI", vous n'avez qu'une image Ubuntu Serveur. Vous allez utiliser l'instruction `user_data` pour passer un script Bash que la VM exécutera toute seule lors de son tout premier démarrage.

**L'exemple de code (spécifique aux postes de travail) :**
```hcl
resource "openstack_compute_instance_v2" "uc_poste_prof" {
  name        = "uc-poste-prof"
  flavor_name = "m1.tiny"
  image_id    = data.openstack_images_image_v2.ubuntu_2204.id
  key_pair    = openstack_compute_keypair_v2.uc_keypair.name
  # ... (votre configuration réseau) ...

  # Le script Bash injecté
  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              # Installe l'interface graphique en mode silencieux
              DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-desktop
              # Dit à Ubuntu de démarrer sur l'interface graphique par défaut
              systemctl set-default graphical.target
              EOF
}
```

---
## floating_ips.tf
On cherche à donner des adresses publiques à certaines de nos machines : le server vpn, le server mail, moodle, le firewall 

### 1. L'Allocation (Réserver l'adresse)

Avant de brancher une adresse, il faut demander à OpenStack d'en sortir une du "sac" (le pool) du réseau externe. On utilise pour cela l'ID du réseau externe récupéré dans votre `data.tf`.

**L'exemple de code :**
```hcl
# On reserve une IP publique dans le pool externe pour le serveur Mail
resource "openstack_networking_floatingip_v2" "fip_mail" {
  pool = data.openstack_networking_network_v2.ext_net.name
}
```
*Note : À ce stade, l'IP est réservée pour vous, mais elle n'est reliée à rien. Elle "flotte" dans votre projet.*

### 2. L'Association (Brancher l'adresse sur une VM)


**L'exemple de code :**
```hcl
# On associe l'IP reservee au port specifique de la VM Mail
resource "openstack_compute_floatingip_associate_v2" "fip_assoc_mail" {
  floating_ip = openstack_networking_floatingip_v2.fip_mail.address
  instance_id = openstack_compute_instance_v2.uc_srv_mail.id
}
```

### Cas particulier : Le branchement sur un Port fixe
Si vous avez utilisé l'option de créer des **Ports** (pour avoir des IPs fixes comme 192.168.107.10), il est plus précis d'associer l'IP flottante directement au port plutôt qu'à l'instance.

```hcl
resource "openstack_networking_floatingip_associate_v2" "fip_assoc_mail" {
  floating_ip = openstack_networking_floatingip_v2.fip_mail.address
  port_id     = openstack_networking_port_v2.port_mail.id
}
```


## variables.tf


Le fichier `variables.tf` permet de centraliser les réglages comme le préfixe ou le nom du réseau externe ou les plages d'ip.

### 1. Déclarer les variables (`variables.tf`)

Dans ce fichier, vous ne créez aucune ressource OpenStack. Vous définissez simplement les "tiroirs" qui vont contenir vos réglages, leur type (texte, nombre, liste) et éventuellement une valeur par défaut.

**L'exemple de code :**
```hcl
# On définit le préfixe du projet
variable "prefix" {
  type        = string
  description = "Le préfixe à ajouter devant le nom de chaque ressource"
  default     = "uc-"
}

# On définit le réseau externe (facilite le changement si l'université le renomme)
variable "external_network_name" {
  type        = string
  description = "Nom du réseau public pour les IPs flottantes"
  default     = "ext-net"
}

# On définit la plage IP de votre maquette
variable "subnet_cidr" {
  type        = string
  description = "Le CIDR du sous-réseau interne"
  default     = "192.168.107.0/24"
}
```

### 2. Utiliser les variables 

Maintenant on peut remplacer en utilisant la syntaxe `var.nom_de_la_variable`.

**L'exemple de code (dans `network.tf`) :**
```hcl
resource "openstack_networking_network_v2" "uc_net" {
  # Au lieu d'écrire "uc-net-campus", on assemble la variable et le texte
  name = "${var.prefix}net-campus" 
}

resource "openstack_networking_subnet_v2" "uc_subnet" {
  name       = "${var.prefix}subnet-campus"
  network_id = openstack_networking_network_v2.uc_net.id
  # On appelle la variable contenant le plan d'adressage
  cidr       = var.subnet_cidr
  ip_version = 4
}
```

**L'exemple de code (dans `data.tf`) :**
```hcl
data "openstack_networking_network_v2" "ext_net" {
  # On utilise la variable au lieu d'écrire "ext-net"
  name = var.external_network_name 
}
```

### 3. Surcharger les variables 

Sans jamais toucher à votre code Terraform, vous pouvez créer une variable d'environnement dans les réglages de GitLab CI appelée `TF_VAR_prefix` et lui donner la valeur `examen-`. 
Lorsque votre pipeline s'exécutera, Terraform ignorera le `uc-` par défaut et nommera instantanément toutes vos machines `examen-srv-mail`, `examen-fw-legacy`, etc. 

## Pipeline gitlab 

https://spacelift.io/blog/gitlab-terraform

On crée un fichier .gitlab-ci.yml qui va servir de pipeline 

Pour éviter d'avoir des lancements à chaque push il faudra mettre des règles dans le fichier par exemple :
```yaml
terraform_apply:
  stage: deploy
  script:
    - terraform apply -auto-approve
  rules:
    # Ne s'exécute QUE sur la branche main
    - if: $CI_COMMIT_BRANCH == "main"
      # Et QUE si des fichiers terraform ont changé
      changes:
        - "terraform/**/*"
      when: manual # Demande une validation humaine par un clic
```
