# siem.tf
# ============================================================================
#  SIEM / SOC — Wazuh all-in-one (manager + indexer + dashboard)
# ============================================================================
#
# Composant V2 « Supervision » (cf. docs/V2/Supervision.md). Ce fichier est
# ADDITIF et auto-contenu : il ne modifie aucune ressource des autres lots
# (segmentation, pare-feu, IAM, VPN). Il peut donc être mergé indépendamment.
#
# Choix d'architecture
# --------------------
#   * Le SIEM vit dans un réseau de supervision DÉDIÉ « uc-net-soc »
#     (192.168.109.0/24), conforme au cloisonnement SOC (le serveur de
#     supervision ne doit pas partager le segment des actifs qu'il surveille).
#   * La VM n'installe RIEN via cloud-init : tout Wazuh est provisionné par
#     Ansible (cf. ansible/). cloud-init ne fait que préparer l'accès SSH/clé
#     et garantir un Python pour Ansible.
#   * Flavor dédié (var.siem_flavor_name) : l'indexer OpenSearch a besoin de
#     ~4 Go de RAM ; m1.small (2 Go) ne suffit pas pour l'all-in-one.
#
# Routage des agents (topologie segmentée)
# -----------------------------------------
#   * Le SIEM est mono-rattaché à uc-net-soc, dont la gateway est le routeur
#     Neutron (sortie Internet pour l'install + Floating IP pour le dashboard).
#   * Les agents Wazuh (VLAN internes uc-net-*) joignent le manager 192.168.109.1
#     via le firewall central : firewall -> routeur Neutron -> SOC, et le retour
#     SOC -> agents emprunte les ROUTES STATIQUES du routeur (uc-net-* -> firewall,
#     cf. openstack_networking_router_route_v2.internal_via_fw dans network.tf).

# ---------------------------------------------------------------------------
# Variables (locales à ce lot pour faciliter le merge isolé)
# ---------------------------------------------------------------------------

variable "siem_flavor_name" {
  description = "Flavor de la VM SIEM. All-in-one Wazuh : >= 4 Go RAM / 2 vCPU. Vérifier 'openstack flavor list' (m1.medium/m1.large selon le cluster)."
  type        = string
  default     = "m1.medium"
}

variable "siem_subnet_cidr" {
  description = "CIDR du réseau de supervision dédié (SOC)."
  type        = string
  default     = "192.168.109.0/24"
}

