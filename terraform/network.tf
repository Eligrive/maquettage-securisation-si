# network.tf

locals {
  # --- Campus 192.168.107.0/24 (subnet interne des VMs) ---
  # Gateway DHCP = fw-legacy (.2). Le subnet n'a PLUS d'interface routeur
  # Neutron : la seule sortie vers Internet est fw-legacy, qui forwarde via
  # son interface DMZ vers le routeur Neutron. Tout l'ingress (FIPs) et
  # l'egress traversent donc fw-legacy.
  subnet_gateway  = cidrhost(var.subnet_cidr, 2) # 192.168.107.2 (fw-legacy)
  dhcp_pool_start = cidrhost(var.subnet_cidr, 100)
  dhcp_pool_end   = cidrhost(var.subnet_cidr, 200)

  fixed_ips = {
    fw-legacy      = cidrhost(var.subnet_cidr, 2)  # 192.168.107.2 (= subnet_gateway)
    vpn-legacy     = cidrhost(var.subnet_cidr, 3)  # 192.168.107.3
    srv-mail       = cidrhost(var.subnet_cidr, 10) # 192.168.107.10
    srv-ldap       = cidrhost(var.subnet_cidr, 11) # 192.168.107.11
    srv-moodle     = cidrhost(var.subnet_cidr, 12) # 192.168.107.12
    web-rh         = cidrhost(var.subnet_cidr, 14) # 192.168.107.14
    calc-recherche = cidrhost(var.subnet_cidr, 15) # 192.168.107.15
    db-rh          = cidrhost(var.subnet_cidr, 20) # 192.168.107.20
  }

  # --- DMZ 10.0.0.0/24 (entre fw-legacy et routeur Neutron) ---
  # 10.0.0.1 = routeur Neutron (gateway DMZ)
  # 10.0.0.2 = fw-legacy primary (SSH admin)
  # 10.0.0.3-6 = alias sur le port fw-legacy DMZ, une IP par service exposé.
  # Chaque FIP s'associe à une de ces IPs via fixed_ip_address ; fw-legacy
  # fait ensuite le DNAT iptables vers l'IP campus correspondante.
  dmz_cidr      = "10.0.0.0/24"
  dmz_router_ip = "10.0.0.1"

  fw_dmz_ips = {
    fw-legacy  = "10.0.0.2" # SSH 22 (terminé localement, pas de DNAT)
    vpn-legacy = "10.0.0.3" # PPTP 1723 + GRE → 192.168.107.3
    srv-mail   = "10.0.0.4" # SMTP/IMAP/POP3 → 192.168.107.10
    srv-moodle = "10.0.0.5" # HTTP 80 → 192.168.107.12
    web-rh     = "10.0.0.6" # HTTP 80 → 192.168.107.14
  }
}

# --- Réseau campus (subnet interne) ---

# port_security_enabled = false au niveau réseau : c'est le défaut hérité par
# les ports DHCP créés automatiquement pour les postes (uc-poste-*). OVS
# firewall avec port_security=true drop les paquets forwardés via fw-legacy
# au niveau du bridge OVS, AVANT que netfilter ne les voie (typique d'une
# topologie "VM en routeur" sur Neutron). En le désactivant côté Neutron,
# le seul firewall qui filtre est fw-legacy lui-même (iptables) — conforme
# au narratif "maquette vulnérable, pas de filtrage périmétrique cloud".

resource "openstack_networking_network_v2" "campus" {
  name                  = "${var.resource_prefix}-net-campus"
  admin_state_up        = true
  port_security_enabled = false
}

resource "openstack_networking_subnet_v2" "campus" {
  name       = "${var.resource_prefix}-subnet-campus"
  network_id = openstack_networking_network_v2.campus.id
  cidr       = var.subnet_cidr
  ip_version = 4
  gateway_ip = local.subnet_gateway

  # DHCP activé pour les postes clients (uc-poste-etu, prof, dsi).
  # Le subnet n'a PAS de router_interface : pas de Floating IP possible
  # vers les VMs internes, c'est volontaire (toute exposition externe
  # passe par fw-legacy).
  enable_dhcp = true
  allocation_pool {
    start = local.dhcp_pool_start
    end   = local.dhcp_pool_end
  }

  dns_nameservers = ["8.8.8.8", "1.1.1.1"]
}

# --- Réseau DMZ (entre fw-legacy et routeur Neutron) ---

resource "openstack_networking_network_v2" "dmz" {
  name                  = "${var.resource_prefix}-net-dmz"
  admin_state_up        = true
  port_security_enabled = false
}

resource "openstack_networking_subnet_v2" "dmz" {
  name       = "${var.resource_prefix}-subnet-dmz"
  network_id = openstack_networking_network_v2.dmz.id
  cidr       = local.dmz_cidr
  ip_version = 4
  gateway_ip = local.dmz_router_ip

  enable_dhcp = true
  allocation_pool {
    start = "10.0.0.100"
    end   = "10.0.0.200"
  }
  dns_nameservers = ["8.8.8.8", "1.1.1.1"]
}

# --- Routeur Neutron : UNIQUEMENT sur la DMZ ---
# Plus de router_interface campus : c'est ce qui garantit que tout l'ingress
# externe passe par fw-legacy (les FIPs ne peuvent plus DNAT-er directement
# vers les VMs internes — Neutron exige un router_interface pour ça).

resource "openstack_networking_router_v2" "campus" {
  name                = "${var.resource_prefix}-router-campus"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.ext_net.id
}

resource "openstack_networking_router_interface_v2" "dmz" {
  router_id = openstack_networking_router_v2.campus.id
  subnet_id = openstack_networking_subnet_v2.dmz.id
}

# --- Port DMZ de fw-legacy (multi fixed_ip pour héberger les FIPs) ---

resource "openstack_networking_port_v2" "fw_dmz" {
  name           = "${var.resource_prefix}-port-fw-dmz"
  network_id     = openstack_networking_network_v2.dmz.id
  admin_state_up = true

  # Port_security off : cf. commentaire sur openstack_networking_network_v2.campus.
  # fw-legacy doit pouvoir recevoir/émettre des paquets avec n'importe quel
  # src/dst IP pour faire son boulot de DNAT + routage.
  port_security_enabled = false
  security_group_ids    = []

  # 5 IPs fixes sur le même port. La primaire (.2) est servie par DHCP ;
  # les autres sont attribuées par cloud-init dans fw-legacy.sh (ip addr
  # add). Chaque FIP s'associe à une IP fixe précise via fixed_ip_address.
  dynamic "fixed_ip" {
    for_each = local.fw_dmz_ips
    content {
      subnet_id  = openstack_networking_subnet_v2.dmz.id
      ip_address = fixed_ip.value
    }
  }
}

# --- Ports campus à IP fixe (VMs internes + port campus de fw-legacy) ---

resource "openstack_networking_port_v2" "fixed" {
  for_each = local.fixed_ips

  name           = "${var.resource_prefix}-port-${each.key}"
  network_id     = openstack_networking_network_v2.campus.id
  admin_state_up = true

  # Port_security off : cf. commentaire sur openstack_networking_network_v2.campus.
  # Sans ça, OVS firewall drop les paquets forwardés via fw-legacy au niveau
  # bridge OVS (avant netfilter), ce qui rend impossible le rôle de fw-legacy
  # comme routeur inline pour egress + ingress DNAT.
  port_security_enabled = false
  security_group_ids    = []

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.campus.id
    ip_address = each.value
  }
}
