#!/bin/bash
# Provisioning uc-poste-prof (Ubuntu 22.04) — cf. architecture §3.4
# Poste enseignant / enseignant-chercheur. Identifiants stockés en clair
# (mauvaise pratique volontaire) donnant accès à Moodle et à la recherche.
set -x
exec > /var/log/uc-provision.log 2>&1
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y nfs-common smbclient firefox 2>/dev/null || \
  apt-get install -y nfs-common smbclient

cat > /home/ubuntu/identifiants.txt <<'EOF'
=== Identifiants UniCampus+ (poste enseignant) ===
Moodle    : http://192.168.107.12   login jdupont / unicampus2024
Messagerie: 192.168.107.10 (IMAP)   login jdupont / unicampus2024
Recherche : //192.168.107.15/recherche (Samba, invite)
Jupyter   : http://192.168.107.15:8888 (sans mot de passe)
EOF
chown ubuntu:ubuntu /home/ubuntu/identifiants.txt
chmod 0644 /home/ubuntu/identifiants.txt

echo "uc-poste-prof provisioning done"
