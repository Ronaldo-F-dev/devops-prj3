# Stratégie de tagging des images Docker

## Deux tags, deux usages différents

Chaque image construite par la CI reçoit un tag basé sur le commit, systématiquement. Un second tag, basé sur la version, est ajouté **seulement** quand le commit correspond à un tag Git.

| Tag | Format | Quand | Usage |
|---|---|---|---|
| Commit | `commit-<sha court>` | À chaque push (branche ou PR) | Traçabilité totale : chaque run de CI produit une image identifiable, utile pour tester une branche précise ou déboguer |
| Version | `vX.Y.Z` | Seulement quand un tag Git `vX.Y.Z` existe sur ce commit | Référence stable pour un déploiement en production — une version, un sens, pas d'ambiguïté |

Exemple réel produit par ce projet :

```
ghcr.io/ronaldo-f-dev/kps-tasks-api:commit-618a039
```

## Pourquoi pas `latest`

Le brief l'interdit comme référence principale de production, et c'est volontaire : `latest` ne dit rien sur la version réellement déployée — c'est juste "la dernière poussée à un moment donné", qui change de sens à chaque nouveau push. Si un déploiement utilise `latest`, il est impossible de savoir avec certitude quelle version tourne réellement, ni de revenir en arrière de façon fiable. C'est directement contraire à un des objectifs du projet : pouvoir tracer et restaurer une version précise (rollback, Jour 4).

## Comment le tag est calculé dans la CI

Extrait de `.github/workflows/ci.yml` (job `docker_build`) :

```yaml
- name: Compute image tags
  id: tags
  run: |
    IMAGE="ghcr.io/${{ github.repository_owner }}/kps-tasks-api"
    IMAGE=$(echo "$IMAGE" | tr '[:upper:]' '[:lower:]')
    COMMIT_TAG="$IMAGE:commit-${GITHUB_SHA::7}"
    echo "commit_tag=$COMMIT_TAG" >> "$GITHUB_OUTPUT"
    if [ "${GITHUB_REF_TYPE}" = "tag" ]; then
      echo "version_tag=$IMAGE:${GITHUB_REF_NAME}" >> "$GITHUB_OUTPUT"
    else
      echo "version_tag=" >> "$GITHUB_OUTPUT"
    fi
```

- `GITHUB_SHA::7` : les 7 premiers caractères du SHA du commit (assez pour être unique en pratique, plus lisible qu'un SHA complet).
- `GITHUB_REF_TYPE` / `GITHUB_REF_NAME` : GitHub Actions les renseigne automatiquement — quand le workflow est déclenché par un tag Git (`v*`, ajouté aux déclencheurs `on: push: tags:`), `GITHUB_REF_TYPE` vaut `tag` et `GITHUB_REF_NAME` contient son nom exact (`v1.0.1`, par exemple).
- Le nom du propriétaire du dépôt (`github.repository_owner`) est mis en minuscules : GHCR exige des noms d'image en minuscules, alors qu'un compte GitHub peut contenir des majuscules (`Ronaldo-F-dev`).

## Ce que ça donne à l'usage

- Un push normal sur une branche → une seule image, taguée par son commit.
- Un `git tag v1.0.1 && git push origin v1.0.1` → le pipeline se redéclenche (le tag Git fait partie des déclencheurs), et l'image obtient **en plus** le tag `v1.0.1`, pointant vers exactement le même contenu que le tag commit correspondant.
- Le déploiement en production (Jour 3) utilisera toujours le tag de version, jamais le tag de commit ni `latest`.
