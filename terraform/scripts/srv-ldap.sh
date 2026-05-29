#!/bin/bash
# Provisioning uc-srv-ldap (Ubuntu 22.04) — cf. architecture §6.1
# Annuaire OpenLDAP : bind anonyme autorisé, pas de TLS, mot de passe admin faible.
set -x
exec > /var/log/uc-provision.log 2>&1
export DEBIAN_FRONTEND=noninteractive

# --- Pré-seed debconf pour une install slapd non interactive ---
debconf-set-selections <<< "slapd slapd/internal/generated_adminpw password unicampus2024"
debconf-set-selections <<< "slapd slapd/internal/adminpw password unicampus2024"
debconf-set-selections <<< "slapd slapd/password1 password unicampus2024"
debconf-set-selections <<< "slapd slapd/password2 password unicampus2024"
debconf-set-selections <<< "slapd slapd/domain string unicampus.local"
debconf-set-selections <<< "slapd shared/organization string UniCampus"
debconf-set-selections <<< "slapd slapd/no_configuration boolean false"
debconf-set-selections <<< "slapd slapd/purge_database boolean true"
debconf-set-selections <<< "slapd slapd/move_old_database boolean true"

apt-get update
apt-get install -y slapd ldap-utils
# Reconfigure pour appliquer le suffixe dc=unicampus,dc=local
dpkg-reconfigure -f noninteractive slapd

# --- slapd écoute sur toutes les interfaces (LDAP en clair, port 389) ---
sed -i 's#^SLAPD_SERVICES=.*#SLAPD_SERVICES="ldap:/// ldapi:///"#' /etc/default/slapd
systemctl restart slapd
sleep 3

# --- Force le rootDN password (dpkg-reconfigure ignore le preseed sur les
#     installs récentes, du coup l'admin password reste celui aléatoire généré
#     au premier install -> ldapadd plus bas plante avec "Invalid credentials").
#     On override via ldapmodify EXTERNAL sur slapd-config. ---
ADMIN_HASH=$(slappasswd -s unicampus2024)
ldapmodify -Y EXTERNAL -H ldapi:/// <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: ${ADMIN_HASH}
EOF
sleep 1

# --- Peuplement : OUs + comptes (cf. §6.1) ---
cat > /tmp/uc-base.ldif <<'EOF'
dn: ou=people,dc=unicampus,dc=local
objectClass: organizationalUnit
ou: people

dn: ou=groups,dc=unicampus,dc=local
objectClass: organizationalUnit
ou: groups

dn: uid=lmartin,ou=people,dc=unicampus,dc=local
objectClass: inetOrgPerson
objectClass: posixAccount
uid: lmartin
cn: Lea Martin
sn: Martin
givenName: Lea
uidNumber: 10001
gidNumber: 10001
homeDirectory: /home/lmartin
loginShell: /bin/bash
mail: lea.martin@unicampus.local
userPassword: unicampus2024

dn: uid=jdupont,ou=people,dc=unicampus,dc=local
objectClass: inetOrgPerson
objectClass: posixAccount
uid: jdupont
cn: Jean-Pierre Dupont
sn: Dupont
givenName: Jean-Pierre
uidNumber: 10002
gidNumber: 10002
homeDirectory: /home/jdupont
loginShell: /bin/bash
mail: j.dupont@unicampus.local
userPassword: unicampus2024

dn: cn=etudiants,ou=groups,dc=unicampus,dc=local
objectClass: posixGroup
cn: etudiants
gidNumber: 20001
memberUid: lmartin

dn: cn=enseignants,ou=groups,dc=unicampus,dc=local
objectClass: posixGroup
cn: enseignants
gidNumber: 20002
memberUid: jdupont
EOF

ldapadd -x -D "cn=admin,dc=unicampus,dc=local" -w unicampus2024 -f /tmp/uc-base.ldif

# Bind anonyme : autorisé par défaut sur cette version, on ne durcit rien.

# --- Compte DSI réutilisé (cf. mail dsi sur srv-mail), admin partout ---
useradd -m -s /bin/bash dsi 2>/dev/null || true; echo 'dsi:admin2024' | chpasswd
echo 'dsi ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/91-uc-dsi
chmod 0440 /etc/sudoers.d/91-uc-dsi

echo "uc-srv-ldap provisioning done"
