# Rapport d'incidents — Projet 5

Trois incidents réels rencontrés en construisant ce déploiement Kubernetes, documentés avec la même méthode qu'au Projet 4 (contexte / symptôme / diagnostic / correctif / prévention). Aucun n'était anticipé — chacun a été découvert en exécutant réellement les manifestes.

---

## Incident 1 — `kubectl` de k3s ignore `~/.kube/config`

**Contexte** : première configuration de `kubectl` pour l'utilisateur `ronaldo`, juste après l'installation de k3s (Jour 1).

**Symptôme** : après avoir copié `/etc/rancher/k3s/k3s.yaml` vers `~/.kube/config` avec les bonnes permissions, `kubectl get nodes` échoue quand même avec `permission denied` sur `/etc/rancher/k3s/k3s.yaml` — le fichier que `kubectl` tentait de lire n'était pas celui qui venait d'être copié.

**Diagnostic** : le `kubectl` fourni par k3s est en réalité un lien symbolique vers le binaire `k3s` lui-même, qui a un chemin de configuration par défaut différent d'un `kubectl` autonome classique (`/etc/rancher/k3s/k3s.yaml` plutôt que `~/.kube/config`).

**Correctif** : export explicite de la variable `KUBECONFIG` vers le fichier copié, ajouté au `.bashrc` de l'utilisateur.

**Prévention** : sur un cluster k3s, toujours vérifier `echo $KUBECONFIG` avant de supposer qu'un problème d'accès `kubectl` est un problème de permissions de fichier.

Détail complet : `docs/prj5/k3s-installation.md`.

---

## Incident 2 — Un Deployment silencieusement ignoré à l'application

**Contexte** : première application des manifestes de l'application (Jour 2), deux fichiers appliqués en une seule commande.

**Symptôme** : `cat app-deployment.yaml app-service.yaml | kubectl apply -f -` ne crée que le Service — aucune erreur affichée, mais le Deployment n'existe pas.

**Diagnostic** : concaténer deux fichiers YAML avec `cat` sans séparateur `---` entre eux ne produit pas un flux multi-documents valide ; `kubectl` n'a traité que le dernier bloc reconnu.

**Correctif** : appliquer chaque fichier séparément (ou utiliser `kubectl apply -f k8s/`, qui traite chaque fichier d'un dossier indépendamment).

**Prévention** : ne jamais supposer qu'une application de manifestes a réussi sans vérifier ensuite avec `kubectl get` — l'absence d'erreur n'est pas une preuve de succès.

Détail complet : `docs/prj5/kubernetes-app-deployment.md`.

---

## Incident 3 — Connexion à PostgreSQL réussie, mais aucune table

**Contexte** : premier branchement de l'application sur PostgreSQL déployé dans Kubernetes (Jour 3), juste après la création des Secrets et du Service.

**Symptôme** : `/health` passe à `ok` (la connexion réseau à PostgreSQL fonctionne), mais `POST /tasks` et `GET /tasks` renvoient une erreur 500.

**Diagnostic** : l'image Docker, seule, ne lance que `uvicorn` (voir le `CMD` du `Dockerfile`) — c'est `docker-compose.yml` (Projet 4) qui ajoutait `python -m app.init_db` avant, pour créer les tables. Ce comportement n'existe pas dans l'image elle-même, seulement dans la commande Docker Compose, qui n'a pas d'équivalent automatique en Kubernetes.

**Correctif** : ajout d'un `initContainer` dédié, exécutant `python -m app.init_db` avant que le conteneur principal ne démarre.

**Prévention** : quand une commande de démarrage personnalisée (`command:` dans `docker-compose.yml`) fait plus que ce que prévoit le `CMD` de l'image, vérifier explicitement si ce comportement supplémentaire doit être reproduit ailleurs avant de migrer vers un nouvel environnement d'exécution.

Détail complet : `docs/prj5/configmap-secret-postgres.md`.

---

## Ce que ces incidents ont en commun

Les trois sont des différences de comportement entre deux outils qui semblent équivalents en surface (`kubectl` k3s vs autonome, `cat` de fichiers vs flux multi-documents, image Docker vs orchestration Docker Compose) — aucun n'était documenté à l'avance, chacun n'est apparu qu'à l'exécution réelle.
