#!/bin/bash
# Provisioning uc-fw-legacy (Debian 10) — cf. architecture §5.2
# Pare-feu « legacy » volontairement permissif : tout est en ACCEPT, routage activé.
set -x
exec > /var/log/uc-provision.log 2>&1
export DEBIAN_FRONTEND=noninteractive

# --- IP forwarding (routeur) ---
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-uc-forward.conf
sysctl -p /etc/sysctl.d/99-uc-forward.conf

# --- Politique iptables : tout ACCEPT, tables vidées ---
for t in filter nat mangle; do iptables -t "$t" -F; iptables -t "$t" -X; done
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Règle résiduelle (vestige d'une ancienne conf, cf. §5.2)
iptables -A INPUT -p tcp --dport 8080 -j ACCEPT

# --- Persistance des règles ---
apt-get update
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
apt-get install -y iptables-persistent
netfilter-persistent save

echo "uc-fw-legacy provisioning done"
