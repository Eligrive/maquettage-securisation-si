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

# --- Comptes de messagerie (Unix locaux, mots de passe faibles) ---
for u in jdupont lmartin sleblanc; do
  useradd -m -s /bin/bash "$u" 2>/dev/null || true
done
echo 'jdupont:unicampus2024'  | chpasswd
echo 'lmartin:Printemps2024'  | chpasswd
echo 'sleblanc:recherche2024' | chpasswd

# --- Dépôt du leurre (email DSI contenant les identifiants VPN) ---
if [ -f /opt/loot/email_dsi_acces_vpn_CONFIDENTIEL.pdf ]; then
  install -o jdupont -g jdupont -m 0644 \
    /opt/loot/email_dsi_acces_vpn_CONFIDENTIEL.pdf \
    /home/jdupont/email_dsi_acces_vpn_CONFIDENTIEL.pdf
fi

systemctl enable postfix dovecot
systemctl restart postfix dovecot

echo "uc-srv-mail provisioning done"
