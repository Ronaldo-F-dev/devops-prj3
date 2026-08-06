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
