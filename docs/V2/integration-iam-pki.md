# Intégration IaC du lot IAM + PKI (Terraform / Ansible)

Ce document décrit **comment** les briques IAM (SSO Keycloak + bastion Teleport)
et PKI (autorité interne) — prototypées en bash dans `V2_scripts/` sur les
branches `feat/IAM` et `feature/PKI` — ont été intégrées à la maquette V2
segmentée via **Terraform** (infrastructure) et **Ansible** (provisioning).

> **Pas de Let's Encrypt.** L'infrastructure n'a aucun nom de domaine public ni
> accès ACME entrant : on utilise une **PKI interne** (Root CA hors-ligne → CA
> intermédiaire → certificats serveurs *fullchain*), dont l'ancre de confiance
> est distribuée à tous les hôtes. cf. `docs/V2/PKI.md`.

---

## 1. Vue d'ensemble

```
                     Internet
                        │  (FIP firewall : 443 HTTPS + 22 SSH rebond)
                        ▼
        ┌───────────────────────────────────────────┐
        │  uc-srv-firewall (192.168.108.1)           │
        │   • routeur/pare-feu inter-VLAN (iptables) │
        │   • reverse proxy nginx (TLS PKI interne)  │  ← rôle reverse_proxy
        └───────┬───────────────┬───────────────┬────┘
        sso.    │ moodle. mail. │ rh/webrh.     │ bastion.
        unicampus.fr (split DNS interne → 192.168.108.1)
                │               │               │
   ┌────────────▼───┐   ┌───────▼─────┐   ┌─────▼──────────┐
   │ uc-srv-sso     │   │ uc-srv-     │   │ uc-srv-bastion │
   │ Keycloak       │   │ moodle /    │   │ Teleport       │
   │ (107.3, DMZ)   │   │ roundcube / │   │ (103.2, admin) │
   │  └─ fédère ──┐ │   │ web-rh      │   └──────▲─────────┘
   └──────────────┼─┘   └─────────────┘   agents │ (SSH/DB)
                  ▼                        ldap/mail/moodle/roundcube/
        uc-srv-ldap (104.1, LDAPS)        web-rh/db-rh/calc-recherche
```

