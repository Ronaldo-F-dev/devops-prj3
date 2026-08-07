# Rapport d'incidents — Projet 4

Quatre incidents réels rencontrés pendant la construction de ce pipeline, documentés avec la méthode contexte / symptôme / diagnostic / correctif / prévention. Aucun n'est un exercice simulé — chacun a été trouvé en testant réellement le système.

---

## Incident 1 — Push GHCR refusé (`permission_denied: write_package`)

**Contexte** : premier test du job `docker_build` sur GitHub Actions, juste après avoir validé l'authentification manuellement (Jour 1).

**Symptôme** : le `docker push` échoue avec `denied: permission_denied: write_package`, alors que `docker login` avait réussi juste avant, avec le même token, à la même minute.

**Diagnostic** : le package `kps-tasks-api` avait été créé **manuellement** (via un Personal Access Token, pendant le test d'authentification), donc rattaché au compte utilisateur mais à **aucun dépôt**. Le `GITHUB_TOKEN` généré par un run GitHub Actions n'a de droits d'écriture que sur les packages explicitement liés au dépôt qui l'exécute — un package créé "à la main" n'est lié à rien.

**Correctif** : suppression du package de test, laissant la CI le recréer elle-même au premier push réel — un package créé directement par le workflow d'un dépôt est automatiquement lié à ce dépôt.

**Prévention** : ne jamais créer manuellement une ressource que la CI est censée créer elle-même ; si un test manuel est nécessaire, le traiter explicitement comme jetable.

Détail complet : `docs/prj4/cicd-architecture.md`.

---

## Incident 2 — Le rollback automatique a restauré la mauvaise image

**Contexte** : premier test réel d'une version cassée (Jour 4), pour valider le mécanisme de rollback.

**Symptôme** : `deploy.sh` détecte correctement l'échec du healthcheck (10/10 tentatives) et déclenche `rollback.sh`. Les logs de `rollback.sh` annoncent "Rolling back to commit-f83cfa4" (la bonne version), mais l'étape suivante (`docker compose pull`) télécharge en réalité `commit-43783ad` — la version **cassée**, censée être remplacée. Le rollback échoue aussi : le service reste en panne.

**Diagnostic** : `IMAGE_TAG` est transmis à `deploy.sh` comme variable d'environnement du shell (préfixe de la commande SSH). `rollback.sh`, appelé en sous-processus, hérite de cette variable. `rollback.sh` modifiait bien la valeur dans le **fichier** `.env`, mais `docker compose` donne la priorité à une variable d'environnement déjà présente sur celle lue via `--env-file` — la correction dans le fichier était donc silencieusement ignorée.

**Correctif** : `rollback.sh` réassigne et exporte explicitement `IMAGE_TAG` avec la version précédente avant d'appeler `docker compose`, supprimant toute possibilité de désaccord entre le fichier et l'environnement du process.

**Intervention manuelle nécessaire** : le temps du diagnostic, le service était réellement en panne (healthcheck en échec côté production). Restauration manuelle immédiate via SSH (`docker compose pull` + `up -d` avec `IMAGE_TAG` explicitement dépourvu de la variable d'environnement parasite), avant même de corriger le script.

**Prévention** : ce type de conflit (variable d'environnement vs fichier de configuration) est une classe d'erreur générale avec `docker compose` — à vérifier systématiquement dès qu'un script modifie un `.env` puis appelle `docker compose` dans le même processus ou un processus enfant.

Détail complet et logs : `docs/prj4/rollback-strategy.md`, `evidence/deploy-failed.txt`, `evidence/rollback-success.txt`.

---

## Incident 3 — Approbation manuelle contournée sur le premier déploiement

**Contexte** : premier test du job `deploy` après configuration de l'environnement GitHub `production` avec approbation obligatoire (Jour 3).

**Symptôme** : le déploiement s'exécute immédiatement, sans passer par l'état "waiting" attendu — comme si la règle d'approbation n'existait pas.

**Diagnostic** : GitHub autorise les **administrateurs du dépôt** à contourner une règle de protection d'environnement (`can_admins_bypass: true`), et le compte utilisé pour ce projet est justement propriétaire du dépôt. Ce n'était pas un défaut de configuration — la règle a été vérifiée à nouveau sur le déploiement suivant, et a correctement bloqué en attente d'approbation.

**Correctif** : aucun — comportement de plateforme attendu. Documenté pour ne pas être surpris pendant une démonstration.

**Prévention** : sur un vrai projet d'équipe (pas solo), un collaborateur non-administrateur reste soumis à la règle sans exception — le risque de contournement silencieux ne concerne que les comptes admin/propriétaire, ce qui est un cas connu et acceptable pour ce contexte d'apprentissage individuel.

Détail complet : `docs/prj4/deployment-process.md`.

---

## Incident 4 — Deux déploiements approuvés en même temps, le plus ancien écrase le plus récent

**Contexte** : démo complète du Jour 5 (Phase 1). Deux commits poussés à quelques minutes d'intervalle, chacun ayant généré son propre run et sa propre demande d'approbation de déploiement.

**Symptôme** : les deux approbations ont été données. Le déploiement du commit le plus **récent** a réussi en premier (logique), mais celui du commit **plus ancien**, resté en attente, s'est exécuté juste après et a redéployé une version antérieure — sans erreur ni alerte, juste un `current-version.txt` revenu en arrière silencieusement.

**Diagnostic** : le job `deploy` n'avait aucune protection de concurrence. Rien n'empêchait deux runs différents de déployer en parallèle ou dans le désordre — chacun ignore totalement l'existence de l'autre, et le dernier à s'exécuter gagne, indépendamment de l'ordre des commits.

**Correctif** : ajout d'un groupe de concurrence sur le job `deploy` (`concurrency: group: production-deploy, cancel-in-progress: true`). Désormais, si un déploiement plus récent est créé pendant qu'un autre est en cours ou en attente d'approbation pour le même environnement, l'ancien est automatiquement annulé plutôt que de s'exécuter plus tard.

**Prévention** : toute ressource partagée et mutable (ici, l'état déployé sur un VPS) déclenchée par des événements asynchrones (des approbations humaines, qui n'arrivent pas forcément dans l'ordre) a besoin d'une garantie d'ordonnancement explicite — ne jamais supposer que "les jobs CI s'exécutent dans l'ordre des commits" sans le forcer.

## Ce que ces incidents ont en commun

Aucun n'a été anticipé à l'avance — les quatre ont été découverts en **exécutant réellement** le pipeline, pas en le relisant. C'est exactement l'argument central du Jour 4 : un système qui n'a jamais échoué en conditions réelles n'a pas prouvé qu'il fonctionne, il a juste eu de la chance de ne pas encore avoir été testé sérieusement.
