# Compte rendu d'incident

## Contexte

L'environnement du Projet 1 faisait encore tourner une application FastAPI via `systemd` et possédait des tâches cron liées aux sauvegardes PostgreSQL.

## Symptômes observés

- Le service `task.service` était actif au démarrage de l'analyse.
- L'application écoutait sur le port 8000.
- Une tâche cron de backup existait dans `/etc/cron.d/kps-tasks-api-backup`.
- La stack Docker ne devait pas être lancée en même temps que l'ancienne stack Linux.

## Diagnostic

Commandes utilisées :

```bash
sudo systemctl list-units --type=service --all | grep -Ei "kps|task|fastapi|uvicorn"
sudo systemctl status task.service --no-pager
sudo ss -tulpn | grep ":8000"
sudo grep -R -nEi "kps|task|backup_postgres|healthcheck|check_system|uvicorn|fastapi" /etc/crontab /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly 2>/dev/null
```

## Cause racine

- Le service `task.service` lançait encore l'application FastAPI via `uvicorn`.
- Une configuration cron dans `/etc/cron.d` déclenchait un backup PostgreSQL lié à l'ancien déploiement.

## Correctif appliqué

```bash
sudo systemctl stop task.service
sudo systemctl disable task.service
sudo rm /etc/systemd/system/task.service
sudo systemctl daemon-reload
sudo rm -rf /etc/cron.d/*
```

## Vérifications réalisées

- `task.service` est devenu `inactive (dead)`.
- Le port 8000 n'écoutait plus.
- `curl http://127.0.0.1:8000/health` échouait comme attendu après l'arrêt.
- Aucun cron lié au projet n'a été retrouvé après nettoyage.

## Conclusion

L'incident provenait de l'ancien déploiement Linux encore présent sur le VPS.
Après arrêt propre du service, suppression du fichier unit et nettoyage des tâches cron, l'environnement a pu basculer vers la stack Docker sans conflit.