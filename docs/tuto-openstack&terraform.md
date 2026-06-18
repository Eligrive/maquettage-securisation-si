# Terraform + OpenStack — Documentation de référence

Ce document explique :
- comment fonctionne **OpenStack** et quelles sont les briques qu'on manipule (Keystone, Nova, Neutron, Glance, Cinder…)
- comment fonctionne **Terraform** et quelles commandes existent
- la **syntaxe HCL** en détail (variables, expressions, fonctions, méta-arguments)
- la **référence des principales ressources** du provider OpenStack avec leurs arguments

Il est pensé comme une documentation à consulter, pas comme un pas-à-pas.

---

# Partie I — OpenStack : comprendre ce qu'on manipule

## I.1 Vue d'ensemble

OpenStack n'est pas *un* logiciel mais un ensemble de services indépendants qui se parlent par des API REST. Chaque service a un nom de code (Keystone, Nova, Neutron…) et expose son propre endpoint HTTP. Quand tu utilises le client `openstack` ou Terraform, tu appelles successivement plusieurs de ces API.

Cette architecture en microservices explique la convention de nommage des ressources Terraform : `openstack_<service>_<objet>_v<version_API>`. Par exemple :

- `openstack_compute_instance_v2` → service Compute (Nova), objet « instance », API v2
- `openstack_networking_network_v2` → service Networking (Neutron), objet « network », API v2
- `openstack_blockstorage_volume_v3` → service Block Storage (Cinder), objet « volume », API v3

Une fois qu'on connaît la dizaine de services courants, le nom de chaque ressource devient lisible.

## I.2 Les services courants et leurs primitives

### Keystone — service d'identité

Keystone gère l'authentification et l'autorisation. Trois notions à connaître :

- **User** : un compte utilisateur.
- **Project** (ou tenant, ancien nom) : un espace cloisonné qui possède ses ressources (VMs, réseaux, volumes…). Tes quotas sont définis par projet.
- **Domain** : conteneur de projets et d'utilisateurs (utile pour la multi-tenance).

Quand tu te connectes à OpenStack, tu obtiens un **token** Keystone qui prouve « je suis user X dans le projet Y ». Toutes les autres API vérifient ce token.

L'**openrc** que tu télécharges depuis Horizon contient les variables nécessaires pour qu'un client (CLI ou Terraform) puisse demander un token automatiquement : `OS_AUTH_URL`, `OS_USERNAME`, `OS_PASSWORD`, `OS_PROJECT_NAME`, `OS_USER_DOMAIN_NAME`, `OS_PROJECT_DOMAIN_NAME`, `OS_REGION_NAME`.

Côté Terraform, tu n'as presque jamais à manipuler Keystone. Tu sources l'openrc, le provider lit les variables, l'authentification est transparente.

### Nova — service Compute

Nova gère les machines virtuelles. Notions :

- **Instance** : la VM elle-même. Type Terraform : `openstack_compute_instance_v2`.
- **Flavor** : un gabarit (CPU, RAM, disque). Par exemple `m1.small` = 1 vCPU, 2 Go RAM, 20 Go disque. Les flavors sont définis par l'admin du cloud, tu les consommes.
- **Keypair** : une clé SSH publique enregistrée dans Nova. Quand tu crées une instance, tu lui associes une keypair, et cloud-init injecte la clé publique dans `/home/<user>/.ssh/authorized_keys` au premier boot. Type : `openstack_compute_keypair_v2`.
- **user_data** : un script (généralement cloud-init) exécuté au premier démarrage de la VM.

### Glance — service d'images

Glance stocke les images disque (templates) à partir desquelles on lance les VMs. « Ubuntu 22.04 », « Debian 12 », « CentOS Stream 9 » sont des images Glance.

Tu ne crées presque jamais d'image en Terraform — l'admin du cloud les fournit. Tu les **lis** via un data source `openstack_images_image_v2` pour obtenir leur ID, qu'on passe ensuite à Nova quand on crée une instance.

### Neutron — service Networking

C'est le service le plus dense d'OpenStack, et celui où Terraform est le plus utile. Neutron implémente du SDN (Software Defined Networking) : tout est virtuel, on construit des réseaux logiques par-dessus l'infrastructure physique du cloud.

Les primitives Neutron :

**Network** (`openstack_networking_network_v2`) — un réseau L2 logique, l'équivalent virtuel d'un switch. C'est un conteneur, il ne porte pas d'IP par lui-même.

**Subnet** (`openstack_networking_subnet_v2`) — un plan d'adressage IP attaché à un network. Il définit le CIDR (par exemple `10.0.10.0/24`), la passerelle, les serveurs DNS et le pool DHCP. Un network peut avoir plusieurs subnets, mais pour démarrer on en met un seul.

**Port** (`openstack_networking_port_v2`) — un point d'attache sur un network. C'est l'équivalent virtuel d'une carte réseau. Quand tu crées une VM, OpenStack lui crée automatiquement un port (sauf si tu lui en fournis un explicitement). Manipuler les ports explicitement permet de fixer une IP précise au lieu de subir le DHCP.

**Router** (`openstack_networking_router_v2`) — un routeur virtuel qui interconnecte des subnets entre eux et fait le NAT vers l'extérieur. Sans routeur, ton subnet privé n'a aucun moyen de joindre internet.

**Floating IP** (`openstack_networking_floatingip_v2`) — une IP publique allouée depuis un pool externe et associable à un port. Le routeur fait du DNAT 1:1 entre la floating IP et l'IP fixe de la VM. C'est le mécanisme standard pour rendre une VM joignable depuis l'extérieur.

**Security Group** (`openstack_networking_secgroup_v2`) — un pare-feu stateful appliqué au niveau de l'hyperviseur, juste devant les ports. Un security group est un conteneur de règles ; les règles (`openstack_networking_secgroup_rule_v2`) précisent direction (ingress/egress), protocole (tcp/udp/icmp), ports et source/destination. Plusieurs security groups peuvent être appliqués à un port simultanément.

Pour visualiser : un paquet qui arrive sur ta VM passe par routeur → port → security group → interface réseau de la VM.

### Cinder — service Block Storage

Cinder gère les volumes persistants (disques). Notions :

