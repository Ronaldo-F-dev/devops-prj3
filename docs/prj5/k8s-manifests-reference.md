# Référence des manifestes Kubernetes — explication ligne par ligne

Ce document couvre chaque fichier de `k8s/`, champ par champ. Objectif : pouvoir justifier n'importe quelle ligne d'un manifeste sans hésitation, condition explicite du brief ("documenter chaque objet Kubernetes", "savoir expliquer chaque commande kubectl utilisée").

---

## `namespace.yaml`

```yaml
apiVersion: v1        # groupe d'API "core", celui des objets Kubernetes de base
kind: Namespace        # type d'objet : un espace de noms
metadata:
  name: kps-tasks      # nom du namespace, référencé par tous les autres manifestes
```

Rôle : isoler tous les objets de l'application dans un espace nommé, séparé de `default` et des namespaces système (`kube-system`, etc.). Sans lui, chaque `kubectl apply` devrait préciser `-n kps-tasks` manuellement ou les objets finiraient dans `default`, mélangés à d'éventuels autres projets sur le même cluster.

---

## `app-configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap                      # stockage de configuration non sensible
metadata:
  name: kps-tasks-api-config         # nom utilisé en référence (configMapKeyRef) par le Deployment
  namespace: kps-tasks
data:
  APP_NAME: "KPS Tasks API"          # variables classiques de l'application (voir app/config.py)
  APP_ENV: "production"
  LOG_LEVEL: "INFO"
  POSTGRES_HOST: "postgres"          # nom du Service PostgreSQL, pas une IP (résolution DNS interne)
  POSTGRES_PORT: "5432"
  POSTGRES_DB: "kps_tasks_db"
```

`POSTGRES_HOST`/`POSTGRES_PORT`/`POSTGRES_DB` ne sont pas utilisées directement par l'application (qui utilise plutôt `DATABASE_URL`, dans le Secret), mais servent de référence documentée pour la configuration de PostgreSQL lui-même — `POSTGRES_DB` est repris par `postgres-deployment.yaml` via `configMapKeyRef`.

---

## `app-secret.example.yaml` (modèle, jamais appliqué tel quel)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: kps-tasks-api-secret
  namespace: kps-tasks
type: Opaque                         # type générique, données arbitraires clé/valeur
stringData:
  DATABASE_URL: "postgresql+psycopg://REPLACE_USER:REPLACE_PASSWORD@postgres:5432/kps_tasks_db"
```

`stringData` (plutôt que `data`) permet d'écrire la valeur en clair dans le YAML — Kubernetes se charge de l'encoder en base64 au moment de la création. Ce fichier n'est qu'un modèle : le vrai Secret a été créé directement sur le cluster via `kubectl create secret generic`, sans jamais écrire la vraie valeur dans un fichier versionné (voir `docs/prj5/configmap-secret-postgres.md`).

---

## `app-deployment.yaml`

