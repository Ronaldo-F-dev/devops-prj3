# Support de soutenance — Projet 2 : OpsReady-02

Support pour une présentation orale de 10 à 15 minutes. Chaque section correspond à un point attendu du brief (Jour 5, Phase 3).

## 1. Contexte

- Le client fictif LogiCare Solutions a validé une première mise en production de son API interne (KPS Tasks API) directement sur un VPS Linux (Projet 1) : installation manuelle, PostgreSQL sur la machine, service `systemd`, reverse proxy.
- Limites constatées : installation difficile à reproduire, dépendances couplées à la machine, environnements longs à préparer, erreurs de configuration fréquentes.
- Objectif du Projet 2 : conteneuriser l'application avec Docker et Docker Compose, en vue d'une future chaîne CI/CD et d'une migration Kubernetes.

## 2. Architecture Docker Compose

```
Utilisateur externe
   -> IP publique du VPS
   -> Conteneur app (port 8000 publié)
   -> Réseau Docker dédié : kps_net
   -> Conteneur db : PostgreSQL (port 5432, non publié)
   -> Volume Docker persistant : postgres_data
```

- Deux services définis dans `docker-compose.yml` : `app` (construit depuis le `Dockerfile` du projet) et `db` (image officielle `postgres:16-alpine`).
- Le `Dockerfile` de `app` est multi-stage : une étape `builder` compile les dépendances Python en `.whl`, l'image finale n'installe que les paquets déjà construits — image plus légère, pas d'outils de compilation superflus.

## 3. Rôle de chaque service

- **`app`** : exécute `python -m app.init_db` (création des tables si besoin) puis démarre `uvicorn` sur le port 8000. Tourne avec un utilisateur non-root (`appuser`), pas `root`.
- **`db`** : stocke les données de l'API dans PostgreSQL 16, isolé du réseau public.

## 4. Gestion des variables

- Toutes les valeurs qui changent selon l'environnement (mot de passe PostgreSQL, `APP_ENV`, `DATABASE_URL`...) sont injectées par variables d'environnement, jamais écrites en dur dans une image.
- `.env.example` : modèle sans secret, commité dans Git.
- `.env` : vraies valeurs, créé localement (`cp .env.example .env`), exclu de Git via `.gitignore`.

## 5. Gestion des volumes

- Le volume nommé `postgres_data` est monté sur `/var/lib/postgresql/data` dans le conteneur `db`.
- Un conteneur est éphémère : sans volume, les données de PostgreSQL disparaîtraient à chaque suppression du conteneur.
- Preuve réalisée (voir `docs/postgres-persistence-proof.md`) : une tâche créée avant `docker compose down && docker compose up -d` est toujours présente après, aussi bien en local que sur le VPS.

## 6. Gestion du réseau

- `docker-compose.yml` déclare un réseau bridge dédié et nommé, `kps_net`, auquel `app` et `db` sont reliés (voir `docs/docker-networking.md`).
- Résolution de noms interne à Compose : `app` joint PostgreSQL via `db` (nom du service), pas via `localhost` — depuis un conteneur, `localhost` désigne le conteneur lui-même.
- Seul le port de `app` (8000) est publié sur l'hôte. PostgreSQL n'a aucune section `ports` : il n'est joignable que depuis le réseau Docker interne.

## 7. Logs

- Logs applicatifs consultables avec `docker compose logs -f app` (ou `scripts/logs.sh app`).
- Logs PostgreSQL consultables avec `docker compose logs -f db` (ou `scripts/logs.sh db`).
- L'application logge chaque requête HTTP (méthode, route, code de statut, durée) sur la sortie standard — récupérée automatiquement par Docker.

## 8. Healthcheck

- `db` : `pg_isready -U $POSTGRES_USER -d $POSTGRES_DB`, vérifie que PostgreSQL accepte des connexions.
- `app` : requête HTTP vers `/health`, qui vérifie à la fois que le serveur répond et que la connexion PostgreSQL fonctionne.
- `depends_on: condition: service_healthy` sur `app` : le conteneur applicatif n'est lancé qu'une fois `db` réellement prêt, pas juste démarré.
- Preuve réalisée (voir `docs/healthcheck-proof.md`) : `curl http://127.0.0.1:8000/health` renvoie `{"status":"ok","database":"ok"}` une fois la stack `healthy`.

## 9. Comparaison avec systemd

Voir `docs/systemd-vs-docker.md` pour le détail complet. Résumé :

| Aspect | systemd (Projet 1) | Docker Compose (Projet 2) |
|---|---|---|
| Dépendances | Installées sur la machine hôte | Embarquées dans l'image |
| Reproductibilité | Faible, dépend de l'état du serveur | Élevée, même image partout |
| Redémarrage | `systemctl restart` | `docker compose restart` |
| Isolation | Aucune, partage le système hôte | Filesystem et réseau isolés par conteneur |
| Persistance | Fichiers/DB directement sur disque hôte | Volumes Docker explicites |
| Complexité | Simple à comprendre, mais fragile à reproduire | Concepts supplémentaires (image, réseau, volume) à maîtriser |

## 10. Incident diagnostiqué

Pendant la migration, l'ancien déploiement Linux du Projet 1 était encore actif sur le VPS et entrait en conflit avec la nouvelle stack Docker (voir `docs/incident-report.md` pour le détail complet) :

- `task.service` (systemd) faisait encore tourner l'API directement sur le port 8000.
- Une tâche cron dans `/etc/cron.d/kps-tasks-api-backup` déclenchait encore un backup PostgreSQL lié à l'ancien déploiement.

Diagnostic : `systemctl list-units`, `systemctl status task.service`, `ss -tulpn | grep :8000`, `grep -R` dans les répertoires cron.

Correctif : arrêt et désactivation de `task.service`, suppression du fichier unit, nettoyage des fichiers cron obsolètes, `systemctl daemon-reload`. Vérification : le port 8000 ne répondait plus avant de relancer la stack Docker, qui a ensuite pu démarrer proprement sans conflit de port.

## 11. Limites et améliorations possibles

- La stack Docker Compose actuelle expose l'application directement sur le port 8000 (option A du brief) — une évolution possible est d'ajouter Nginx en reverse proxy (option B) pour ne plus publier directement ce port.
- Docker Compose reste un outil mono-machine : il ne gère ni la haute disponibilité, ni le scaling automatique, ni le déploiement multi-serveurs — ce sont les limites qui justifient une future migration vers Kubernetes.
- L'utilisateur système qui exécute `docker compose` sur le VPS n'est pas membre du groupe `docker` : les commandes nécessitent `sudo`. À corriger avec `sudo usermod -aG docker <utilisateur>` pour un usage courant sans `sudo`.
- Les sauvegardes PostgreSQL (`scripts/backup_postgres.sh`) sont manuelles ou à planifier via cron sur l'hôte ; une amélioration serait de les automatiser proprement dans la stack elle-même (conteneur dédié ou tâche planifiée versionnée).
