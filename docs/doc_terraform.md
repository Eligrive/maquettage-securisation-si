    Ce document rassemble la documentation et les démarches effectuées et à effectuer pour un bon setup d'openstack avec terraform 

# Terraform
Dans notre maquette il va nous falloir les .tf suivants : 

- provider.tf : Le point d'entrée

Rôle : Déclare que vous utilisez OpenStack et indique la version du plugin.

Création/Lecture : Ni l'un ni l'autre, c'est de la configuration pure (et comme nous l'avons vu, sans aucun mot de passe écrit en dur !).

- instance.tf : Le cœur du projet

Rôle : C'est ici que vous déclarez la création de vos machines virtuelles (VMs).

Création/Lecture : Utilise le bloc resource "openstack_compute_instance_v2". 

- keypair.tf (Les clés SSH)

Rôle : Permet de se connecter aux VMs une fois qu'elles sont créées, sans utiliser de mot de passe.

Pratique courante : On crée une resource dans Terraform qui va prendre la clé publique (.pub) de votre ordinateur et l'injecter dans OpenStack.

- security.tf (Le Pare-feu / Groupes de sécurité)

Rôle : Par défaut, OpenStack bloque tout le trafic entrant. Il faut créer des règles.

Pratique courante : On utilise presque toujours des resource pour créer un groupe de sécurité sur mesure (ex: ouvrir le port 22 pour le SSH, et le port 80 pour un serveur web).

- flavors.tf (Le gabarit / La puissance)

Rôle : Définir la taille de la VM (ex: 2 vCPU, 4 Go RAM).

Pratique courante : Pareil que pour les images, les gabarits sont figés par l'admin. On utilise un bloc data pour trouver le nom du gabarit (ex: m1.small).

-  glance.tf (Les images OS)

Rôle : Indiquer quel système d'exploitation installer (ex: Ubuntu 22.04, Debian 12).

Pratique courante : On utilise un bloc data pour chercher l'image par son nom parmi celles déjà proposées par votre OpenStack.

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
