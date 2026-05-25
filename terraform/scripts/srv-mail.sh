#!/bin/bash
# Provisioning uc-srv-mail (Ubuntu 22.04) — cf. architecture §4.2, §6.2
# Messagerie en clair : SMTP 25, IMAP 143, POP3 110, auth plaintext, pas de TLS.
set -x
exec > /var/log/uc-provision.log 2>&1
export DEBIAN_FRONTEND=noninteractive

debconf-set-selections <<< "postfix postfix/mailname string unicampus.local"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
apt-get update
apt-get install -y postfix dovecot-imapd dovecot-pop3d mailutils

# --- Postfix : écoute partout, aucun TLS, Maildir ---
postconf -e 'inet_interfaces = all'
postconf -e 'inet_protocols = ipv4'
postconf -e 'mydestination = unicampus.local, localhost.localdomain, localhost'
postconf -e 'mynetworks = 0.0.0.0/0'        # relais ouvert (vuln volontaire)
postconf -e 'smtpd_tls_security_level = none'
postconf -e 'home_mailbox = Maildir/'

# --- Dovecot : plaintext autorisé, pas de TLS ---
sed -i 's/^#\?disable_plaintext_auth.*/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf
sed -i 's/^#\?auth_mechanisms.*/auth_mechanisms = plain login/'      /etc/dovecot/conf.d/10-auth.conf
sed -i 's|^#\?mail_location.*|mail_location = maildir:~/Maildir|'    /etc/dovecot/conf.d/10-mail.conf
sed -i 's/^#\?ssl =.*/ssl = no/'                                    /etc/dovecot/conf.d/10-ssl.conf

# --- Comptes de messagerie (Unix locaux, mots de passe identiques aux autres
#     services -> dérive "pas de SSO -> réutilisation des credentials").
#     Ces comptes servent aussi de comptes SSH (bootstrap activé partout). ---
useradd -m -s /bin/bash jdupont   2>/dev/null || true; echo 'jdupont:unicampus2024'   | chpasswd
useradd -m -s /bin/bash lmartin   2>/dev/null || true; echo 'lmartin:Printemps2024'   | chpasswd
useradd -m -s /bin/bash sleblanc  2>/dev/null || true; echo 'sleblanc:recherche2024'  | chpasswd
useradd -m -s /bin/bash cfournier 2>/dev/null || true; echo 'cfournier:finance2024'   | chpasswd
# Compte DSI réutilisé sur tous les serveurs (cf. justif §X dans archi technique).
useradd -m -s /bin/bash dsi       2>/dev/null || true; echo 'dsi:admin2024'           | chpasswd
echo 'dsi ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/91-uc-dsi
chmod 0440 /etc/sudoers.d/91-uc-dsi

# --- Dépôt du leurre PDF (email DSI contenant les identifiants VPN) ---
if [ -f /opt/loot/email_dsi_acces_vpn_CONFIDENTIEL.pdf ]; then
  install -o jdupont -g jdupont -m 0644 \
    /opt/loot/email_dsi_acces_vpn_CONFIDENTIEL.pdf \
    /home/jdupont/email_dsi_acces_vpn_CONFIDENTIEL.pdf
fi

# --- Leurre texte : mail informel DSI partagé en clair (compte admin réutilisé).
#     Modélise une dérive courante : la DSI distribue par mail un compte d'admin
#     "de secours" en clair, finissant par traîner dans les boites des personnels. ---
mkdir -p /home/jdupont/Maildir/cur
cat > /home/jdupont/Maildir/cur/1700000000.uc.mail:2,S <<'EOF'
From: dsi@unicampus.local
To: all-staff@unicampus.local
Subject: [INFO DSI] Compte d'urgence acces serveurs
Date: Mon, 10 Sep 2024 09:14:22 +0200

Bonjour a tous,

En cas d'indisponibilite du support, vous pouvez utiliser le compte
d'administration "de secours" partage avec l'equipe :

  login   : dsi
  mdp     : admin2024
  serveurs: uc-srv-moodle, uc-web-rh, uc-srv-mail, uc-calc-recherche,
            uc-srv-ldap, uc-db-rh (SSH 22)

Ce compte dispose de sudo sans mot de passe sur toutes les VMs.
Merci de ne pas le diffuser hors de l'etablissement.

Cordialement,
Service DSI - UniCampus+
EOF
chown -R jdupont:jdupont /home/jdupont/Maildir

systemctl enable postfix dovecot
systemctl restart postfix dovecot

echo "uc-srv-mail provisioning done"
