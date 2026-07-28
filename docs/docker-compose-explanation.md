# `docker-compose.yml` expliqué ligne par ligne

Ce document reprend le fichier `docker-compose.yml` du projet et explique **chaque ligne**, dans l'ordre. Pour les concepts généraux (image vs conteneur, réseau, volumes...), voir `docs/guide-docker.md` — ici on reste au niveau de la syntaxe et du rôle précis de chaque champ.

---

```yaml
services:
```
Mot-clé racine du fichier : tout ce qui suit et qui est indenté dessous décrit les **conteneurs** que Docker Compose doit gérer. Ici, il y en a deux : `db` et `app`.

---

## Le service `db`

```yaml
  db:
```
Nom du service, choisi par nous. C'est aussi le nom **DNS** utilisé par les autres services du projet pour le joindre sur le réseau Docker (voir plus bas, `DATABASE_URL: ...@db:5432...`).

```yaml
    image: postgres:16-alpine
```
Au lieu de construire une image nous-mêmes (pas de `build:` ici), on utilise directement une image déjà publiée sur Docker Hub : PostgreSQL version 16, variante `alpine` (basée sur une distribution Linux très légère). Docker la télécharge automatiquement si elle n'est pas déjà en local.

```yaml
    restart: unless-stopped
```
Politique de redémarrage automatique. Si le conteneur plante ou si la machine hôte redémarre, Docker le relance tout seul — sauf si quelqu'un l'a arrêté volontairement avec `docker compose stop` (dans ce cas, il reste arrêté).

```yaml
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-kps_tasks_db}
      POSTGRES_USER: ${POSTGRES_USER:-kps_tasks_user}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-change_me}
```
- `environment:` : liste de variables d'environnement injectées **dans** le conteneur au démarrage.
- `${POSTGRES_DB:-kps_tasks_db}` : syntaxe de substitution de Compose. Elle veut dire *"utilise la valeur de la variable `POSTGRES_DB` définie dans `.env` ; si elle n'existe pas, utilise `kps_tasks_db` par défaut"*. Le `:-` introduit la valeur par défaut.
- Ces trois variables sont lues par l'image officielle PostgreSQL **la toute première fois** que le conteneur démarre avec un volume vide : elles servent à créer la base, l'utilisateur, et son mot de passe.

```yaml
    volumes:
      - postgres_data:/var/lib/postgresql/data
```
Monte le volume Docker nommé `postgres_data` (déclaré plus bas, tout en bas du fichier, sous la clé `volumes:` de premier niveau) sur le chemin `/var/lib/postgresql/data` **à l'intérieur du conteneur** — c'est exactement l'endroit où PostgreSQL écrit ses fichiers de données. Résultat : les données survivent à la suppression du conteneur, parce qu'elles ne sont pas stockées dans le système de fichiers éphémère du conteneur, mais dans ce volume géré séparément par Docker.

```yaml
    networks:
      - kps_net
```
Rattache ce conteneur au réseau Docker nommé `kps_net` (déclaré tout en bas du fichier). C'est ce qui permet à `app` de joindre `db` par son nom.

```yaml
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB"]
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 10s
```
- `healthcheck:` : commande que Docker exécute périodiquement **depuis l'intérieur** du conteneur pour juger s'il est réellement opérationnel, pas juste démarré.
- `test: ["CMD-SHELL", "..."]` : exécute la chaîne donnée dans un shell (`sh -c "..."`). `pg_isready` est un outil PostgreSQL qui renvoie un succès si le serveur accepte des connexions.
- `$$POSTGRES_USER` (avec un double `$`) : dans `docker-compose.yml`, un simple `$VAR` serait interprété par Compose lui-même (substitution avant même que la commande parte dans le conteneur). Le double `$$` dit à Compose *"ne substitue rien ici, laisse passer un seul `$` littéral"* — pour que ce soit le **shell à l'intérieur du conteneur** qui lise la variable d'environnement `POSTGRES_USER` (celle définie juste au-dessus, dans `environment:`).
- `interval: 5s` : Docker relance ce test toutes les 5 secondes.
- `timeout: 5s` : si le test ne répond pas en 5 secondes, il est considéré comme échoué.
- `retries: 10` : il faut 10 échecs consécutifs pour que le conteneur soit déclaré `unhealthy`.
- `start_period: 10s` : pendant les 10 premières secondes après le démarrage, les échecs ne comptent pas contre `retries` — le temps que PostgreSQL s'initialise.

---

## Le service `app`

```yaml
  app:
```
Nom du deuxième service — c'est aussi le nom DNS que `db` pourrait utiliser pour joindre `app` (non utilisé ici, mais disponible).

```yaml
    build:
      context: .
      dockerfile: Dockerfile
```
Contrairement à `db`, ce service n'utilise pas d'image prête à l'emploi : il faut la **construire**.
- `context: .` : le "contexte de build" est le dossier courant (la racine du projet, là où se trouve `docker-compose.yml`). C'est le seul dossier dans lequel les instructions `COPY` du `Dockerfile` ont le droit d'aller chercher des fichiers.
- `dockerfile: Dockerfile` : nom du fichier recette à utiliser, ici `Dockerfile` à la racine (valeur par défaut de toute façon, écrite ici explicitement).

```yaml
    restart: unless-stopped
```
Même politique de redémarrage automatique que pour `db`.

