# cloudinit.tf
# Construit, par VM, un user_data shell BRUT combinant :
#   1. Le dépôt des assets PDF (heredoc base64 inline)
#   2. Le bootstrap commun _bootstrap.sh (sauf fw-legacy)
#   3. Le script de configuration spécifique scripts/<vm>.sh
#
# Pourquoi PAS le data source `cloudinit_config` (multipart MIME) ?
# Cloud-init plante sur ShellScriptPartHandler au moment d'enregistrer les
# parts text/x-shellscript dans /var/lib/cloud/instance/scripts/ (warning
# "Failed calling handler" dans cloud-init-output.log). Conséquence : les
# scripts ne sont JAMAIS exécutés en modules:final → les VMs bootent avec
# une image cloud Ubuntu vanilla, sans Apache/Postfix/MariaDB/… installés.
# Bug observé sur cloud-init 18.3 (Debian 10) ET 24.4.1 (Ubuntu 24.04).
#
# Bypass : on envoie un seul shellscript bash brut. Cloud-init le détecte
# via son shebang (#!/bin/bash) et l'exécute en modules:final sans passer
# par le ShellScriptPartHandler.

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

  bootstrap_content = file("${path.module}/scripts/_bootstrap.sh")

  # Bloc shell qui dépose les assets dans /opt/loot. filebase64 retourne
  # une seule ligne de base64 ; on l'enveloppe dans un heredoc 'EOF_LOOT'
  # (pas d'interpolation, content base64 ne contient que [A-Za-z0-9+/=]).
  asset_blocks = {
    for vm_key in keys(local.all_vms) :
    vm_key => contains(keys(local.asset_dirs), vm_key) ? join("\n", concat(
      ["mkdir -p /opt/loot"],
      [
        for f in fileset("${path.module}/../assets/${local.asset_dirs[vm_key]}", "*.pdf") :
        "base64 -d > '/opt/loot/${f}' <<'EOF_LOOT'\n${filebase64("${path.module}/../assets/${local.asset_dirs[vm_key]}/${f}")}\nEOF_LOOT"
      ]
    )) : "# (no assets for ${vm_key})"
  }

  # user_data combiné par VM. fw-legacy garde son script seul (pas de
  # bootstrap, c'est Debian 10 géré séparément cf. scripts/fw-legacy.sh).
  user_data = {
    for vm_key in keys(local.all_vms) :
    vm_key => vm_key == "fw-legacy" ? file("${path.module}/scripts/fw-legacy.sh") : join("\n\n", [
      "#!/bin/bash",
      "# Combined user_data (assets + bootstrap + setup)",
      "# Bypass du multipart cloudinit_config (cf. cloudinit.tf)",
      local.asset_blocks[vm_key],
      local.bootstrap_content,
      file("${path.module}/scripts/${vm_key}.sh"),
    ])
  }
}
