# network.tf

locals {
  subnet_gateway  = cidrhost(var.subnet_cidr, 1)     
  dhcp_pool_start = cidrhost(var.subnet_cidr, 100)   
  dhcp_pool_end   = cidrhost(var.subnet_cidr, 200)   
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


resource "openstack_networking_router_interface_v2" "campus" {
  router_id = openstack_networking_router_v2.campus.id
  subnet_id = openstack_networking_subnet_v2.campus.id
}