# Stratégie de versioning

## Schéma

Le projet suit [SemVer](https://semver.org/) : `MAJOR.MINOR.PATCH`.

- **MAJOR** : rupture de compatibilité (ex. changement de contrat d'API, migration de base de données non rétrocompatible)
- **MINOR** : nouvelle fonctionnalité rétrocompatible (ex. nouvel endpoint)
- **PATCH** : correctif rétrocompatible (ex. bug fix, dépendance mise à jour)

## Ce qui est versionné

Deux choses distinctes, gardées volontairement synchronisées :

1. **Le tag Git** (`vX.Y.Z`), posé sur `main` une fois un état stable atteint et mergé.
2. **`APP_VERSION`** (variable d'environnement, `.env.example` → visible sur `GET /version`), qui reflète la même version côté application.

## Quand tagger

Un tag est créé uniquement sur `main`, jamais sur une branche de travail, et seulement après un merge dont le pipeline complet (lint, test, build, Gitleaks, Sonar) est vert.

```bash
git checkout main
git pull
git tag -a vX.Y.Z -m "Message court décrivant la version"
git push origin vX.Y.Z
```

## Première version

`v1.0.0` : première version stable du projet, marquant la fin du Jour 5 (CI complète : lint, test, build Docker, Gitleaks, SonarCloud, toutes intégrées et documentées). Voir `CHANGELOG.md` pour le détail des changements inclus.
