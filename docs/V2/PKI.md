# Guide de Déploiement de l'Infrastructure à Clés Publiques (PKI) - UniCampus+ v2

Ce document dresse le guide technique complet pour le déploiement opérationnel de la PKI dans l'infrastructure. L'objectif est de corriger l'absence de chiffrement (HTTP et LDAP en clair - Règle 31 ANSSI) et de centraliser la confiance via une topologie à deux niveaux.

---

## 1. Architecture de la Chaîne de Confiance

L'architecture se compose de deux autorités distinctes pour respecter les normes de sécurité (cloisonnement) :

* **Autorité de Certification Racine (Root CA) :** Maintenue **hors-ligne (offline)**. Sa clé privée ne transite jamais par le réseau. Elle sert uniquement à signer l'AC intermédiaire.
* **Autorité de Certification Intermédiaire (Issuing CA) :** Déployée sur une machine (ou répertoire) dédiée au sein du VLAN d'administration (`uc-net-admin`). Elle gère les requêtes quotidiennes et signe les certificats des serveurs web, mail et annuaire.

> ⚠️ **Sécurité de la Clé Racine** > La clé `rootCA.key` doit être protégée par chiffrement (AES-256) et une passphrase. Elle ne doit en aucun cas être provisionnée dynamiquement par Terraform dans les machines de production.

---

## 2. Génération de l'AC Racine (Offline)

À exécuter localement sur votre poste sécurisé :

```bash
#!/bin/bash
# 1. Génération de la clé privée de la racine (chiffrée en AES-256)
openssl genrsa -aes256 -out rootCA.key 4096

# 2. Création du certificat racine auto-signé (Validité: 10 ans)
openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 3650 \
  -out rootCA.crt \
  -subj "/C=FR/ST=Ile-de-France/L=Paris/O=UniCampus/OU=DSI-Securite/CN=UniCampus Root CA"
```

## 3. Initialisation de l'AC Intermédiaire
Sur l'environnement dédié à l'AC intermédiaire, générez sa clé et la demande de signature (CSR), puis signez cette dernière avec l'AC Racine.

```Bash
#!/bin/bash
# 1. Génération de la clé privée de l'AC intermédiaire
openssl genrsa -out intermediateCA.key 4096

# 2. Création de la CSR
openssl req -new -key intermediateCA.key -out intermediateCA.csr \
  -subj "/C=FR/ST=Ile-de-France/L=Paris/O=UniCampus/OU=DSI-Securite/CN=UniCampus Intermediate CA"

# 3. Signature par l'AC Racine (à exécuter côté Root CA) avec extensions v3_ca
openssl x509 -req -days 1825 -sha256 \
  -in intermediateCA.csr \
  -CA rootCA.crt -CAkey rootCA.key -CAcreateserial \
  -out intermediateCA.crt \
  -extfile <(cat <<EOF
[v3_ca]
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer
basicConstraints=critical,CA:true,pathlen:0
keyUsage=critical,digitalSignature,cRLSign,keyCertSign
EOF
)
```
## 4. Automatisation des Certificats Serveurs (Génération Fullchain)
Script generate_server_cert.sh à exécuter par l'AC intermédiaire pour émettre les certificats des services. L'étape 4 (Fullchain) est critique pour que la confiance s'établisse chez les clients.

```Bash
#!/bin/bash
set -e

SERVICE=$1
FQDN=$2

# 1. Clé privée du serveur
openssl genrsa -out ${SERVICE}.key 2048

# 2. CSR avec les informations du service
openssl req -new -key ${SERVICE}.key -out ${SERVICE}.csr \
  -subj "/C=FR/ST=Ile-de-France/L=Paris/O=UniCampus/OU=Services/CN=${FQDN}"

# 3. Signature par l'AC Intermédiaire (Ajout des Subject Alternative Names)
openssl x509 -req -days 730 -sha256 \
  -in ${SERVICE}.csr \
  -CA intermediateCA.crt -CAkey intermediateCA.key -CAcreateserial \
  -out ${SERVICE}.crt \
  -extfile <(cat <<EOF
[v3_req]
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
subjectAltName=DNS:${FQDN}
EOF
)

# 4. Création de la chaîne complète (Fullchain)
cat ${SERVICE}.crt intermediateCA.crt > ${SERVICE}.fullchain.crt
echo "[OK] Certificat fullchain généré pour ${FQDN}"
```

# 5. Scripts de Configuration Applicative (Migration V2)
Fichiers à injecter sur les VMs de la v2. Assurez-vous de transférer les fichiers .key et .fullchain.crt appropriés.

A. Moodle et Web RH (Apache)
```Bash
cp moodle.key /etc/ssl/private/moodle.key
cp moodle.fullchain.crt /etc/ssl/certs/moodle.fullchain.crt
chmod 600 /etc/ssl/private/moodle.key

cat << 'EOF' > /etc/apache2/sites-available/moodle-ssl.conf
<VirtualHost *:443>
    ServerName moodle.unicampus.fr
    DocumentRoot /var/www/html/moodle

    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/moodle.fullchain.crt
    SSLCertificateKeyFile /etc/ssl/private/moodle.key

    # Durcissement
    SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
</VirtualHost>
EOF

a2enmod ssl
a2ensite moodle-ssl
systemctl restart apache2
```
## B. Service de Messagerie (Postfix / Dovecot)
```Bash
# Postfix (SMTP)
postconf -e "smtpd_tls_cert_file = /etc/ssl/certs/mail.fullchain.crt"
postconf -e "smtpd_tls_key_file = /etc/ssl/private/mail.key"
postconf -e "smtpd_tls_security_level = encrypt"
systemctl restart postfix

# Dovecot (IMAP)
sed -i 's/^#ssl = yes/ssl = required/' /etc/dovecot/conf.d/10-ssl.conf
sed -i 's|<ssl_cert_file|</etc/ssl/certs/mail.fullchain.crt|' /etc/dovecot/conf.d/10-ssl.conf
sed -i 's|<ssl_key_file|</etc/ssl/private/mail.key|' /etc/dovecot/conf.d/10-ssl.conf
systemctl restart dovecot
C. Annuaire OpenLDAPS (Port 636)
Bash
cp ldap.key /etc/ssl/private/ldap.key
cp ldap.fullchain.crt /etc/ssl/certs/ldap.fullchain.crt
cp unicampus-root.crt /etc/ssl/certs/unicampus-root.crt

cat << 'EOF' > /tmp/tls_setup.ldif
dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/ssl/certs/ldap.fullchain.crt
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/ssl/private/ldap.key
-
replace: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/ssl/certs/unicampus-root.crt
EOF

ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/tls_setup.ldif
systemctl restart slapd
```
# 6. Distribution de la Confiance sur les Postes Clients
À exécuter sur les machines Linux (postes étudiants et admins) pour approuver l'autorité racine sans alerter les navigateurs ni les clients de messagerie.

```Bash
#!/bin/bash
cat << 'EOF' > /usr/local/share/ca-certificates/unicampus-root.crt
-----BEGIN CERTIFICATE-----
[INSERER LE CONTENU DU ROOTCA.CRT]
-----END CERTIFICATE-----
EOF

update-ca-certificates
```