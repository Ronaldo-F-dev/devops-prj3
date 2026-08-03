# La chaîne CI — vue d'ensemble

Ce document décrit le fonctionnement complet de `.github/workflows/ci.yml` : ce que fait chaque job, comment lire ses logs, et comment diagnostiquer un échec.

## Déclenchement

```yaml
on:
  push:
    branches: [main, feature/**]
  pull_request:
    branches: [main]
```

Chaque push sur `main` ou une branche `feature/*`, et chaque Pull Request vers `main`, déclenche un run complet. C'est ce qui garantit qu'aucun code n'entre dans `main` sans être passé par tous les jobs.

## Les jobs, dans l'ordre d'exécution

```
lint ──▶ test ──▶ build (Docker)
              └──▶ sonar (SonarCloud)
secret_scan (Gitleaks)   ← indépendant, tourne en parallèle
```

| Job | Dépend de | Rôle |
|---|---|---|
| `lint` | — | `ruff check app --fix` : style et erreurs statiques Python |
| `test` | `lint` | `pytest` : tests unitaires de l'API |
| `build` | `test` | Construit l'image Docker (`docker build`) — voir [docker-build-local-vs-ci.md](docker-build-local-vs-ci.md) pour les pièges spécifiques à la CI |
| `secret_scan` | — (parallèle) | Gitleaks scanne l'historique des commits du push/PR à la recherche de secrets — voir [security-and-quality.md](security-and-quality.md) |
| `sonar` | `test` | Génère un rapport de couverture (`pytest --cov`) puis lance l'analyse SonarCloud — voir [security-and-quality.md](security-and-quality.md) |

`lint` et `test` sont enchaînés (`needs:`) parce qu'il est inutile de lancer les tests sur du code qui ne passe même pas le lint. `build` et `sonar` dépendent seulement de `test` : ils peuvent tourner en parallèle l'un de l'autre une fois les tests validés. `secret_scan` est totalement indépendant : il doit détecter un secret même si le reste du pipeline échoue.

## Variables et secrets utilisés

| Nom | Type | Origine | Usage |
|---|---|---|---|
| `GITHUB_TOKEN` | Secret automatique | Fourni par GitHub Actions à chaque run | Utilisé par Gitleaks pour commenter la PR en cas de détection |
| `SONAR_TOKEN` | Secret du dépôt | Généré sur SonarCloud (My Account → Security), ajouté dans *Settings → Secrets and variables → Actions* | Authentifie l'analyse SonarCloud |
| `SONAR_HOST_URL` | Valeur fixe dans le workflow | `https://sonarcloud.io` | Indique au scanner qu'il s'agit de SonarCloud (et non une instance SonarQube auto-hébergée) |

Aucun de ces secrets n'apparaît jamais en clair dans les logs (GitHub masque automatiquement la valeur des secrets déclarés, y compris dans les sorties de commande).

## Lire les logs d'un run

```bash
gh run list --branch <branche>              # liste les runs récents
gh run view <run-id>                         # résumé jobs/succès-échec
gh run view <run-id> --log --job <job-id>    # log complet d'un job précis
```

Chaque ligne de log est préfixée par le nom du step qui l'a produite. En cas d'échec, GitHub place un repère `##[error]` juste avant la ligne fautive — c'est le point de départ le plus rapide pour diagnostiquer.

## Diagnostiquer un pipeline en échec — méthode

1. **Identifier le job qui a échoué**, pas juste "la CI a échoué" — `lint`, `test`, `build`, `secret_scan` et `sonar` échouent chacun pour des raisons complètement différentes.
2. **Lire le dernier `##[error]`** dans le log du job, pas le début : la cause réelle est presque toujours juste avant l'arrêt du job.
3. **Reproduire en local si possible** — mais attention, un build ou un test peut passer en local et échouer en CI à cause d'une différence d'environnement (voir [docker-build-local-vs-ci.md](docker-build-local-vs-ci.md)).
4. **Cas particulier de `secret_scan`** : un échec ne signifie pas toujours "le code est cassé" — ça peut vouloir dire "un secret a été détecté", ce qui est le comportement voulu du job. Voir [security-and-quality.md](security-and-quality.md) pour un cas réel traité dans ce projet.

Exemple concret déjà rencontré et documenté dans ce dépôt : une erreur de chemin dans un `COPY` du `Dockerfile`, introduite volontairement pour tester la CI, a fait échouer le job `build` — diagnostic et correctif détaillés dans [docker-build-local-vs-ci.md](docker-build-local-vs-ci.md).

## Liens

- Versioning et tags : [versioning.md](versioning.md)
- Changelog : [../CHANGELOG.md](../CHANGELOG.md)
- Sécurité et qualité (Gitleaks, SonarCloud) : [security-and-quality.md](security-and-quality.md)
- Preuves : `evidence/pipeline-green.txt`, `evidence/docker-build-ci.txt`, `evidence/sonar-report.txt`, `evidence/gitleaks-detection.txt`