```yaml
apiVersion: apps/v1                  # groupe d'API "apps", celui des objets de charge de travail
kind: Deployment
metadata:
  name: kps-tasks-api
  namespace: kps-tasks
  labels:
    app: kps-tasks-api                # label du Deployment lui-même (utile pour le retrouver avec kubectl get -l)
spec:
  replicas: 1                         # une seule instance du pod applicatif
  selector:
    matchLabels:
      app: kps-tasks-api               # le Deployment gère tout pod portant ce label -- doit correspondre au template ci-dessous
  template:
    metadata:
      labels:
        app: kps-tasks-api             # label effectivement posé sur les pods créés
    spec:
      initContainers:
        - name: init-db
          image: ghcr.io/ronaldo-f-dev/kps-tasks-api:commit-ed490e5
          command: ["python", "-m", "app.init_db"]   # crée les tables ; doit réussir avant que le conteneur principal démarre
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: kps-tasks-api-secret
                  key: DATABASE_URL
      containers:
        - name: kps-tasks-api
          image: ghcr.io/ronaldo-f-dev/kps-tasks-api:commit-ed490e5   # tag de commit précis, jamais "latest"
          ports:
            - containerPort: 8000     # port sur lequel uvicorn écoute à l'intérieur du conteneur
          env:
            - name: APP_NAME
              valueFrom:
                configMapKeyRef: {name: kps-tasks-api-config, key: APP_NAME}
            - name: APP_ENV
              valueFrom:
                configMapKeyRef: {name: kps-tasks-api-config, key: APP_ENV}
            - name: APP_VERSION
              value: "1.0.0"           # valeur fixe, pas dans le ConfigMap (constante de build, pas une config d'environnement)
            - name: LOG_LEVEL
              valueFrom:
                configMapKeyRef: {name: kps-tasks-api-config, key: LOG_LEVEL}
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef: {name: kps-tasks-api-secret, key: DATABASE_URL}
          readinessProbe:
            httpGet: {path: /health, port: 8000}   # vérifie la DB -- retire le pod du trafic si elle échoue
            initialDelaySeconds: 5     # attend 5s après le démarrage avant le premier appel
            periodSeconds: 10          # rappelle toutes les 10s
            failureThreshold: 3        # 3 échecs consécutifs avant de considérer le pod NOT READY
          livenessProbe:
            httpGet: {path: /, port: 8000}   # ne vérifie PAS la DB -- seulement "le processus répond"
            initialDelaySeconds: 10
            periodSeconds: 15
            failureThreshold: 3        # 3 échecs consécutifs avant redémarrage du conteneur
```

Points de conception à savoir justifier :
- **`initContainers` vs `containers`** : un `initContainer` s'exécute jusqu'à la fin (succès ou échec) *avant* que les conteneurs principaux ne démarrent. Ici, il garantit que le schéma de base existe avant que l'application ne commence à servir des requêtes.
- **Deux probes, deux endpoints différents** : décision volontaire, expliquée en détail dans `docs/prj5/probes-and-exposure.md` — éviter qu'une panne de PostgreSQL ne déclenche des redémarrages inutiles de l'application via la `livenessProbe`.
- **`APP_VERSION` en valeur fixe** : les autres variables viennent du ConfigMap parce qu'elles peuvent varier selon l'environnement de déploiement ; `APP_VERSION` est traitée comme une constante liée à l'image elle-même.

---

## `app-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kps-tasks-api                 # nom utilisé pour la résolution DNS interne
  namespace: kps-tasks
spec:
  type: NodePort                      # expose sur un port de chaque noeud, en plus du ClusterIP habituel
  selector:
    app: kps-tasks-api                 # doit correspondre exactement au label du template du Deployment
  ports:
    - port: 8000                       # port exposé côté Service (utilisé pour la communication interne au cluster)
      targetPort: 8000                 # port réel du conteneur (containerPort du Deployment)
      nodePort: 30080                  # port fixe ouvert sur le noeud, accessible depuis l'extérieur du VPS
```

Sans `type: NodePort` (valeur par défaut : `ClusterIP`), l'application ne serait joignable que depuis l'intérieur du cluster — exactement le choix fait pour PostgreSQL.

---

## `postgres-secret.example.yaml` (modèle, jamais appliqué tel quel)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
  namespace: kps-tasks
type: Opaque
stringData:
  POSTGRES_USER: "REPLACE_ME"
  POSTGRES_PASSWORD: "REPLACE_ME"
```

Même logique que `app-secret.example.yaml` : modèle documentaire, valeurs réelles créées directement sur le cluster.

---

## `postgres-pvc.yaml`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim           # demande de stockage persistant (indépendant du cycle de vie d'un pod)
metadata:
  name: postgres-pvc                  # référencé par postgres-deployment.yaml
  namespace: kps-tasks
spec:
  accessModes:
    - ReadWriteOnce                    # monté en lecture/écriture par un seul noeud à la fois -- suffisant pour un seul pod PostgreSQL
  resources:
    requests:
      storage: 1Gi                     # taille demandée ; k3s la satisfait via son local-path-provisioner intégré