```yaml
    environment:
      APP_NAME: ${APP_NAME:-KPS Tasks API}
      APP_ENV: ${APP_ENV:-production}
      APP_VERSION: ${APP_VERSION:-0.1.0}
      LOG_LEVEL: ${LOG_LEVEL:-INFO}
      DATABASE_URL: ${DATABASE_URL:-postgresql+psycopg://kps_tasks_user:change_me@db:5432/kps_tasks_db}
```
Variables d'environnement lues par `app/config.py` au démarrage de l'application (nom affiché, environnement d'exécution, version, niveau de log, et surtout la chaîne de connexion à PostgreSQL). Même mécanisme `${VAR:-défaut}` que pour `db`. Remarque : `DATABASE_URL` pointe vers `@db:5432` — `db` est le **nom du service** `db` défini plus haut, pas une adresse IP fixe ; Compose s'occupe de la résolution grâce au réseau `kps_net`.

```yaml
    depends_on:
      db:
        condition: service_healthy
```
Ordre de démarrage : `app` ne sera lancé qu'une fois que Docker a déclaré `db` `healthy` (grâce au `healthcheck` de `db` vu plus haut) — pas juste "conteneur démarré", ce qui laisserait à PostgreSQL le temps d'être réellement prêt à accepter des connexions.

```yaml
    ports:
      - "${APP_PORT:-8000}:8000"
```
Publie un port du conteneur sur la machine hôte, au format `"HÔTE:CONTENEUR"`. Ici : le port `8000` du conteneur (celui sur lequel `uvicorn` écoute) est rendu accessible sur le port `${APP_PORT:-8000}` de l'hôte (donc `8000` par défaut). C'est ce qui permet à `curl http://127.0.0.1:8000/health`, exécuté depuis la machine hôte, de fonctionner. Remarque : `db` n'a **aucune** section `ports` — volontairement, pour que PostgreSQL reste inaccessible depuis l'extérieur du réseau Docker.

```yaml
    networks:
      - kps_net
```
Même réseau dédié que `db` — condition nécessaire pour que `app` puisse joindre `db` par son nom.

```yaml
    healthcheck:
      test:
        - CMD-SHELL
        - python -c "from urllib.request import urlopen; urlopen('http://127.0.0.1:8000/health').read()"
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s
```
- Même principe que le `healthcheck` de `db`, mais écrit en syntaxe de **liste** plutôt qu'en tableau JSON sur une ligne — les deux syntaxes sont équivalentes, Compose accepte les deux.
- La commande lance un interpréteur Python qui fait une requête HTTP vers `http://127.0.0.1:8000/health` **depuis l'intérieur du conteneur** (le `127.0.0.1` désigne donc bien le conteneur `app` lui-même ici, puisque le test s'exécute dedans) ; si la requête échoue (code d'erreur, connexion refusée), la commande Python lève une exception et le test est considéré en échec.
- `start_period: 20s` est plus long que pour `db` (`10s`) : le conteneur `app` doit d'abord attendre `db`, puis exécuter `init_db`, avant que `uvicorn` soit prêt à répondre — ça prend plus de temps qu'un simple démarrage de PostgreSQL.

```yaml
    command: >
      sh -c "python -m app.init_db && exec uvicorn app.main:app --host 0.0.0.0 --port 8000"
```
- `command:` **remplace** le `CMD` défini dans le `Dockerfile` (qui ne fait que lancer `uvicorn` directement) — Compose a le dernier mot sur la commande de démarrage.
- `>` en YAML : replie les lignes suivantes en une seule chaîne (avec des espaces à la place des retours à la ligne) ; ici tout tient sur une ligne de toute façon, c'est surtout une habitude d'écriture.
- `sh -c "..."` : exécute la chaîne comme une commande shell.
- `python -m app.init_db` : exécute le module `init_db` du package `app` (crée les tables si elles n'existent pas encore) et attend qu'il se termine.
- `&&` : n'exécute la suite **que si** `init_db` s'est terminé avec succès (code de sortie 0). Si l'initialisation de la base échoue, le conteneur s'arrête plutôt que de démarrer une API cassée.
- `exec uvicorn ...` : `exec` remplace le processus `sh` actuel par `uvicorn`, au lieu de lancer `uvicorn` comme un sous-processus de `sh`. Concrètement, ça permet à `uvicorn` de recevoir directement les signaux d'arrêt envoyés par Docker (`docker compose stop`), pour un arrêt propre au lieu d'un arrêt forcé après un délai.
- `--host 0.0.0.0` : `uvicorn` écoute sur toutes les interfaces réseau du conteneur (pas seulement `127.0.0.1`) — indispensable pour que la publication du port (`ports:` vue plus haut) puisse fonctionner.
- `--port 8000` : le port d'écoute, cohérent avec le `8000` utilisé dans `ports:` et dans le `healthcheck`.

---

## Les volumes (niveau racine)

```yaml
volumes:
  postgres_data:
```
Déclare l'existence du volume nommé `postgres_data`, utilisé par le service `db` plus haut. Une déclaration vide (rien après les `:`) veut dire *"laisse Docker le gérer avec les options par défaut"* — pas de configuration particulière (chemin sur l'hôte, driver externe...). Docker crée ce volume automatiquement au premier `docker compose up` s'il n'existe pas déjà, et le réutilise ensuite tel quel à chaque redémarrage.

---

## Les réseaux (niveau racine)

```yaml
networks:
  kps_net:
    driver: bridge
```
Déclare le réseau nommé `kps_net`, utilisé par `app` et `db`.
- `driver: bridge` : type de réseau Docker standard pour une seule machine — un réseau privé virtuel, avec sa propre plage d'adresses IP internes, isolé des autres réseaux Docker et de l'extérieur, mais permettant aux conteneurs qui y sont rattachés de se joindre entre eux par leur nom de service.

Sans cette déclaration explicite, Compose aurait quand même créé un réseau par défaut (nommé automatiquement d'après le dossier du projet, par exemple `prj_default`) — le déclarer ici avec un nom choisi (`kps_net`) sert uniquement à le rendre explicite et lisible, conformément à la contrainte du brief ("utiliser un réseau Docker dédié").
