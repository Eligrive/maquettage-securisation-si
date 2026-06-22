# network.tf
# ============================================================================
#  Topologie V2 SEGMENTÉE (cf. docs/V2/network.md)
# ============================================================================
#
# 7 VLAN internes, un par zone métier. Le pare-feu central uc-srv-firewall est
# la GATEWAY (.254) de chaque VLAN interne : il n'y a PAS de router_interface
# Neutron sur ces subnets, donc TOUT le trafic inter-VLAN traverse le firewall
# (qui filtre, cf. rôle Ansible fw_central). C'est la généralisation du pattern
# « VM-routeur inline » utilisé en V1 par fw-legacy.
#
# Un réseau de TRANSIT (192.168.108.0/24) relie le firewall au routeur Neutron :
#   - egress  : VM interne -> firewall (.254) -> SNAT -> transit -> routeur Neutron -> Internet
#   - ingress : FIP -> routeur Neutron -> alias transit du firewall -> DNAT -> service interne
#
# Le routeur Neutron porte des ROUTES STATIQUES (chaque VLAN interne -> firewall)
# pour que le réseau de supervision SOC (uc-net-soc, cf. siem.tf, rattaché au même
# routeur) puisse joindre les agents Wazuh à travers le firewall.
#
# port_security_enabled = false partout : comme en V1, le firewall effectif est
# iptables sur le firewall central, pas les Security Groups OpenStack (l'OVS
# firewall droppe sinon les paquets forwardés au niveau du bridge).

locals {
  # IP du firewall central sur chaque VLAN interne (= gateway du VLAN).
  fw_vlan_ip_octet = 254

  # VLAN internes (cf. docs/V2/network.md). DHCP activé partout : les ports à IP
  # fixe reçoivent leur réservation, et les VMs obtiennent IP + gateway (.254)
  # sans dépendre du datasource config-drive. Pool .100-.200 (hors IP fixes).
  internal_vlans = {
    user      = { cidr = "192.168.101.0/24" } # étudiants/profs
    recherche = { cidr = "192.168.102.0/24" } # calc-recherche
    admin     = { cidr = "192.168.103.0/24" } # DSI / bastion
    rh        = { cidr = "192.168.104.0/24" } # ldap/web-rh/db-rh
    mail      = { cidr = "192.168.105.0/24" } # mail
    vpn       = { cidr = "192.168.106.0/24" } # vpn
    dmz       = { cidr = "192.168.107.0/24" } # moodle (+roundcube/sso V2)
  }

  # Réseau de transit firewall <-> routeur Neutron.
  transit_cidr  = "192.168.108.0/24"
  fw_transit_ip = cidrhost(local.transit_cidr, 1)   # 192.168.108.1 (firewall)
  transit_gw_ip = cidrhost(local.transit_cidr, 254) # 192.168.108.254 (routeur Neutron)

  # IP fixe du firewall sur chaque VLAN interne.
  fw_vlan_ips = {
    for k, v in local.internal_vlans : k => cidrhost(v.cidr, local.fw_vlan_ip_octet)
  }

  # IP fixes des VMs internes (cf. docs/V2/network.md).
  vm_ips = {
    poste-etu      = "192.168.101.1"
    poste-prof     = "192.168.101.2"
    calc-recherche = "192.168.102.1"
    poste-dsi      = "192.168.103.1"
    srv-ldap       = "192.168.104.1"
    web-rh         = "192.168.104.2"
    db-rh          = "192.168.104.3"
    srv-mail       = "192.168.105.1"
    vpn-legacy     = "192.168.106.1"
    srv-moodle     = "192.168.107.1"
  }

  # VLAN d'appartenance de chaque VM.
  vm_vlan = {
    poste-etu      = "user"
    poste-prof     = "user"
    calc-recherche = "recherche"
    poste-dsi      = "admin"
    srv-ldap       = "rh"
    web-rh         = "rh"
    db-rh          = "rh"
    srv-mail       = "mail"
    vpn-legacy     = "vpn"
    srv-moodle     = "dmz"
  }

  # Services exposés en Floating IP : chaque service a une IP alias sur le port
  # transit du firewall, qui fait le DNAT vers l'IP interne du service.
  fw_transit_aliases = {
    vpn-legacy = "192.168.108.10" # PPTP 1723 + GRE -> 192.168.106.1
    srv-mail   = "192.168.108.11" # SMTP/IMAP/POP3 -> 192.168.105.1
    srv-moodle = "192.168.108.12" # HTTP/HTTPS    -> 192.168.107.1
    web-rh     = "192.168.108.13" # HTTP          -> 192.168.104.2
  }
}

