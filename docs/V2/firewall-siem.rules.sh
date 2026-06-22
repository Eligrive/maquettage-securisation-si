#!/bin/bash
# ============================================================================
#  Règles firewall requises par le lot SUPERVISION (SIEM Wazuh + Suricata)
# ============================================================================
#
#  À INTÉGRER dans le ruleset du firewall central (lot feat/pare_feu), entre la
#  politique `iptables -P FORWARD DROP` et la fin du script. Style identique à
#  terraform/scripts/fw-legacy.sh (chaîne FORWARD, ACCEPT explicites).
#
#  Hypothèses de topologie (cf. docs/V2/network.md + terraform/siem.tf) :
#    - Le SIEM (uc-srv-siem) est dans le VLAN SOC dédié, IP 192.168.109.1.
#    - Le VLAN SOC (192.168.109.0/24) est routé/filtré par le firewall central
#      au même titre que les autres VLAN (le firewall est sa passerelle).
#    - La règle ESTABLISHED,RELATED -> ACCEPT est déjà posée en amont (elle
#      gère tout le trafic retour : on n'autorise donc que le sens initiateur).
#
#  Rappel des flux :
#    Agents  --1514/tcp (events) + 1515/tcp (enrôlement)-->  SIEM
#    Admin   --443/tcp (dashboard)----------------------->  SIEM
#    Équip.  --514/udp (syslog, filet sans-agent)-------->  SIEM
#    SIEM    --80/443/tcp + 53 (install/màj/règles ET)--->  Internet
# ============================================================================

SIEM_IP="192.168.109.1"

# --- 1. Agents Wazuh -> manager (depuis TOUS les VLAN internes) -------------
# events (1514) + enrôlement authd (1515).
for VLAN in \
    192.168.101.0/24 \
    192.168.102.0/24 \
    192.168.103.0/24 \
    192.168.104.0/24 \
    192.168.105.0/24 \
    192.168.106.0/24 \
    192.168.107.0/24 \
    192.168.108.0/24 ; do
  iptables -A FORWARD -s "$VLAN" -d "$SIEM_IP" -p tcp -m multiport --dports 1514,1515 -j ACCEPT
done

# --- 2. Accès dashboard (HTTPS 443) : VLAN admin uniquement -----------------
# Le dashboard SOC n'est PAS exposé aux utilisateurs : seuls les postes admin
# (et le bastion) y accèdent. Tout autre accès distant passe par le VPN.
iptables -A FORWARD -s 192.168.103.0/24 -d "$SIEM_IP" -p tcp --dport 443 -j ACCEPT

# --- 3. Syslog distant (filet pour équipements sans agent) ------------------
# À ne garder que si des équipements non-Linux poussent du syslog vers le SIEM.
for VLAN in \
    192.168.104.0/24 \
    192.168.105.0/24 \
    192.168.106.0/24 \
    192.168.107.0/24 \
    192.168.108.0/24 ; do
  iptables -A FORWARD -s "$VLAN" -d "$SIEM_IP" -p udp --dport 514 -j ACCEPT
done

# --- 4. Sortie Internet du SIEM (install Wazuh, MàJ, règles Emerging Threats)
# Nécessaire au bootstrap (packages.wazuh.com) et à suricata-update.
# Restreindre si une politique d'egress stricte est en place.
iptables -A FORWARD -s "$SIEM_IP" -p tcp -m multiport --dports 80,443 -j ACCEPT
iptables -A FORWARD -s "$SIEM_IP" -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -s "$SIEM_IP" -p tcp --dport 53 -j ACCEPT

# ============================================================================
#  NB IDS/IPS : si Suricata tourne en mode IPS (inline) sur CE firewall, la
#  redirection NFQUEUE est posée par le rôle Ansible suricata_ids :
#      iptables -I FORWARD -j NFQUEUE --queue-num 0 --queue-bypass
#  Pour la rendre persistante, l'ajouter ici, APRÈS les ACCEPT ci-dessus, afin
#  que le trafic déjà autorisé soit inspecté (et non bloqué) par la sonde.
# ============================================================================
