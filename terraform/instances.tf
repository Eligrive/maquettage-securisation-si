# instances.tf

# Architecture :
#   - 8 VMs avec IP fixe → ports Neutron définis dans network.tf, attachés via "port"
#   - 3 postes clients en DHCP → attache directe via "uuid"
#
# Toutes les VMs utilisent m1.small : l'image Debian 10 ne tient pas dans le
# disque de 1 Go de m1.tiny (erreur Nova "Flavor's disk is too small for
# requested image").
#
# availability_zone = "cisco" : la zone par défaut "nova" du cluster école est
# saturée (No valid host was found) ; les hosts disponibles sont dans la zone
# "cisco".

locals {
  # VMs avec IP fixe : utilisent les ports Neutron définis dans network.tf
  vms_fixed = {
    fw-legacy = {
      flavor_id = data.openstack_compute_flavor_v2.small.id
      image_id  = data.openstack_images_image_v2.debian10.id
    }
    vpn-legacy = {
      flavor_id = data.openstack_compute_flavor_v2.small.id
      image_id  = data.openstack_images_image_v2.ubuntu.id
    }
    srv-mail = {
      flavor_id = data.openstack_compute_flavor_v2.small.id
      image_id  = data.openstack_images_image_v2.ubuntu.id
    }
    srv-ldap = {
      flavor_id = data.openstack_compute_flavor_v2.small.id
      image_id  = data.openstack_images_image_v2.ubuntu.id
    }
    srv-moodle = {
      flavor_id = data.openstack_compute_flavor_v2.small.id
      image_id  = data.openstack_images_image_v2.ubuntu.id
    }
    web-rh = {
      flavor_id = data.openstack_compute_flavor_v2.small.id
      image_id  = data.openstack_images_image_v2.ubuntu.id
    }
    calc-recherche = {
      flavor_id = data.openstack_compute_flavor_v2.small.id
      image_id  = data.openstack_images_image_v2.ubuntu.id
    }
    db-rh = {
      flavor_id = data.openstack_compute_flavor_v2.small.id
      image_id  = data.openstack_images_image_v2.ubuntu.id
    }
  }

  # Postes clients en DHCP : pas de port explicite
  vms_dhcp = {
    # NB : l'image Kali de l'OpenStack école n'est qu'un ISO (non bootable en
    # cloud), on déploie donc Ubuntu ; l'outillage offensif sera installé
    # via le provisioning du poste attaquant.
    poste-etu = {
      flavor_id = data.openstack_compute_flavor_v2.small.id
      image_id  = data.openstack_images_image_v2.ubuntu.id
    }
    poste-prof = {
      flavor_id = data.openstack_compute_flavor_v2.small.id
      image_id  = data.openstack_images_image_v2.ubuntu.id
    }
    poste-dsi = {
      flavor_id = data.openstack_compute_flavor_v2.small.id
      image_id  = data.openstack_images_image_v2.ubuntu.id
    }
  }
}


resource "openstack_compute_instance_v2" "fixed" {
  for_each = local.vms_fixed

  name              = "${var.resource_prefix}-${each.key}"
  image_id          = each.value.image_id
  flavor_id         = each.value.flavor_id
  key_pair          = openstack_compute_keypair_v2.admin.name
  availability_zone = "cisco"

  # Provisioning : script de service + assets (cf. cloudinit.tf).
  # Cas particulier fw-legacy : cloud-init 18.3 (Debian 10) échoue sur le
  # multipart MIME mono-part généré par cloudinit_config (le handler
  # ShellScriptPartHandler n'enregistre pas le script -> jamais exécuté ->
  # default route reste en boucle sur .2 et fw-legacy ne sort plus).
  # On envoie le script brut : cloud-init détecte le shebang et l'exécute.
  user_data = each.key == "fw-legacy" ? file("${path.module}/scripts/fw-legacy.sh") : data.cloudinit_config.vm[each.key].rendered

  # Interface campus (eth0 sur toutes les VMs).
  network {
    port = openstack_networking_port_v2.fixed[each.key].id
  }

  # Interface DMZ pour fw-legacy uniquement (eth1). C'est ce qui lui permet
  # d'être périmétrique : il a un pied côté Internet (via la DMZ et le
  # routeur Neutron) et un pied côté campus.
  dynamic "network" {
    for_each = each.key == "fw-legacy" ? [openstack_networking_port_v2.fw_dmz.id] : []
    content {
      port = network.value
    }
  }
}

resource "openstack_compute_instance_v2" "dhcp" {
  for_each = local.vms_dhcp

  name              = "${var.resource_prefix}-${each.key}"
  image_id          = each.value.image_id
  flavor_id         = each.value.flavor_id
  key_pair          = openstack_compute_keypair_v2.admin.name
  availability_zone = "cisco"

  # Provisioning : script de service + assets (cf. cloudinit.tf)
  user_data = data.cloudinit_config.vm[each.key].rendered

  # Security group appliqué directement (pas de port explicite ici)
  security_groups = [openstack_networking_secgroup_v2.allow_all.name]

  # Attache au réseau campus, IP attribuée par DHCP
  network {
    uuid = openstack_networking_network_v2.campus.id
  }
}