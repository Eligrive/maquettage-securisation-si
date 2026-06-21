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
# Compatibilité « flat » (develop actuel) vs « segmenté » (cible V2)
# ------------------------------------------------------------------
#   * Par défaut le SIEM est mono-rattaché à uc-net-soc, qui possède une
#     interface routeur Neutron (sortie Internet pour l'install + Floating IP
#     pour le dashboard). Dans la cible V2, le firewall central (192.168.108.1)
#     route le trafic agents uc-net-* -> uc-net-soc:1514/1515.
#   * Tant que la segmentation + le firewall central ne sont pas mergés, le
#     réseau campus plat (192.168.107.0/24) n'a pas de route vers uc-net-soc.
#     Pour permettre une démo de bout en bout sur develop, mettre
#     `siem_attach_campus = true` : une 2e interface est ajoutée sur le réseau
#     campus (192.168.107.30) pour que les agents joignent le manager
#     directement. cloud-init force alors la route par défaut côté SOC pour
#     ne pas casser le retour de la Floating IP.

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

variable "siem_attach_campus" {
  description = "Rattache une 2e interface du SIEM au réseau campus plat (transitoire, pour démo sur develop avant la segmentation). Mettre false dès que le firewall central route uc-net-* -> uc-net-soc."
  type        = bool
  default     = false
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
  # 192.168.107.30 : IP campus du SIEM (cible des agents en mode flat)
  siem_campus_ip = cidrhost(var.subnet_cidr, 30)
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

# Interface campus (eth1) — UNIQUEMENT si siem_attach_campus=true (mode flat
# transitoire). Permet aux agents du réseau plat de joindre le manager sans
# attendre la segmentation/firewall central.
resource "openstack_networking_port_v2" "siem_campus" {
  count = var.siem_attach_campus ? 1 : 0

  name                  = "${var.resource_prefix}-port-siem-campus"
  network_id            = openstack_networking_network_v2.campus.id
  admin_state_up        = true
  port_security_enabled = false
  security_group_ids    = []

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.campus.id
    ip_address = local.siem_campus_ip
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
  # SSH/Python et, en mode flat, fixe la route par défaut côté SOC.
  user_data = local.siem_user_data

  # eth0 : SOC
  network {
    port = openstack_networking_port_v2.siem_soc.id
  }

  # eth1 : campus (conditionnel, mode flat)
  dynamic "network" {
    for_each = var.siem_attach_campus ? [openstack_networking_port_v2.siem_campus[0].id] : []
    content {
      port = network.value
    }
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

    # Mode flat (siem_attach_campus=true) : la VM est bi-rattachée (SOC + campus).
    # DHCP installe deux routes par défaut -> le retour de la Floating IP peut
    # sortir par la mauvaise interface. On force la route par défaut côté SOC
    # (identification par IP, pas par nom d'interface, pour rester robuste).
    SOC_IF=$(ip -o -4 addr show | awk '/192\.168\.109\./ {print $2; exit}')
    CAMPUS_IF=$(ip -o -4 addr show | awk '/192\.168\.107\./ {print $2; exit}')
    if [ -n "$SOC_IF" ] && [ -n "$CAMPUS_IF" ]; then
      ip route del default dev "$CAMPUS_IF" 2>/dev/null || true
      ip route replace default via ${local.siem_soc_gateway} dev "$SOC_IF" || true
    fi

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

output "siem_campus_ip" {
  description = "IP du SIEM côté campus (cible des agents en mode flat), null si non rattaché."
  value       = var.siem_attach_campus ? local.siem_campus_ip : null
}

output "siem_floating_ip" {
  description = "Floating IP du SIEM (accès dashboard/SSH admin), null si non exposé."
  value       = var.siem_expose_fip ? openstack_networking_floatingip_v2.siem[0].address : null
}
