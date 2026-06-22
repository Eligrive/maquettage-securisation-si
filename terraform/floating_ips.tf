# floating_ips.tf
# ============================================================================
#  Floating IPs — toutes portées par le port TRANSIT du firewall central.
# ============================================================================
#
# Chaque service exposé a une IP alias sur le port transit du firewall
# (cf. local.fw_transit_aliases). La FIP s'y associe, et le firewall fait le
# DNAT iptables vers l'IP interne du service (rôle Ansible fw_central).
#
#   FIP firewall -> 192.168.108.1  -> SSH admin (rebond Ansible/ProxyJump)
#   FIP vpn      -> 192.168.108.10 -> DNAT 192.168.106.1 (PPTP 1723 + GRE)
#   FIP mail     -> 192.168.108.11 -> DNAT 192.168.105.1 (SMTP/IMAP/POP3)
#   FIP moodle   -> 192.168.108.12 -> DNAT 192.168.107.1 (HTTP/HTTPS)
#   FIP web-rh   -> 192.168.108.13 -> DNAT 192.168.104.2 (HTTP)
#
# Le SIEM a sa propre FIP (cf. siem.tf, réseau SOC routé par le routeur Neutron).

# --- FIP admin du firewall (rebond SSH des VMs internes sans FIP) ------------
resource "openstack_networking_floatingip_v2" "firewall" {
  pool        = data.openstack_networking_network_v2.ext_net.name
  description = "${var.resource_prefix}-fip-firewall"
}

resource "openstack_networking_floatingip_associate_v2" "firewall" {
  floating_ip = openstack_networking_floatingip_v2.firewall.address
  port_id     = openstack_networking_port_v2.fw_transit.id
  fixed_ip    = local.fw_transit_ip

  depends_on = [openstack_networking_router_interface_v2.transit]
}

# --- FIP des services exposés (DNAT par le firewall) ------------------------
resource "openstack_networking_floatingip_v2" "public" {
  for_each = local.fw_transit_aliases

  pool        = data.openstack_networking_network_v2.ext_net.name
  description = "${var.resource_prefix}-fip-${each.key}"
}

resource "openstack_networking_floatingip_associate_v2" "public" {
  for_each = local.fw_transit_aliases

  floating_ip = openstack_networking_floatingip_v2.public[each.key].address
  port_id     = openstack_networking_port_v2.fw_transit.id
  fixed_ip    = each.value

  depends_on = [openstack_networking_router_interface_v2.transit]
}

# --- Outputs — consommés par le provisioning Ansible (cf. ansible/) ----------

output "public_floating_ips" {
  description = "Floating IPs des services exposés via le firewall (clé = service)."
  value       = { for k, v in openstack_networking_floatingip_v2.public : k => v.address }
}

output "moodle_floating_ip" {
  description = "Floating IP de srv-moodle (wwwroot public du LMS)."
  value       = openstack_networking_floatingip_v2.public["srv-moodle"].address
}

output "firewall_floating_ip" {
  description = "Floating IP du firewall central (rebond SSH/ProxyJump des VMs internes)."
  value       = openstack_networking_floatingip_v2.firewall.address
}
