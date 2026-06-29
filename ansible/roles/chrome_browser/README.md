# Rôle `chrome_browser` — Google Chrome + confiance PKI interne (NSS)

Installe **Google Chrome** sur les postes graphiques et fait **approuver l'ancre de
confiance UniCampus** dans la base **NSS** de l'utilisateur du bureau, pour que les
sites internes en HTTPS (reverse proxy PKI) s'ouvrent **sans avertissement**.

## Pourquoi ce rôle (le problème qu'il corrige)

Le rôle `ca_trust` dépose le `rootCA.crt` dans le **magasin système**
(`/usr/local/share/ca-certificates` + `update-ca-certificates`). Cela suffit pour
`curl`, `openssl`, Teleport, le back-channel OIDC d'Apache/PHP… **mais pas pour
Chrome**.

Sous Linux, Chrome (≥ M131) valide les certificats via son **Chrome Root Store**
et la **base NSS personnelle** de l'utilisateur (`~/.pki/nssdb`) ; il **n'utilise
pas** `/etc/ssl/certs`. Résultat sans ce rôle :

```
Votre connexion n'est pas privée
NET::ERR_CERT_AUTHORITY_INVALID
```

alors que `openssl s_client … -CAfile /etc/ssl/certs/ca-certificates.crt` renvoie
`Verify return code: 0 (ok)`.

> Vérifié empiriquement sur la maquette (Chrome 149) : **seul** l'ajout du CA dans
> NSS (`certutil -A -t "C,,"`) lève l'avertissement. La politique d'entreprise
> `CACertificates` (`/etc/opt/chrome/policies/managed/`) n'était **pas** honorée
> sur cette build — d'où le choix de NSS.

## Où il s'exécute

Listé sur le groupe `[postes]` dans `provision.yml`, **conditionné par
`chrome_enabled`** qui vaut par défaut `vnc_enabled` : il ne s'active donc que là
où il y a un bureau graphique (`uc-poste-etu`, `uc-poste-dsi`).

## Dépendance

Doit s'exécuter **après `ca_trust`** : il réutilise le fichier
`/usr/local/share/ca-certificates/unicampus-root.crt` déposé par celui-ci comme
source unique de l'ancre.

## Principales variables (`defaults/main.yml`)

| Variable | Défaut | Rôle |
|---|---|---|
| `chrome_enabled` | `{{ vnc_enabled }}` | Active le rôle (bureau graphique) |
| `chrome_package` | `google-chrome-stable` | Paquet Chrome |
| `chrome_trust_users` | `[ubuntu]` | Utilisateurs dont la base NSS approuve la CA |
| `chrome_ca_src` | `…/unicampus-root.crt` | Ancre déposée par `ca_trust` |
| `chrome_ca_nickname` | `UniCampus Root CA` | Nom de l'entrée dans NSS |

## Déploiement

```bash
cd ansible/
ansible-playbook -i inventory/hosts.ini provision.yml \
    -e ssh_jump_host="ubuntu@<FIP_firewall>" --tags chrome
```

## Vérification

```bash
# Sur le poste (session utilisateur) : le CA doit apparaître, fié « C,, »
certutil -d sql:$HOME/.pki/nssdb -L | grep UniCampus
# Test bout-en-bout : aucun « net_error -202 » (ERR_CERT_AUTHORITY_INVALID)
google-chrome --headless=new --no-sandbox --dump-dom https://moodle.unicampus.fr
```
