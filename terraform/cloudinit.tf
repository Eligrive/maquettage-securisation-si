# cloudinit.tf
# ============================================================================
#  user_data MINIMAL par VM — provisioning applicatif délégué à Ansible.
# ============================================================================
#
# Terraform = infrastructure (VM, réseau segmenté, FIP) + cloud-init minimal.
# Tout le provisioning logiciel (paquets, config, comptes, leurres, politique
# pare-feu) est joué par Ansible (cf. ansible/), idempotent et rejouable.
#
# cloud-init est réduit au strict nécessaire pour qu'Ansible se connecte :
#   - VMs métier : hostname (uc-<vm>) + garantie d'un python3.
#   - firewall central : route par défaut côté transit (pour que sa Floating IP
#     réponde et que les VMs internes soient atteintes par rebond). Forwarding +
#     NAT + filtrage inter-VLAN = rôle Ansible fw_central.
#
# Pourquoi un shellscript brut et pas cloudinit_config (multipart) ? Cloud-init
# plante sur ShellScriptPartHandler (Debian 10 ET Ubuntu 24.04) ; le shebang
# #!/bin/bash est exécuté directement en modules:final.

locals {
  # VMs métier (le firewall central a son propre user_data ci-dessous).
  all_vms = keys(local.vm_ips)

  # --- Bootstrap minimal générique (Ubuntu) --------------------------------
  user_data = {
    for vm_key in local.all_vms :
    vm_key => <<-EOT
      #!/bin/bash
      # cloud-init minimal — provisioning applicatif délégué à Ansible (cf. ansible/).
      set -x
      exec > /var/log/uc-bootstrap.log 2>&1
      export DEBIAN_FRONTEND=noninteractive
      hostnamectl set-hostname ${var.resource_prefix}-${vm_key} || true
      command -v python3 >/dev/null 2>&1 || { apt-get update && apt-get install -y python3; }
      echo "uc-bootstrap minimal done (${var.resource_prefix}-${vm_key})"
    EOT
  }

  # --- Bring-up réseau minimal du firewall central -------------------------
  # Le firewall a un pied sur chaque VLAN (gateway .254) et un pied transit
  # (.108.1). Le DHCP de chaque VLAN pousserait une route par défaut : on force
  # la route par défaut côté transit (routeur Neutron .108.254) et on la persiste
  # via un hook dhclient. Le reste (forwarding, NAT, DNAT, filtrage) = Ansible.
  firewall_user_data = <<-EOT
    #!/bin/bash
    # cloud-init minimal firewall central — route par defaut cote transit.
    set -x
    exec > /var/log/uc-bootstrap.log 2>&1
    export DEBIAN_FRONTEND=noninteractive

    hostnamectl set-hostname ${var.resource_prefix}-srv-firewall || true
    TRANSIT_GW=${local.transit_gw_ip}

    # Attendre que l'interface transit ait son IP (.108.1) puis forcer la route.
    for i in $(seq 1 30); do
      TRANSIT_IF=$(ip -o -4 addr show 2>/dev/null | awk '/${replace(local.fw_transit_ip, ".", "\\.")}\// {print $2; exit}')
      [ -n "$TRANSIT_IF" ] && break
      sleep 2
    done

    # Persistance de la route par défaut via un hook dhclient.
    mkdir -p /etc/dhcp/dhclient-exit-hooks.d
    printf '#!/bin/sh\ncase "$reason" in\n  BOUND|RENEW|REBIND|REBOOT) ip route replace default via %s 2>/dev/null || true ;;\nesac\n' "$TRANSIT_GW" > /etc/dhcp/dhclient-exit-hooks.d/uc-override-gateway
    chmod +x /etc/dhcp/dhclient-exit-hooks.d/uc-override-gateway
    ip route replace default via "$TRANSIT_GW" 2>/dev/null || true

    command -v python3 >/dev/null 2>&1 || { apt-get update && apt-get install -y python3; }
    echo "uc-bootstrap minimal firewall done"
  EOT
}
