# Processus de déploiement automatisé

## Vue d'ensemble

```
Merge sur main
  → CI : lint, test, build, Gitleaks, Sonar
  → docker_build : image taguée et poussée sur GHCR
  → deploy (environnement "production", approbation manuelle si non-admin) :
      copie docker-compose.prod.yml + scripts/deploy.sh vers le VPS (SCP)
      exécution de scripts/deploy.sh sur le VPS (SSH) :
        sauvegarde previous-version.txt
        met à jour IMAGE_TAG dans .env
        docker login → docker compose pull → docker compose up -d
        vérifie /health (jusqu'à 10 tentatives, 3s d'intervalle)
        si OK : écrit current-version.txt
```

## Pourquoi deux fichiers Compose distincts (question 42)

`docker-compose.yml` (développement) **construit** l'image localement (`build:`) — pratique pour itérer vite, mais chaque environnement qui l'utilise doit refaire la compilation.

`docker-compose.prod.yml` **consomme** une image déjà construite et déjà validée par la CI (`image: ${IMAGE_TAG}`, pas de `build:`). La production ne doit jamais reconstruire quoi que ce soit : elle déploie exactement l'artefact qui a passé lint/test/Gitleaks/Sonar, ni plus ni moins. Séparer les deux fichiers rend cette différence explicite au lieu de la cacher dans des conditions.

## Pourquoi ne pas construire l'image directement sur le VPS (question 43)

Voir `docs/prj4/intermediate-questions.md` (question 24, Jour 2) — les mêmes raisons s'appliquent : reproductibilité, séparation des responsabilités (le VPS sert l'application, il ne la compile pas), traçabilité, rapidité (un `pull` est plus rapide qu'un `build` complet à chaque déploiement).

## `current-version.txt` et `previous-version.txt` (question 44)

Avant toute modification, `scripts/deploy.sh` copie `current-version.txt` vers `previous-version.txt` **si le fichier existe déjà**. Ça donne, à tout moment, une réponse simple et fiable à deux questions :
- *Quelle version tourne actuellement ?* → `cat current-version.txt`
- *Vers quelle version faut-il revenir en cas de problème ?* → `cat previous-version.txt`

C'est la base du mécanisme de rollback automatique du Jour 4 : sans ce fichier, le script de rollback n'aurait aucun moyen fiable de savoir quelle image redéployer.

## Comment on s'assure que PostgreSQL n'est pas supprimé (question 45)

Deux protections, à deux niveaux différents :

1. **`docker compose down` n'est jamais utilisé** par `deploy.sh` (qui supprimerait les conteneurs mais pas les volumes par défaut — mais `down -v` le ferait, donc on l'évite catégoriquement). Seul `docker compose up -d` est utilisé, qui recrée/redémarre les conteneurs sans toucher aux volumes.
2. **Le volume est déclaré `external: true`** dans `docker-compose.prod.yml`, avec un nom explicite (`app_postgres_data`, celui qui existait déjà avant ce projet). Un volume externe n'est **jamais** créé ni supprimé par Docker Compose — il doit exister au préalable, et Compose se contente de le monter. C'est une garantie structurelle, pas juste une question de discipline dans les commandes exécutées.

Preuve réelle (pas un test simulé) : ce projet a migré un vrai déploiement (Projet 2, `/home/ronaldo/app`) vers le nouveau pipeline automatisé, en réutilisant ce volume exact. Après bascule, `GET /tasks` renvoie toujours la tâche créée avant la migration — voir `evidence/deploy-verification.txt`.

## Différence entre déployer une image et déployer du code (question 46)

Déployer du **code**, c'est transférer des fichiers sources sur une machine et les exécuter avec l'environnement (interpréteur, dépendances) déjà présent sur cette machine — l'environnement d'exécution et le code sont couplés, et un environnement légèrement différent peut faire échouer un déploiement qui marchait ailleurs.

Déployer une **image**, c'est transférer un artefact qui contient déjà tout : le code, les dépendances exactes, et un environnement d'exécution figé. Le VPS n'a besoin que de Docker pour l'exécuter — peu importe ce qui est installé dessus par ailleurs. C'est ce qui permet à `deploy.sh` de ne faire qu'un `pull` + `up -d`, sans jamais avoir à installer quoi que ce soit sur le serveur lui-même.

## Note sur l'approbation manuelle (bonus)

Un environnement GitHub `production` a été configuré avec approbation manuelle obligatoire (`required_reviewers`) avant tout déploiement, restreint à la branche `main`.

Le tout premier run n'a pas marqué de pause (probablement le temps que la règle de protection, créée juste avant, se propage pleinement côté GitHub). Le run suivant, lui, s'est bien arrêté sur `Deploy to VPS: waiting`, avec un déploiement en attente visible via l'API (`pending_deployments`) et dans l'onglet Actions → "Review deployments". L'approbation manuelle a été donnée depuis l'interface GitHub, et le déploiement a repris et terminé avec succès — le mécanisme fonctionne comme attendu.

## Preuves

- Job de déploiement complet : `evidence/deploy-success.txt`
- Vérification post-déploiement (`/health`, `/version`, `/tasks`, conteneurs, volume) : `evidence/deploy-verification.txt`
- Migration de l'ancien déploiement manuel : `docs/prj4/cicd-architecture.md`, section 7
