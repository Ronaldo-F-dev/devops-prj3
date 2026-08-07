# Guide de présentation — quoi montrer, jour par jour

Ce document sert de script pour la démo complète (Jour 5, Phase 1) et la mini-soutenance (Phase 4) : pour chaque jour, ce qui a été fait, où le retrouver, et exactement quoi montrer en direct.

---

## Jour 1 — Registre, variables CI/CD, préparation du VPS

**Ce qui a été fait** : choix de GitHub Container Registry, permissions du token CI configurées, package privé, authentification testée dans les deux sens (push et pull), utilisateur de déploiement (`ronaldo`, réutilisé, ajouté au groupe `docker`), répertoire `/opt/kps-tasks-api` préparé, découverte et anticipation de la migration depuis l'ancien déploiement manuel.

**Doc de référence** : `docs/prj4/cicd-architecture.md`, `docs/prj4/ci-cd-variables.md`

**Quoi montrer en direct** :
1. La page du package GHCR (connecté à GitHub) : https://github.com/users/Ronaldo-F-dev/packages/container/package/kps-tasks-api — montrer qu'il est privé, et l'onglet "Manage Actions access"
2. *Settings → Secrets and variables → Actions* du dépôt : la liste des noms de secrets (`REGISTRY_URL`, `REGISTRY_USER`, `REGISTRY_PASSWORD`, `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_PRIVATE_KEY`, `SONAR_TOKEN`) — les valeurs ne s'affichent jamais, c'est le point à souligner
3. Connexion SSH en direct : `ssh ronaldo@<VPS> "id"` → montrer l'utilisateur non-root, membre du groupe `docker`
4. `ls -la /opt/kps-tasks-api` sur le VPS

---

## Jour 2 — Build et push d'une image versionnée

**Ce qui a été fait** : job `docker_build` dans la CI (tag commit SHA + tag de version si un tag Git existe), push vers GHCR, vérification automatique de présence dans le registre, test volontaire d'un build en échec puis correction.

**Doc de référence** : `docs/prj4/image-versioning.md`

**Quoi montrer en direct** :
1. `.github/workflows/ci.yml`, job `docker_build` — expliquer le calcul des tags (`Compute image tags`)
2. Un run vert dans l'onglet **Actions** de GitHub, job "Build and push Docker image" ouvert — montrer les étapes login/push/vérification
3. Le contraste entre `evidence/image-build-failed.txt` (l'erreur `COPY` volontaire, message clair) et `evidence/image-build.txt` (le même job, corrigé, vert)
4. Sur la page du package GHCR : les différents tags `commit-<sha>` accumulés au fil des pushs

---

## Jour 3 — Déploiement automatisé sur le VPS

**Ce qui a été fait** : `docker-compose.prod.yml` (consomme l'image du registre, volume PostgreSQL externe), `scripts/deploy.sh`, job `deploy` (SSH, copie, exécution), environnement GitHub `production` avec approbation manuelle, **migration réelle** de l'ancien déploiement manuel du Projet 2 sans perte de données.

**Doc de référence** : `docs/prj4/deployment-process.md`

**Quoi montrer en direct** — celle-ci est la plus parlante :
1. `docker-compose.prod.yml` : pointer la ligne `image: ${IMAGE_TAG}` (pas de `build:`) et `external: true` sur le volume — expliquer pourquoi
2. Onglet **Actions** → un run → job "Deploy to VPS" en attente ("waiting") → **Review deployments** → montrer l'approbation manuelle en direct
3. Une fois déployé :
   ```bash
   curl http://<VPS>:8000/health
   curl http://<VPS>:8000/version
   curl http://<VPS>:8000/tasks
   ```
   Le dernier appel est le plus important : il montre la tâche `"Post 1"` créée pendant le **Projet 2**, toujours là après la bascule complète vers le pipeline automatisé — preuve concrète qu'aucune donnée n'a été perdue.
4. `evidence/deploy-verification.txt` si on préfère montrer une trace déjà capturée plutôt que de tout relancer en direct

---

## Jour 4 — Healthcheck et rollback automatique

**Ce qui a été fait** : `scripts/healthcheck.sh`, `scripts/rollback.sh`, intégration dans `deploy.sh`, test réel avec une version volontairement cassée, **un vrai bug découvert et corrigé** pendant le test (le rollback repullait la mauvaise image), second test réussi.

**Doc de référence** : `docs/prj4/rollback-strategy.md` (contient aussi les réponses aux questions 57-62)

**Quoi montrer en direct** — c'est le moment le plus fort de la soutenance, à raconter comme une histoire en 2 temps :

*Temps 1 — l'échec du rollback (le plus intéressant pédagogiquement)* :
- `evidence/deploy-failed.txt` : montrer les 10 tentatives de healthcheck échouées, puis le rollback qui se déclenche... et échoue aussi
- Expliquer la cause : une variable d'environnement héritée qui prenait le pas sur le fichier `.env`
- Montrer le diff du correctif : `git log -p --follow scripts/rollback.sh` ou directement le commit `fix: export IMAGE_TAG in rollback.sh...`

*Temps 2 — le rollback qui fonctionne* :
- `evidence/rollback-success.txt` : mêmes 10 tentatives échouées (volontaire), puis rollback réussi vers la bonne version, `current-version.txt` mis à jour, **et le job marqué en échec malgré tout**
- Expliquer pourquoi ce dernier point est volontaire (question 60)

**Option pour une démo 100% en direct pendant la soutenance** (au lieu de montrer des logs déjà capturés) : re-casser `/health` sur une branche de test, pousser, et regarder le rollback se dérouler en temps réel devant le formateur — reproductible à volonté puisque le mécanisme est maintenant fiable.

---

## Checklist rapide avant de présenter

- [ ] Pipeline actuel vert sur `main` (`gh run list --branch main --limit 1` ou onglet Actions)
- [ ] Application actuellement saine : `curl http://<VPS>:8000/health`
- [ ] `git log --oneline` propre, pas de commit de test oublié en cours
- [ ] Tous les fichiers `docs/prj4/*.md` à jour et liés depuis le `README.md`
