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

# --- Peuplement : OUs + comptes (cf. §6.1 et IAM.md) ---
cat > /tmp/uc-base.ldif <<'EOF'
dn: ou=people,dc=unicampus,dc=local
objectClass: organizationalUnit
ou: people

# ========== ÉTUDIANTS ==========

dn: uid=lmartin,ou=people,dc=unicampus,dc=local
objectClass: inetOrgPerson
uid: lmartin
sn: Martin
givenName: Lea
title: Etudiant
mail: lea.martin@unicampus.local
endscol: 20260619

dn: uid=sgarnier,ou=people,dc=unicampus,dc=local
objectClass: inetOrgPerson
uid: sgarnier
sn: Garnier
givenName: Sophie
title: Etudiant
mail: sophie.garnier@unicampus.local
endscol: 20260901

dn: uid=mbernard,ou=people,dc=unicampus,dc=local
objectClass: inetOrgPerson
uid: mbernard
sn: Bernard
givenName: Marc
title: Etudiant
mail: marc.bernard@unicampus.local
endscol: 20270630

# ========== PROFESSEURS ==========

dn: uid=jdupont,ou=people,dc=unicampus,dc=local
objectClass: inetOrgPerson
uid: jdupont
sn: Dupont
givenName: Jean-Pierre
title: Professeur
mail: j.dupont@unicampus.local
endscol: 20270630

dn: uid=mduchamp,ou=people,dc=unicampus,dc=local
objectClass: inetOrgPerson
uid: mduchamp
sn: Duchamp
givenName: Martine
title: Professeur
mail: martine.duchamp@unicampus.local
endscol: 20270630

# ========== CHERCHEURS ==========

dn: uid=lfouquet,ou=people,dc=unicampus,dc=local
objectClass: inetOrgPerson
uid: lfouquet
sn: Fouquet
givenName: Laurent
title: Chercheur
mail: laurent.fouquet@unicampus.local
endscol: 20270630

# ========== Admin ==========

dn: uid=eparfait,ou=people,dc=unicampus,dc=local
objectClass: inetOrgPerson
uid: eparfait
sn: Parfait
givenName: Eric
title: Admin
mail: eric.parfait@unicampus.local
endscol: 20270630

# ========== DSI ==========

dn: uid=jmoreau,ou=people,dc=unicampus,dc=local
objectClass: inetOrgPerson
uid: jmoreau
sn: Moreau
givenName: Jean
title: DSI
mail: jean.moreau@unicampus.local
endscol: 20270630

# ========== RH ==========

dn: uid=elauren,ou=people,dc=unicampus,dc=local
objectClass: inetOrgPerson
uid: elauren
sn: Lauren
givenName: Elise
title: RH
mail: elise.lauren@unicampus.local
endscol: 20280630
# ========== INTERVENANT EXTERNE ==========

dn: uid=pexternal,ou=people,dc=unicampus,dc=local
objectClass: inetOrgPerson
uid: pexternal
sn: External
givenName: Pierre
title: Intervenant Externe
mail: pierre.external@unicampus.local
endscol: 20290630

EOF

ldapadd -x -D "cn=admin,dc=unicampus,dc=local" -w unicampus2024 -f /tmp/uc-base.ldif

# Bind anonyme : autorisé par défaut sur cette version, on ne durcit rien.

# --- Compte DSI réutilisé (cf. mail dsi sur srv-mail), admin partout ---
useradd -m -s /bin/bash dsi 2>/dev/null || true; echo 'dsi:admin2024' | chpasswd
echo 'dsi ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/91-uc-dsi
chmod 0440 /etc/sudoers.d/91-uc-dsi

echo "uc-srv-ldap provisioning done"
