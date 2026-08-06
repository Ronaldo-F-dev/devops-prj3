# Variables CI/CD

## Liste complète

| Variable | Valeur / origine | Utilisée par | Pourquoi |
|---|---|---|---|
| `REGISTRY_URL` | `ghcr.io` | Job `deploy` (déploiement VPS) | Adresse du registre pour le `docker login` côté VPS |
| `REGISTRY_USER` | `Ronaldo-F-dev` | Job `deploy` | Identifiant pour le `docker login` côté VPS |
| `REGISTRY_PASSWORD` | Personal Access Token GitHub (scope `write:packages`) | Job `deploy` | Authentifie le `docker pull` sur le VPS (le job `docker_build`, lui, utilise `GITHUB_TOKEN`, voir `docs/prj4/cicd-architecture.md`) |
| `DEPLOY_HOST` | IP du VPS 1 | Job `deploy` | Cible de la connexion SSH |
| `DEPLOY_USER` | `ronaldo` | Job `deploy` | Utilisateur SSH non-root (voir `docs/prj4/cicd-architecture.md`, section 4) |
| `DEPLOY_SSH_PRIVATE_KEY` | Clé privée `id_ed25519` | Job `deploy` | Authentification SSH sans mot de passe depuis la CI |
| `SONAR_TOKEN` | Token SonarCloud | Job `sonar` | Authentifie l'analyse de qualité (mis en place au Projet 3) |

Toutes ces valeurs vivent uniquement dans *Settings → Secrets and variables → Actions* du dépôt GitHub — jamais dans le code, jamais dans un fichier commité.

## Types de variables — le vocabulaire du brief, appliqué à GitHub

Le brief distingue quatre notions (vocabulaire hérité de GitLab, mais les concepts sont transférables) :

| Terme du brief | Équivalent GitHub Actions | Utilisé ici ? |
|---|---|---|
| **Project variable** | *Repository variable* (`Settings → Secrets and variables → Actions → Variables`) — valeur simple, visible en clair dans les logs et l'interface, pas chiffrée | Non — même `REGISTRY_URL`/`REGISTRY_USER`, qui ne sont pas sensibles en soi, ont été mis en secret par simplicité et cohérence (un seul endroit à gérer) |
| **Protected variable** | *Environment secret*, lié à un environnement protégé (ici, `production`) | Partiellement — la protection appliquée est celle de l'environnement `production` lui-même (approbation manuelle, restriction de branche à `main`), pas une protection variable par variable |
| **Masked variable** | *Repository secret* (`Settings → Secrets and variables → Actions → Secrets`) — la valeur est chiffrée au repos et automatiquement remplacée par `***` dans tous les logs de run | Oui, pour toutes les variables ci-dessus |
| **Secret stored in Git (à éviter)** | Committer une valeur en clair dans le code | Jamais volontairement — et un incident réel de ce type (identifiants VPS oubliés dans `.gitignore`) a été rencontré et corrigé au Projet 3, voir `docs/prj3/security-and-quality.md` |

## Pourquoi `GITHUB_TOKEN` n'apparaît pas dans ce tableau

`GITHUB_TOKEN` n'est pas une variable à configurer : GitHub le génère automatiquement pour chaque run, avec une durée de vie limitée au run lui-même. Il est utilisé par le job `docker_build` pour pousser l'image vers GHCR (voir `docs/prj4/cicd-architecture.md`, section 3), sans qu'aucun secret persistant n'ait besoin d'être stocké pour cet usage précis.
