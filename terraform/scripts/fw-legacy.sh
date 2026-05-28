#!/bin/bash
# Provisioning uc-fw-legacy (Debian 10) — cf. architecture §5.2
# Pare-feu « legacy » volontairement permissif : tout est en ACCEPT, routage activé.
#
# fw-legacy est INLINE pour l'egress Internet de toutes les VMs : le subnet
# annonce .2 (fw-legacy) comme gateway via DHCP, donc tout le trafic sortant
# arrive ici avant d'être forwardé vers le routeur Neutron (.1).
# Politique iptables ACCEPT = ne filtre rien (firewall obsolète, cf. énoncé).
set -x
exec > /var/log/uc-provision.log 2>&1
export DEBIAN_FRONTEND=noninteractive

# --- ÉTAPE 0 : override de la route par défaut (priorité absolue) ---
# fw-legacy reçoit lui-même .2 comme gateway via DHCP -> il s'enverrait à
# lui-même son propre trafic sortant (boucle). On le pointe vers le routeur
# Neutron à .1. Le hook dhclient garantit la persistance après renew.
NEUTRON_ROUTER=192.168.107.1
mkdir -p /etc/dhcp/dhclient-exit-hooks.d
cat > /etc/dhcp/dhclient-exit-hooks.d/uc-override-gateway <<EOF
#!/bin/sh
case "\$reason" in
  BOUND|RENEW|REBIND|REBOOT)
    ip route replace default via $NEUTRON_ROUTER dev "\$interface" 2>/dev/null || true
    ;;
esac
EOF
chmod +x /etc/dhcp/dhclient-exit-hooks.d/uc-override-gateway
ip route replace default via $NEUTRON_ROUTER 2>/dev/null || true

# --- ÉTAPE 1 : IP forwarding + désactivation ICMP redirects ---
# send_redirects=0 : sans ça, Linux annonce aux VMs "envoie directement à .1"
# (route plus courte) ce qui fait que les VMs court-circuitent fw-legacy.
cat > /etc/sysctl.d/99-uc-forward.conf <<EOF
net.ipv4.ip_forward=1
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
EOF
sysctl -p /etc/sysctl.d/99-uc-forward.conf

# --- ÉTAPE 2 : Politique iptables ACCEPT (vide tout, accepte tout) ---
for t in filter nat mangle; do iptables -t "$t" -F; iptables -t "$t" -X; done
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Règle résiduelle (vestige d'une ancienne conf, cf. §5.2)
iptables -A INPUT -p tcp --dport 8080 -j ACCEPT

# À ce stade : les autres VMs peuvent router via fw-legacy.

# --- ÉTAPE 3 : Persistance des règles ---
apt-get update
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
apt-get install -y iptables-persistent
netfilter-persistent save

echo "uc-fw-legacy provisioning done"
