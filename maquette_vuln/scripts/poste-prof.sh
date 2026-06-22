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
Tous les services utilisent le MEME mot de passe (pas de SSO -> dérive
"un mot de passe par utilisateur, valable partout").

Moodle      : http://192.168.107.12     login jdupont / unicampus2024
Messagerie  : 192.168.107.10 (IMAP/25)  login jdupont / unicampus2024
LDAP        : ldap://192.168.107.11     uid=jdupont,ou=people,... / unicampus2024
Recherche   : //192.168.107.15/recherche (Samba, guest)
Jupyter     : http://192.168.107.15:8888 (sans mot de passe)
SSH labo    : ssh jdupont@192.168.107.15                          / unicampus2024
SSH mail    : ssh jdupont@192.168.107.10                          / unicampus2024
SSH moodle  : ssh jdupont@192.168.107.12                          / unicampus2024
EOF
chown ubuntu:ubuntu /home/ubuntu/identifiants.txt
chmod 0644 /home/ubuntu/identifiants.txt

# --- Compte Unix nominatif (cred reuse) ---
useradd -m -s /bin/bash jdupont 2>/dev/null || true; echo 'jdupont:unicampus2024' | chpasswd

echo "uc-poste-prof provisioning done"
