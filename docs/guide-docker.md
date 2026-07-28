# Guide Docker — comprendre ce projet sans rien connaître à Docker

Ce document explique Docker à partir de zéro, en s'appuyant uniquement sur les fichiers réels de **ce** projet (KPS Tasks API). Pas de théorie abstraite : chaque concept est illustré avec le code qu'on a réellement.

---

## 1. C'est quoi Docker, en une image

Avant Docker, pour faire tourner cette application il fallait :

- Installer Python 3.12 sur le serveur
- Installer PostgreSQL sur le serveur
- Installer toutes les dépendances Python (`fastapi`, `sqlalchemy`, etc.)
- Espérer que la version de Python sur le serveur soit la bonne
- Recommencer cette installation à chaque nouveau serveur (dev, test, prod...)

C'est fragile : "ça marche chez moi mais pas en prod" vient de là.

**Docker résout ça en mettant l'application et tout ce dont elle a besoin dans une boîte fermée et portable.** Cette boîte contient déjà Python, les dépendances, le code — tout. On peut la faire tourner sur n'importe quelle machine qui a Docker installé, et elle se comportera exactement pareil.

Analogie : un conteneur maritime. Peu importe ce qu'il y a dedans (meubles, vêtements, électronique), il a une forme standard, et n'importe quel bateau/camion/grue sait le manipuler. Docker fait la même chose avec les applications.

---

## 2. Image vs conteneur — la différence qui bloque tout le monde au début

- **Une image** = une recette de cuisine figée. C'est un fichier (en couches) qui contient : le système de base, Python, les dépendances installées, le code de l'app. Elle ne "tourne" pas, elle existe juste sur le disque.
- **Un conteneur** = le plat une fois cuisiné, en train d'être servi. C'est une image qu'on a **lancée** — elle tourne, utilise du CPU/RAM, a une IP réseau, peut être arrêtée puis relancée.

Dans ce projet :

```bash
docker compose build   # fabrique l'IMAGE prj-app à partir du Dockerfile
docker compose up -d   # démarre les CONTENEURS à partir des images (prj-app-1, prj-db-1)
```

Une seule image peut donner naissance à plusieurs conteneurs identiques (utile pour scaler), et on peut supprimer un conteneur sans toucher à l'image qui a servi à le créer.

---

## 3. Le système de fichiers d'un conteneur — la base pour comprendre `WORKDIR` et les chemins

C'est le point qui bloque presque tout le monde, donc on prend le temps.

### 3.1 Ta machine et le conteneur ont deux disques complètement séparés

Quand tu lances un conteneur, Docker ne lui donne pas accès à ton disque dur. Le conteneur a **son propre système de fichiers**, isolé, qui part d'une racine `/` complètement différente de celle de ta machine (`ronaldo@ronaldo:~/Bureau/prj$` n'existe pas à l'intérieur du conteneur).

