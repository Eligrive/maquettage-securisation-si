# instances.tf
# ============================================================================
#  Instances V2 segmentées
# ============================================================================
#
# 10 VMs métier, chacune sur un port à IP fixe dans son VLAN (cf. network.tf),
# + le pare-feu central uc-srv-firewall, multi-homed (un pied par VLAN interne
# + le transit). Le firewall remplace l'ancien fw-legacy périmétrique : il route
# et filtre tout l'inter-VLAN (rôle Ansible fw_central).
#
# Toutes les VMs : Ubuntu 24.04, m1.small, zone "cisco" (la zone "nova" du
# cluster école est saturée ; m1.tiny trop petit pour l'image, cf. data.tf).

locals {
  internal_vms = {
    for k, _ in local.vm_ips : k => {
      flavor_id = data.openstack_compute_flavor_v2.small.id
      image_id  = data.openstack_images_image_v2.ubuntu.id
    }
  }
}

resource "openstack_compute_instance_v2" "vm" {
  for_each = local.internal_vms

  name              = "${var.resource_prefix}-${each.key}"
  image_id          = each.value.image_id
  flavor_id         = each.value.flavor_id
  key_pair          = openstack_compute_keypair_v2.admin.name
  availability_zone = "cisco"

  # cloud-init minimal (hostname + python) ; provisioning logiciel = Ansible.
  user_data = local.user_data[each.key]

  network {
    port = openstack_networking_port_v2.vm[each.key].id
  }
}

# --- Pare-feu central (multi-homed) ------------------------------------------
resource "openstack_compute_instance_v2" "firewall" {
  name              = "${var.resource_prefix}-srv-firewall"
  image_id          = data.openstack_images_image_v2.ubuntu.id
  flavor_id         = data.openstack_compute_flavor_v2.small.id
  key_pair          = openstack_compute_keypair_v2.admin.name
  availability_zone = "cisco"

  # cloud-init : route par défaut côté transit (pour que la FIP réponde et
  # qu'Ansible se connecte). Forwarding + NAT + filtrage = rôle Ansible fw_central.
  user_data = local.firewall_user_data

  # eth0 = transit (route par défaut + arrivée des FIP).
  network {
    port = openstack_networking_port_v2.fw_transit.id
  }

  # Un pied par VLAN interne (le firewall en est la gateway .254).
  dynamic "network" {
    for_each = local.internal_vlans
    content {
      port = openstack_networking_port_v2.fw_vlan[network.key].id
    }
  }
}
