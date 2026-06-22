#!/bin/bash
# Provisioning uc-fw-legacy (Debian 10) — pare-feu périmétrique inline
# (topologie DMZ + campus, cf. docs/architecture-technique.md §2)
#
# fw-legacy a deux interfaces :
#   - campus (192.168.107.2) : gateway annoncée par DHCP aux VMs internes
#   - DMZ    (10.0.0.2 + alias .3-.6) : face au routeur Neutron 10.0.0.1
#
# Tout l'ingress (FIPs externes -> alias DMZ -> DNAT vers VMs campus) et
# tout l'egress (VMs campus -> SNAT -> DMZ -> Internet) transitent par
# fw-legacy. Le subnet campus n'a plus de router_interface Neutron, c'est
# fw-legacy l'unique chemin entre les VMs et l'extérieur.
#
# Politique iptables ACCEPT partout : firewall obsolète qui laisse tout
# passer (cf. énoncé "firewall obsolète, règles incohérentes"), on ne fait
# que les translations NAT strictement nécessaires au routage.

set -x
exec > /var/log/uc-provision.log 2>&1
export DEBIAN_FRONTEND=noninteractive

# --- ÉTAPE 0 : identifier les interfaces (campus vs DMZ) ---
# Les noms ne sont pas garantis (eth0/eth1 ou ens3/ens4), on identifie par
# l'IP DHCP. Si une interface n'a pas reçu d'IP après 20s, on force
# dhclient dessus (workaround pour cloud-init qui ne configure parfois que
# la primary).

CAMPUS_IF=""
DMZ_IF=""
for i in $(seq 1 30); do
  CAMPUS_IF=$(ip -o -4 addr show 2>/dev/null | awk '/192\.168\.107\.2\// {print $2; exit}')
  DMZ_IF=$(ip -o -4 addr show 2>/dev/null | awk '/10\.0\.0\.2\// {print $2; exit}')
  if [ -n "$CAMPUS_IF" ] && [ -n "$DMZ_IF" ]; then
    echo "Interfaces detected: campus=$CAMPUS_IF dmz=$DMZ_IF"
    break
  fi
  if [ "$i" = "10" ]; then
    # Force DHCP sur toutes les NICs sans IP
    for iface in $(ls /sys/class/net | grep -vE '^(lo|docker|veth)'); do
      if ! ip -4 addr show "$iface" 2>/dev/null | grep -q 'inet '; then
        echo "Force dhclient on $iface"
        dhclient "$iface" 2>/dev/null || true
      fi
    done
  fi
  echo "Waiting for interfaces (try $i/30) campus=$CAMPUS_IF dmz=$DMZ_IF"
  sleep 2
done

if [ -z "$CAMPUS_IF" ] || [ -z "$DMZ_IF" ]; then
  echo "FATAL: could not detect both interfaces (campus=$CAMPUS_IF dmz=$DMZ_IF)" >&2
  exit 1
fi

# --- ÉTAPE 1 : default route via le routeur Neutron (DMZ 10.0.0.1) ---
# Le subnet campus annonce .2 (fw-legacy lui-même) comme gateway DHCP -> sans
# override, fw-legacy enverrait son propre trafic à lui-même (boucle). On
# force default via 10.0.0.1 (côté DMZ). Le hook dhclient garantit la
# persistance après chaque RENEW (le campus DHCP pousserait sinon à nouveau
# .2 comme gateway).
NEUTRON_ROUTER=10.0.0.1
mkdir -p /etc/dhcp/dhclient-exit-hooks.d
cat > /etc/dhcp/dhclient-exit-hooks.d/uc-override-gateway <<EOF
#!/bin/sh
case "\$reason" in
  BOUND|RENEW|REBIND|REBOOT)
    ip route replace default via $NEUTRON_ROUTER 2>/dev/null || true
    ;;
esac
EOF
chmod +x /etc/dhcp/dhclient-exit-hooks.d/uc-override-gateway
ip route replace default via $NEUTRON_ROUTER 2>/dev/null || true

# --- ÉTAPE 2 : alias IPs sur l'interface DMZ ---
# 10.0.0.3-6 hébergent les FIPs entrantes (vpn, mail, moodle, web-rh).
# Le port Neutron a ces fixed_ip réservés mais DHCP ne sert que la primary
# — on les ajoute manuellement.
for ip in 10.0.0.3 10.0.0.4 10.0.0.5 10.0.0.6; do
  ip addr add "$ip/24" dev "$DMZ_IF" 2>/dev/null || true
done

# Persistance des alias via service systemd oneshot (relance après chaque
# boot, après que network-online soit atteint).
cat > /usr/local/sbin/uc-fw-aliases <<'EOF'
#!/bin/sh
DMZ_IF=$(ip -o -4 addr show 2>/dev/null | awk '/10\.0\.0\.2\// {print $2; exit}')
[ -z "$DMZ_IF" ] && exit 0
for ip in 10.0.0.3 10.0.0.4 10.0.0.5 10.0.0.6; do
  ip addr add "$ip/24" dev "$DMZ_IF" 2>/dev/null || true
done
EOF
chmod +x /usr/local/sbin/uc-fw-aliases

cat > /etc/systemd/system/uc-fw-aliases.service <<EOF
[Unit]
Description=uc-fw-legacy DMZ IP aliases
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/uc-fw-aliases

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable uc-fw-aliases.service

# --- ÉTAPE 3 : IP forwarding + désactivation des ICMP redirects ---
cat > /etc/sysctl.d/99-uc-forward.conf <<EOF
net.ipv4.ip_forward=1
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
EOF
sysctl -p /etc/sysctl.d/99-uc-forward.conf

