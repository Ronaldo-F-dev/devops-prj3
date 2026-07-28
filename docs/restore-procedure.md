# Procédure de restauration PostgreSQL

Cette procédure restaure une sauvegarde créée par `scripts/backup_postgres.sh`.

## Prérequis

- Docker et Docker Compose installés
- La stack lancée (`docker compose up -d`)
- Un fichier de sauvegarde, par exemple `/opt/backups/kps-tasks-api/kps_tasks_api_YYYYMMDD_HHMM.sql.gz`

## Format de la sauvegarde

Le script de backup produit un dump SQL compressé :

```text
kps_tasks_api_YYYYMMDD_HHMM.sql.gz
```

## Étapes de restauration

1. Arrêter le conteneur applicatif si besoin :

```bash
docker compose stop app
```

2. Restaurer la sauvegarde dans PostgreSQL :

```bash
gunzip -c /opt/backups/kps-tasks-api/kps_tasks_api_YYYYMMDD_HHMM.sql.gz | \
  docker compose exec -T db sh -lc 'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
```

3. Relancer l'application :

```bash
docker compose start app
```

4. Vérifier le résultat :

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/tasks
```

## Règle de validation

Une sauvegarde n'est considérée comme valide qu'après un test de restauration réalisé avec succès.
