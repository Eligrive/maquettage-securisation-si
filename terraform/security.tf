# security.tf
# Security groups pour la maquette vulnérable
# Politique "allow all" volontairement permissive

resource "openstack_networking_secgroup_v2" "allow_all" {
  name        = "${var.resource_prefix}-sg-allow-all"
  description = "Security group permissif (maquette vulnérable)"

  # Désactive les règles egress par défaut créées auto par Neutron
  # pour avoir un contrôle total sur le ruleset
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