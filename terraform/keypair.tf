resource "openstack_compute_keypair_v2" "admin" {
  name       = "${var.resource_prefix}-keypair-admin"
  public_key = var.ssh_public_key
}
