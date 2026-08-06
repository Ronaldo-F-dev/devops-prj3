# Architecture CI/CD — Jour 1 : registre et accès

Ce document explique, pas à pas et en langage clair, ce qui a été mis en place et pourquoi. Il sera complété au fil des jours.

## 1. Choix du registre Docker (tâche 1)

**Décision : GitHub Container Registry (GHCR, `ghcr.io`).**

Un registre Docker, c'est l'endroit où on stocke les images construites, pour que d'autres machines (ici, le VPS) puissent les télécharger (`docker pull`) sans avoir besoin de reconstruire l'image elles-mêmes.

Pourquoi GHCR et pas un autre (Docker Hub, etc.) :
- Le dépôt est déjà sur GitHub → pas de nouveau compte à créer, pas de nouveau système d'authentification à apprendre.
- L'intégration avec les GitHub Actions (notre CI) est native.
- C'est exactement ce que le brief recommande : "utiliser le registre intégré à la plateforme Git".

## 2. Configuration du registre (tâche 2)

Sur GHCR, il n'y a **pas de bouton "activer"** à chercher : le package (l'image stockée) se crée tout seul dès le premier `docker push`. Mais deux réglages ont dû être vérifiés/décidés :

### a) Les permissions du token de CI

Chaque run de GitHub Actions dispose d'un jeton automatique, `GITHUB_TOKEN`, valable seulement le temps du run. En vérifiant les réglages du dépôt, j'ai trouvé que ce token a par défaut uniquement la permission **lecture** (`default_workflow_permissions: read`).

Conséquence concrète : si on essaie de faire un `docker push` depuis un job GitHub Actions sans rien changer, ça échouera avec une erreur "permission denied". **Il faudra donc, au Jour 2, ajouter explicitement dans le job de build/push :**

```yaml
permissions:
  packages: write
```

C'est une bonne pratique de sécurité (le principe du "moindre privilège" : chaque job ne demande que les droits dont il a vraiment besoin), donc on ne change rien au réglage global du dépôt — on l'autorise juste, job par job, là où c'est nécessaire.

### b) La visibilité du package (image privée ou publique)

**Décision : privée.**

Une image Docker peut contenir des détails qu'on ne veut pas rendre publics (structure interne, dépendances précises, etc.), même si le code source, lui, est public. On a choisi que l'image reste privée : ça veut dire que pour la télécharger (`docker pull`), il faut être authentifié — y compris pour le VPS qui va la récupérer au moment du déploiement.

C'est cohérent avec ce que le brief attend : il liste explicitement des variables `REGISTRY_USER` / `REGISTRY_PASSWORD`, ce qui suppose qu'une authentification est nécessaire quelque part dans la chaîne.

### c) Où voir l'image concrètement

Point important à bien comprendre : **l'image Docker n'est pas un fichier du dépôt Git**. On ne la trouvera jamais en naviguant dans les fichiers du repo sur GitHub — elle vit dans une section séparée de GitHub appelée **Packages**.

- Sur le profil GitHub, onglet **Packages** : https://github.com/Ronaldo-F-dev?tab=packages
- Lien direct vers le package de ce projet : https://github.com/users/Ronaldo-F-dev/packages/container/package/kps-tasks-api

Comme le package est **privé** (décision du point 2b), seul le compte `Ronaldo-F-dev` (connecté) peut le voir dans l'interface GitHub — ce n'est pas visible publiquement, même si le code source du dépôt, lui, est public. Pour que le VPS puisse le récupérer plus tard, il devra s'authentifier avec le PAT (voir tâche 3 ci-dessous), exactement comme n'importe quel utilisateur externe.

Chaque version poussée de l'image apparaît comme un **tag** sur cette page (ex. `auth-check` pour l'instant — le tag de test créé pendant la vérification ci-dessous). Au Jour 2, ces tags seront remplacés par la vraie stratégie de versioning (SHA de commit, version Git).

## 3. Vérification de l'authentification (tâche 3)

Ici, il fallait distinguer **deux mécanismes d'authentification différents**, qui servent à deux moments différents :

| Qui s'authentifie | Avec quoi | Quand | Pourquoi |
|---|---|---|---|
| Le pipeline CI (GitHub Actions), pour **pousser** l'image | `GITHUB_TOKEN` automatique | Uniquement pendant l'exécution du job | Ce token existe et vit seulement le temps du run — inutile de le stocker, GitHub le fournit à chaque fois |
| Le VPS, pour **récupérer** (`pull`) l'image au moment du déploiement | Un **Personal Access Token (PAT)** créé manuellement sur GitHub | À chaque déploiement, depuis une machine externe (le VPS) | Le VPS n'est pas un run GitHub Actions : il n'a pas de `GITHUB_TOKEN`. Il lui faut un identifiant à lui, qui dure dans le temps |

### Ce qui a été testé concrètement

Un PAT classique a été créé (scope `write:packages`, qui inclut aussi la lecture) et testé en conditions réelles, depuis ce poste de travail (pour simuler ce que fera le VPS plus tard) :

