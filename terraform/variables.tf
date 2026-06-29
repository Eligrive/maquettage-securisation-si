# variables.tf
# Variables paramétrables du déploiement

variable "external_network_name" {
  description = "Nom du réseau externe OpenStack (vérifier sur Horizon)"
  type        = string
  default     = "provider"
}

variable "resource_prefix" {
  description = "Préfixe des ressources, inclut la version de maquette pour cohabitation"
  type        = string
  default     = "uc"
}

variable "ssh_public_key" {
  type        = string
  description = "Clé SSH publique injectée dans les VMs"
  sensitive   = false
}
