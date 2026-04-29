# instances.tf

# Architecture :
#   - 8 VMs avec IP fixe → ports Neutron définis dans network.tf, attachés via "port"
#   - 3 postes clients en DHCP → attache directe via "uuid"

locals {
  # VMs avec IP fixe : utilisent les ports Neutron définis dans network.tf
  vms_fixed = {
    fw-legacy = {
      flavor_id = data.openstack_compute_flavor_v2.tiny.id
      image_id  = data.openstack_images_image_v2.debian10.id
    }
    vpn-legacy = {
      flavor_id = data.openstack_compute_flavor_v2.tiny.id
      image_id  = data.openstack_images_image_v2.ubuntu22.id
    }
    srv-mail = {
      flavor_id = data.openstack_compute_flavor_v2.tiny.id
      image_id  = data.openstack_images_image_v2.ubuntu22.id
    }
    srv-ldap = {
      flavor_id = data.openstack_compute_flavor_v2.tiny.id
      image_id  = data.openstack_images_image_v2.ubuntu22.id
    }
    srv-moodle = {
      flavor_id = data.openstack_compute_flavor_v2.small.id
      image_id  = data.openstack_images_image_v2.ubuntu22.id
    }
    web-rh = {
      flavor_id = data.openstack_compute_flavor_v2.tiny.id
      image_id  = data.openstack_images_image_v2.ubuntu22.id
    }
    calc-recherche = {
      flavor_id = data.openstack_compute_flavor_v2.small.id
      image_id  = data.openstack_images_image_v2.ubuntu22.id
    }
    db-rh = {
      flavor_id = data.openstack_compute_flavor_v2.tiny.id
      image_id  = data.openstack_images_image_v2.ubuntu22.id
    }
  }

  # Postes clients en DHCP : pas de port explicite
  vms_dhcp = {
    poste-etu = {
      flavor_id = data.openstack_compute_flavor_v2.tiny.id
      image_id  = data.openstack_images_image_v2.kali.id
    }
    poste-prof = {
      flavor_id = data.openstack_compute_flavor_v2.tiny.id
      image_id  = data.openstack_images_image_v2.ubuntu22.id
    }
    poste-dsi = {
      flavor_id = data.openstack_compute_flavor_v2.tiny.id
      image_id  = data.openstack_images_image_v2.ubuntu22.id
    }
  }
}


resource "openstack_compute_instance_v2" "fixed" {
  for_each = local.vms_fixed

  name      = "${var.resource_prefix}-${each.key}"
  image_id  = each.value.image_id
  flavor_id = each.value.flavor_id
  key_pair  = openstack_compute_keypair_v2.admin.name

  # Le port Neutron porte déjà l'IP fixe + le security group
  network {
    port = openstack_networking_port_v2.fixed[each.key].id
  }
}

resource "openstack_compute_instance_v2" "dhcp" {
  for_each = local.vms_dhcp

  name      = "${var.resource_prefix}-${each.key}"
  image_id  = each.value.image_id
  flavor_id = each.value.flavor_id
  key_pair  = openstack_compute_keypair_v2.admin.name

  # Security group appliqué directement (pas de port explicite ici)
  security_groups = [openstack_networking_secgroup_v2.allow_all.name]

  # Attache au réseau campus, IP attribuée par DHCP
  network {
    uuid = openstack_networking_network_v2.campus.id
  }
}