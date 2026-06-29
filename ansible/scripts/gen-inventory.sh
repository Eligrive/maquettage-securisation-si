#!/usr/bin/env bash
# ============================================================================
#  Génère un inventaire Ansible exploitable à partir des outputs Terraform.
#
#  Remplace le placeholder __SIEM_FIP__ de l'inventaire modèle par la Floating
#  IP réelle du SIEM (sortie `terraform output`). Utilisé par la CI après le
#  terraform apply, mais aussi en local.
#
#  Usage :
#    ansible/scripts/gen-inventory.sh [TEMPLATE] [SORTIE]
#  Variables d'env :
#    TF_DIR   : dossier Terraform (défaut: terraform)
#  Exemples :
#    TF_DIR=terraform ansible/scripts/gen-inventory.sh \
#        ansible/inventory/hosts.ini ansible/inventory/hosts.generated.ini
# ============================================================================
set -euo pipefail

TF_DIR="${TF_DIR:-terraform}"
TEMPLATE="${1:-ansible/inventory/hosts.ini}"
OUTPUT="${2:-ansible/inventory/hosts.generated.ini}"

if [ ! -f "$TEMPLATE" ]; then
  echo "ERREUR : inventaire modèle introuvable : $TEMPLATE" >&2
  exit 1
fi

# La Floating IP peut être absente si siem_expose_fip=false : on tolère.
SIEM_FIP="$(terraform -chdir="$TF_DIR" output -raw siem_floating_ip 2>/dev/null || true)"
SIEM_INT="$(terraform -chdir="$TF_DIR" output -raw siem_internal_ip 2>/dev/null || true)"

if [ -z "$SIEM_FIP" ] || [ "$SIEM_FIP" = "null" ]; then
  echo "AVERTISSEMENT : aucune Floating IP SIEM (siem_expose_fip=false ?)." >&2
  echo "                Le SIEM devra être atteint via le rebond bastion." >&2
  SIEM_FIP="__SIEM_FIP__"
fi

sed "s/__SIEM_FIP__/${SIEM_FIP}/g" "$TEMPLATE" > "$OUTPUT"

echo "Inventaire généré : $OUTPUT"
echo "  SIEM Floating IP : ${SIEM_FIP}"
echo "  SIEM IP interne  : ${SIEM_INT:-<inconnue>}"
