#!/bin/bash
# Provisioning uc-vpn-legacy (Ubuntu 22.04) — cf. architecture §5.3
# VPN PPTP déprécié : compte partagé, MPPE-128 (RC4), pas de MFA.
set -x
exec > /var/log/uc-provision.log 2>&1
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y pptpd

# --- Configuration du démon ---
cat > /etc/pptpd.conf <<'EOF'
option /etc/ppp/pptpd-options
localip 192.168.107.3
remoteip 192.168.107.210-220
EOF

cat > /etc/ppp/pptpd-options <<'EOF'
name pptpd
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
require-mppe-128
ms-dns 8.8.8.8
ms-dns 1.1.1.1
proxyarp
nodefaultroute
lock
nobsdcomp
novj
novjccomp
nologfd
EOF

# --- Compte VPN partagé en clair (cf. §5.3 et leurre mail) ---
# Format : <login> <service> <secret> <adresses autorisées>
echo 'campus pptpd unicampus2024 *' >> /etc/ppp/chap-secrets

# GRE (proto 47) + 1723/tcp passent déjà via le security group allow-all
systemctl enable pptpd
systemctl restart pptpd

echo "uc-vpn-legacy provisioning done"
