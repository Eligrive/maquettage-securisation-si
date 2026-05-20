# floating_ips.tf
# Floating IPs pour les 4 VMs exposées sur le réseau externe (cf. architecture §7.1)
#   uc-fw-legacy   -> SSH admin
#   uc-vpn-legacy  -> PPTP 1723/tcp + GRE
#   uc-srv-mail    -> SMTP 25, IMAP 143
#   uc-srv-moodle  -> HTTP 80

locals {
  # VMs à exposer publiquement.
  # Chaque clé doit exister dans local.fixed_ips (network.tf) car on attache
  # la floating IP au port Neutron correspondant.
  floating_vms = ["fw-legacy", "vpn-legacy", "srv-mail", "srv-moodle"]
}

resource "openstack_networking_floatingip_v2" "public" {
  for_each = toset(local.floating_vms)

  # Le pool est le nom du réseau externe (ext-net), récupéré dans data.tf
  pool        = data.openstack_networking_network_v2.ext_net.name
  description = "${var.resource_prefix}-fip-${each.key}"
}

resource "openstack_networking_floatingip_associate_v2" "public" {
  for_each = toset(local.floating_vms)

  floating_ip = openstack_networking_floatingip_v2.public[each.key].address
  port_id     = openstack_networking_port_v2.fixed[each.key].id
}
