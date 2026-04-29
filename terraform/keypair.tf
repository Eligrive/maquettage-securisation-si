resource "openstack_compute_keypair_v2" "uc_keypair" {
  name       = "${var.prefix}keypair-admin"
  public_key = var.ssh_public_key
}
