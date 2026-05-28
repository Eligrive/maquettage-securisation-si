# network.tf

locals {
  # Passerelle annoncée par DHCP = fw-legacy (.2) au lieu du routeur Neutron
  # (.1). Toutes les VMs envoient leur trafic sortant vers fw-legacy, qui le
  # forwarde au routeur Neutron. fw-legacy devient ainsi "inline" pour
  # l'egress Internet ; il garde sa politique iptables ACCEPT (firewall
  # obsolète qui laisse tout passer, cf. énoncé).
  # NB : VM↔VM en L2 dans le même subnet contourne fw-legacy (volontaire,
  # modélise "pas de cloisonnement réseau interne").
  neutron_router_ip = cidrhost(var.subnet_cidr, 1) # 192.168.107.1
  subnet_gateway    = cidrhost(var.subnet_cidr, 2) # 192.168.107.2 (fw-legacy)
  dhcp_pool_start   = cidrhost(var.subnet_cidr, 100)
  dhcp_pool_end     = cidrhost(var.subnet_cidr, 200)

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
}

resource "openstack_networking_network_v2" "campus" {
  name           = "${var.resource_prefix}-net-campus"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "campus" {
  name       = "${var.resource_prefix}-subnet-campus"
  network_id = openstack_networking_network_v2.campus.id
  cidr       = var.subnet_cidr
  ip_version = 4
  gateway_ip = local.subnet_gateway

  # DHCP activé pour les postes clients (uc-poste-etu, prof, dsi)
  enable_dhcp = true
  allocation_pool {
    start = local.dhcp_pool_start
    end   = local.dhcp_pool_end
  }

  dns_nameservers = ["8.8.8.8", "1.1.1.1"]
}

resource "openstack_networking_router_v2" "campus" {
  name                = "${var.resource_prefix}-router-campus"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.ext_net.id
}

# Le routeur Neutron auto-alloue son IP sur le subnet lors de la création
# initiale (a pris .1 quand gateway_ip valait .1). Une fois alloué, l'IP du
# routeur reste stable même si gateway_ip change. fw-legacy.sh hardcode .1
# comme NEUTRON_ROUTER, ce qui est cohérent avec cet état.
#
# NB : pour un déploiement entièrement fresh (terraform destroy + apply), il
# faudrait re-vérifier que le routeur se voit bien attribuer .1 (l'IP gateway
# .2 étant prise par fw-legacy). Si problème, créer un port explicite à .1
# pour le routeur — mais ce changement déclenche un destroy/create du
# router_interface, qui hang souvent sur Neutron quand des FIPs existent.
resource "openstack_networking_router_interface_v2" "campus" {
  router_id = openstack_networking_router_v2.campus.id
  subnet_id = openstack_networking_subnet_v2.campus.id
}

resource "openstack_networking_port_v2" "fixed" {
  for_each = local.fixed_ips

  name           = "${var.resource_prefix}-port-${each.key}"
  network_id     = openstack_networking_network_v2.campus.id
  admin_state_up = true

  # Security group appliqué à l'interface (cf. security.tf)
  security_group_ids = [openstack_networking_secgroup_v2.allow_all.id]

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.campus.id
    ip_address = each.value
  }
}
