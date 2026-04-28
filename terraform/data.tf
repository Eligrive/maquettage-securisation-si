data "openstack_networking_network_v2" "ext_net" {
    name = "provider"
    external = true
}

# OS utilisé par le firewall obsolète
data "openstack_images_image_v2" "debian10" {
    name = "debian-10"
    most_recent = true
}

# OS utilisé par la plupart des VM
data "openstack_images_image_v2" "ubuntu22" {
    name = "ubuntu-jammy-22.04"
    most_recent = true
}

# OS pour le poste de l'étudiant
data "openstack_images_image_v2" "kali" {
  name = "kali"
  most_recent = true
}

# Taille des VM
data "openstack_compute_flavor_v2" "tiny" {
  name = "m1.tiny"
}

data "openstack_compute_flavor_v2" "small" {
  name = "m1.small"
}