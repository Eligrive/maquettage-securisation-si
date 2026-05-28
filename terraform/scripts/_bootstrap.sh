#!/bin/bash
# Bootstrap commun à toutes les VMs Ubuntu de la maquette.
# Exécuté en premier (multipart cloud-init, cf. cloudinit.tf).
#
# Objectifs :
# 1. Activer l'authentification SSH par mot de passe (cred reuse, cf. énoncé
#    "pas de SSO -> mots de passe multiples").
# 2. Attendre que fw-legacy soit prêt à forwarder le trafic sortant
#    (sinon apt-get échoue au premier boot car la gateway = .2 = fw-legacy
#    n'est pas encore configurée en mode forwarding).
#
# Les comptes Unix nominatifs (jdupont, lmartin, sleblanc, cfournier, dsi, pa1)
# sont créés par les scripts spécifiques de chaque VM avec le MÊME mot de passe
# que celui utilisé dans les applications associées (Moodle, LDAP, mail, etc.).
set -x
exec > /var/log/uc-bootstrap.log 2>&1
export DEBIAN_FRONTEND=noninteractive

# --- ÉTAPE 1 : Attendre que fw-legacy forwarde vers Internet ---
# Toutes les VMs ont 192.168.107.2 (fw-legacy) comme gateway DHCP. Tant que
# fw-legacy n'a pas activé ip_forward + iptables ACCEPT, on ne peut pas
# atteindre Internet -> apt-get échouera. On attend jusqu'à 5 min.
echo "Waiting for fw-legacy to be ready to forward..."
for i in $(seq 1 60); do
  if curl -s --max-time 3 -o /dev/null http://archive.ubuntu.com/ubuntu/; then
    echo "Routing via fw-legacy OK (try $i)"
    break
  fi
  echo "Waiting for fw-legacy ($i/60)..."
  sleep 5
done

# --- ÉTAPE 2 : SSH password authentication (vuln volontaire : pas de SSO) ---
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

echo "uc-bootstrap done (SSH password auth enabled, fw-legacy reachable)"
