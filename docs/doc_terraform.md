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
## security.tf
## keypair.tf
## instances.tf
## floating_ips.tf
## variables.tf

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
