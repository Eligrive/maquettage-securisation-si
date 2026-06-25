# Rôle `vnc_server` — bureau distant TigerVNC + XFCE

Installe un serveur **TigerVNC** piloté par **systemd** avec une session **XFCE**,
pour accéder graphiquement à un poste de la maquette **depuis l'extérieur de
l'OpenStack**, via un simple **tunnel SSH** (rebond par la Floating IP du firewall).

> **Cadrage.** C'est une facilité d'**accès** à la maquette (démos, tests), pas un
> composant du SI modélisé. Le serveur n'écoute **que sur `127.0.0.1`** : il n'est
> joignable **qu'à travers le tunnel SSH**, jamais exposé sur le réseau — seule
> configuration acceptable, l'authentification VNC (DES, 8 caractères max) étant faible.

## Où il s'exécute

Listé sur tout le groupe `[postes]` dans `provision.yml`, mais **conditionné par
`vnc_enabled`** : il ne s'active que là où un `host_vars` le demande.

| Poste | Hôte | IP interne | Activé (`vnc_enabled`) |
|---|---|---|---|
| Étudiant | `uc-poste-etu` | `192.168.101.1` | ✅ |
| DSI / admin | `uc-poste-dsi` | `192.168.103.1` | ✅ |
| Enseignant | `uc-poste-prof` | `192.168.101.2` | ❌ (défaut) |

## Déploiement

```bash
cd ansible/
# Tout le lot postes (dont VNC) :
ansible-playbook -i inventory/hosts.generated.ini provision.yml \
    -e ssh_jump_host="ubuntu@<FIP_firewall>" --tags postes
# Ou uniquement le VNC :
ansible-playbook -i inventory/hosts.generated.ini provision.yml \
    -e ssh_jump_host="ubuntu@<FIP_firewall>" --tags vnc
```

## Connexion (depuis un poste extérieur, OpenStack joignable)

Rebond SSH (`-J`) par la Floating IP du firewall, puis redirection du port 5901 :

```bash
# Poste étudiant (192.168.101.1)
ssh -J ubuntu@<FIP_firewall> -L 5901:127.0.0.1:5901 ubuntu@192.168.101.1 -N

# Poste DSI/admin (192.168.103.1) — autre port local pour les avoir en parallèle
ssh -J ubuntu@<FIP_firewall> -L 5902:127.0.0.1:5901 ubuntu@192.168.103.1 -N
```

Puis, en local, avec n'importe quel client VNC :

```bash
vncviewer localhost:5901     # mot de passe = vnc_password (défaut : Secured1)
```

> Le display `:1` correspond au port `5901` côté poste. La redirection
> `-L 5901:127.0.0.1:5901` reprend exactement le port côté serveur sur la loopback.

## Principales variables (`defaults/main.yml`)

| Variable | Défaut | Rôle |
|---|---|---|
| `vnc_enabled` | `false` | Active le rôle sur l'hôte |
| `vnc_user` | `ubuntu` | Utilisateur propriétaire de la session |
| `vnc_display` | `1` | Display X → port `5900 + display` (1 ⇒ 5901) |
| `vnc_password` | `Secured1` | Mot de passe VNC (**8 car. max**, tronqué par TigerVNC) |
| `vnc_geometry` | `1280x800` | Résolution du bureau |
| `vnc_depth` | `24` | Profondeur de couleur |
| `vnc_localhost_only` | `true` | N'écoute que sur `127.0.0.1` (laisser à `true`) |

## Service & rotation du mot de passe

- Service systemd : `vncserver@<display>.service` (ex. `vncserver@1.service`),
  activé au boot, `Restart=on-failure`.
- Le mot de passe est généré une seule fois (`~/.vnc/passwd`, idempotent). Pour le
  **changer**, rejouer avec `-e vnc_force_passwd=true` (ou supprimer le fichier).

## Sécurité

- **Pas d'ouverture firewall** : VNC reste en loopback, l'accès passe par SSH.
- L'authentification forte est celle de **SSH** (clé) ; le mot de passe VNC n'est
  qu'une barrière secondaire derrière le tunnel.
