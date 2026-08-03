# KPS Tasks API - Project 2 Docker Compose

This repository contains the application used in Project 1 and its Docker Compose packaging for Project 2.

## What is included

- FastAPI application in `app/`
- Multi-stage `Dockerfile` at the repository root
- `docker-compose.yml` at the repository root
- `.dockerignore`
- Example environment file `.env.example`
- Project documentation in `docs/`
- Operational scripts in `scripts/`

## Application features

- `GET /health` checks the API and PostgreSQL connection
- `GET /version` returns the application version
- `GET /tasks` lists tasks
- `POST /tasks` creates a task
- `PATCH /tasks/{id}` updates a task
- `DELETE /tasks/{id}` deletes a task
- Logging on standard output
- Configuration through environment variables

## Docker quick start

1. Copy the example environment file:

```bash
cp .env.example .env
```

2. Start the stack:

```bash
docker compose up -d --build
```

3. Check the app:

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/version
```

4. View logs:

```bash
docker compose logs -f app
docker compose logs -f db
```

5. Stop the stack:

```bash
docker compose down
```

## Configuration

The stack uses these variables from `.env`:

- `APP_NAME`
- `APP_ENV`
- `APP_VERSION`
- `LOG_LEVEL`
- `APP_PORT`
- `POSTGRES_DB`
- `POSTGRES_USER`
- `POSTGRES_PASSWORD`
- `DATABASE_URL`

## Project documents

- [Docker guide for beginners](docs/guide-docker.md)
- [docker-compose.yml explained line by line](docs/docker-compose-explanation.md)
- [Application analysis](docs/application-analysis.md)
- [Systemd vs Docker](docs/systemd-vs-docker.md)
- [Docker networking](docs/docker-networking.md)
- [Architecture](docs/architecture.md)
- [Restore procedure](docs/restore-procedure.md)
- [Incident report template](docs/incident-report.md)
- [Soutenance notes](docs/soutenance.md)
- [Healthcheck proof](docs/healthcheck-proof.md)
- [PostgreSQL persistence proof](docs/postgres-persistence-proof.md)
- [Changelog](CHANGELOG.md)

### Project 3 (CI, security, quality) — `docs/prj3/`

- [Security and quality (Gitleaks, SonarCloud)](docs/prj3/security-and-quality.md)
- [CI pipeline](docs/prj3/ci-pipeline.md)
- [Versioning strategy](docs/prj3/versioning.md)
- [Branching strategy (ADR-001)](docs/prj3/adr/0001-git-branching-strategy.md)
- [Docker build: local vs CI](docs/prj3/docker-build-local-vs-ci.md)
- [Commit convention](docs/prj3/commit-convention.md)
- [Mini-defense support](docs/prj3/defense-support.md)

## Operational scripts

- `scripts/start.sh`
- `scripts/stop.sh`
- `scripts/status.sh`
- `scripts/logs.sh`
- `scripts/healthcheck.sh`
- `scripts/backup_postgres.sh`
- `scripts/check_system.sh`

Examples:

```bash
./scripts/start.sh
./scripts/status.sh
./scripts/logs.sh app
./scripts/stop.sh
```

If Docker requires elevated privileges on the VPS, use:

```bash
DOCKER_COMPOSE="sudo docker compose" ./scripts/start.sh
```

## Notes

- PostgreSQL is not exposed on the host.
- Secrets should live in `.env`, not in the image.
- The healthcheck is defined on the application container and the database container.
