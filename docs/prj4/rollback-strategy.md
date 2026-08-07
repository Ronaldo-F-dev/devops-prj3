# Stratégie de rollback automatique

## Logique, résumée

```
Avant le déploiement :
  current-version.txt (s'il existe) → copié vers previous-version.txt

Pendant le déploiement :
  nouvelle image déployée (docker compose up -d)
  healthcheck.sh interroge /health, jusqu'à HEALTH_RETRIES fois, avec HEALTH_DELAY secondes entre chaque essai

Si le healthcheck réussit :
  current-version.txt ← nouvelle version
  le job se termine avec succès

Si le healthcheck échoue :
  rollback.sh est déclenché automatiquement :
    lit previous-version.txt
    redéploie cette image (login, pull, up -d)
    relance healthcheck.sh pour confirmer que l'ancienne version répond
    si oui : current-version.txt ← ancienne version
  dans tous les cas, le job de déploiement se termine en ÉCHEC
  (voir "Pourquoi le job doit échouer même si le rollback réussit" ci-dessous)
```

## Les trois scripts, et pourquoi ils sont séparés

- **`healthcheck.sh`** : une seule responsabilité — interroger `/health` avec des tentatives et un délai configurables, renvoyer 0 (succès) ou 1 (échec). Utilisé à deux endroits différents (`deploy.sh` et `rollback.sh`) : le séparer évite de dupliquer cette logique.
- **`rollback.sh`** : restaure `previous-version.txt`, et vérifie lui-même (via `healthcheck.sh`) que la restauration a réellement fonctionné — un rollback qui ne vérifie pas son propre résultat n'est qu'un espoir, pas une garantie.
- **`deploy.sh`** : orchestre les deux — décide QUAND appeler le healthcheck, et QUAND déclencher le rollback si besoin.

## Nombre de tentatives et délai (tâches 49-50)

Valeurs par défaut : **10 tentatives, 3 secondes d'intervalle** (30 secondes de marge au total), configurables via les variables d'environnement `HEALTH_RETRIES` et `HEALTH_DELAY` sans modifier le script. Choisies empiriquement : assez courtes pour ne pas bloquer le pipeline longtemps sur un vrai échec, assez longues pour laisser le temps normal de démarrage de l'application (migration de base, chargement de l'ASGI) de se dérouler sans fausse alerte.

## 57. Pourquoi lancer un healthcheck après le déploiement ?

Parce qu'un conteneur "démarré" (`docker compose up -d` qui réussit) n'est pas la même chose qu'une application "qui fonctionne". Le conteneur peut démarrer et planter juste après, ou démarrer mais ne jamais réussir à se connecter à la base de données, ou écouter sur le mauvais port. Le seul moyen fiable de savoir si le déploiement est réellement utilisable, c'est de l'interroger comme le ferait un vrai client — d'où `/health`.

## 58. Qu'est-ce qu'un rollback automatique ?

C'est un mécanisme qui détecte lui-même l'échec d'un déploiement et restaure la version précédente **sans intervention humaine**. La différence avec un rollback manuel n'est pas seulement la vitesse : c'est que le système ne dépend pas de quelqu'un qui doit remarquer le problème, se connecter, et taper les bonnes commandes sous pression — au moment même où les choses vont mal.

## 59. Différence entre un rollback applicatif et un rollback de base de données

Un **rollback applicatif** (celui de ce projet) remplace le code qui tourne par une version antérieure — c'est rapide et sans risque, parce que l'ancienne image existe déjà, prête à être relancée telle quelle.