variable "siem_expose_fip" {
  description = "Attache une Floating IP au SIEM (accès dashboard 443 + SSH admin). Dans la cible V2 l'accès passe par le bastion/VPN ; FIP utile pour le bootstrap et la démo."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Données : flavor SIEM (l'image Ubuntu et le keypair sont définis ailleurs)
# ---------------------------------------------------------------------------

data "openstack_compute_flavor_v2" "siem" {
  name = var.siem_flavor_name
}

# ---------------------------------------------------------------------------
# Réseau de supervision dédié : uc-net-soc
# ---------------------------------------------------------------------------
# port_security_enabled=false : même contrainte que le reste de la maquette
# (cf. network.tf) — les Security Groups OpenStack ne sont pas le point de
# filtrage, c'est le firewall (iptables/nftables) qui fait foi.

locals {
  # 192.168.109.1 : IP SOC du SIEM (cible des agents en topologie segmentée)
  siem_soc_ip = cidrhost(var.siem_subnet_cidr, 1)
  # 192.168.109.254 : routeur Neutron du SOC (gateway par défaut du SIEM)
  siem_soc_gateway = cidrhost(var.siem_subnet_cidr, 254)
}

resource "openstack_networking_network_v2" "soc" {
  name                  = "${var.resource_prefix}-net-soc"
  admin_state_up        = true
  port_security_enabled = false
}

resource "openstack_networking_subnet_v2" "soc" {
  name       = "${var.resource_prefix}-subnet-soc"
  network_id = openstack_networking_network_v2.soc.id
  cidr       = var.siem_subnet_cidr
  ip_version = 4
  gateway_ip = local.siem_soc_gateway

  enable_dhcp     = true
  dns_nameservers = ["8.8.8.8", "1.1.1.1"]
}

# Interface routeur : raccorde le SOC au routeur Neutron existant
# (openstack_networking_router_v2.campus, défini dans network.tf). Donne au
# SIEM une sortie Internet pour l'installation et permet l'attache d'une FIP.
resource "openstack_networking_router_interface_v2" "soc" {
  router_id = openstack_networking_router_v2.campus.id
  subnet_id = openstack_networking_subnet_v2.soc.id
}

# ---------------------------------------------------------------------------
# Ports réseau du SIEM
# ---------------------------------------------------------------------------

# Interface SOC (eth0) : management, dashboard, sortie Internet, FIP.
resource "openstack_networking_port_v2" "siem_soc" {
  name                  = "${var.resource_prefix}-port-siem-soc"
  network_id            = openstack_networking_network_v2.soc.id
  admin_state_up        = true
  port_security_enabled = false
  security_group_ids    = []

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.soc.id
    ip_address = local.siem_soc_ip
  }
}

# ---------------------------------------------------------------------------
# Instance SIEM
# ---------------------------------------------------------------------------

resource "openstack_compute_instance_v2" "siem" {
  name              = "${var.resource_prefix}-srv-siem"
  image_id          = data.openstack_images_image_v2.ubuntu.id
  flavor_id         = data.openstack_compute_flavor_v2.siem.id
  key_pair          = openstack_compute_keypair_v2.admin.name
  availability_zone = "cisco" # zone par défaut "nova" saturée (cf. instances.tf)

  # Provisioning minimal : Ansible installe Wazuh. cloud-init garantit juste
  # SSH/Python (le SOC est routé par Neutron, route par défaut native).
  user_data = local.siem_user_data

  # eth0 : SOC
  network {
    port = openstack_networking_port_v2.siem_soc.id
  }
}

# ---------------------------------------------------------------------------
# Floating IP (accès dashboard + SSH admin pour le bootstrap Ansible)
# ---------------------------------------------------------------------------

resource "openstack_networking_floatingip_v2" "siem" {
  count       = var.siem_expose_fip ? 1 : 0
  pool        = data.openstack_networking_network_v2.ext_net.name
  description = "${var.resource_prefix}-fip-siem"
}

resource "openstack_networking_floatingip_associate_v2" "siem" {
  count = var.siem_expose_fip ? 1 : 0

  floating_ip = openstack_networking_floatingip_v2.siem[0].address
  port_id     = openstack_networking_port_v2.siem_soc.id

  # Le FIP a besoin de l'interface routeur SOC <-> réseau externe.
  depends_on = [openstack_networking_router_interface_v2.soc]
}

# ---------------------------------------------------------------------------
# cloud-init minimal du SIEM
# ---------------------------------------------------------------------------

locals {
  siem_user_data = <<-EOT
    #!/bin/bash
    # cloud-init minimal pour uc-srv-siem — l'installation Wazuh est faite par Ansible.
    set -x
    exec > /var/log/uc-siem-bootstrap.log 2>&1
    export DEBIAN_FRONTEND=noninteractive

    # Hostname cohérent avec l'inventaire Ansible
    hostnamectl set-hostname uc-srv-siem || true

    # Python3 requis par Ansible (présent par défaut sur l'image cloud Ubuntu,
    # on s'en assure malgré tout).
    command -v python3 >/dev/null 2>&1 || (apt-get update && apt-get install -y python3)

    echo "uc-siem-bootstrap done"
  EOT
}

# ---------------------------------------------------------------------------
# Outputs — consommés par la génération d'inventaire Ansible (cf. CI)
# ---------------------------------------------------------------------------

output "siem_internal_ip" {
  description = "IP interne du SIEM côté SOC (cible des agents en topologie segmentée)."
  value       = local.siem_soc_ip
}

output "siem_floating_ip" {
  description = "Floating IP du SIEM (accès dashboard/SSH admin), null si non exposé."
  value       = var.siem_expose_fip ? openstack_networking_floatingip_v2.siem[0].address : null
}