# --- ÉTAPE 4 : conntrack helpers PPTP (pour vpn-legacy) ---
# Sans nf_nat_pptp, le DNAT GRE proto 47 ne fonctionne pas et le tunnel
# PPTP se monte mais le trafic chiffré ne passe pas.
modprobe nf_conntrack_pptp 2>/dev/null || true
modprobe nf_nat_pptp 2>/dev/null || true
cat > /etc/modules-load.d/uc-pptp-nat.conf <<EOF
nf_conntrack_pptp
nf_nat_pptp
EOF

# --- ÉTAPE 5 : politique iptables ACCEPT (firewall obsolète) ---
for t in filter nat mangle; do iptables -t "$t" -F; iptables -t "$t" -X; done

iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

iptables -P INPUT ACCEPT
iptables -P FORWARD DROP # On bloque tout par défaut
iptables -P OUTPUT ACCEPT

# --- Blocage trafic Etudiants <-> RH/Recherche ---

# Blocage étudiants -> RH
iptables -A FORWARD -s 192.168.101.0/24 -d 192.168.104.0/24 -j DROP

# Blocage RH -> étudiants
iptables -A FORWARD -s 192.168.104.0/24 -d 192.168.101.0/24 -j DROP

# Blocage étudiants -> recherche
iptables -A FORWARD -s 192.168.101.0/24 -d 192.168.102.0/24 -j DROP

#Blocage recherche -> étudiants
iptables -A FORWARD -s 192.168.102.0/24 -d 192.168.101.0/24 -j DROP

# Autorisation HTTPS extérieur -> DMZ
iptables -A FORWARD -s 192.168.101.0/24 -d 192.168.107.0/24 -p tcp --dport 443 -j ACCEPT

# Autorisation étudiants -> mail
iptables -A FORWARD -s 192.168.101.0/24 -d 192.168.105.0/24 -p tcp -m multiport --dports 25,143,110 -j ACCEPT

# Autorisation accès SSH par la dsi (vers tout)
iptables -A FORWARD -s 192.168.103.1 -p tcp --dport 22 -j ACCEPT

# Autorisation chercheur -> mail
iptables -A FORWARD -s 192.168.102.0/24 -d 192.168.105.0/24 -p tcp -m multiport --dports 25,143,110 -j ACCEPT

# Autorisation chercheur -> recherche (PostgreSQL)
iptables -A FORWARD -s 192.168.102.0/24 -d 192.168.102.1 -p tcp --dport 5432 -j ACCEPT

# Autorisation accès VPN (en supposant qu'on utilise Wireguard, port 51820)
iptables -A FORWARD -d 192.168.106.1 -p udp --dport 51820 -j ACCEPT

# --- ÉTAPE 6 : DNAT ingress (services exposés sur les alias DMZ) ---
# Chaque FIP s'associe à une alias DMZ de fw-legacy (cf. floating_ips.tf) ;
# iptables redirige le trafic vers l'IP campus de la VM cible.

# 10.0.0.3 -> vpn-legacy (PPTP 1723 TCP + GRE proto 47)
iptables -t nat -A PREROUTING -d 10.0.0.3 -p tcp --dport 1723 -j DNAT --to-destination 192.168.107.3:1723
iptables -t nat -A PREROUTING -d 10.0.0.3 -p gre -j DNAT --to-destination 192.168.107.3

# 10.0.0.4 -> srv-mail (SMTP 25, IMAP 143, POP3 110)
iptables -t nat -A PREROUTING -d 10.0.0.4 -p tcp --dport 25  -j DNAT --to-destination 192.168.107.10:25
iptables -t nat -A PREROUTING -d 10.0.0.4 -p tcp --dport 143 -j DNAT --to-destination 192.168.107.10:143
iptables -t nat -A PREROUTING -d 10.0.0.4 -p tcp --dport 110 -j DNAT --to-destination 192.168.107.10:110

# 10.0.0.5 -> srv-moodle (HTTP 80)
iptables -t nat -A PREROUTING -d 10.0.0.5 -p tcp --dport 80 -j DNAT --to-destination 192.168.107.12:80

# 10.0.0.6 -> web-rh (HTTP 80)
iptables -t nat -A PREROUTING -d 10.0.0.6 -p tcp --dport 80 -j DNAT --to-destination 192.168.107.14:80

# --- ÉTAPE 7 : SNAT / MASQUERADE sur les deux interfaces ---
# Egress (campus -> DMZ -> Internet) : on masque les VMs internes derrière
# l'IP DMZ primaire de fw-legacy (10.0.0.2). Le routeur Neutron sait
# router les replies vers 10.0.0.2 (qui a une FIP attachée pour le SNAT
# final vers Internet).
iptables -t nat -A POSTROUTING -o "$DMZ_IF" -s 192.168.107.0/24 -j MASQUERADE

# Ingress (DMZ -> DNAT -> campus) : on masque la connexion entrante
# derrière l'IP campus de fw-legacy (192.168.107.2). Sans ce SNAT, la VM
# cible verrait src=IP-externe et son reply repartirait via sa default
# route (= fw-legacy) -> conntrack résoudrait, mais Neutron port_security
# côté campus dropperait le forward initial (src ∉ subnet campus). C'est
# du hide-NAT classique côté firewall périmétrique.
iptables -t nat -A POSTROUTING -o "$CAMPUS_IF" -j MASQUERADE

# --- ÉTAPE 8 : persistance des règles iptables ---
apt-get update
echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
apt-get install -y iptables-persistent
netfilter-persistent save

# Démarrer le service aliases en safety net (au cas où network-online ne
# soit pas encore atteint à ce point — il s'exécutera correctement au
# prochain boot via l'enable au-dessus).
systemctl start uc-fw-aliases.service || true

echo "uc-fw-legacy provisioning done"
