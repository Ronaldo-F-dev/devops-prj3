# Convention de commits

Le projet suit une variante simplifiée de [Conventional Commits](https://www.conventionalcommits.org/) : `<type>: <description au présent, courte>`.

## Types utilisés dans ce projet

| Type | Usage | Exemple réel |
|---|---|---|
| `feat` | Nouvelle fonctionnalité applicative | `feat: Initial commit` |
| `fix` | Correction d'un bug ou d'un défaut | `fix: extract duplicated 'Task not found' literal into a constant` |
| `ci` | Ajout/modification de la configuration CI | `ci: add Gitleaks secret_scan job` |
| `test` | Ajout/modification de tests | `test: add root endpoint test` |
| `docs` | Documentation uniquement | `docs: document Gitleaks and SonarCloud setup` |
| `style` | Formatage, sans changement de comportement | `style: format imports with ruff` |
| `chore` | Tâche de maintenance sans impact fonctionnel | `chore: remove stray empty files accidentally committed by a ruff invocation` |
| `security` | Correction liée à la sécurité, hors périmètre `fix` classique | `security: remove leaked credential and IP from .gitignore` |
| `build(deps)` | Mise à jour de dépendance (généré par Dependabot) | `build(deps): bump SonarSource/sonarqube-scan-action` |

## Règles

- Un commit = un changement logique cohérent (éviter de mélanger un `fix` et un `docs` dans le même commit).
- Description au présent, à l'infinitif implicite ("add", pas "added" ni "adding").
- Le corps du commit (optionnel, après une ligne vide) explique le *pourquoi* si ce n'est pas évident — pas un résumé de ce que le diff montre déjà.

## Pourquoi

- Historique lisible : `git log --oneline` donne une vue claire du type de chaque changement sans ouvrir le diff.
- Facilite la rédaction du `CHANGELOG.md` : les sections "Principaux changements" / "Amélioration CI" / "Contrôles qualité" de ce projet ont été construites directement à partir des types `feat`/`fix`/`ci`/`docs` de l'historique.
