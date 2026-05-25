# cloudinit.tf
# Assemble, pour chaque VM, un user_data cloud-init combinant :
#   1. (si la VM a des assets) un cloud-config write_files qui dépose les PDF
#      leurres dans /opt/loot via base64 (aucune dépendance réseau) ;
#   2. le script de configuration du service, isolé dans scripts/<vm>.sh.

locals {
  # Toutes les VMs (IP fixe + postes DHCP)
  all_vms = merge(local.vms_fixed, local.vms_dhcp)

  # VMs disposant d'un dossier d'assets (assets/<dir>/) à déployer
  asset_dirs = {
    srv-moodle     = "srv-moodle"
    web-rh         = "web-rh"
    calc-recherche = "calc-recherche"
    srv-mail       = "srv-mail"
    poste-dsi      = "poste-dsi"
  }
}

data "cloudinit_config" "vm" {
  for_each = local.all_vms

  gzip          = false
  base64_encode = false

  # Partie 1 : dépôt des assets dans /opt/loot (uniquement si la VM en a)
  dynamic "part" {
    for_each = contains(keys(local.asset_dirs), each.key) ? [each.key] : []
    content {
      content_type = "text/cloud-config"
      content = yamlencode({
        write_files = [
          for f in fileset("${path.module}/../assets/${local.asset_dirs[each.key]}", "*.pdf") : {
            path        = "/opt/loot/${f}"
            encoding    = "b64"
            content     = filebase64("${path.module}/../assets/${local.asset_dirs[each.key]}/${f}")
            permissions = "0644"
          }
        ]
      })
    }
  }

  # Partie 2 : bootstrap commun (SSH password auth, cf. _bootstrap.sh)
  # Skip pour fw-legacy (Debian 10, géré par son propre script)
  dynamic "part" {
    for_each = each.key != "fw-legacy" ? [1] : []
    content {
      content_type = "text/x-shellscript"
      filename     = "00-bootstrap.sh"
      content      = file("${path.module}/scripts/_bootstrap.sh")
    }
  }

  # Partie 3 : script de configuration du service
  part {
    content_type = "text/x-shellscript"
    filename     = "setup-${each.key}.sh"
    content      = file("${path.module}/scripts/${each.key}.sh")
  }
}
