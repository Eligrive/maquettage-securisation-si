terraform {
  required_version = ">= 1.10"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.3"
    }
  }

  backend "http" {}
}

provider "openstack" {
  # Les crédentials seront initalisés dans la pipeline CI/CD de gitlab.
}