1. `docker login ghcr.io` avec le PAT → connexion acceptée
2. `docker build` de l'image du projet, taguée `ghcr.io/ronaldo-f-dev/kps-tasks-api:auth-check`
3. `docker push` → **réussi** (preuve que le PAT a bien le droit d'écrire sur le registre)
4. Suppression de l'image en local, puis `docker pull` du même tag → **réussi** (preuve que le PAT a bien le droit de lire/télécharger, comme devra le faire le VPS)
5. Vérification via l'API GitHub que le package `kps-tasks-api` est bien créé et **privé**, comme décidé au point 2b

Une fois ce test validé, le fichier local contenant le token a été supprimé, et la session Docker locale déconnectée (`docker logout`) — le PAT ne doit pas traîner sur la machine plus longtemps que nécessaire.

### Secrets stockés dans GitHub Actions

Ces trois valeurs sont maintenant enregistrées dans *Settings → Secrets and variables → Actions* du dépôt (jamais visibles en clair, ni dans le code, ni dans les logs) :

- `REGISTRY_URL` = `ghcr.io`
- `REGISTRY_USER` = `Ronaldo-F-dev`
- `REGISTRY_PASSWORD` = le PAT créé ci-dessus

Ces variables serviront au Jour 2 (le job de la CI qui pousse l'image) et au Jour 3 (le script `deploy.sh` qui, exécuté sur ou vers le VPS, doit lui aussi s'authentifier pour faire le `pull`).

## 4. Utilisateur de déploiement sur le VPS (tâche 5)

**Décision : réutiliser l'utilisateur existant `ronaldo`, ne pas en créer un nouveau.**

Pourquoi :
- Il est déjà **non-root** — ce qui est justement une des contraintes non négociables du brief ("non-root deployment user"). Créer un utilisateur dédié supplémentaire n'apporterait rien de plus en sécurité ici, juste une identité de plus à gérer.
- Il a déjà accès SSH au VPS (clé régénérée le 2026-08-03, suite à l'incident de sécurité documenté dans `docs/prj3/security-and-quality.md`).
- Il fait déjà partie du groupe `sudo` pour les opérations d'administration ponctuelles (créer un dossier, changer un groupe) — mais **pas** pour les déploiements de routine, qui doivent pouvoir s'exécuter sans mot de passe interactif (voir point suivant).

Un ajustement a été nécessaire : `ronaldo` n'était pas membre du groupe `docker`, donc chaque commande `docker`/`docker compose` exigeait `sudo` — impossible à automatiser depuis un pipeline (sudo demande un mot de passe interactif, qu'un job CI ne peut pas fournir). Correctif, exécuté une fois manuellement sur le VPS (nécessite les droits root, donc pas automatisable depuis ce poste) :

```bash
sudo usermod -aG docker ronaldo
```

Une fois dans le groupe `docker`, `ronaldo` peut lancer `docker`/`docker compose` sans `sudo` — exactement ce qu'il faut pour un déploiement automatisé non interactif.

## 5. Accès SSH depuis le pipeline (tâche 6)

La clé SSH déjà présente (`~/.ssh/id_ed25519`, régénérée le 2026-08-03) a été testée avec succès :

```bash
ssh -i ~/.ssh/id_ed25519 ronaldo@<IP_VPS> "whoami"
# → ronaldo
```

Pour que le pipeline GitHub Actions puisse se connecter de la même façon, la **clé privée** doit devenir un secret (`DEPLOY_SSH_PRIVATE_KEY`), et l'hôte/l'utilisateur des secrets simples (`DEPLOY_HOST`, `DEPLOY_USER`) — voir `docs/prj4/ci-cd-variables.md`.

## 6. Répertoire applicatif sur le VPS (tâche 7)

Créé (opération root, faite une fois manuellement) :

```bash
sudo mkdir -p /opt/kps-tasks-api
sudo chown ronaldo:ronaldo /opt/kps-tasks-api
```

`ronaldo` est propriétaire du dossier, donc tout ce qui suit (copier `docker-compose.prod.yml`, écrire `.env`, exécuter `deploy.sh`) peut se faire sans `sudo`.

## 7. Découverte importante : un déploiement manuel existe déjà (tâches 8-9)

En inspectant le VPS, on a trouvé que le déploiement manuel du **Projet 2** tourne toujours, dans `/home/ronaldo/app/` — exactement le scénario "déploiement manuel" que le brief du Projet 4 décrit comme point de départ à corriger. Deux conséquences concrètes pour la suite :

1. **Conflit de port** : cet ancien déploiement utilise aussi le port 8000. Le nouveau déploiement automatisé (`/opt/kps-tasks-api/`) va le remplacer, pas coexister avec lui.
2. **Données réelles à préserver** : la base PostgreSQL de cet ancien déploiement contient de vraies données, dans un volume Docker nommé `app_postgres_data` (le nom vient du dossier `app/`, que Docker Compose utilise par défaut comme préfixe). Le nouveau `docker-compose.prod.yml`, lancé depuis `/opt/kps-tasks-api/`, nommerait son volume différemment (`kps-tasks-api_postgres_data`) s'il n'était pas configuré explicitement — ce qui créerait une base **vide**, et donnerait l'impression d'une perte de données alors que l'ancien volume existerait toujours, juste orphelin. La correction : déclarer le volume comme **externe**, avec le nom exact de l'existant, dans `docker-compose.prod.yml`, pour que le nouveau déploiement reprenne exactement les mêmes données (détail dans `docs/prj4/deployment-process.md`).

Schéma d'architecture complet (flux cible) :

```
Dépôt GitHub (push/tag)
  → CI : lint, test, build, Gitleaks, Sonar
  → docker_build : build + tag + push vers GHCR
  → deploy (nouveau job) :
      SSH vers le VPS (ronaldo@<IP>, clé privée en secret)
      → copie docker-compose.prod.yml + scripts/deploy.sh vers /opt/kps-tasks-api/
      → exécution de deploy.sh sur le VPS :
          docker login (registre) → docker compose pull → docker compose up -d
          → vérification /health
```

## 8. Vérifier que le VPS peut faire un `pull` (tâche 10)

À valider une fois `docker-compose.prod.yml` et le job `deploy` en place (Jour 3, section suivante) — le premier déploiement réel servira de preuve.
