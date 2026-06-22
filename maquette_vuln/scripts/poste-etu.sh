#!/bin/bash
# Provisioning uc-poste-etu (Ubuntu 22.04) — cf. architecture §3.4
# Poste étudiant / machine attaquante. L'image Kali n'étant pas bootable sur
# l'OpenStack école, on installe un outillage offensif de base sur Ubuntu.
set -x
exec > /var/log/uc-provision.log 2>&1
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y nmap netcat-openbsd python3 python3-pip curl git \
  hydra nfs-common smbclient ldap-utils

cat > /home/ubuntu/README.txt <<'EOF'
Poste etudiant / attaquant (uc-poste-etu)
Outils installes : nmap, netcat, hydra, smbclient, nfs-common, ldap-utils.
Cible : sous-reseau 192.168.107.0/24 (maquette UniCampus+).
EOF
chown ubuntu:ubuntu /home/ubuntu/README.txt

echo "uc-poste-etu provisioning done"
