# Preuve de persistance PostgreSQL

## Objectif

Démontrer qu'une tâche créée avant un redémarrage de la stack est toujours présente après ce redémarrage — preuve que le volume Docker conserve bien les données de PostgreSQL indépendamment du cycle de vie des conteneurs.

## Procédure de test

1. Créer une tâche :

```bash
curl -X POST http://127.0.0.1:8000/tasks \
  -H "Content-Type: application/json" \
  -d '{"title":"test persistence","description":"doit survivre au redémarrage"}'
```

2. Vérifier qu'elle existe :

```bash
curl http://127.0.0.1:8000/tasks
```

3. Redémarrer la stack :

```bash
docker compose down
docker compose up -d
```

4. Vérifier à nouveau la présence de la tâche :

```bash
curl http://127.0.0.1:8000/tasks
```

## Résultat obtenu (testé en local et sur le VPS)

```text
$ curl -X POST http://127.0.0.1:8000/tasks -H "Content-Type: application/json" \
  -d '{"title":"test persistence","description":"doit survivre au redémarrage"}'
{"title":"test persistence","description":"doit survivre au redémarrage","status":"todo","id":1,
 "created_at":"2026-07-24T10:37:17.530506Z","updated_at":"2026-07-24T10:37:17.530506Z"}

$ docker compose down
$ docker compose up -d
[+] up 3/3
 ✔ Network app_kps_net Created
 ✔ Container app-db-1  Healthy
 ✔ Container app-app-1 Started

$ curl http://127.0.0.1:8000/tasks
[{"title":"test persistence","description":"doit survivre au redémarrage","status":"todo","id":1,
 "created_at":"2026-07-24T10:37:17.530506Z","updated_at":"2026-07-24T10:37:17.530506Z"}]
```

La tâche créée avant l'arrêt (`id: 1`) est toujours présente après `docker compose down` puis `docker compose up -d`, alors même que les conteneurs `app` et `db` ont été entièrement recréés (voir `Network ... Created`, `Container ... Healthy/Started`).

## Ce que cela prouve

- Les données PostgreSQL sont stockées dans le volume Docker `postgres_data`, pas dans le système de fichiers éphémère du conteneur `db`.
- Le volume survit à la suppression et à la recréation des conteneurs (`docker compose down` supprime les conteneurs, pas les volumes nommés).
- L'application se reconnecte à la même base de données après redémarrage, sans perte de données.
