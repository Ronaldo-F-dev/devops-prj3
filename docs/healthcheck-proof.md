# Preuve du healthcheck

## Objectif

Démontrer que l'endpoint `/health` de l'API répond correctement une fois la stack Docker Compose démarrée, et que le healthcheck Docker déclare bien les conteneurs `healthy`.

## Commande utilisée

```bash
docker compose ps
curl -i http://127.0.0.1:8000/health
curl -i http://127.0.0.1:8000/version
```

## Résultat obtenu

```text
$ curl http://localhost:8000/health
{"status":"ok","database":"ok"}

$ curl -i http://127.0.0.1:8000/version
HTTP/1.1 200 OK
content-type: application/json

{"name":"KPS Tasks API","version":"0.1.0","environment":"production"}
```

`docker compose ps` affiche les conteneurs `app` et `db` avec l'état `healthy` (healthcheck HTTP pour `app`, `pg_isready` pour `db`).

## Ce que cela prouve

- L'API est joignable sur le port 8000.
- L'application tourne et répond aux requêtes HTTP.
- L'API arrive bien à se connecter à PostgreSQL (`"database":"ok"`), pas seulement à démarrer.
- Le healthcheck Docker Compose (défini dans `docker-compose.yml`) reflète correctement l'état réel des deux services.
