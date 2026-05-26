data "openstack_networking_network_v2" "ext_net" {
  name     = var.external_network_name
  external = true
}

# OS utilisé par le firewall obsolète
data "openstack_images_image_v2" "debian10" {
  name        = "debian-10"
  most_recent = true
}

# OS utilisé par la plupart des VM.
# Image communautaire Ubuntu 24.04 plus légère que ubuntu-jammy-22.04 :
# tient sur les hosts cisco où ubuntu-jammy-22.04 ne se schedulait pas.
# visibility = "community" : sans ça, Glance ne retourne pas les images
# communautaires dans le filtre par défaut (-> Your query returned no results).
data "openstack_images_image_v2" "ubuntu" {
  name        = "Ubuntu 24.04 2025"
  visibility  = "community"
  most_recent = true
}

# Taille des VM : toutes les instances utilisent m1.small (cf. note instances.tf).
data "openstack_compute_flavor_v2" "small" {
  name = "m1.small"
}
