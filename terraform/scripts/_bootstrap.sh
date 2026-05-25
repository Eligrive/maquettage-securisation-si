#!/bin/bash
# Bootstrap commun à toutes les VMs Ubuntu de la maquette.
# Exécuté en premier (multipart cloud-init, cf. cloudinit.tf).
#
# Objectif : activer l'authentification SSH par mot de passe afin de permettre
# la latéralisation par réutilisation de credentials, qui est LA conséquence
# directe de l'absence de SSO décrite dans l'énoncé.
#
# Les comptes Unix nominatifs (jdupont, lmartin, sleblanc, cfournier, dsi, pa1)
# sont créés par les scripts spécifiques de chaque VM avec le MÊME mot de passe
# que celui utilisé dans les applications associées (Moodle, LDAP, mail, etc.),
# modélisant la dérive "un seul mot de passe par utilisateur, partout".
set -x
exec > /var/log/uc-bootstrap.log 2>&1
export DEBIAN_FRONTEND=noninteractive

# --- SSH password authentication (vuln volontaire : pas de SSO) ---
# Les images cloud Ubuntu ont par défaut PasswordAuthentication=no via
# /etc/ssh/sshd_config.d/60-cloudimg-settings.conf. On override.
cat > /etc/ssh/sshd_config.d/99-uc-passwords.conf <<'EOF'
PasswordAuthentication yes
KbdInteractiveAuthentication yes
PermitRootLogin no
EOF
# Filet de sécurité si une distrib n'utilise pas le sshd_config.d
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null || true

systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true

echo "uc-bootstrap done (SSH password auth enabled)"
