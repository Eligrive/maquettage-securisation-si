# security.tf
# Security group "allow all" historique.
#
# Status : DEFINI MAIS PLUS ATTACHE à aucun de nos ports.
#
# Pourquoi ne pas le supprimer :
#   - Le groupe artvisio (autre groupe du projet OpenStack mutualisé) a
#     attaché ce SG à 2 de leurs ports (probablement par erreur, ou réutil
#     croisée). Neutron refuse de détruire un SG encore référencé.
#   - On ne peut pas casser leurs ports pour libérer le SG, donc on garde
#     le resource en Terraform pour qu'apply ne tente plus la destruction.
#
# Pourquoi il n'est plus attaché à nos ports :
#   - On a désactivé port_security sur tous nos ports (cf. network.tf) pour
#     contourner le drop OVS firewall sur les paquets forwardés via fw-legacy.
#   - Avec port_security=False, les SG ne sont pas appliqués de toute façon ;
#     le filtrage effectif est entièrement délégué à iptables sur fw-legacy.

resource "openstack_networking_secgroup_v2" "allow_all" {
  name        = "${var.resource_prefix}-sg-allow-all"
  description = "Security group permissif (maquette vulnérable) - non attaché"

  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "ingress_tcp_all" {
  description       = "Allow all inbound TCP (vuln)"
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.allow_all.id
}

resource "openstack_networking_secgroup_rule_v2" "ingress_udp_all" {
  description       = "Allow all inbound UDP (vuln)"
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.allow_all.id
}

resource "openstack_networking_secgroup_rule_v2" "ingress_icmp" {
  description       = "Allow all inbound ICMP (vuln)"
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.allow_all.id
}

resource "openstack_networking_secgroup_rule_v2" "egress_all" {
  description       = "Allow all outbound (vuln)"
  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.allow_all.id
}