```

Aucune `StorageClass` n'est précisée : le cluster utilise celle par défaut (`local-path`, installée par k3s — vue au Jour 1 parmi les composants du cluster).

---

## `postgres-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: kps-tasks
  labels:
    app: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  strategy:
    type: Recreate                     # arrête l'ancien pod avant de créer le nouveau (voir explication ci-dessous)
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine    # image officielle, tag de version précis
          ports:
            - containerPort: 5432       # port PostgreSQL standard
          env:
            - name: POSTGRES_DB
              valueFrom:
                configMapKeyRef: {name: kps-tasks-api-config, key: POSTGRES_DB}
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef: {name: postgres-secret, key: POSTGRES_USER}
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef: {name: postgres-secret, key: POSTGRES_PASSWORD}
          volumeMounts:
            - name: postgres-storage
              mountPath: /var/lib/postgresql/data   # chemin où PostgreSQL écrit ses données, à l'intérieur du conteneur
      volumes:
        - name: postgres-storage
          persistentVolumeClaim:
            claimName: postgres-pvc     # relie ce volume nommé au PVC défini plus haut
```

**`strategy.type: Recreate`, la ligne la plus importante à savoir justifier** : le volume est `ReadWriteOnce`, donc monté par un seul pod à la fois. Avec la stratégie par défaut (`RollingUpdate`), Kubernetes tenterait de démarrer un nouveau pod PostgreSQL avant d'arrêter l'ancien — le nouveau resterait bloqué en attente du volume, déjà occupé. `Recreate` supprime l'ancien pod avant de créer le nouveau, ce qui implique une brève coupure de PostgreSQL à chaque mise à jour de ce Deployment (acceptable pour ce lab, à ne jamais faire tel quel dans un vrai système à haute disponibilité).

`POSTGRES_DB` vient du `ConfigMap` (non sensible), `POSTGRES_USER`/`POSTGRES_PASSWORD` viennent du `Secret` — les trois variables ont exactement les noms attendus par l'image officielle `postgres`.

---

## `postgres-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres                      # nom = ce que l'application utilise comme "hôte" dans DATABASE_URL
  namespace: kps-tasks
spec:
  selector:
    app: postgres                      # sélectionne le pod du Deployment postgres
  ports:
    - port: 5432
      targetPort: 5432
```

Aucun `type` précisé → `ClusterIP` par défaut → **jamais accessible depuis l'extérieur du cluster**, ce qui satisfait directement la contrainte non négociable "ne pas exposer PostgreSQL publiquement". C'est la ligne absente (`type: NodePort`) qui fait toute la différence avec `app-service.yaml`.

---

## Thèmes par jour, et où trouver la preuve correspondante

| Jour | Thème | Objets concernés | Preuve |
|---|---|---|---|
| 1 | Installation k3s, `kubectl` | — | `docs/prj5/k3s-installation.md`, `evidence/kubectl-get-nodes.txt` |
| 2 | Deployment + Service applicatif | `namespace.yaml`, `app-deployment.yaml` (sans probes/secret au départ), `app-service.yaml` | `docs/prj5/kubernetes-app-deployment.md`, `evidence/kubectl-get-pods-day2.txt` |
| 3 | ConfigMap, Secret, PostgreSQL | `app-configmap.yaml`, `*-secret.example.yaml`, `postgres-*.yaml` | `docs/prj5/configmap-secret-postgres.md`, `evidence/day3-*.txt` |
| 4 | Probes, NodePort, rollout/rollback | `app-deployment.yaml` (probes), `app-service.yaml` (NodePort) | `docs/prj5/probes-and-exposure.md`, `evidence/day4-*.txt`, `evidence/rollout-status.txt` |

Chaque réponse aux questions posées jour par jour (21 à 56) est dans `docs/prj5/intermediate-questions.md`.