# --- VLAN internes (network + subnet, gateway = firewall, sans router_interface) ---

resource "openstack_networking_network_v2" "internal" {
  for_each = local.internal_vlans

  name                  = "${var.resource_prefix}-net-${each.key}"
  admin_state_up        = true
  port_security_enabled = false
}

resource "openstack_networking_subnet_v2" "internal" {
  for_each = local.internal_vlans

  name       = "${var.resource_prefix}-subnet-${each.key}"
  network_id = openstack_networking_network_v2.internal[each.key].id
  cidr       = each.value.cidr
  ip_version = 4

  # Gateway = firewall central (.254). Le subnet n'a PAS de router_interface
  # Neutron : le firewall est l'unique chemin inter-VLAN et vers l'extérieur.
  gateway_ip = local.fw_vlan_ips[each.key]

  enable_dhcp     = true
  dns_nameservers = ["8.8.8.8", "1.1.1.1"]
  allocation_pool {
    start = cidrhost(each.value.cidr, 100)
    end   = cidrhost(each.value.cidr, 200)
  }
}

# --- Réseau de transit firewall <-> routeur Neutron --------------------------

resource "openstack_networking_network_v2" "transit" {
  name                  = "${var.resource_prefix}-net-transit"
  admin_state_up        = true
  port_security_enabled = false
}

resource "openstack_networking_subnet_v2" "transit" {
  name       = "${var.resource_prefix}-subnet-transit"
  network_id = openstack_networking_network_v2.transit.id
  cidr       = local.transit_cidr
  ip_version = 4
  gateway_ip = local.transit_gw_ip # routeur Neutron

  enable_dhcp     = true
  dns_nameservers = ["8.8.8.8", "1.1.1.1"]
  allocation_pool {
    start = cidrhost(local.transit_cidr, 100)
    end   = cidrhost(local.transit_cidr, 200)
  }
}

# --- Routeur Neutron : porte externe + UNIQUEMENT le transit -----------------
# (resource address "campus" conservée : siem.tf y rattache le réseau SOC.)

resource "openstack_networking_router_v2" "campus" {
  name                = "${var.resource_prefix}-router-campus"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.ext_net.id
}

resource "openstack_networking_router_interface_v2" "transit" {
  router_id = openstack_networking_router_v2.campus.id
  subnet_id = openstack_networking_subnet_v2.transit.id
}

# Routes statiques : les VLAN internes sont joignables via le firewall (.108.1).
# Indispensable pour que le SOC (uc-net-soc, même routeur) atteigne les agents.
resource "openstack_networking_router_route_v2" "internal_via_fw" {
  for_each = local.internal_vlans

  router_id        = openstack_networking_router_v2.campus.id
  destination_cidr = each.value.cidr
  next_hop         = local.fw_transit_ip

  depends_on = [openstack_networking_router_interface_v2.transit]
}

# --- Ports du firewall central : un par VLAN interne + le transit ------------

# Un pied sur chaque VLAN interne (IP .254 = gateway du VLAN).
resource "openstack_networking_port_v2" "fw_vlan" {
  for_each = local.internal_vlans

  name                  = "${var.resource_prefix}-port-fw-${each.key}"
  network_id            = openstack_networking_network_v2.internal[each.key].id
  admin_state_up        = true
  port_security_enabled = false
  security_group_ids    = []

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.internal[each.key].id
    ip_address = local.fw_vlan_ips[each.key]
  }
}

# Pied transit : IP primaire .108.1 + une IP alias par service exposé (FIP/DNAT).
resource "openstack_networking_port_v2" "fw_transit" {
  name                  = "${var.resource_prefix}-port-fw-transit"
  network_id            = openstack_networking_network_v2.transit.id
  admin_state_up        = true
  port_security_enabled = false
  security_group_ids    = []

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.transit.id
    ip_address = local.fw_transit_ip
  }

  dynamic "fixed_ip" {
    for_each = local.fw_transit_aliases
    content {
      subnet_id  = openstack_networking_subnet_v2.transit.id
      ip_address = fixed_ip.value
    }
  }
}

# --- Ports des VMs internes (IP fixe dans leur VLAN) -------------------------

resource "openstack_networking_port_v2" "vm" {
  for_each = local.vm_ips

  name                  = "${var.resource_prefix}-port-${each.key}"
  network_id            = openstack_networking_network_v2.internal[local.vm_vlan[each.key]].id
  admin_state_up        = true
  port_security_enabled = false
  security_group_ids    = []

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.internal[local.vm_vlan[each.key]].id
    ip_address = each.value
  }
}
