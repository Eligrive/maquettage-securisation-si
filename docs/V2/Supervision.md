# Supervision — SIEM, IDS/IPS et centralisation des logs (V2)

> Lot **Supervision** de la maquette UniCampus+ V2. Couvre les failles **5.1**
> (absence de centralisation des logs) et **5.2** (absence de SOC / IDS-IPS) du
> [récapitulatif des failles](solutions.md), et les **règles ANSSI 35**
> (journalisation) et **40** (gestion d'incident).

## 1. Objectif et périmètre

La V1 n'a **aucune** capacité de détection : les logs restent locaux sur chaque
VM (effaçables par un attaquant), aucune corrélation inter-services n'est
possible, et aucune sonde réseau ne voit les attaques. Ce lot déploie :

1. un **SIEM Wazuh** centralisé (manager + indexer + dashboard) ;
2. des **agents Wazuh** (HIDS) sur tous les hôtes, avec collecte des logs
   applicatifs des services critiques ;
3. une **sonde IDS/IPS Suricata** sur le firewall central (point de passage
   inter-VLAN), dont les alertes sont corrélées dans le SIEM ;
4. une **entrée syslog** sur le manager comme filet pour les équipements qui ne
   peuvent pas héberger d'agent.

Le tout est **déployé par Ansible** (et non par des scripts cloud-init), et
**intégré à la CI GitLab**.

## 2. Architecture

### 2.1 Placement réseau — VLAN SOC dédié

Le serveur de supervision ne doit pas partager le segment des actifs qu'il
surveille (s'il tombe avec eux, on perd la visibilité au pire moment). On crée
donc un **VLAN SOC dédié** :

| Réseau | CIDR | Hôte | IP |
|---|---|---|---|
| `uc-net-soc` | `192.168.109.0/24` | `uc-srv-siem` | `192.168.109.1` |

```
                         Internet
                            │
                     ┌──────┴───────┐
                     │  Firewall    │  (central, 192.168.108.1)
                     │  central     │  + Suricata IDS/IPS (inline)
                     └──┬───┬───┬───┘
        ┌───────────────┘   │   └────────────────┐
   VLAN user/         VLAN rh/mail/         VLAN SOC
   recherche/admin    vpn/dmz...            192.168.109.0/24
   (agents)           (agents)             ┌──────────────┐
        │                  │               │  uc-srv-siem │
        └── 1514/1515 ─────┴──────────────▶│  Wazuh AIO   │
            (events + enrôlement)          │  mgr+idx+dash│
                                           └──────────────┘
                                              ▲ 443 (dashboard)
                                              │  depuis VLAN admin / bastion
```

Tous les flux agents → SIEM transitent par le **firewall central**, qui les
autorise via les règles fournies (cf. §5). La sonde **Suricata** est posée sur
ce même firewall : étant le seul point de passage inter-VLAN (topologie
« VM-routeur » Neutron), il voit tout le trafic latéral — c'est le meilleur
emplacement possible compte tenu des contraintes OpenStack (pas de port-mirror
ni de security policy ; cf. §6).

### 2.2 SIEM — Wazuh all-in-one

On déploie Wazuh en **all-in-one** (manager + indexer OpenSearch + dashboard sur
une seule VM, `uc-srv-siem`). C'est le bon compromis pour une maquette : une
seule VM à gérer, dashboard riche, corrélation et FIM complets. L'indexer étant
gourmand (~4 Go RAM), la VM utilise un flavor dédié (`var.siem_flavor_name`,
défaut `m1.medium`) — cf. [`terraform/siem.tf`](../../terraform/siem.tf).

| Composant | Port | Rôle |
|---|---|---|
| `wazuh-manager` | 1514/tcp, 1515/tcp | réception des events agents + enrôlement (authd) |
| `wazuh-indexer` | 9200/tcp (local) | stockage/index OpenSearch |
| `wazuh-dashboard` | 443/tcp | visualisation, alertes, recherche |
| entrée syslog | 514/udp | logs des équipements sans agent |

### 2.3 Collecte des logs — agent vs syslog

**Choix : agent Wazuh partout où l'on maîtrise l'hôte ; syslog en filet.**

L'agent Wazuh est très supérieur au simple forwarding syslog : en plus de
remonter les logs, il fait l'**intégrité de fichiers** (FIM), le **contrôle de
configuration** (SCA/CIS), la **détection de rootkits** et la **réponse active**.
Tous les hôtes de la maquette sont des VMs Linux que l'on maîtrise → **agent**.

Le **syslog distant** (514/udp sur le manager) est conservé comme **filet** pour
d'éventuels équipements non administrables (appliances réseau) qui ne peuvent
pas faire tourner d'agent.

#### Logs collectés par service

| Hôte | Criticité | Logs applicatifs collectés (au-delà des logs système) |
|---|---|---|
| `uc-web-rh` | critique | Apache access/error (détection SO3 : injection SQL, accès non-auth) |
| `uc-db-rh` | critique | MariaDB error + general log (accès données RH) |
| `uc-srv-ldap` | critique | slapd (bind échoués, bind anonyme, modifs d'entrées) |
| `uc-srv-mail` | critique | Postfix/Dovecot mail.log (brute-force IMAP/SMTP, relais) |
| `uc-srv-moodle` | critique | Apache + MariaDB |
| `uc-calc-recherche` | critique | Samba + PostgreSQL (accès partages/recherche) |
| `uc-srv-sso` (Keycloak) | critique | événements d'auth Keycloak (journald + fichier) |
| `uc-srv-bastion` (Teleport) | critique | **audit log Teleport** (qui/quand/quelle session SSH) |
| `uc-vpn-legacy` | critique | logs VPN |
| `firewall central` | critique | **Suricata eve.json** + iptables/kernel |
| `uc-srv-roundcube` | standard | logs système + Apache (webmail) |

Les logs système de base (`/var/log/auth.log`, `syslog`, `journald`, FIM sur
`/etc`, `/usr/bin`…) sont collectés par défaut par l'agent, sur **tous** les
hôtes sous agent. Le détail par hôte est dans
[`ansible/host_vars/`](../../ansible/host_vars/) et
[`ansible/group_vars/firewall.yml`](../../ansible/group_vars/firewall.yml).

#### Cas des postes BYOD (étudiant, enseignant, DSI)

Les postes utilisateurs sont des appareils **BYOD** (personnels, non
administrés). On **n'y déploie donc pas d'agent** : on n'a ni les droits ni la
pérennité nécessaires (un BYOD se réinstalle / change), et y pousser un agent de
type EDR poserait des problèmes de propriété et de vie privée. Ils sont rangés
dans le groupe d'inventaire `[postes_byod]`, **hors** de `[agents]` : aucun rôle
ne s'exécute dessus.

Leur supervision se fait **indirectement**, ce qui est la bonne pratique pour du
BYOD considéré comme non fiable :

- **Réseau** : toute leur activité traverse le firewall central → vue par la
  sonde **Suricata** (scans, exploits, C2, exfiltration).
- **Services** : ce qu'ils consomment est déjà sous agent (Moodle/Apache, mail,
  **SSO Keycloak** = source d'autorité des authentifications, VPN).
- **Admin** : toute action privilégiée passe par le **bastion** (Teleport),
  journalisé — l'endpoint utilisé importe peu.

> *Option démo* : dans la maquette, `uc-poste-etu` est en réalité une VM (poste
> attaquant). Si l'on veut **montrer la détection côté hôte** des outils
> offensifs, on peut exceptionnellement le basculer dans `[agents_noncritical]`
> pour lui mettre un agent. Ça ne reflète pas le modèle BYOD réel mais enrichit
> la démonstration.

### 2.4 IDS/IPS — Suricata sur le firewall central

Suricata est installé sur le firewall central (rôle
[`suricata_ids`](../../ansible/roles/suricata_ids/)) :

- **Mode IDS (défaut)** : `af-packet`, détection passive, ne bloque rien — sûr
  pour ne pas casser de trafic légitime.
- **Mode IPS (optionnel)** : `NFQUEUE` inline avec `--queue-bypass`
  (*fail-open* : si Suricata tombe, le trafic continue). À activer après tuning
  des règles, via `suricata_mode: ips` dans
  [`group_vars/firewall.yml`](../../ansible/group_vars/firewall.yml).
- Règles **Emerging Threats Open** via `suricata-update`.
- Les alertes (`/var/log/suricata/eve.json`) sont lues par l'**agent Wazuh** du
  firewall et **corrélées dans le SIEM** : on obtient ainsi à la fois la
  détection réseau (NIDS) et hôte (HIDS) dans une seule console.

## 3. Déploiement

### 3.1 Pourquoi Ansible plutôt que les scripts cloud-init ?

Les scripts `terraform/scripts/*.sh` injectés en `user_data` ne s'exécutent
**qu'une fois au premier boot**, ne sont **pas idempotents**, ne se
**réexécutent pas** sans recréer la VM, et n'ont **aucune vue d'inventaire**.
Installer/maintenir un agent sur ~14 hôtes et reconfigurer un SIEM dans ces
conditions est ingérable.

**Répartition des responsabilités :**

- **Terraform** = infrastructure : VM SIEM, réseau SOC, Floating IP
  ([`terraform/siem.tf`](../../terraform/siem.tf)).
- **Ansible** = provisioning logiciel : Wazuh, agents, Suricata
  ([`ansible/`](../../ansible/)) — idempotent, piloté par l'inventaire,
  réexécutable.

### 3.2 Exécution

Voir le [README Ansible](../../ansible/README.md). En résumé :

```bash
cd ansible/
# Inventaire avec la vraie Floating IP du SIEM (depuis les outputs Terraform)
TF_DIR=../terraform scripts/gen-inventory.sh inventory/hosts.ini inventory/hosts.generated.ini
# Déploiement complet
ansible-playbook -i inventory/hosts.generated.ini site.yml -e ssh_jump_host="ubuntu@<FIP_bastion>"
```

### 3.3 Intégration CI/CD

Deux ajouts à [`.gitlab-ci.yml`](../../.gitlab-ci.yml) :

| Job | Stage | Déclenchement | Rôle |
|---|---|---|---|
| `ansible_syntax` | `lint_and_validate` | toutes branches | `ansible-playbook --syntax-check` |
| `ansible_provision` | `provision` | develop/main, **manuel** | déploie Wazuh + Suricata après `terraform_apply` |

Variables CI/CD à définir (en plus des credentials OpenStack existants) :

- `ANSIBLE_SSH_PRIVATE_KEY_B64` — clé privée SSH (correspondant à
  `TF_VAR_ssh_public_key`) encodée base64 (`base64 -w0 ~/.ssh/id_ed25519`),
  variable **masquée**.
- `SSH_JUMP_HOST` — rebond pour les VMs sans FIP, ex. `ubuntu@<FIP_bastion>`.

## 4. Accès au dashboard

Après le rôle `wazuh_manager`, les identifiants générés sont rapatriés dans
`ansible/.wazuh-credentials/` (ignoré par git). Dashboard :
`https://<FIP_SIEM>`, utilisateur `admin`.

> **Sécurité** : en cible V2 le dashboard n'est **pas** exposé sur Internet.
> L'accès se fait depuis le VLAN admin / via le bastion ou le VPN. La Floating
> IP (`siem_expose_fip`) sert au bootstrap et à la démo ; la mettre à `false`
> une fois l'accès interne en place.

## 5. Règles firewall requises

Le forwarding des logs traverse le firewall central. Les règles à intégrer dans
le lot pare-feu sont fournies prêtes à l'emploi (style `fw-legacy.sh`) dans
[`firewall-siem.rules.sh`](firewall-siem.rules.sh) :

- Agents → SIEM : `1514,1515/tcp` depuis tous les VLAN internes.
- Admin → SIEM : `443/tcp` (dashboard), depuis le VLAN admin uniquement.
- Équipements → SIEM : `514/udp` (syslog, filet).
- SIEM → Internet : `80,443/tcp` + `53` (install Wazuh, MàJ, règles ET).

## 6. Contraintes OpenStack et choix associés

La maquette modélise une infra **physique** par un réseau **OpenStack**, d'où
des contraintes spécifiques (cf. [network.tf](../../terraform/network.tf)) :

- **`port_security_enabled=false`** sur les ports (les Security Groups OpenStack
  ne sont pas le point de filtrage) → le filtrage réel est fait par le firewall
  (iptables/nftables), et c'est lui qui porte les règles SIEM du §5.
- **Pas de port-mirroring / SPAN** simple → on ne peut pas faire un IDS sur un
  TAP réseau. La sonde Suricata est donc placée **inline sur le firewall
  central**, qui voit déjà tout le trafic inter-VLAN (meilleur compromis).
- **Floating IP via routeur Neutron** → le SIEM obtient sa sortie Internet et
  son FIP via le routeur Neutron en mode autonome (cf. §7).

## 7. Compatibilité « flat » (develop) ↔ « segmenté » (cible V2)

La segmentation réseau et le firewall central sont désormais **mergés** sur
`develop` : le SIEM est seul dans `uc-net-soc`, et les agents (VLAN internes
`uc-net-*`) joignent le manager (`192.168.109.1`) **à travers le firewall
central** `uc-srv-firewall`. Le routeur Neutron porte des routes statiques
(`uc-net-* -> firewall`) qui assurent le retour SOC -> agents (cf.
`openstack_networking_router_route_v2.internal_via_fw` dans
[`terraform/network.tf`](../../terraform/network.tf)). Le mode « flat »
transitoire (`siem_attach_campus`) a été retiré.

> **Point d'intégration** : quand le firewall central existera, re-router le
> VLAN SOC derrière lui (passerelle = firewall) et appliquer
> [`firewall-siem.rules.sh`](firewall-siem.rules.sh). L'attache au routeur
> Neutron dans `siem.tf` est le mode autonome de bootstrap.

## 8. Traçabilité ANSSI

| Faille V1 | Règle ANSSI | Remédiation de ce lot |
|---|---|---|
| 5.1 Pas de logs centralisés | R35 (journalisation) | Wazuh manager + agents + syslog ; logs hors de portée d'un attaquant local |
| 5.2 Pas de SOC ni IDS/IPS | R40 (gestion d'incident) | Suricata (NIDS/NIPS) + corrélation Wazuh + dashboard d'alertes |

## 9. Limites et suites possibles

- **Alerting actif** (mail/webhook sur alerte critique) non configuré : à
  brancher sur l'intégration Wazuh (ex. Shuffle/TheHive) si besoin.
- **Active Response** Wazuh (bannissement IP automatique) désactivé par défaut —
  à activer prudemment après tuning.
- **Sauvegardes immuables** des index (évoqué en 5.2) hors périmètre de ce lot.
- Le dimensionnement de l'indexer (RAM/disque) est à valider sur le flavor réel
  du cluster (`openstack flavor list`).