* **Reverse proxy = sur le firewall** (choix d'archi) : nginx y termine le TLS
  pour tous les services web et relaie en HTTP vers les backends. Le firewall a
  un pied sur chaque VLAN, il joint donc tous les backends en local.
* **Entrée web unique** : la Floating IP du firewall, port 443.
* **Split DNS** : en interne `*.unicampus.fr` → `192.168.108.1` (rôle
  `unicampus_dns`) ; en externe → la Floating IP du firewall.

---

## 2. Terraform (infrastructure)

`terraform/network.tf` — 3 nouvelles VMs ajoutées à `vm_ips` / `vm_vlan`
(création automatique des ports + instances via `for_each`) :

| VM | IP | VLAN | Rôle |
|---|---|---|---|
| `uc-srv-sso` | 192.168.107.3 | dmz | Keycloak (Docker) |
| `uc-srv-roundcube` | 192.168.107.2 | dmz | Webmail Roundcube |
| `uc-srv-bastion` | 192.168.103.2 | admin | Teleport (auth + proxy) |

`terraform/floating_ips.tf` — la **FIP du firewall** sert désormais aussi
d'entrée web (443) ; nouveaux outputs `web_entrypoint_ip` et `sso_url`.
Aucune nouvelle FIP : le reverse proxy étant sur le firewall, son `:443`
répond directement derrière la FIP existante.

`terraform validate` : **OK**.

---

## 3. Ansible (provisioning)

### Nouveaux rôles

| Rôle | Cible | Rôle joué |
|---|---|---|
| `pki` | contrôleur (localhost) | génère Root CA + CA intermédiaire + certs serveurs (openssl, idempotent) sous `ansible/pki/` (gitignored) |
| `ca_trust` | tous les serveurs + postes | installe `rootCA.crt` dans le magasin système (`update-ca-certificates`) |
| `unicampus_dns` | tous les serveurs + postes | `/etc/hosts` : `*.unicampus.fr` → reverse proxy |
| `reverse_proxy` | firewall | nginx + certificat multi-SAN + vhosts HTTPS |
| `keycloak` | uc-srv-sso | Docker + Compose (Keycloak + PostgreSQL) + realm `unicampus` (rôles + groupes RBAC) + fédération LDAP + clients OIDC |
| `srv_roundcube` | uc-srv-roundcube | Apache/PHP + Roundcube + plugin OIDC |
| `bastion` | uc-srv-bastion | Teleport (auth+proxy) + connecteur OIDC + rôles RBAC |
| `teleport_agent` | nœuds infra + bases | agent Teleport raccordé au bastion (SSH/DB) |

### Rôles existants modifiés

* `srv_ldap` → **LDAPS** (port 636, certificat PKI, `olcTLS*`).
* `srv_mail` → **STARTTLS** Postfix (`smtpd_tls_security_level = may`) + Dovecot
  (`ssl = yes`) avec le certificat PKI.
* `srv_moodle` → **plugin OIDC** `auth_oidc` + `$CFG->sslproxy` + `wwwroot` HTTPS.
* `web_rh` → dépôt de la **configuration OIDC** (`/etc/webrh-oidc.env`).
* `fw_central` → règles FORWARD : `keycloak → ldap` et `agents → bastion`.

### Ordre de déploiement (`provision.yml`)

1. **`pki`** (contrôleur) — certificats générés en premier.
2. wait_for_connection.
3. **firewall** : `fw_central` (active l'egress) → `reverse_proxy`.
4. **base client V2** : `ca_trust` + `unicampus_dns` sur tous les serveurs.
5. `srv_ldap` (LDAPS), `db_rh`, `web_rh` (OIDC), `srv_mail` (TLS).
6. **`keycloak`** (après LDAP, qu'il fédère) → **`srv_roundcube`**.
7. `srv_moodle` (OIDC, après Keycloak), `calc_recherche`, `vpn`.
8. **`bastion`** (après Keycloak) → **`teleport_agent`**.
9. postes (+ `ca_trust` + `unicampus_dns`).

### Variables (`group_vars/all.yml`)

FQDN, mapping vhost→backend (`iam_vhosts`), identifiants Keycloak, secrets OIDC
(`oidc_secrets`), paramètres LDAP/Teleport et définition des certificats PKI
(`pki_server_certs`). Secrets **en clair assumés** (maquette pédagogique ;
reprennent les valeurs des `V2_scripts/` ; passeraient par `ansible-vault` en
production).

---

## 4. Exécution

```bash
cd ansible/
# Pré-requis : openssl sur le contrôleur (génération de la PKI).
ansible-playbook provision.yml \
    -e ssh_jump_host="ubuntu@<FIP_firewall>"

# Rejeux ciblés :
ansible-playbook provision.yml --tags pki,proxy      # PKI + reverse proxy
ansible-playbook provision.yml --tags keycloak       # reconfigurer le SSO
ansible-playbook provision.yml --tags bastion,teleport
```

Accès web : `https://sso.unicampus.fr`, `https://moodle.unicampus.fr`,
`https://mail.unicampus.fr`, `https://rh.unicampus.fr`,
`https://bastion.unicampus.fr` (résolus vers la FIP du firewall côté Internet,
vers `192.168.108.1` côté interne).

---

## 5. Limites connues / points d'attention

* **Connecteur OIDC Teleport = fonctionnalité Enterprise.** En édition OSS,
  remplacer le `kind: oidc` par un connecteur `kind: github`. L'application du
  connecteur est rendue tolérante (`teleport_oidc_required: false`).
* **Realms Keycloak** : un realm applicatif dédié **`unicampus`** porte les
  utilisateurs fédérés, les clients OIDC et le RBAC (rôles `Etudiant`,
  `Professeur`, `Chercheur`, `Admin_DSI`, `Admin_DBA`, `Admin_RH`, `Externe` +
  groupes `Etudiants`/`Equipe_DSI`/… avec rôle assigné). Le realm **`master`**
  est **strictement réservé à l'administration** de Keycloak (login admin). Le
  rattachement des utilisateurs LDAP aux groupes se fait en console (ou via un
  group-mapper LDAP).
* **TLS messagerie en `may`/`yes`** (et non `required`) : le chiffrement est
  *disponible* sans casser les scénarios plaintext de la maquette V1. À durcir
  (`required`) pour la cible de production.
* **Durcissement SSH** (`teleport_agent_harden_ssh`, défaut `true`) désactive
  l'auth par mot de passe sur les nœuds — mettre à `false` pour conserver les
  scénarios « cred reuse » de la V1.
* **Clés PKI** : jamais commitées (`ansible/pki/` gitignored). La Root CA est
  régénérée localement par le rôle `pki` ; en production sa clé resterait
  hors-ligne, chiffrée AES-256.
