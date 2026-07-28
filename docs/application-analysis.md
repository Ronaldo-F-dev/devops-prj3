# Analyse de l'application

Ce document décrit le fonctionnement de KPS Tasks API telle qu'elle tournait en Projet 1 (déploiement Linux manuel), avant sa conteneurisation en Projet 2.

## Runtime

- Langage : Python 3.12+
- Framework : FastAPI
- ORM : SQLAlchemy 2.x
- Driver PostgreSQL : psycopg
- Chargement de configuration : python-dotenv

## Points d'entrée principaux

- Application API : `app.main:app` (lancée par `uvicorn`)
- Initialisation de la base : `python -m app.init_db`

## Endpoints exposés

| Méthode | Route | Rôle |
|---|---|---|
| GET | `/` | Informations générales (nom, version, environnement) |
| GET | `/version` | Nom, version et environnement de l'application |
| GET | `/health` | Vérifie que l'API et la connexion PostgreSQL fonctionnent |
| GET | `/tasks` | Liste les tâches (pagination via `limit`/`offset`) |
| POST | `/tasks` | Crée une tâche |
| GET | `/tasks/{task_id}` | Récupère une tâche par son identifiant |
| PATCH | `/tasks/{task_id}` | Met à jour une tâche existante |
| DELETE | `/tasks/{task_id}` | Supprime une tâche |

## Variables d'environnement

| Variable | Rôle | Valeur par défaut |
|---|---|---|
| `APP_NAME` | Nom affiché de l'API | `KPS Tasks API` |
| `APP_ENV` | Environnement d'exécution (`development`, `production`...) | `development` |
| `APP_VERSION` | Version affichée par `/version` | `0.1.0` |
| `LOG_LEVEL` | Niveau de log Python | `INFO` |
| `DATABASE_URL` | Chaîne de connexion SQLAlchemy vers PostgreSQL | `postgresql+psycopg://kps_tasks_user:change_me@localhost:5432/kps_tasks_db` |

Ces variables sont lues au démarrage par `app/config.py`, jamais écrites en dur dans le code.

## Dépendances applicatives

Listées dans `requirements.txt` : FastAPI, Uvicorn, SQLAlchemy, psycopg, python-dotenv, et leurs dépendances transitives. Aucune dépendance système particulière au-delà de Python 3.12.

## Ports utilisés

- Port HTTP de l'application : `8000`
- Port PostgreSQL : `5432`

En Projet 1 (déploiement Linux), l'application et PostgreSQL tournaient tous les deux sur la même machine, avec PostgreSQL accessible via `localhost:5432`.
En Projet 2 (Docker Compose), l'application doit être exposée par Docker Compose et PostgreSQL doit rester privé sur le réseau Docker interne.

## Connexion à PostgreSQL

L'application lit `DATABASE_URL` au démarrage. En dehors de Docker (Projet 1), la valeur pointe vers `localhost`. Dans Docker Compose (Projet 2), la valeur doit pointer vers le nom du service `db` :

```text
postgresql+psycopg://kps_tasks_user:change_me@db:5432/kps_tasks_db
```

`localhost`, à l'intérieur d'un conteneur, désignerait le conteneur applicatif lui-même — pas la base de données. C'est pour cela que le nom du service Docker Compose (`db`) doit être utilisé à la place.

## Flux de démarrage (dans Docker Compose)

1. Docker Compose démarre le conteneur PostgreSQL (`db`).
2. PostgreSQL devient `healthy` (healthcheck `pg_isready`).
3. Le conteneur applicatif (`app`) exécute `python -m app.init_db` pour créer les tables si elles n'existent pas encore.
4. Uvicorn démarre l'application FastAPI sur le port 8000.

## Constats

- L'API expose déjà un endpoint `/health` qui vérifie la connexion PostgreSQL — aucune modification de code n'est nécessaire pour la conteneurisation.
- Les secrets (mot de passe PostgreSQL, etc.) doivent vivre dans `.env`, jamais dans l'image Docker ni dans le dépôt Git.
