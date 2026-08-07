# Questions intermédiaires — Projet 4

Ce document regroupe, jour par jour, les réponses aux "questions intermédiaires" du brief. Il se remplit au fur et à mesure de l'avancement.

## Jour 2 — Build et push d'une image versionnée

### 21. Pourquoi tagger une image Docker ?

Sans tag explicite, Docker utilise `latest` par défaut — un nom qui ne dit rien sur le contenu réel de l'image. Tagger permet d'identifier précisément *quel* code tourne dans *quelle* image : indispensable pour déployer une version précise, revenir en arrière (rollback) sur une version connue, ou déboguer un problème en sachant exactement ce qui a été construit et quand.

### 22. Pourquoi éviter `latest` en production ?

Parce que `latest` change de sens à chaque nouveau push : ce n'est pas une version, c'est juste "la dernière image poussée à un instant donné". Un déploiement basé sur `latest` ne peut pas garantir de façon fiable quelle version tourne réellement, et un rollback vers "l'image d'avant" devient impossible à cibler précisément puisqu'il n'y a pas de référence stable à restaurer.

### 23. Quelle est la différence entre un tag Git et un tag Docker ?

- Un **tag Git** (`v1.0.0`) marque un point précis dans l'historique du **code source**.
- Un **tag Docker** (`commit-618a039`, `v1.0.0`) identifie une **image construite**, c'est-à-dire un artefact binaire (le code + ses dépendances + son environnement d'exécution, déjà assemblés).

Le lien entre les deux se fait par convention dans ce projet : quand un tag Git `vX.Y.Z` existe, l'image Docker correspondante reçoit le même nom comme tag. Mais rien n'oblige les deux à être synchronisés — on peut très bien construire une image sans qu'aucun tag Git n'existe (c'est le cas à chaque push normal, d'où le tag `commit-<sha>`).

### 24. Pourquoi construire l'image en CI plutôt que sur le serveur ?

- **Reproductibilité** : la CI construit toujours dans un environnement propre et identique (voir `docs/prj3/docker-build-local-vs-ci.md`) — pas de dépendance à l'état particulier d'un serveur.
- **Séparation des responsabilités** : le serveur de production sert à *faire tourner* l'application, pas à la *compiler*. Lui donner des outils de build (compilateurs, dépendances de développement) élargit inutilement sa surface d'attaque.
- **Traçabilité** : chaque build en CI est lié à un commit précis et laisse des logs consultables ; un build fait à la main sur un serveur ne laisse aucune trace fiable.
- **Rapidité de déploiement** : le serveur n'a plus qu'à faire un `docker pull` d'une image déjà prête, au lieu d'attendre une compilation complète à chaque déploiement.

### 25. Comment vérifie-t-on qu'une image est bien dans le registre ?

Dans ce projet, la CI le vérifie elle-même juste après le push, avec `docker manifest inspect <tag>` : cette commande interroge le registre et échoue si l'image n'y est pas — donc si le job passe, l'image est confirmée présente (voir l'étape "Verify image is available in the registry" du job `docker_build`). On peut aussi le vérifier manuellement : soit avec `docker pull <tag>` depuis n'importe quelle machine authentifiée, soit visuellement sur la page du package GitHub (`docs/prj4/cicd-architecture.md`, section "Où voir l'image concrètement").

## Jour 3 — Déploiement automatisé sur le VPS

Réponses détaillées dans `docs/prj4/deployment-process.md`. Résumé :

### 42. Pourquoi séparer `docker-compose.yml` et `docker-compose.prod.yml` ?

Le premier **construit** l'image (`build:`), pour développer/itérer. Le second **consomme** une image déjà construite et validée par la CI (`image: ${IMAGE_TAG}`) — la production ne recompile jamais, elle déploie exactement ce qui a été testé.

### 43. Pourquoi ne pas construire l'image directement sur le VPS ?

Mêmes raisons qu'à la question 24 : reproductibilité, séparation des responsabilités (servir ≠ compiler), traçabilité, rapidité d'un `pull` face à un `build` complet.

### 44. Pourquoi garder un fichier `current-version.txt` ?

Pour toujours savoir, de façon fiable et sans ambiguïté, quelle version tourne actuellement — et pouvoir y revenir. C'est la base du rollback automatique (Jour 4) : sans cette trace, aucun script ne peut savoir vers quoi revenir en cas d'échec.

### 45. Comment s'assurer que les données PostgreSQL ne sont pas supprimées ?

Deux garanties : `deploy.sh` n'utilise jamais `docker compose down` (seulement `up -d`, qui ne touche pas aux volumes), et le volume est déclaré `external: true` dans `docker-compose.prod.yml` — un volume externe n'est jamais créé ni supprimé par Compose, il doit préexister. Testé en conditions réelles : migration de l'ancien déploiement manuel du Projet 2 vers le nouveau pipeline, données toujours présentes après coup (`evidence/deploy-verification.txt`).

### 46. Quelle est la différence entre déployer une image et déployer du code ?

Déployer du code couple l'exécution à l'environnement déjà présent sur la machine cible (risque de divergence). Déployer une image transporte un artefact complet et figé (code + dépendances + environnement d'exécution) — le serveur n'a besoin que de Docker pour l'exécuter, rien d'autre à installer.

## Jour 4 — Healthcheck et rollback automatique

Réponses détaillées, avec la preuve réelle (bug trouvé et corrigé en testant), dans `docs/prj4/rollback-strategy.md`. Résumé :

### 57. Pourquoi lancer un healthcheck après le déploiement ?

Parce qu'un conteneur démarré n'est pas la même chose qu'une application qui fonctionne. Seule une vraie requête vers `/health` confirme que l'application répond réellement.

### 58. Qu'est-ce qu'un rollback automatique ?

Un mécanisme qui détecte lui-même l'échec d'un déploiement et restaure la version précédente, sans intervention humaine.

### 59. Différence entre un rollback applicatif et un rollback de base de données ?

Un rollback applicatif remplace le code par une version antérieure (rapide, sans risque, l'ancienne image existe déjà). Un rollback de base de données doit gérer des données qui ont changé dans le temps (perte d'écritures récentes, risques de migration) — ce projet n'automatise jamais ce second type.

### 60. Pourquoi le job doit échouer même si le rollback réussit ?

Parce qu'un rollback réussi restaure un état stable, pas l'état voulu : le déploiement a échoué, et ça doit rester visible pour que quelqu'un corrige le problème avant le prochain push.

### 61. Que se passe-t-il si le rollback échoue aussi ?

Ça s'est produit réellement pendant ce projet (voir `docs/prj4/rollback-strategy.md`) : `rollback.sh` détecte l'échec via son propre healthcheck et se termine en erreur en réclamant une intervention manuelle — ce qui a effectivement été nécessaire pour restaurer le service, le temps de diagnostiquer et corriger le bug en cause.

### 62. Quelles limites vois-tu à cette stratégie ?

Un seul niveau d'historique (`previous-version.txt`), healthcheck limité à `/health` (ne couvre pas toutes les régressions possibles), aucune alerte active (juste des logs à consulter), et une dépendance totale à la disponibilité du VPS lui-même.
