# variables.tf
# Variables paramétrables du déploiement

variable "external_network_name" {
  description = "Nom du réseau externe OpenStack (vérifier sur Horizon)"
  type        = string
  default     = "provider"
}

variable "subnet_cidr" {
  description = "CIDR du réseau interne du campus (à adapter selon OpenStack de l'école)"
  type        = string
  default     = "192.168.107.0/24"
}

variable "resource_prefix" {
  description = "Préfixe des ressources, inclut la version de maquette pour cohabitation"
  type        = string
  default     = "uc"
}