Concrètement, dans ce projet, sur **ta machine** (l'hôte), tu as :

```
/home/ronaldo/Bureau/prj/          <-- ça c'est TON disque, ta machine
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
├── .env
└── app/                           <-- un dossier qui s'appelle "app"
    ├── main.py
    ├── config.py
    ├── database.py
    ├── models.py
    └── schemas.py
```

Et à l'intérieur du **conteneur** `prj-app-1`, une fois qu'il tourne, il y a un système de fichiers totalement différent, qui ressemble à ça (on va voir juste après pourquoi) :

```
/                                  <-- la racine DU CONTENEUR, rien à voir avec ta machine
├── app/                           <-- créé par le Dockerfile (WORKDIR /app)
│   ├── requirements.txt
│   └── app/                      <-- le dossier "app" du host, copié ici
│       ├── main.py
│       ├── config.py
│       ├── database.py
│       ├── models.py
│       └── schemas.py
├── usr/
├── bin/
├── home/appuser/
└── ... (tout le reste de Debian slim fourni par l'image python:3.12-slim)
```

Tu peux vérifier ça toi-même, en direct, avec :

```bash
docker exec -it prj-app-1 sh
# tu es maintenant DANS le conteneur, pas sur ta machine
pwd
ls -la /app
ls -la /app/app
exit
```

⚠️ **Piège à éviter** : quand tu fais `docker exec -it prj-app-1 sh`, le shell démarre **déjà dans `/app`** (c'est le `WORKDIR` du Dockerfile, voir section 3.2 — il s'applique aussi quand tu ouvres un shell dans le conteneur, pas seulement au démarrage de l'app). Résultat :
- `pwd` te confirme que tu es dans `/app`.
- `ls` **sans argument** liste donc déjà `/app`, pas la racine `/`.
- Si tu tapes `ls app` (sans `/` devant), c'est un chemin **relatif** à `/app` → ça pointe vers `/app/app`.
- Si tu tapes `ls app/app` (toujours sans `/`), ça pointerait vers `/app/app/app`, qui **n'existe pas** — il n'y a que deux niveaux (`/app` puis `/app/app`), pas trois.

C'est pour ça que les commandes ci-dessus utilisent des chemins **absolus** (`/app`, `/app/app`, avec le `/` au début) : ils pointent toujours vers le même endroit, peu importe ton répertoire courant. Ce que tu verras confirmera exactement l'arborescence ci-dessus. C'est la clé de tout : **le Dockerfile construit ce système de fichiers, instruction par instruction, avant même que le conteneur existe.**

### 3.2 `WORKDIR` = un "cd" qui reste collé pour tout le reste du fichier

`WORKDIR /app` ne fait rien de magique : c'est l'équivalent d'un `cd /app` (et `mkdir -p /app` s'il n'existe pas encore) exécuté une fois, mais dont l'effet **reste actif pour toutes les instructions suivantes** du Dockerfile — `COPY`, `RUN`, et même la commande finale `CMD`.

Donc dès qu'on lit `WORKDIR /app`, il faut se dire : *"à partir de maintenant, chaque fois qu'une instruction utilise un chemin relatif (comme `./` ou un nom sans `/` devant), ça part de `/app` dans le conteneur."*

### 3.3 `COPY <source> <destination>` — deux étapes séparées, pas une seule

C'est là que se joue la confusion `app/app`. Il faut la voir comme **deux étapes strictement successives**, pas comme une seule opération magique.

**Étape 1 — ce que `WORKDIR /app` a déjà fait (section précédente) :**
```
/
└── app/          <-- créé par WORKDIR, vide pour l'instant
```

**Étape 2 — ce que fait `COPY --chown=appuser:appuser app /app/app` :**

- `app` (la source, sans `/` devant) = le dossier `app/` qui est à la racine de **ton projet sur ta machine** (celui qui contient `main.py`, `config.py`...), relatif au "build context" (`context: .` dans `docker-compose.yml`, donc la racine du projet).
- `/app/app` (la destination, chemin absolu) = un endroit précis **dans le conteneur en construction**.

Règle de `COPY` quand la source est un dossier : *si la destination n'existe pas encore, Docker la crée et y place le **contenu** du dossier source.* Ici, la destination `/app/app` n'existe pas encore (seul `/app` existe, créé à l'étape 1) — donc Docker crée ce sous-dossier `app` à l'intérieur du `/app` existant, et y verse tout le contenu de ton dossier local `app/` :

```
/
└── app/                    <-- le /app créé par WORKDIR (étape 1)
    └── app/                <-- créé par ce COPY, contient le CONTENU de ton dossier local "app"
        ├── main.py
        ├── config.py
        ├── database.py
        ├── models.py
        └── schemas.py
```

**Le `/app/app` n'est donc pas une erreur ni une redondance bizarre : c'est un sous-dossier `app` (étape 2) créé à l'intérieur du dossier `app` qui existait déjà dans l'image (étape 1) — ils portent le même nom par coïncidence, mais ce sont deux choses différentes :**
1. `/app` = le dossier de travail qu'on a choisi dans le conteneur (aurait pu s'appeler `/srv` ou `/code`, c'est juste une convention, fixée par `WORKDIR`).
2. le deuxième `app` = le nom donné à la destination du `COPY`, qui reprend (par choix, pas par obligation) le nom du dossier source sur ton disque.

Si le dossier source s'était appelé `src/` au lieu de `app/`, la ligne aurait été `COPY --chown=appuser:appuser src /app/src`, et il n'y aurait pas eu de confusion visuelle — mais le mécanisme aurait été rigoureusement identique : un dossier `src` créé à l'intérieur du `/app` existant.

### 3.4 Pourquoi ça compte pour faire tourner l'application

La commande finale est :

```dockerfile
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

`uvicorn` est lancé alors que le répertoire courant du conteneur est `/app` (à cause de `WORKDIR /app`, toujours actif). L'argument `app.main:app` est une **notation Python**, pas un chemin de fichier :
- `app.main` → va chercher un module Python appelé `main` dans un package appelé `app`. Comme le répertoire courant est `/app`, Python trouve le sous-dossier `/app/app/`, y voit `main.py`, et l'importe.
- `:app` (après les deux-points) → à l'intérieur de ce fichier `main.py`, va chercher une variable qui s'appelle `app` — c'est justement la ligne `app = FastAPI(...)` que tu as dans `app/main.py` sur ta machine.

Donc la chaîne `app.main:app` se lit : *"dossier app, fichier main.py, variable app dedans"*. Si `WORKDIR` avait été `/code` et qu'on avait fait `COPY app /code/app`, la commande `uvicorn app.main:app` aurait fonctionné exactement pareil, parce que Python cherche `app/` en partant du répertoire courant (`/code`), pas depuis la racine `/`.

### 3.5 Récapitulatif visuel : chaque instruction et son effet sur le disque du conteneur

| Instruction du Dockerfile | Effet concret sur le système de fichiers du conteneur |
|---|---|
| `WORKDIR /app` | Crée `/app` s'il n'existe pas, et en fait le "répertoire courant" pour la suite |
| `COPY requirements.txt ./` | Copie le fichier `requirements.txt` (host, racine du projet) vers `/app/requirements.txt` |
| `COPY --from=builder /wheels /wheels` | Copie le dossier `/wheels` **de l'étape `builder`** (pas du host !) vers `/wheels` dans l'image finale |
| `COPY --chown=appuser:appuser app /app/app` | Copie le dossier `app/` (host) vers `/app/app` (conteneur), en donnant les fichiers à `appuser` |

### 3.6 Le film complet du build : deux boîtes séparées, pas une seule

C'est le point qui manquait pour que tout s'emboîte : ce Dockerfile ne construit **pas un seul** système de fichiers progressivement, il en construit **deux, complètement indépendants l'un de l'autre**, l'un jetable (`builder`), l'autre final. Voici la chronologie exacte, instruction par instruction, avec l'état du disque à chaque étape.

**BOÎTE 1 — l'étape `builder`, temporaire et jetable**

| Instruction | État du disque de la BOÎTE 1 après cette instruction |
|---|---|
| `FROM python:3.12-slim AS builder` | Nouveau disque vide, avec juste Python installé dedans |
| `WORKDIR /build` | `/build` créé (vide) |
| `COPY requirements.txt ./` | `/build/requirements.txt` (copié **depuis ton host**) |
| `RUN pip wheel --wheel-dir /wheels -r requirements.txt` | `/wheels/*.whl` créé, en plus de `/build/requirements.txt` |

À la fin de cette étape, la BOÎTE 1 contient donc `/build/requirements.txt` **et** `/wheels/*.whl`, deux dossiers distincts à la racine.

**BOÎTE 2 — l'image finale, celle qui devient le conteneur `prj-app-1`**

| Instruction | État du disque de la BOÎTE 2 après cette instruction |
|---|---|
| `FROM python:3.12-slim` | **Nouveau disque vide, sans AUCUN rapport avec la BOÎTE 1.** `/build` n'existe pas ici et n'existera jamais ici. |
| `RUN useradd ... appuser` | L'utilisateur `appuser` existe |
| `WORKDIR /app` | `/app` créé (vide) |
| `COPY requirements.txt ./` | `/app/requirements.txt` — copié **depuis ton host**, pas depuis la BOÎTE 1 |
| `COPY --from=builder /wheels /wheels` | `/wheels/*.whl` — ici, exceptionnellement, la source est la **BOÎTE 1** (grâce à `--from=builder`), pas ton host. C'est la SEULE ligne qui fait le pont entre les deux boîtes. |
| `RUN pip install ... --find-links=/wheels && rm -rf /wheels` | Les paquets Python sont installés (rangés par `pip` dans ses propres dossiers système, pas visibles dans ce tableau simplifié) ; `/wheels` est ensuite supprimé |
| `COPY --chown=appuser:appuser app /app/app` | `/app/app/*.py` — copié **depuis ton host** |

**État final de la BOÎTE 2** (= ce que tu vois avec `docker exec -it prj-app-1 sh`) :
```
/
├── app/
│   ├── requirements.txt
│   └── app/
│       ├── main.py
│       ├── config.py
│       └── ...
├── home/appuser/
└── ... (Python + paquets installés, système Debian slim)
```

**Ce qu'il faut retenir :**
- `/build` n'a existé que dans la BOÎTE 1, qui est **entièrement jetée** dès que le deuxième `FROM` s'exécute. C'est pour ça qu'il n'apparaît **jamais** dans le conteneur qui tourne — il est mort avant que l'image finale existe.
- La seule chose qui traverse de la BOÎTE 1 vers la BOÎTE 2, c'est `/wheels` (via `COPY --from=builder`) — et même celui-là est supprimé juste après avoir servi.
- `requirements.txt` et `app/` ne sont "mélangés" nulle part : ils sont copiés par **deux instructions séparées**, chacune depuis ton host, vers deux destinations différentes (`/app/requirements.txt` et `/app/app`) qui se trouvent être **côte à côte** sous `/app` — exactement comme ils sont côte à côte sous la racine de ton projet sur le host.

---

## 4. Le `Dockerfile` de ce projet, expliqué bloc par bloc

Le `Dockerfile` est la recette qui décrit comment construire l'image de l'application (le service `app`, pas PostgreSQL — PostgreSQL utilise une image toute faite, voir section 5). Garde en tête la section 3 : chaque instruction ci-dessous modifie le système de fichiers du conteneur qu'on est en train de construire.

```dockerfile
FROM python:3.12-slim AS builder
```
On part d'une image officielle Python 3.12 en version "slim" (allégée, sans outils inutiles). Cette image contient déjà tout un système de fichiers Linux minimal (avec Python installé dedans). On lui donne le nom `builder` : c'est une étape **temporaire**, juste utilisée pour installer les dépendances.

```dockerfile
WORKDIR /build
COPY requirements.txt ./
RUN python -m pip install --upgrade pip && \
    pip wheel --wheel-dir /wheels -r requirements.txt
```
- `WORKDIR /build` : le répertoire courant de cette étape devient `/build` (voir section 3.2).
- `COPY requirements.txt ./` : copie `requirements.txt` (host) vers `/build/requirements.txt` (le `./` = le WORKDIR actif, donc `/build`).
- `RUN pip wheel --wheel-dir /wheels ...` : télécharge/compile chaque dépendance sous forme de fichier `.whl` (un paquet Python prêt à installer), et les range dans `/wheels` — un dossier séparé, pas dans `/build`.

On ne copie pas encore le code de l'app ici — c'est volontaire (voir "multi-stage" plus bas).

```dockerfile
FROM python:3.12-slim
```
Deuxième `FROM` : on **repart de zéro** avec une image Python toute propre, un tout nouveau système de fichiers. Tout ce qui existait dans l'étape `builder` (le `/build`, les outils de compilation, le cache pip...) **n'existe pas** dans cette nouvelle image — c'est un disque neuf. Seul ce qu'on copie explicitement avec `COPY --from=builder ...` sera transféré.

```dockerfile
RUN useradd --create-home --shell /usr/sbin/nologin appuser
```
On crée un utilisateur `appuser` qui n'est pas root. Par défaut un conteneur tourne en root, ce qui est risqué si quelqu'un arrive à exécuter du code dans le conteneur (root dans le conteneur a beaucoup de droits). On va faire tourner l'app avec cet utilisateur limité.

```dockerfile
WORKDIR /app
```
Cette fois le répertoire courant devient `/app` dans **cette nouvelle image** (pas la même chose que le `/build` de l'étape `builder`, qui n'existe plus). C'est le `/app` qu'on retrouvera dans le conteneur final.

```dockerfile
COPY requirements.txt ./
COPY --from=builder /wheels /wheels
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt && \
    rm -rf /wheels
```
- `COPY requirements.txt ./` : copie à nouveau depuis le **host** (pas depuis `builder`) vers `/app/requirements.txt` dans l'image finale.
- `COPY --from=builder /wheels /wheels` : ici la source n'est **pas** le host, c'est le dossier `/wheels` **de l'étape `builder`** — Docker va chercher dans le système de fichiers de cette étape précédente, pas sur ton disque. Destination : `/wheels` dans l'image finale (chemin absolu, donc indépendant du `WORKDIR`).
- `pip install ... --find-links=/wheels` : installe les paquets Python déjà compilés, sans re-télécharger sur Internet.
- `rm -rf /wheels` : supprime les fichiers `.whl` une fois installés, pour ne pas les garder dans l'image finale.

Résultat : l'image finale ne contient pas les outils de build utilisés dans `builder`, juste les paquets Python installés → image plus légère.

```dockerfile
COPY --chown=appuser:appuser app /app/app
```
On copie enfin le code de l'application (voir le détail complet en section 3.3), en donnant la propriété des fichiers à `appuser` (pas à root).

```dockerfile
USER appuser
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```
- `USER appuser` : à partir de cette ligne, tout ce qui tourne dans le conteneur (y compris la commande finale) s'exécute avec les droits limités de `appuser`, pas root.
- `EXPOSE 8000` : documentation — indique que l'app écoute sur le port 8000 (ça n'ouvre rien tout seul, voir section "ports" plus bas).
- `CMD [...]` : la commande lancée par défaut au démarrage du conteneur — ici, le serveur `uvicorn` qui fait tourner l'app FastAPI (détail de `app.main:app` en section 3.4).

**Pourquoi "multi-stage" (deux `FROM`) ?** Parce que compiler des dépendances Python demande parfois des outils (compilateurs, headers) qu'on ne veut pas garder dans l'image finale — ils prennent de la place et augmentent la surface d'attaque pour rien. Le multi-stage permet de tout faire dans une étape jetable puis de ne garder que le résultat utile dans l'image finale.

---

## 5. `docker-compose.yml` — faire tourner plusieurs conteneurs ensemble

L'application seule ne suffit pas : elle a besoin d'une base PostgreSQL. Docker Compose sert à décrire **plusieurs conteneurs qui doivent tourner ensemble**, dans un seul fichier, au lieu de taper des commandes `docker run` à rallonge.

### Le service `db`

```yaml
db:
  image: postgres:16-alpine
```
Pas de `Dockerfile` ici : on utilise directement l'image officielle PostgreSQL 16 (version "alpine" = très légère), déjà prête à l'emploi, publiée sur Docker Hub.

```yaml
  environment:
    POSTGRES_DB: ${POSTGRES_DB:-kps_tasks_db}
    POSTGRES_USER: ${POSTGRES_USER:-kps_tasks_user}
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-change_me}
```
Ces variables configurent PostgreSQL au premier démarrage (nom de la base, utilisateur, mot de passe). Elles viennent du fichier `.env` (voir section 7) — jamais écrites en dur dans une image.

```yaml
  volumes:
    - postgres_data:/var/lib/postgresql/data
```
Voir section 6 (volumes).

```yaml
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB"]
```
Voir section 9 (healthcheck).

### Le service `app`

```yaml
app:
  build:
    context: .
    dockerfile: Dockerfile
```
Contrairement à `db`, ici on **construit** l'image à partir du `Dockerfile` du projet (voir section 4), on ne la télécharge pas.

```yaml
  depends_on:
    db:
      condition: service_healthy
```
`app` ne démarre que lorsque `db` est déclaré "healthy" (sain), pas juste "démarré". PostgreSQL peut mettre quelques secondes à être réellement prêt à accepter des connexions même une fois le conteneur lancé — cette condition évite à `app` de se connecter trop tôt et de planter.

```yaml
  ports:
    - "${APP_PORT:-8000}:8000"
```
Voir section 8 (ports vs expose).

```yaml
  command: >
    sh -c "python -m app.init_db && exec uvicorn app.main:app --host 0.0.0.0 --port 8000"
```
Ceci **remplace** le `CMD` du Dockerfile : avant de lancer le serveur, on exécute `init_db` (création des tables si elles n'existent pas encore), puis on démarre `uvicorn`.

---

## 6. Le réseau et les volumes — pourquoi les données ne disparaissent pas

### Le réseau

Quand Compose démarre les services, il crée un réseau privé (visible dans les logs sous le nom `prj_default`) auquel seuls `app` et `db` ont accès. À l'intérieur de ce réseau, chaque service est joignable **par son nom** — c'est pour ça que dans `DATABASE_URL` on écrit :

```
postgresql+psycopg://kps_tasks_user:change_me@db:5432/kps_tasks_db
```

et pas `@localhost:5432`. Depuis le conteneur `app`, `localhost` désignerait le conteneur `app` lui-même (pas la base) — c'est le piège classique. `db` fonctionne parce que Compose fait de la résolution de noms automatique entre les services d'un même projet.

### Le volume

```yaml
volumes:
  postgres_data:/var/lib/postgresql/data
```

Un conteneur est **éphémère** par nature : si on le supprime, tout ce qui a été écrit à l'intérieur disparaît avec lui. Problème : PostgreSQL écrit ses données dans `/var/lib/postgresql/data` à l'intérieur du conteneur.

Un **volume Docker** est un espace de stockage géré par Docker, qui existe **en dehors** du cycle de vie du conteneur. On le "branche" (mount) sur `/var/lib/postgresql/data` : PostgreSQL écrit dedans sans savoir que ce n'est pas un dossier normal du conteneur. Si le conteneur `db` est supprimé et recréé, le volume `postgres_data` reste intact et les données sont toujours là.

C'est exactement ce qu'on a vérifié avec le test : créer une tâche, faire `docker compose restart`, et retrouver la tâche via `curl http://127.0.0.1:8000/tasks`.

---

## 7. Les variables d'environnement et `.env`

L'app a besoin de valeurs qui changent selon l'endroit où elle tourne (mot de passe, environnement `production`/`development`...). Ces valeurs ne doivent **jamais** être écrites en dur dans une image Docker : n'importe qui pourrait extraire l'image et lire le secret.

- `.env.example` : un modèle **sans vrai secret**, commité dans Git, qui montre quelles variables existent.
- `.env` : le vrai fichier avec les vraies valeurs, créé localement (`cp .env.example .env`), **jamais commité** (il est dans `.gitignore`).

Docker Compose lit automatiquement `.env` à la racine du projet et remplace les `${VARIABLE}` du `docker-compose.yml` par les vraies valeurs au démarrage.

---

## 8. `ports` vs `expose` — pourquoi PostgreSQL n'est pas accessible depuis l'extérieur

- `app` a une section `ports: - "8000:8000"` → le port 8000 du conteneur est **publié** sur la machine hôte. Depuis l'extérieur (ton navigateur, `curl`), on peut taper `http://IP_DU_VPS:8000`.
- `db` n'a **aucune section `ports`** → PostgreSQL n'est joignable que **depuis le réseau Docker interne**, par les autres conteneurs (`app`). Personne depuis l'extérieur ne peut s'y connecter directement, même en connaissant l'IP du serveur.

C'est une contrainte de sécurité volontaire : une base de données ne doit jamais être exposée directement sur Internet.

---

## 9. Le healthcheck — comment Docker sait qu'un service est réellement prêt

Un conteneur "démarré" n'est pas forcément "prêt à travailler". Le healthcheck est une commande que Docker exécute régulièrement à l'intérieur du conteneur pour vérifier qu'il répond correctement.

- **`db`** : `pg_isready` vérifie que PostgreSQL accepte des connexions.
- **`app`** : une requête HTTP vers `/health`, qui vérifie non seulement que le serveur web répond, mais aussi que la connexion à PostgreSQL fonctionne (voir `app/main.py`, endpoint `/health`).

Tant que le healthcheck échoue, le conteneur reste marqué `unhealthy` (visible avec `docker compose ps`), ce qui permet notamment au `depends_on: condition: service_healthy` de fonctionner (section 5).

---

## 10. Ce qu'il se passe réellement quand tu tapes `docker compose up -d`

1. Compose lit `docker-compose.yml` et `.env`.
2. Il télécharge l'image `postgres:16-alpine` si elle n'est pas déjà en local.
3. Il construit l'image `prj-app` à partir du `Dockerfile` si elle n'existe pas ou si le code a changé.
4. Il crée le réseau privé du projet (`prj_default`).
5. Il crée le volume `postgres_data` s'il n'existe pas déjà.
6. Il démarre le conteneur `db`, attend qu'il devienne `healthy`.
7. Il démarre le conteneur `app` (qui exécute `init_db` puis `uvicorn`), attend qu'il devienne `healthy`.
8. Le `-d` ("detached") fait tout ça en arrière-plan et te rend la main sur le terminal.

---

## 11. Commandes du quotidien pour ce projet

```bash
docker compose up -d --build   # (re)construire les images et démarrer la stack
docker compose ps              # voir l'état des conteneurs (running/healthy)
docker compose logs -f app     # suivre les logs de l'application en direct
docker compose logs -f db      # suivre les logs de PostgreSQL
docker compose restart         # redémarrer tous les services (test de persistance)
docker compose down            # arrêter et supprimer les conteneurs (le volume reste)
docker compose down -v         # arrêter et supprimer AUSSI le volume (perte des données !)
docker exec -it prj-app-1 sh   # ouvrir un shell dans le conteneur app pour inspecter
```

---

## 12. Ce qu'il faut retenir en une phrase

Docker ne change pas ce que fait l'application — il change **comment elle est packagée et déployée** : au lieu d'installer des dépendances directement sur un serveur fragile, on encapsule tout dans des images reproductibles, orchestrées par `docker-compose.yml`, avec un réseau isolé, des volumes pour la persistance, et des healthchecks pour savoir quand tout est réellement prêt.