- **Volume** (`openstack_blockstorage_volume_v3`) — un disque, indépendant de toute VM. Il survit à la destruction de l'instance.
- **Attachment** (`openstack_compute_volume_attach_v2`) — l'opération qui rattache un volume à une instance, vu côté VM comme `/dev/vdb`, `/dev/vdc`, etc.
- **Snapshot** — une copie figée d'un volume à un instant donné.
- **Boot from Volume** : option qui consiste à booter une VM directement depuis un volume Cinder au lieu du disque éphémère du flavor. Recommandé en production pour la persistance.

### Swift — service Object Storage

Swift est un stockage objet (équivalent S3 d'AWS), parfait pour stocker des fichiers, des sauvegardes, ou… le state Terraform. Notions : **container** (équivalent bucket) et **object**. Types Terraform : `openstack_objectstorage_container_v1`, `openstack_objectstorage_object_v1`.

### Octavia — Load Balancer as a Service

Service de répartition de charge L4/L7. Types `openstack_lb_loadbalancer_v2`, `openstack_lb_listener_v2`, `openstack_lb_pool_v2`. Pas indispensable au démarrage.

### Heat — orchestration

Heat est l'orchestrateur natif d'OpenStack, qui consomme des templates YAML. **Si tu utilises Terraform, tu n'utilises pas Heat** : ce sont deux outils concurrents qui font la même chose. Terraform est généralement préféré parce qu'il est multi-cloud et que son langage est plus riche.

## I.3 Tableau de correspondance OpenStack ↔ Terraform

| Service OpenStack | Rôle | Type Terraform principal |
|---|---|---|
| Keystone | Identité, projets | (transparent via openrc) |
| Nova | VMs | `openstack_compute_instance_v2`, `openstack_compute_keypair_v2` |
| Glance | Images disque | `openstack_images_image_v2` (le plus souvent en *data*) |
| Neutron | Réseau | `openstack_networking_network_v2`, `_subnet_v2`, `_port_v2`, `_router_v2`, `_floatingip_v2`, `_secgroup_v2`, `_secgroup_rule_v2` |
| Cinder | Volumes | `openstack_blockstorage_volume_v3`, `openstack_compute_volume_attach_v2` |
| Swift | Object storage | `openstack_objectstorage_container_v1` |
| Octavia | Load balancer | `openstack_lb_loadbalancer_v2`, `_listener_v2`, `_pool_v2` |

Le suffixe `v2` ou `v3` correspond à la version d'API OpenStack que le provider cible, pas à la version du provider Terraform. Tu peux ignorer la version : utilise toujours celle qu'utilise la doc du provider.

## I.4 Le client `openstack` (CLI)

Le client en ligne de commande `openstack` est utile en parallèle de Terraform pour explorer et déboguer. Quelques commandes utiles :

| Commande | Ce qu'elle fait |
|---|---|
| `openstack image list` | Liste les images Glance disponibles (utile pour connaître le nom exact à mettre dans Terraform) |
| `openstack flavor list` | Liste les flavors Nova |
| `openstack network list` | Liste les networks Neutron |
| `openstack server list` | Liste les VMs du projet courant |
| `openstack server show <nom>` | Détaille une VM |
| `openstack security group list` | Liste les security groups |
| `openstack floating ip list` | Liste les floating IPs allouées |
| `openstack quota show` | Affiche tes quotas (CPU, RAM, IPs, etc.) |
| `openstack token issue` | Récupère un token Keystone (utile pour vérifier que l'auth marche) |

Toutes ces commandes lisent ton openrc sourcé.

---

# Partie II — Terraform : concepts et syntaxe

## II.1 Le modèle déclaratif

Tu décris l'état final souhaité de ton infrastructure dans des fichiers `.tf`. Terraform compare cet état désiré avec ce qui existe vraiment (en interrogeant les API du provider) et calcule un **plan** : quelles ressources créer, modifier, détruire ou remplacer pour converger.

C'est l'inverse d'un script bash qui lance des `openstack server create` les uns après les autres. Avec un script tu décris le **chemin** ; avec Terraform tu décris le **but**.

## II.2 Provider

Un **provider** est un plugin qui sait parler à une API spécifique. `terraform-provider-openstack/openstack` traduit ton HCL en appels Keystone/Nova/Neutron. Le provider AWS traduit en appels EC2. Etc.

Le provider est déclaré dans un bloc `terraform { required_providers { … } }` et configuré dans un bloc `provider "openstack" {}`. Au minimum, on déclare le provider et on laisse l'authentification se faire via les variables d'environnement de l'openrc.

## II.3 Resource

Une **resource** est un objet géré par Terraform. Elle a un type (`openstack_compute_instance_v2`) et un nom local choisi par toi (`web`, `db`, …). Le nom local n'a pas d'existence côté OpenStack : il sert juste à référencer la ressource dans tes autres fichiers `.tf`.

Quand tu fais `terraform apply`, Terraform crée la ressource si elle n'existe pas, met à jour les attributs si ils ont changé, ou la remplace (détruire + recréer) si l'attribut modifié n'est pas modifiable in place.

## II.4 Data source

Une **data source** lit un objet existant sans le gérer. Elle se déclare avec le mot-clé `data` au lieu de `resource`, et a la même syntaxe sinon. On l'utilise pour récupérer des éléments du cloud que Terraform ne possède pas : le réseau externe partagé, une image officielle, un flavor existant.

`terraform destroy` ne supprime jamais ce qui est lu via data source.

## II.5 State

Le **state** est un fichier JSON (`terraform.tfstate`) où Terraform mémorise la correspondance entre tes ressources HCL et les objets réels chez le provider. Sans state, Terraform ne sait pas que la ressource `openstack_compute_instance_v2.web` correspond à la VM avec l'ID `abc-123` dans Nova.

Trois conséquences pratiques :

1. **Le state est la source de vérité de Terraform.** Si tu le perds, Terraform considère que rien n'existe et proposera de tout recréer.
2. **Le state contient des informations sensibles** (mots de passe générés, clés…). Ne le commit pas en clair.
3. **À plusieurs, le state doit être partagé** via un *backend distant* (Swift, S3, GitLab, Terraform Cloud) avec verrouillage pour éviter les apply concurrents qui se piétinent.

## II.6 Module

Un **module** est un dossier `.tf` qu'on instancie depuis un autre. Il regroupe des ressources et expose des variables d'entrée et des outputs. C'est la brique de réutilisation : un module « VM applicative standard » peut être instancié dix fois avec dix configurations différentes.

Un projet Terraform basique a un seul module implicite (le dossier courant). On découpe en sous-modules quand le projet grossit ou qu'un pattern se répète.

## II.7 Variables

### Déclaration

```hcl
variable "name" {
  type        = string
  description = "Nom de la ressource"
  default     = "demo"     # rend la variable optionnelle
  nullable    = false      # interdit la valeur null
  sensitive   = true       # masque la valeur dans les logs

  validation {
    condition     = length(var.name) <= 20
    error_message = "Le nom doit faire 20 caractères max."
  }
}
```

Si `default` est absent, la variable est **obligatoire** et doit être fournie par une des sources ci-dessous.

### Types

| Type | Exemple |
|---|---|
| `string` | `"hello"` |
| `number` | `42` |
| `bool` | `true` |
| `list(<type>)` | `["a", "b", "c"]` — liste ordonnée, doublons autorisés |
| `set(<type>)` | `["a", "b"]` — non ordonné, sans doublons |
| `map(<type>)` | `{ env = "prod", owner = "team" }` — toutes les valeurs ont le même type |
| `object({...})` | `{ name = string, count = number }` — attributs typés différemment |
| `tuple([...])` | `[string, number, bool]` — taille et types fixes |
| `any` | n'importe quel type, à éviter |

### Sources des valeurs (par priorité décroissante)

1. **`-var "x=val"`** sur la ligne de commande
2. **`-var-file=fichier.tfvars`** sur la ligne de commande (dernier fichier listé gagne)
3. **`*.auto.tfvars`** dans le dossier (ordre alphabétique)
4. **`terraform.tfvars`** ou **`terraform.tfvars.json`**
5. **`TF_VAR_<nom>`** variable d'environnement
6. **`default`** dans la déclaration

Les fichiers `.tfvars` ont la même syntaxe que les `.tf` mais ne contiennent que des affectations :
```hcl
prefix      = "prod"
vm_count    = 5
allowed_ips = ["10.0.0.0/8"]
```

## II.8 Locals

Un `local` est une valeur dérivée, calculée une fois et réutilisable.

```hcl
locals {
  prefix    = "myapp"
  full_name = "${local.prefix}-${var.environment}"
  common_tags = {
    project = var.project_name
    owner   = "platform-team"
  }
}
```

Référence : `local.full_name`. Ne pas confondre `local.x` (valeur dérivée) et `var.x` (entrée).

## II.9 Expressions

### Référence

```hcl
var.x                          # variable
local.x                        # valeur locale
data.<type>.<nom>.<attr>       # data source
<type>.<nom>.<attr>            # resource
module.<nom>.<output>          # output d'un module
each.key, each.value           # dans un for_each
count.index                    # dans un count
terraform.workspace            # nom du workspace courant
path.module, path.root, path.cwd
```

### Conditionnel (ternaire)

```hcl
flavor = var.env == "prod" ? "m1.large" : "m1.small"
```

### `for` — list/map comprehension

```hcl
# Filtre + transforme une liste
[for s in var.servers : s.name if s.role == "web"]

# Construit une map
{ for s in var.servers : s.name => s.ip }
```

### Splat — extraire un attribut d'une liste de ressources

```hcl
# Toutes les IPs des VMs créées avec for_each
values(openstack_compute_instance_v2.web)[*].access_ip_v4

# Avec count
openstack_compute_instance_v2.web[*].id
```

### `dynamic` — bloc conditionnel ou répété

Très utile quand une ressource accepte des sous-blocs répétables. Syntaxe générique :

```hcl
dynamic "<nom_du_bloc>" {
  for_each = <collection>
  content {
    # attributs du bloc, accessibles via <nom_du_bloc>.value
  }
}
```

## II.10 Fonctions intégrées

Terraform fournit ~150 fonctions. Catégories principales :

| Catégorie | Exemples |
|---|---|
| **String** | `format`, `join`, `split`, `lower`, `upper`, `replace`, `regex`, `trimspace` |
| **Numeric** | `min`, `max`, `abs`, `ceil`, `floor`, `parseint` |
| **Collection** | `length`, `keys`, `values`, `lookup`, `merge`, `concat`, `flatten`, `contains`, `distinct`, `range` |
| **Encoding** | `jsonencode`, `jsondecode`, `yamlencode`, `yamldecode`, `base64encode` |
| **Filesystem** | `file`, `templatefile`, `fileexists`, `fileset`, `pathexpand` |
| **IP** | `cidrhost`, `cidrsubnet`, `cidrnetmask` |
| **Date** | `formatdate`, `timestamp`, `timeadd` |
| **Hash** | `md5`, `sha256`, `bcrypt`, `uuid` |
| **Type** | `tostring`, `tonumber`, `tolist`, `tomap`, `toset`, `try`, `can` |

Les plus utiles au quotidien :

- **`file("chemin")`** — lit un fichier en tant que string. Typique : `public_key = file("~/.ssh/id_rsa.pub")`.
- **`templatefile("chemin", { var = val })`** — comme `file` mais interpole des variables. Idéal pour cloud-init paramétrable.
- **`lookup(map, clé, défaut)`** — accès sécurisé à une map.
- **`merge(map1, map2, ...)`** — fusionne des maps (clés des suivantes écrasent).
- **`format("vm-%02d", count.index)`** — formatage style printf.
- **`cidrsubnet("10.0.0.0/16", 8, 5)`** → `"10.0.5.0/24"` (découpe un CIDR).
- **`try(expr1, expr2, défaut)`** — essaie chaque expression, retourne la première qui marche.

## II.11 Méta-arguments des resources

Cinq arguments spéciaux applicables à toute resource :

### `count`

Crée N copies indexées par numéro.

```hcl
resource "openstack_compute_instance_v2" "web" {
  count = 3
  name  = "web-${count.index}"   # web-0, web-1, web-2
}
```

Référence : `openstack_compute_instance_v2.web[0]`.

### `for_each`

Crée N copies indexées par clé. Préférable à `count` car les clés sont stables : retirer un élément du milieu ne réordonne pas les autres.

```hcl
resource "openstack_compute_instance_v2" "web" {
  for_each = {
    "web-01" = { flavor = "m1.tiny" }
    "web-02" = { flavor = "m1.small" }
  }

  name        = each.key
  flavor_name = each.value.flavor
}
```

Référence : `openstack_compute_instance_v2.web["web-01"]`.

`for_each` accepte une `map(...)` ou un `set(string)`.

### `depends_on`

Force une dépendance explicite. Habituellement Terraform en déduit automatiquement via les références (`<type>.<nom>.attr`), mais parfois la dépendance n'est pas exprimable dans le code.

```hcl
resource "openstack_compute_instance_v2" "app" {
  # ...
  depends_on = [openstack_blockstorage_volume_v3.data]
}
```

### `lifecycle`

Contrôle fin du cycle de vie. Quatre options :

| Option | Effet |
|---|---|
| `create_before_destroy = true` | Crée le remplaçant avant de détruire l'ancien (utile pour zéro downtime) |
| `prevent_destroy = true` | Bloque tout `destroy` ou recréation. Garde-fou pour les ressources critiques |
| `ignore_changes = [attr1, attr2]` | Ignore les modifications externes sur ces attributs |
| `replace_triggered_by = [refs]` | Force une recréation quand les ressources listées changent |

```hcl
resource "openstack_compute_instance_v2" "db" {
  # ...
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [user_data]
  }
}
```

### `provider`

Sélectionne quelle config provider utiliser quand il y en a plusieurs (alias).

```hcl
provider "openstack" {
  alias  = "secondary"
  region = "RegionTwo"
}

resource "openstack_compute_instance_v2" "vm" {
  provider = openstack.secondary
  # ...
}
```

## II.12 Outputs

```hcl
output "web_ip" {
  value       = openstack_networking_floatingip_v2.web.address
  description = "IP publique du serveur web"
  sensitive   = false   # passe à true pour les secrets
}
```

Affichage : à la fin de `apply`, ou via `terraform output`. Récupération machine-readable : `terraform output -json`, ou valeur unique : `terraform output -raw web_ip`.

Les outputs d'un module sont accessibles via `module.<nom>.<output>`.

---

# Partie III — Les commandes Terraform

C'est la partie la plus utile à connaître par cœur. Toutes les commandes s'exécutent depuis le dossier qui contient tes `.tf`.

## III.1 Initialisation

### `terraform init`

À lancer en premier dans tout nouveau projet, et à relancer chaque fois que tu :
- ajoutes un nouveau provider dans `required_providers`
- changes la version d'un provider
- ajoutes ou modifies un module
- changes la configuration du backend

Ce que ça fait concrètement :
1. Télécharge les providers déclarés dans le dossier `.terraform/providers/`.
2. Télécharge les modules externes dans `.terraform/modules/`.
3. Initialise le backend (local ou distant) qui va héberger le state.
4. Crée un fichier `.terraform.lock.hcl` qui pin la version exacte des providers téléchargés (à commiter sur Git pour que toute l'équipe utilise la même).

Options utiles :
- `-upgrade` : récupère les versions les plus récentes compatibles avec tes contraintes.
- `-reconfigure` : force la reconfiguration du backend (utile quand tu changes de bucket Swift).
- `-backend-config=fichier.hcl` : injecte une config backend depuis un fichier (pour ne pas mettre les credentials en dur).

### `terraform get`

Télécharge ou met à jour les modules sans toucher aux providers ni au backend. Utile rarement, `terraform init` fait déjà tout.

## III.2 Validation et formatage

### `terraform fmt`

Reformate les fichiers `.tf` du dossier courant selon le style canonique HCL : indentation, alignement des `=`, espaces. À lancer avant chaque commit. Sans argument, modifie en place ; avec `-check`, retourne juste un code d'erreur si quelque chose n'est pas bien formaté (utile en CI).

### `terraform validate`

Vérifie que la syntaxe est correcte et que les références entre ressources sont cohérentes (pas de référence à une variable ou ressource inexistante). N'appelle pas l'API OpenStack — c'est une vérification statique. Très rapide.

À noter : `validate` ne dit pas si ton plan va marcher ; il dit seulement que ton code est syntaxiquement valide.

## III.3 Le cycle plan / apply / destroy

### `terraform plan`

Le cœur du workflow. Cette commande :
1. Rafraîchit le state en interrogeant le provider (sauf si `-refresh=false`).
2. Compare l'état réel avec ton code HCL.
3. Affiche le diff : ce qui sera créé (`+`), modifié (`~`), détruit (`-`), ou remplacé (`-/+`).

`plan` ne change rien. C'est ton moment de relecture critique. Surtout regarde :
- les **destruction** non voulues
- les **replacements** : Terraform détruit puis recrée la ressource. Sur une VM ça redémarre tout, sur une DB ça peut être catastrophique.
- les **modifications** d'attributs sensibles (security group rules, IPs).

Options utiles :
- `-out=plan.tfplan` : sauvegarde le plan dans un fichier pour pouvoir l'appliquer ensuite à l'identique avec `apply plan.tfplan`. Recommandé en CI/CD pour garantir que ce qui est revu est ce qui est appliqué.
- `-target=type.nom` : limite le plan à une ressource (et ses dépendances). À utiliser exceptionnellement, pour du debug.
- `-var "x=valeur"` ou `-var-file=fichier.tfvars` : passe des variables.
- `-refresh-only` : compare l'état réel et le state sans tenir compte du code, pour détecter le drift (modifications faites hors Terraform).

### `terraform apply`

Applique un plan. Deux modes :
- **Sans argument** : recalcule un plan, l'affiche, demande confirmation interactive (`yes` à taper), puis applique. Pratique en dev local.
- **Avec un fichier de plan** (`terraform apply plan.tfplan`) : applique exactement ce plan sans recalculer. C'est le mode propre pour CI/CD : le plan a été revu en PR, l'apply ne peut pas dévier.

Options utiles :
- `-auto-approve` : skip la confirmation interactive. Utilisé en CI ou quand tu es sûr.
- `-parallelism=N` : nombre d'opérations API en parallèle (10 par défaut). Si ton OpenStack est lent ou rate-limite, descends à 2 ou 3.
- `-target=type.nom` : applique uniquement une ressource. À éviter en routine, légitime pour réparer un état cassé.
- `-replace=type.nom` : force le remplacement de la ressource au prochain apply (équivalent moderne de l'ancien `terraform taint`).

### `terraform destroy`

D�truit toutes les ressources gérées par le state. Demande confirmation, sauf avec `-auto-approve`. Équivalent fonctionnel à `terraform apply` avec un code vide.

Options utiles :
- `-target=type.nom` : détruit uniquement cette ressource (et ses dépendantes). Risqué, à utiliser avec précaution.

## III.4 Inspection et state

### `terraform show`

Affiche le contenu du state actuel, ou d'un fichier de plan si on lui en passe un. Lecture seule, utile pour vérifier ce que Terraform pense gérer.

- `terraform show` : tout le state.
- `terraform show plan.tfplan` : détaille un plan sauvegardé.
- `terraform show -json` : sortie machine-readable, parsable avec `jq`.

### `terraform state list`

Liste les ressources gérées par le state, par leur adresse (`type.nom` ou `type.nom["clé"]` pour celles créées avec `for_each`).

### `terraform state show <adresse>`

D�taille une ressource spécifique : tous ses attributs tels qu'ils sont dans le state.

### `terraform state rm <adresse>`

Retire une ressource du state **sans la détruire** côté provider. Utilisations classiques :
- la ressource a été détruite manuellement et tu veux faire oublier Terraform.
- tu transfères la ressource d'un projet Terraform à un autre.
- tu veux la « libérer » pour la réimporter sous un autre nom.

### `terraform state mv <source> <destination>`

Renomme une ressource dans le state. Indispensable quand tu refactorises ton code (passage en `for_each`, déplacement dans un module) sans vouloir détruire et recréer.

Exemple : tu avais `openstack_compute_instance_v2.web_01` et tu veux passer à `openstack_compute_instance_v2.web["01"]` :
```
terraform state mv 'openstack_compute_instance_v2.web_01' 'openstack_compute_instance_v2.web["01"]'
```

### `terraform state pull` / `terraform state push`

`pull` télécharge le state distant et l'affiche. `push` réécrit le state distant à partir d'un fichier local. À manier avec précaution, surtout `push`.

### `terraform refresh` (ou `terraform apply -refresh-only`)

Met à jour le state en interrogeant le provider, sans rien créer ni détruire. La commande `refresh` historique a été marquée obsolète au profit de `apply -refresh-only` qui a un mode interactif similaire à un apply normal.

### `terraform output`

Affiche les valeurs des `output` déclarés dans ton code. Pratique pour récupérer les IPs après un apply.

- `terraform output` : tous les outputs en HCL.
- `terraform output -json` : format JSON.
- `terraform output <nom>` : un seul output.
- `terraform output -raw <nom>` : valeur brute sans guillemets, pour scripter (`SSH_IP=$(terraform output -raw web_ip)`).

## III.5 Importer du legacy

### `terraform import <adresse> <id>`

Importe une ressource créée hors Terraform (à la main dans Horizon, par exemple) dans le state. **Tu dois écrire le bloc `resource` correspondant à la main d'abord** ; `import` ne génère pas le code HCL.

Exemple : tu as une VM créée à la main dans Horizon, dont l'ID est `abc-123-def`. Tu veux la gérer désormais avec Terraform.

1. Tu écris dans `main.tf` :
```hcl
resource "openstack_compute_instance_v2" "legacy_web" {
  # vide pour l'instant
}
```

2. Tu lances :
```
terraform import openstack_compute_instance_v2.legacy_web abc-123-def
```

3. Tu fais `terraform state show openstack_compute_instance_v2.legacy_web` pour voir tous les attributs réels.

4. Tu remplis le bloc `resource` avec ces attributs jusqu'à ce que `terraform plan` ne propose plus de changement.

C'est manuel et fastidieux. Des outils comme `terraformer` peuvent générer le HCL automatiquement.

Depuis Terraform 1.5, il existe aussi le bloc `import` qu'on déclare dans le HCL et qui est appliqué au prochain `apply`, plus propre que la commande impérative.

## III.6 Workspaces

### `terraform workspace`

Sous-commandes :
- `terraform workspace list` : liste les workspaces (par défaut un seul, `default`).
- `terraform workspace new <nom>` : crée un workspace.
- `terraform workspace select <nom>` : bascule dessus.
- `terraform workspace delete <nom>` : supprime (vide d'abord).
- `terraform workspace show` : affiche le workspace courant.

Chaque workspace a son propre state. Le code est partagé. Permet de gérer plusieurs environnements (dev/staging/prod) ou plusieurs déploiements parallèles avec le même code.

Dans le code, on accède au nom du workspace courant via `terraform.workspace`.

**Limite** : workspaces partagent la même config provider (donc même cloud, même région, même projet). Pour des isolations plus fortes, utilise des dossiers séparés.

## III.7 Console et graphe

### `terraform console`

Ouvre un REPL HCL. On y teste des expressions sans toucher au state. Très utile pour débugger une fonction, vérifier ce que renvoie un `for`, une concaténation, un `lookup`.

Exemple :
```
> upper("hello")
"HELLO"
> [for k, v in var.servers : k if v.role == "web"]
["web-01", "web-02"]
```

`exit` ou `Ctrl-D` pour sortir.

### `terraform graph`

Génère le graphe de dépendances des ressources au format DOT (Graphviz). À piper dans `dot` pour produire une image. Pas indispensable au quotidien, parfois utile pour comprendre pourquoi une ressource est recréée.

## III.8 Providers

### `terraform providers`

Liste les providers utilisés par la configuration et les modules. Variantes :
- `terraform providers schema -json` : dump complet des schémas (très volumineux).
- `terraform providers lock` : régénère le fichier `.terraform.lock.hcl` (utile pour ajouter le hash d'une nouvelle plateforme, par exemple `linux_arm64`).
- `terraform providers mirror <dossier>` : télécharge tous les providers dans un dossier local pour les distribuer en interne.

## III.9 Divers

### `terraform version`

Affiche la version de Terraform et des providers utilisés.

### `terraform login` / `terraform logout`

Gère l'authentification à Terraform Cloud / Enterprise. Inutile si tu utilises seulement OpenStack et un backend Swift.

### `terraform force-unlock <id>`

Casse un verrou de state quand un apply a planté en laissant le state verrouillé. Ne fais ça que si tu es certain qu'aucun autre apply n'est en cours, sinon corruption garantie.

## III.10 Récapitulatif

| Commande | Quand l'utiliser |
|---|---|
| `init` | Avant tout, après ajout de provider/module/backend |
| `fmt` | Avant chaque commit |
| `validate` | Vérification rapide de syntaxe |
| `plan` | Avant chaque apply, à relire attentivement |
| `apply` | Pour appliquer les changements |
| `destroy` | Pour tout démanteler |
| `output` | Récupérer les valeurs en sortie |
| `state list` / `state show` | Inspecter ce que Terraform gère |
| `state mv` | Refactor sans destruction |
| `state rm` | Sortir une ressource du state |
| `import` | Reprendre une ressource créée à la main |
| `workspace` | Gérer plusieurs environnements |
| `console` | Tester une expression HCL |

---

# Partie IV — Workflow type

## IV.1 Première mise en place

1. Créer un dossier projet avec `providers.tf`, `variables.tf`, `main.tf`.
2. `source openrc.sh` pour charger les credentials OpenStack.
3. `terraform init` pour télécharger le provider.
4. Écrire le code HCL.
5. `terraform fmt && terraform validate`.
6. `terraform plan` et lire le diff.
7. `terraform apply`.

## IV.2 Boucle de développement

À chaque modification du code :

1. `terraform fmt`
2. `terraform validate`
3. `terraform plan` (relire)
4. `terraform apply`

Le plan est l'étape critique. Même quand on est pressé, on lit le plan.

## IV.3 En équipe avec backend distant

1. Le backend est configuré dans `providers.tf` (par exemple Swift).
2. `terraform init` connecte tout le monde au même state.
3. Avant un apply, on tire les dernières modifs de Git : `git pull`.
4. `terraform plan -out=plan.tfplan`.
5. Revue de plan (collègue ou auto-revue), commit du code.
6. `terraform apply plan.tfplan`.
7. Le verrou de state empêche les apply concurrents.

## IV.4 CI/CD

Pattern courant :
- Sur chaque PR : `terraform fmt -check`, `terraform validate`, `terraform plan` posté en commentaire.
- Sur merge dans `main` : `terraform apply -auto-approve` du plan généré.
- Credentials OpenStack stockés dans les secrets de la CI (GitLab CI variables, GitHub Actions secrets).

## IV.5 Gestion des secrets

Trois règles non négociables :
1. Pas de credentials en clair dans les fichiers `.tf` versionnés.
2. Le state contient des secrets — backend distant chiffré, accès restreint.
3. Les variables sensibles sont marquées `sensitive = true`.

Sources possibles pour les valeurs sensibles, par ordre de préférence :
- Variables d'environnement `TF_VAR_<nom>` (lues automatiquement).
- Fichier `*.tfvars` ignoré par Git.
- Secret manager (Vault, Barbican OpenStack, AWS Secrets Manager) lu via data source.
- Provider `random_password` qui génère et stocke dans le state.

---

# Partie V — Référence du provider OpenStack

Cette partie liste les arguments principaux des ressources les plus utilisées. La doc officielle complète est sur `registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs`.

Convention des tableaux : ✓ = requis, — = optionnel, *attribut* en italique = renvoyé par OpenStack après création (ne pas le définir, le lire).

## V.1 Compute (Nova)

### `openstack_compute_instance_v2`

| Argument | Type | Req. | Description |
|---|---|---|---|
| `name` | string | ✓ | Nom de la VM |
| `image_id` | string | — | ID de l'image Glance (préférer à `image_name`) |
| `image_name` | string | — | Nom de l'image |
| `flavor_id` | string | — | ID du flavor |
| `flavor_name` | string | — | Nom du flavor |
| `key_pair` | string | — | Nom de la keypair injectée |
| `security_groups` | list(string) | — | Liste de noms de SG (à mettre uniquement si pas de `port` explicite) |
| `availability_zone` | string | — | AZ Nova ciblée |
| `network` | block | — | Bloc(s) réseau, voir ci-dessous |
| `block_device` | block | — | Bloc(s) de boot from volume |
| `metadata` | map(string) | — | Tags clé/valeur stockés par Nova |
| `user_data` | string | — | Script cloud-init exécuté au premier boot |
| `config_drive` | bool | — | Force l'usage du config drive plutôt que metadata service |
| `power_state` | string | — | `active`, `shutoff`, `paused`, `suspended` |
| `stop_before_destroy` | bool | — | Stoppe la VM avant destruction (utile pour les snapshots) |
| `force_delete` | bool | — | `terraform destroy` force même si Nova est lent |
| *`access_ip_v4`* | string | — | Première IP IPv4 (utile en output) |
| *`access_ip_v6`* | string | — | Première IP IPv6 |
| *`id`* | string | — | UUID de la VM |

L'image et le flavor doivent être renseignés via leur `_id` ou leur `_name` — pas les deux.

**Bloc `network`** (un par interface) :

| Argument | Description |
|---|---|
| `uuid` | ID du network — option DHCP |
| `port` | ID du port Neutron explicite — option IP fixe |
| `name` | Nom du network (alternative à `uuid`) |
| `fixed_ip_v4` | IP à demander dans le réseau |
| `access_network` | Marque cette interface comme l'IP d'accès principale |

**Bloc `block_device`** (boot from volume) :

| Argument | Description |
|---|---|
| `uuid` | ID de la source (image/volume/snapshot) |
| `source_type` | `image`, `volume`, `snapshot`, `blank` |
| `destination_type` | `local` ou `volume` |
| `volume_size` | Taille en Go |
| `boot_index` | 0 pour le disque de boot |
| `delete_on_termination` | Détruit le volume avec la VM |

### `openstack_compute_keypair_v2`

| Argument | Type | Req. | Description |
|---|---|---|---|
| `name` | string | ✓ | Nom de la keypair |
| `public_key` | string | — | Clé publique. Si absente, OpenStack en génère une |
| *`private_key`* | string | — | Clé privée si générée par OpenStack |
| *`fingerprint`* | string | — | Empreinte MD5 |

### `openstack_compute_volume_attach_v2`

| Argument | Type | Req. | Description |
|---|---|---|---|
| `instance_id` | string | ✓ | ID de la VM |
| `volume_id` | string | ✓ | ID du volume Cinder |
| `device` | string | — | Chemin de device (`/dev/vdb`) — souvent ignoré, OpenStack décide |
| *`id`* | string | — | Identifiant composé `instance_id/attach_id` |

## V.2 Networking (Neutron)

### `openstack_networking_network_v2`

| Argument | Type | Req. | Description |
|---|---|---|---|
| `name` | string | — | Nom (un network sans nom est techniquement valide) |
| `description` | string | — | Description |
| `admin_state_up` | bool | — | `true` par défaut |
| `shared` | bool | — | Partagé entre projets (admin only) |
| `external` | bool | — | Network externe (admin only) |
| `mtu` | number | — | MTU |
| `port_security_enabled` | bool | — | SG appliqués aux ports de ce network |
| `qos_policy_id` | string | — | Policy QoS Neutron |
| `dns_domain` | string | — | Domaine DNS pour les ports |
| `tags` | set(string) | — | Tags Neutron |

### `openstack_networking_subnet_v2`

| Argument | Type | Req. | Description |
|---|---|---|---|
| `network_id` | string | ✓ | Network parent |
| `cidr` | string | — | CIDR (ex: `10.0.0.0/24`). Requis sauf si `subnetpool_id` fourni |
| `name` | string | — | Nom |
| `ip_version` | number | — | `4` (défaut) ou `6` |
| `gateway_ip` | string | — | IP de la passerelle. Par défaut, première IP utilisable |
| `no_gateway` | bool | — | Pas de passerelle |
| `enable_dhcp` | bool | — | DHCP activé (`true` par défaut) |
| `dns_nameservers` | list(string) | — | Serveurs DNS injectés via DHCP |
| `allocation_pool` | block | — | Pool DHCP. Bloc(s) avec `start` et `end` |
| `subnetpool_id` | string | — | Subnet pool pour allocation auto du CIDR |
| `prefix_length` | number | — | Taille de préfixe (avec `subnetpool_id`) |
| `tags` | set(string) | — | Tags |

### `openstack_networking_port_v2`

| Argument | Type | Req. | Description |
|---|---|---|---|
| `network_id` | string | ✓ | Network parent |
| `name` | string | — | Nom |
| `admin_state_up` | bool | — | `true` par défaut |
| `mac_address` | string | — | MAC custom (sinon généré) |
| `fixed_ip` | block | — | Bloc(s) avec `subnet_id` + `ip_address` pour IP fixe |
| `security_group_ids` | set(string) | — | IDs des SG appliqués au port |
| `no_security_groups` | bool | — | Pas de SG (utile pour les ports d'infra) |
| `allowed_address_pairs` | block | — | Permet d'usurper d'autres IPs/MACs (HA, VRRP) |
| `port_security_enabled` | bool | — | Désactive complètement les SG si `false` |
| `device_owner` | string | — | Type de device (`compute:nova`, `network:router_interface`…) |
| `device_id` | string | — | ID du device qui possède le port |
| *`all_fixed_ips`* | list(string) | — | Toutes les IPs assignées |

### `openstack_networking_router_v2`

| Argument | Type | Req. | Description |
|---|---|---|---|
| `name` | string | — | Nom |
| `admin_state_up` | bool | — | `true` par défaut |
| `external_network_id` | string | — | Network externe pour le SNAT |
| `enable_snat` | bool | — | NAT sortant (`true` par défaut si externe) |
| `external_fixed_ip` | block | — | Forcer une IP précise sur l'interface externe |
| `distributed` | bool | — | Mode DVR (admin only) |
| `availability_zone_hints` | list(string) | — | AZ préférées |
| `tags` | set(string) | — | Tags |

### `openstack_networking_router_interface_v2`

| Argument | Type | Req. | Description |
|---|---|---|---|
| `router_id` | string | ✓ | ID du routeur |
| `subnet_id` | string | — | ID du subnet à connecter (option 1) |
| `port_id` | string | — | ID d'un port existant (option 2) |

### `openstack_networking_floatingip_v2`

| Argument | Type | Req. | Description |
|---|---|---|---|
| `pool` | string | ✓ | Nom du network externe (ex: `ext-net`) |
| `description` | string | — | Description |
| `port_id` | string | — | Port à associer directement (sinon utiliser une ressource d'association) |
| `fixed_ip` | string | — | IP fixe interne ciblée si le port en a plusieurs |
| `subnet_id` | string | — | Subnet du pool si plusieurs |
| `dns_name` | string | — | Nom DNS |
| `dns_domain` | string | — | Domaine DNS |
| `tags` | set(string) | — | Tags |
| *`address`* | string | — | IP allouée |

### `openstack_networking_floatingip_associate_v2`

Association séparée — utile quand on veut découpler la durée de vie de la FIP de son association.

| Argument | Type | Req. | Description |
|---|---|---|---|
| `floating_ip` | string | ✓ | Adresse IP flottante (string, pas l'ID) |
| `port_id` | string | ✓ | Port cible |
| `fixed_ip` | string | — | IP fixe précise du port si plusieurs |

### `openstack_networking_secgroup_v2`

| Argument | Type | Req. | Description |
|---|---|---|---|
| `name` | string | ✓ | Nom |
| `description` | string | — | Description |
| `delete_default_rules` | bool | — | Supprime les règles d'egress par défaut |
| `tags` | set(string) | — | Tags |

### `openstack_networking_secgroup_rule_v2`

| Argument | Type | Req. | Description |
|---|---|---|---|
| `security_group_id` | string | ✓ | SG parent |
| `direction` | string | ✓ | `ingress` ou `egress` |
| `ethertype` | string | ✓ | `IPv4` ou `IPv6` |
| `protocol` | string | — | `tcp`, `udp`, `icmp`, `any`, ou numéro |
| `port_range_min` | number | — | Port début (ignoré pour ICMP) |
| `port_range_max` | number | — | Port fin |
| `remote_ip_prefix` | string | — | CIDR source/destination |
| `remote_group_id` | string | — | SG source (alternative au CIDR) |
| `description` | string | — | Description |

`remote_ip_prefix` et `remote_group_id` sont mutuellement exclusifs.

## V.3 Block Storage (Cinder)

### `openstack_blockstorage_volume_v3`

| Argument | Type | Req. | Description |
|---|---|---|---|
| `size` | number | ✓* | Taille en Go (sauf si `snapshot_id` ou `source_vol_id`) |
| `name` | string | — | Nom |
| `description` | string | — | Description |
| `availability_zone` | string | — | AZ Cinder |
| `image_id` | string | — | Crée le volume depuis une image |
| `snapshot_id` | string | — | Crée depuis un snapshot |
| `source_vol_id` | string | — | Clone d'un volume existant |
| `volume_type` | string | — | Type Cinder (HDD, SSD…) selon le cloud |
| `metadata` | map(string) | — | Métadonnées |
| `multiattach` | bool | — | Permet l'attachement multi-VM |
| `enable_online_resize` | bool | — | Autorise le resize sans détacher |

## V.4 Images (Glance)

Tu crées rarement des images en Terraform — généralement, tu les lis. Mais la ressource existe :

### `openstack_images_image_v2` (resource)

| Argument | Type | Req. | Description |
|---|---|---|---|
| `name` | string | ✓ | Nom |
| `image_source_url` | string | — | URL distante à télécharger |
| `local_file_path` | string | — | Fichier local à uploader |
| `container_format` | string | ✓ | `bare` la plupart du temps |
| `disk_format` | string | ✓ | `qcow2`, `raw`, `vmdk`… |
| `min_disk_gb` | number | — | Taille minimum de disque |
| `min_ram_mb` | number | — | RAM minimum |
| `visibility` | string | — | `private`, `shared`, `community`, `public` |
| `tags` | set(string) | — | Tags |
| `web_download` | bool | — | Téléchargement direct depuis l'URL côté Glance |

## V.5 Data sources les plus utiles

### `openstack_images_image_v2`

| Argument | Description |
|---|---|
| `name` | Nom exact ou regex |
| `name_regex` | Pattern de nom |
| `most_recent` | Si plusieurs matches, prend la plus récente |
| `visibility` | `public`, `private`… |
| `owner` | ID du projet propriétaire |
| `tag` | Filtre par tag |

Attributs renvoyés : `id`, `size_bytes`, `min_disk_gb`, `min_ram_mb`, `properties`…

### `openstack_compute_flavor_v2`

| Argument | Description |
|---|---|
| `flavor_id` | ID exact |
| `name` | Nom exact |
| `min_ram` / `min_disk` / `min_vcpus` | Filtrage |

Attributs : `id`, `ram`, `vcpus`, `disk`, `ephemeral`, `is_public`.

### `openstack_networking_network_v2`

| Argument | Description |
|---|---|
| `name` | Nom |
| `network_id` | ID exact |
| `external` | Filtre les networks externes |
| `tags` | Tags requis |

### `openstack_networking_subnet_v2`

| Argument | Description |
|---|---|
| `name` | Nom |
| `cidr` | CIDR |
| `network_id` | Network parent |
| `subnet_id` | ID exact |

### `openstack_compute_keypair_v2`

| Argument | Description |
|---|---|
| `name` | Nom de la keypair |

---

# Partie VI — Référence rapide

## VI.1 Variables d'environnement Terraform les plus utiles

| Variable | Effet |
|---|---|
| `TF_VAR_<nom>` | Définit la variable `<nom>` |
| `TF_LOG=DEBUG` (ou `TRACE`, `INFO`) | Active les logs verbeux |
| `TF_LOG_PATH=fichier.log` | Redirige les logs |
| `TF_INPUT=0` | Désactive les prompts interactifs |
| `TF_CLI_ARGS_apply="-auto-approve"` | Ajoute des flags à `apply` automatiquement |

## VI.2 Variables d'environnement OpenStack les plus utiles

Lues automatiquement par le provider :

| Variable | Rôle |
|---|---|
| `OS_AUTH_URL` | Endpoint Keystone |
| `OS_USERNAME` | Login |
| `OS_PASSWORD` | Mot de passe (préférer un fichier openrc qui prompte) |
| `OS_PROJECT_NAME` | Projet courant |
| `OS_USER_DOMAIN_NAME`, `OS_PROJECT_DOMAIN_NAME` | Domaines (souvent `Default`) |
| `OS_REGION_NAME` | Région |
| `OS_AUTH_TYPE=v3applicationcredential` | Mode application credentials |
| `OS_APPLICATION_CREDENTIAL_ID` / `_SECRET` | Identifiants application credential |

## VI.3 Fichiers d'un projet Terraform

| Fichier | Rôle | Versionner ? |
|---|---|---|
| `*.tf` | Code source | Oui |
| `*.tfvars` | Valeurs de variables | Non si secrets |
| `terraform.tfstate` | État | Non, jamais |
| `terraform.tfstate.backup` | Backup automatique du state précédent | Non |
| `.terraform/` | Caches local du `init` | Non |
| `.terraform.lock.hcl` | Versions exactes des providers | Oui |
| `*.tfplan` | Plan sauvegardé | Non |

`.gitignore` minimal :
```
*.tfstate
*.tfstate.backup
.terraform/
*.auto.tfvars
secrets.tfvars
*.tfplan
```

## VI.4 Liens

- Documentation du provider OpenStack : `registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs`
- Documentation HCL : `developer.hashicorp.com/terraform/language`
- Documentation OpenStack : `docs.openstack.org`
- Cheatsheet du client `openstack` : `docs.openstack.org/python-openstackclient/latest/cli/command-list.html`