Un **rollback de base de données** est structurellement différent et bien plus dangereux : les données changent avec le temps (nouvelles lignes, mises à jour), donc "revenir en arrière" signifie soit restaurer un backup (perte de toutes les écritures depuis ce backup), soit annuler des migrations de schéma (risqué si l'application actuelle dépend déjà du nouveau schéma). Ce projet ne fait **jamais** de rollback de base de données automatique — volontairement : `docker-compose.prod.yml` ne touche jamais au volume PostgreSQL pendant un déploiement ou un rollback (voir `docs/prj4/deployment-process.md`, question 45).

## 60. Pourquoi le job doit échouer même si le rollback réussit

Parce qu'un rollback réussi ramène le système à un état **stable**, pas à l'état **voulu**. Le déploiement de la nouvelle version a échoué — c'est un fait qui doit rester visible (pipeline rouge, alerte), sinon personne ne sait qu'il faut corriger le problème avant de retenter. Si le job se terminait en vert simplement parce que "le serveur répond à nouveau", l'échec du déploiement passerait inaperçu et se reproduirait au prochain push.

## 61. Que se passe-t-il si le rollback échoue aussi ?

`rollback.sh` le détecte lui-même (son propre appel à `healthcheck.sh` échoue après restauration) et se termine en erreur. `deploy.sh` distingue explicitement les deux cas dans ses logs : *"Rollback executed successfully"* contre *"Rollback ALSO FAILED — manual intervention required"*. Dans ce second cas, le système est dans un état incertain que le script ne peut plus corriger seul — c'est le signal qu'une intervention humaine immédiate est nécessaire, pas un cas que l'automatisation doit essayer de résoudre indéfiniment.

## 62. Limites de cette stratégie

- **Un seul niveau d'historique** : `previous-version.txt` ne garde qu'**une** version en arrière. Si deux déploiements défaillants se suivent, la seconde tentative de rollback écrase la référence vers la dernière version *vraiment* stable.
- **Le healthcheck ne couvre que `/health`** : une régression fonctionnelle qui ne casse pas cet endpoint précis (ex. un bug sur `/tasks` uniquement) ne sera pas détectée par ce mécanisme.
- **Pas de vérification applicative après rollback**, seulement le healthcheck : on sait que l'ancienne version répond, pas qu'elle répond *correctement* à tous les cas d'usage.
- **Aucune alerte externe** (Slack, e-mail...) : l'échec est visible dans les logs du job GitHub Actions, mais rien ne notifie activement une personne — il faut aller consulter le pipeline pour le voir.
- **Le rollback dépend du VPS lui-même** : si le VPS est injoignable ou à court de ressources, ni le déploiement ni le rollback ne peuvent s'exécuter — ce cas n'est pas couvert par ce mécanisme (voir le Jour 5, incident déclenché par le formateur).

## Preuve du mécanisme (tâches 54-56)

Test réalisé en conditions réelles, sur la vraie production, pas un environnement simulé.

1. **Version cassée déployée volontairement** : l'endpoint `/health` a été modifié pour renvoyer systématiquement `503`, peu importe l'état réel de la base (commit `test: break /health endpoint to trigger automatic rollback`). Les tests unitaires ne couvrent pas `/health`, donc `lint`/`test` passent normalement — seul un vrai déploiement peut révéler le problème, ce qui est exactement le point.
2. **Premier essai : le rollback automatique a lui-même échoué.** `deploy.sh` a bien détecté l'échec du healthcheck et appelé `rollback.sh`, mais celui-ci a redéployé... la version cassée elle-même, pas la précédente. Preuve dans `evidence/deploy-failed.txt`.
3. **Diagnostic** : `IMAGE_TAG` est transmis à `deploy.sh` comme variable d'environnement (depuis la commande SSH). Cette variable reste présente dans l'environnement du processus, et `rollback.sh` en hérite en tant que sous-processus. `rollback.sh` mettait bien à jour la **valeur dans le fichier** `.env`, mais `docker compose` donne toujours la priorité à une variable d'environnement déjà définie sur celle lue via `--env-file` — donc le `.env` corrigé était silencieusement ignoré, et l'ancienne valeur (la version cassée) restait utilisée.
4. **Correctif** : `rollback.sh` réassigne et exporte explicitement `IMAGE_TAG` avec la version précédente avant d'appeler `docker compose`, pour qu'il n'y ait plus de désaccord possible entre le fichier et l'environnement du process.
5. **Second essai, après correctif : succès complet.** Healthcheck échoué (10/10, comme prévu), rollback déclenché, cette fois vers la bonne image, vérifié par un nouveau healthcheck (réussi à la 3ᵉ tentative), `current-version.txt` mis à jour, et **le job s'est terminé en échec** malgré le rollback réussi — exactement le comportement voulu (question 60). Log complet : `evidence/rollback-success.txt`.
6. **Vérification finale** : `/health`, `/version` et `/tasks` interrogés directement sur le VPS après rollback — application saine, données intactes.

Ce n'est pas juste une preuve que "le rollback marche" : c'est la preuve qu'un premier essai a **révélé un vrai bug** (une hypothèse implicite fausse sur la priorité `docker compose` entre variables d'environnement et `--env-file`), que ce bug a été diagnostiqué à partir des logs réels, corrigé, puis re-testé avec succès — exactement le genre de cycle qu'un incident de production impose.
