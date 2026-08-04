# Projet 4 — OpsReady-04 : livraison continue vers un VPS avec rollback automatique

Résumé général du brief (`Project4_OpsReady04_Learner_Brief_EN.pdf`), avant de commencer le travail jour par jour.

## Objectif

Construire une première chaîne CI/CD complète, **sans Kubernetes** (ça viendra plus tard). Comprendre et mettre en œuvre le trajet complet :

```
Code validé dans Git
  → pipeline CI
  → image Docker construite
  → image poussée sur un registre
  → déploiement automatisé sur le VPS
  → healthcheck post-déploiement
  → rollback automatique en cas d'échec
```

## Contexte

LogiCare Solutions a déjà une application conteneurisée avec une CI qui vérifie qualité/sécurité (Projets 1-3). Mais le déploiement en production reste manuel : image construite à la main, commandes tapées une par une, versions pas toujours traçables, pas de rollback, une version cassée peut rester en ligne, secrets mal gérés. Objectif : automatiser la livraison **tout en gardant un filet de sécurité** — si la nouvelle version ne répond pas correctement, l'ancienne doit revenir automatiquement.

## Infrastructure

- **VPS 1** (application) : héberge l'app en prod, Docker Compose, PostgreSQL, reçoit les déploiements automatisés.
- **VPS 2** (CI/CD, optionnel) : peut héberger un runner GitLab et piloter les déploiements vers VPS 1.
- **Registre Docker** : le plus simple recommandé — celui intégré à la plateforme Git déjà utilisée (GitHub Container Registry, dans notre cas, puisqu'on est sur GitHub).

## Contraintes non négociables

- Ne jamais déployer une image sans tag (pas de `latest` comme référence de prod)
- Secrets uniquement en variables CI/CD, jamais dans Git
- PostgreSQL jamais exposé publiquement
- Ne jamais supprimer les volumes de données pendant un déploiement
- Garder une référence à la version précédente
- Healthcheck obligatoire après déploiement
- Rollback automatique en cas d'échec
- Tout documenter
- Approbation manuelle avant prod si la plateforme le permet

## Découpage des 5 jours

| Jour | Objectif |
|---|---|
| **1** | Registre Docker, variables CI/CD, préparation du VPS (utilisateur de déploiement, accès SSH, architecture cible) |
| **2** | Build et push d'une image Docker versionnée (tag SHA court + tag de version Git) |
| **3** | Déploiement automatisé vers le VPS (`docker-compose.prod.yml`, `scripts/deploy.sh`, SSH depuis le pipeline) |
| **4** | Healthcheck post-déploiement + rollback automatique (`scripts/healthcheck.sh`, `scripts/rollback.sh`) |
| **5** | Démo complète, incident déclenché par le formateur, mini-soutenance |

## Livrables finaux attendus

- Pipeline CI/CD mis à jour (`.github/workflows/`)
- `docker-compose.prod.yml`, `scripts/deploy.sh`, `scripts/healthcheck.sh`, `scripts/rollback.sh`
- `docs/prj4/cicd-architecture.md`, `ci-cd-variables.md`, `image-versioning.md`, `deployment-process.md`, `rollback-strategy.md`, `incident-report.md`
- Preuves : build d'image, push registre, déploiement, rollback
- Support de mini-soutenance

## Critères de validation obligatoires

Image construite en pipeline, taguée correctement, poussée sur un registre, secrets via variables CI/CD, VPS capable de récupérer l'image, déploiement automatisé, application qui répond après déploiement, `/version` qui reflète la version déployée, rollback automatique fonctionnel, données PostgreSQL préservées, logs de déploiement lisibles, capacité à expliquer la stratégie de rollback.

## Différence clé avec le Projet 3

Le Projet 3 sécurisait le code **avant** intégration (CI : lint, test, build, Gitleaks, Sonar). Le Projet 4 s'occupe de tout ce qui vient **après** : construire l'artefact, le distribuer, le déployer, et se protéger si le déploiement tourne mal. C'est le passage de l'intégration continue (CI) à la livraison/déploiement continu (CD).
