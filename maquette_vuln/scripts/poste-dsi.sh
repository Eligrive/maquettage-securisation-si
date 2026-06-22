#!/bin/bash
# Provisioning uc-poste-dsi (Ubuntu 22.04) — cf. architecture §3.4, §6.3
# Poste DSI / admin : sudo NOPASSWD, documents administratifs sensibles,
# emplacement prévu pour la clé privée d'admin (déposée hors-template).
set -x
exec > /var/log/uc-provision.log 2>&1
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y openssh-client nfs-common smbclient

# --- sudo NOPASSWD pour ubuntu (cf. §6.3) ---
echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-uc-nopasswd
chmod 0440 /etc/sudoers.d/90-uc-nopasswd

# --- Compte 'dsi' nominatif (cred réutilisé partout, cf. leurre srv-mail) ---
useradd -m -s /bin/bash dsi 2>/dev/null || true; echo 'dsi:admin2024' | chpasswd
echo 'dsi ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/91-uc-dsi
chmod 0440 /etc/sudoers.d/91-uc-dsi

# --- Documents administratifs / DSI (leurres) ---
mkdir -p /home/ubuntu/Documents
cp /opt/loot/*.pdf /home/ubuntu/Documents/ 2>/dev/null || true
chown -R ubuntu:ubuntu /home/ubuntu/Documents

# Copie également pour le compte dsi (poste DSI = admin)
mkdir -p /home/dsi/Documents
cp /opt/loot/*.pdf /home/dsi/Documents/ 2>/dev/null || true

# --- Notes admin DSI (anti-pattern volontaire) : compte d'urgence en clair ---
# Modélise une dérive courante : la DSI conserve ses identifiants administratifs
# en clair dans un fichier texte sur son poste de travail.
cat > /home/dsi/credentials-admin.txt <<'EOF'
=== Identifiants administration UniCampus+ (DSI) ===

Compte d'admin "dsi" (sudo NOPASSWD sur tous les serveurs) :
  dsi / admin2024

VPN d'acces distant (compte partage, cf. mail diffuse) :
  campus / unicampus2024

Comptes base RH (uc-db-rh, 192.168.107.20:3306) :
  root / root                  (administrateur, GRANT ALL ON *.*)
  rhapp / rh2024               (compte applicatif, GRANT sur rh.*)

Annuaire LDAP (uc-srv-ldap, 192.168.107.11) :
  cn=admin,dc=unicampus,dc=local / unicampus2024
EOF
chown -R dsi:dsi /home/dsi

# --- Clé d'admin (optionnel, pour usage humain pratique du groupe) ---
# Le scénario SO2 est démontré via réutilisation de credentials (cf. mail dsi
# sur srv-mail), pas par vol de clé SSH. La clé reste référencée ici pour
# rester fidèle à la justif §6.3, mais son dépôt manuel n'est plus requis.
install -d -o ubuntu -g ubuntu -m 0700 /home/ubuntu/.ssh
cat > /home/ubuntu/NOTE-cle-admin.txt <<'EOF'
Optionnel : si vous souhaitez aussi démontrer le chemin "vol de clé SSH" plutôt
que la latéralisation par mot de passe, déposez la clé privée correspondant
à la keypair du groupe ici :
  /home/ubuntu/.ssh/id_rsa   (chmod 600)
La chaîne d'attaque principale de SO2 passe désormais par la réutilisation
du compte 'dsi' (cf. docs/scenarios-attaque.md).
EOF
chown ubuntu:ubuntu /home/ubuntu/NOTE-cle-admin.txt

echo "uc-poste-dsi provisioning done"
