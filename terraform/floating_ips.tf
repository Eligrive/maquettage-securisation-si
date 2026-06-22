# floating_ips.tf
# Floating IPs : toutes attachées au port DMZ de fw-legacy, sur une IP
# fixe distincte (cf. local.fw_dmz_ips dans network.tf). Chaque IP fixe
# DMZ est dédiée à un service ; fw-legacy fait le DNAT iptables vers la
# VM cible côté campus.
#
# Cette topologie rend fw-legacy périmétrique : tout l'ingress externe
# arrive sur fw-legacy avant d'être routé vers les VMs internes.
#
#   FIP fw-legacy → 10.0.0.2 → SSH admin (local sur fw-legacy)
#   FIP vpn       → 10.0.0.3 → DNAT vers 192.168.107.3   (PPTP 1723 + GRE)
#   FIP mail      → 10.0.0.4 → DNAT vers 192.168.107.10  (SMTP/IMAP/POP3)
#   FIP moodle    → 10.0.0.5 → DNAT vers 192.168.107.12  (HTTP 80)
#   FIP web-rh    → 10.0.0.6 → DNAT vers 192.168.107.14  (HTTP 80, expo vuln SO3)

resource "openstack_networking_floatingip_v2" "public" {
  for_each = local.fw_dmz_ips

  pool        = data.openstack_networking_network_v2.ext_net.name
  description = "${var.resource_prefix}-fip-${each.key}"
}

resource "openstack_networking_floatingip_associate_v2" "public" {
  for_each = local.fw_dmz_ips

  floating_ip = openstack_networking_floatingip_v2.public[each.key].address
  port_id     = openstack_networking_port_v2.fw_dmz.id
  fixed_ip    = each.value

  # Sans l'interface routeur reliant la DMZ au réseau externe, Neutron
  # refuse d'attacher un FIP avec ExternalGatewayForFloatingIPNotFound.
  depends_on = [openstack_networking_router_interface_v2.dmz]
}

# ---------------------------------------------------------------------------
# Outputs — consommés par le provisioning Ansible (cf. ansible/).
# ---------------------------------------------------------------------------
# Les services exposés (mail/moodle/web-rh/vpn) sont atteints depuis l'extérieur
# par leur Floating IP. srv_moodle en a besoin : Moodle redirige toutes les
# requêtes vers son wwwroot, qui doit donc être l'URL publique (FIP) et non l'IP
# interne. Passé à Ansible via -e moodle_wwwroot=http://<FIP> (cf. .gitlab-ci.yml).

output "public_floating_ips" {
  description = "Floating IPs des services exposés via fw-legacy (clé = service)."
  value       = { for k, v in openstack_networking_floatingip_v2.public : k => v.address }
}

output "moodle_floating_ip" {
  description = "Floating IP de srv-moodle (wwwroot public du LMS)."
  value       = openstack_networking_floatingip_v2.public["srv-moodle"].address
}

output "fw_legacy_floating_ip" {
  description = "Floating IP de fw-legacy (rebond SSH/ProxyJump des VMs internes en topologie flat)."
  value       = openstack_networking_floatingip_v2.public["fw-legacy"].address
}
