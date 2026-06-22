# cloudinit.tf
# ============================================================================
#  user_data MINIMAL par VM — le provisioning applicatif est délégué à Ansible.
# ============================================================================
#
# Migration cloud-init -> Ansible (cf. ansible/) : Terraform ne fait plus que
# l'INFRASTRUCTURE (VM, réseau, FIP). Tout le provisioning logiciel (paquets,
# config des services, comptes, leurres) est désormais joué par Ansible, qui est
# idempotent, piloté par l'inventaire et rejouable sans recréer les VMs.
#
# cloud-init est réduit au strict minimum nécessaire pour qu'Ansible puisse se
# connecter :
#   - VMs Ubuntu : hostname cohérent + garantie d'un python3 (interpréteur
#     Ansible). L'accès SSH par clé est déjà fourni par le keypair (keypair.tf).
#   - fw-legacy (Debian 10) : bring-up réseau minimal (route par défaut côté DMZ
#     + persistance) pour que sa Floating IP réponde et que les VMs internes
#     soient atteintes par rebond. La politique firewall complète (forwarding,
#     NAT/DNAT, alias DMZ, persistance) est jouée par le rôle Ansible fw_legacy.
#
# Pourquoi PAS le data source cloudinit_config (multipart MIME) ?
# Cloud-init plante sur ShellScriptPartHandler au moment d'enregistrer les
# parts text/x-shellscript dans /var/lib/cloud/instance/scripts/ (warning
# "Failed calling handler") -> les scripts ne sont jamais exécutés. Bug observé
# sur cloud-init 18.3 (Debian 10) ET 24.4.1 (Ubuntu 24.04). On envoie donc un
# shellscript bash brut, détecté via son shebang et exécuté en modules:final.

locals {
  # Toutes les VMs (IP fixe + postes DHCP)
  all_vms = merge(local.vms_fixed, local.vms_dhcp)

  # --- Bootstrap minimal générique (Ubuntu) --------------------------------
  # Hostname aligné sur l'inventaire Ansible (uc-<vm>) + python3 garanti.
  generic_user_data = {
    for vm_key in keys(local.all_vms) :
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

  # --- Bring-up réseau minimal de fw-legacy (Debian 10) --------------------
  # Le subnet campus annonce .2 (fw-legacy lui-même) comme gateway DHCP : sans
  # override, fw-legacy enverrait son propre trafic à lui-même. On force la
  # route par défaut via le routeur Neutron (côté DMZ) et on la persiste via un
  # hook dhclient (le RENEW campus repousserait sinon .2 comme gateway). C'est
  # le minimum pour que la Floating IP de fw-legacy réponde et qu'Ansible se
  # connecte ; le reste (forwarding, NAT, DNAT, alias DMZ) est fait par le rôle
  # Ansible fw_legacy.
  fw_legacy_user_data = <<-EOT
    #!/bin/bash
    # cloud-init minimal fw-legacy — route par défaut côté DMZ. Firewall = Ansible.
    set -x
    exec > /var/log/uc-bootstrap.log 2>&1
    export DEBIAN_FRONTEND=noninteractive

    NEUTRON_ROUTER=${local.dmz_router_ip}

    # Attendre que l'interface DMZ ait son IP (10.0.0.2) puis forcer la route.
    for i in $(seq 1 30); do
      DMZ_IF=$(ip -o -4 addr show 2>/dev/null | awk '/10\.0\.0\.2\// {print $2; exit}')
      [ -n "$DMZ_IF" ] && break
      # Au bout de ~20s, forcer DHCP sur les NIC sans IP (cloud-init ne configure
      # parfois que l'interface primaire).
      if [ "$i" = "10" ]; then
        for iface in $(ls /sys/class/net | grep -vE '^(lo|docker|veth)'); do
          ip -4 addr show "$iface" 2>/dev/null | grep -q 'inet ' || dhclient "$iface" 2>/dev/null || true
        done
      fi
      sleep 2
    done

    # Persistance de la route par défaut via un hook dhclient (printf pour
    # éviter un heredoc bash imbriqué dans le heredoc Terraform). $reason reste
    # littéral (variable du hook), %s est rempli par $NEUTRON_ROUTER.
    mkdir -p /etc/dhcp/dhclient-exit-hooks.d
    printf '#!/bin/sh\ncase "$reason" in\n  BOUND|RENEW|REBIND|REBOOT) ip route replace default via %s 2>/dev/null || true ;;\nesac\n' "$NEUTRON_ROUTER" > /etc/dhcp/dhclient-exit-hooks.d/uc-override-gateway
    chmod +x /etc/dhcp/dhclient-exit-hooks.d/uc-override-gateway
    ip route replace default via "$NEUTRON_ROUTER" 2>/dev/null || true

    # python3 pour Ansible (présent par défaut sur l'image cloud Debian).
    command -v python3 >/dev/null 2>&1 || { apt-get update && apt-get install -y python3; }
    echo "uc-bootstrap minimal fw-legacy done"
  EOT

  # user_data final : générique pour toutes les VMs, override pour fw-legacy.
  user_data = merge(local.generic_user_data, {
    fw-legacy = local.fw_legacy_user_data
  })
}
