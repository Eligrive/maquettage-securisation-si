# Clés SSH du groupe

## Structure

```
ssh-keys/
  groupe/
    groupe11.pub      # Clé partagée du groupe (OpenStack, déploiement Terraform)
  authorized_keys     # Clés individuelles des membres (format authorized_keys)
```

## Ajouter sa clé

1. Récupère ta clé publique SSH : `cat ~/.ssh/id_ed25519.pub` (ou `ssh-add -L`)
2. Ajoute une ligne dans `ssh-keys/authorized_keys` : `ssh-ed25519 AAAA... prenom.nom`
3. Ouvre une MR sur `develop`
