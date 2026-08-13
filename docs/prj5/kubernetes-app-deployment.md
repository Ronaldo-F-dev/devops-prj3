# Déploiement Kubernetes de l'application — Jour 2

## Fichiers créés

- `k8s/app-deployment.yaml` — un `Deployment` pour l'application
- `k8s/app-service.yaml` — un `Service` pour y accéder de façon stable

## Le Deployment (tâches 13-16)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kps-tasks-api
  namespace: kps-tasks
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kps-tasks-api
  template:
    metadata:
      labels:
        app: kps-tasks-api
    spec:
      containers:
        - name: kps-tasks-api
          image: ghcr.io/ronaldo-f-dev/kps-tasks-api:commit-ed490e5
          ports:
            - containerPort: 8000
          env:
            - name: APP_NAME
              value: "KPS Tasks API"
            - name: APP_ENV
              value: "production"
            - name: APP_VERSION
              value: "1.0.0"
            - name: LOG_LEVEL
              value: "INFO"
```

- **Image** (tâche 14) : reprend le même tag que celui actuellement déployé en production via Docker Compose (`commit-ed490e5`, voir Projet 4), pour garder une continuité entre les deux déploiements pendant la migration.
- **Port** (tâche 15) : `containerPort: 8000`, le port sur lequel `uvicorn` écoute à l'intérieur du conteneur (défini dans le `Dockerfile`).
- **Variables d'environnement** (tâche 16) : uniquement les valeurs non sensibles pour l'instant. **`DATABASE_URL` a été volontairement omise** — la mettre en dur ici (même avec un mot de passe fictif) aurait été un secret en clair dans un manifeste versionné, ce qui est une contrainte non négociable du projet. Sans cette variable, l'application retombe sur sa valeur de repli interne (définie dans `app/config.py`), non sensible. La vraie connexion sera injectée proprement au Jour 3, via `ConfigMap` (hôte, port, nom de base) et `Secret` (utilisateur, mot de passe) séparés.

## Le Service (tâche 17)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kps-tasks-api
  namespace: kps-tasks
spec:
  selector:
    app: kps-tasks-api
  ports:
    - port: 8000
      targetPort: 8000
```

Un `Service` (type `ClusterIP` par défaut, pas encore accessible depuis l'extérieur du cluster — ça viendra au Jour 4) donne un point d'accès **stable** à l'application : son IP change à chaque redémarrage de pod, mais celle du Service ne bouge pas. Le `selector` (`app: kps-tasks-api`) doit correspondre exactement au label du `template` du Deployment — c'est ce qui relie les deux objets.

## Application des manifestes (tâche 18)

```bash
kubectl apply -f k8s/app-deployment.yaml
kubectl apply -f k8s/app-service.yaml
```

**Piège rencontré** : appliquer les deux fichiers en une seule commande via `cat app-deployment.yaml app-service.yaml | kubectl apply -f -` a silencieusement ignoré le Deployment — sans séparateur `---` entre deux documents YAML, la simple concaténation de fichiers ne produit pas un flux multi-documents valide. Il faut soit ajouter `---` entre les fichiers, soit les appliquer séparément (`kubectl apply -f k8s/`, qui traite tous les fichiers d'un dossier correctement).

## Vérification (tâches 19-20)

```bash
kubectl get pods -n kps-tasks -o wide
# kps-tasks-api-7c65679d5c-sdrhw   1/1   Running   0   33s

kubectl logs -n kps-tasks kps-tasks-api-7c65679d5c-sdrhw
# Uvicorn running on http://0.0.0.0:8000
```

Pod à l'état **Running**, logs lisibles, aucun crash au démarrage.

### Accessibilité depuis le cluster

```bash
curl http://<IP-du-pod>:8000/health
# {"status":"degraded","database":"error","version":"1.0.0","details":"OperationalError"}

curl http://<ClusterIP-du-service>:8000/version
# {"name":"KPS Tasks API","version":"1.0.0","environment":"production"}
```

`/health` renvoie `degraded` — **attendu et normal à ce stade** : PostgreSQL n'existe pas encore dans le cluster (arrive au Jour 3), donc l'application ne peut pas s'y connecter. `/version` fonctionne car il ne dépend pas de la base de données. Le test via le Service (`ClusterIP`) plutôt que directement via l'IP du pod confirme que le Service route bien le trafic vers le pod.

Preuves : `evidence/kubectl-get-pods-day2.txt`, `evidence/app-health.txt`.
