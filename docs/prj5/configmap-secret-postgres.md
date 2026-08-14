# ConfigMap, Secret et PostgreSQL — Jour 3

## Répartition config non sensible / sensible (tâches 26-27)

| Type | Objet | Contenu |
|---|---|---|
| Non sensible | `ConfigMap kps-tasks-api-config` | `APP_NAME`, `APP_ENV`, `LOG_LEVEL`, `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB` |
| Sensible | `Secret postgres-secret` | `POSTGRES_USER`, `POSTGRES_PASSWORD` |
| Sensible | `Secret kps-tasks-api-secret` | `DATABASE_URL` (inclut déjà l'utilisateur et le mot de passe) |

### Ce qui est committé dans Git, et ce qui ne l'est jamais

`k8s/app-configmap.yaml` contient de vraies valeurs et est commité tel quel — rien de sensible dedans.

Pour les Secrets, **seuls des fichiers `.example.yaml` avec des valeurs `REPLACE_ME` sont commités** (`k8s/postgres-secret.example.yaml`, `k8s/app-secret.example.yaml`) : ils documentent la structure attendue, mais ne sont jamais appliqués tels quels. Les **vrais** Secrets ont été créés directement sur le cluster, en ligne de commande, à partir des identifiants déjà utilisés par le déploiement Docker Compose du Projet 4 (`/opt/kps-tasks-api/.env` sur le VPS) — jamais recopiés dans un fichier versionné :

```bash
kubectl create secret generic postgres-secret -n kps-tasks \
  --from-literal=POSTGRES_USER="$POSTGRES_USER" \
  --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD"

kubectl create secret generic kps-tasks-api-secret -n kps-tasks \
  --from-literal=DATABASE_URL="postgresql+psycopg://$POSTGRES_USER:$POSTGRES_PASSWORD@postgres:5432/$POSTGRES_DB"
```

## PostgreSQL dans Kubernetes (tâches 28-29)

Trois objets, dans `k8s/postgres-deployment.yaml`, `postgres-service.yaml`, `postgres-pvc.yaml` :

- **`PersistentVolumeClaim postgres-pvc`** (1 Gi) : demande de stockage persistant. k3s la satisfait automatiquement via son `local-path-provisioner` intégré (vu au Jour 1 parmi les composants installés) — pas de configuration de stockage supplémentaire nécessaire pour ce lab.
- **`Deployment postgres`** : un seul réplica, image `postgres:16-alpine`, avec `POSTGRES_DB` tiré du ConfigMap et `POSTGRES_USER`/`POSTGRES_PASSWORD` tirés du Secret (`valueFrom.secretKeyRef` / `configMapKeyRef` — jamais de valeur en dur). Volume monté sur `/var/lib/postgresql/data`.
- **`Service postgres`** : `ClusterIP` (type par défaut, non précisé dans le manifeste) — c'est justement ce qui garantit qu'il n'est **pas** accessible depuis l'extérieur du cluster (tâche 31).

**Point technique rencontré** : `strategy.type: Recreate` a été ajouté explicitement sur le Deployment PostgreSQL, au lieu du `RollingUpdate` par défaut. Une base de données avec un volume `ReadWriteOnce` (monté par un seul pod à la fois) ne peut pas supporter un rolling update classique : Kubernetes tenterait de démarrer le nouveau pod avant d'arrêter l'ancien, et le nouveau resterait bloqué en attente du volume, déjà occupé. `Recreate` arrête l'ancien pod avant de créer le nouveau, évitant ce blocage.

## Connexion de l'application à PostgreSQL (tâche 30)

Le Deployment de l'application (`k8s/app-deployment.yaml`) a été mis à jour : `DATABASE_URL` vient maintenant du Secret `kps-tasks-api-secret`, et pointe vers `postgres:5432` — `postgres` étant le **nom du Service**, pas une IP.

### Piège rencontré : les tables n'existaient pas

Premier test après connexion : `/health` passait à `ok`, mais `POST /tasks` et `GET /tasks` renvoyaient une erreur 500. Cause : l'image Docker, seule, ne lance que `uvicorn` (voir le `CMD` du `Dockerfile`) — c'est `docker-compose.yml` (Projet 4) qui ajoutait `python -m app.init_db` avant, pour créer les tables. Ce comportement n'existe pas nativement dans l'image, il fallait le reproduire en Kubernetes.

**Solution retenue : un `initContainer`.** Plutôt que de modifier la commande du conteneur principal (ce qui mélangerait initialisation et exécution), un `initContainer` dédié exécute `python -m app.init_db` et se termine **avant** que le conteneur principal démarre :

```yaml
initContainers:
  - name: init-db
    image: ghcr.io/ronaldo-f-dev/kps-tasks-api:commit-ed490e5
    command: ["python", "-m", "app.init_db"]
    env:
      - name: DATABASE_URL
        valueFrom:
          secretKeyRef:
            name: kps-tasks-api-secret
            key: DATABASE_URL
```

C'est un pattern Kubernetes standard : séparer une tâche unique de préparation (migration de schéma, ici) du processus principal de longue durée — le conteneur principal ne démarre que si l'initContainer se termine avec succès.

## Vérification (tâches 31-33)

```bash
# Creation d'une tache de test
curl -X POST http://<pod-ip>:8000/tasks -H "Content-Type: application/json" \
  -d '{"title":"Test Kubernetes","description":"Creee depuis le pod k8s Jour 3"}'

# Relecture
curl http://<pod-ip>:8000/tasks
```

Résultat : la tâche est créée puis relue avec succès — preuve complète de bout en bout (application → Service → Pod PostgreSQL → volume). Détail : `evidence/day3-app-db-communication.txt`.

Absence d'exposition publique de PostgreSQL vérifiée depuis une machine **externe** au VPS : le port `5432` est injoignable (timeout), confirmant que le `Service` `ClusterIP` ne route que le trafic interne au cluster.

## Résolution DNS interne (tâche 34)

Kubernetes fournit une résolution DNS automatique pour chaque `Service`, gérée par CoreDNS (vu au Jour 1). Le nom court utilisé dans `DATABASE_URL` (`postgres`) se résout en `postgres.kps-tasks.svc.cluster.local`, qui pointe vers le `ClusterIP` du Service :

```bash
kubectl exec <pod-app> -n kps-tasks -- getent hosts postgres
# 10.43.80.67   postgres.kps-tasks.svc.cluster.local
```

Le format complet est `<service>.<namespace>.svc.cluster.local` — utiliser juste `postgres` fonctionne parce que la résolution DNS d'un pod cherche automatiquement dans son propre namespace en priorité. C'est ce qui permet à l'application de ne jamais coder d'IP en dur : même si le pod PostgreSQL est recréé (et change d'IP), le Service — et donc le nom DNS — reste stable.

## Flux complet application → base de données (tâche 35)

```
Pod kps-tasks-api
  → résout "postgres" via CoreDNS → 10.43.80.67 (ClusterIP du Service postgres)
  → Service postgres (ClusterIP, port 5432)
  → sélectionne les pods avec le label app=postgres
  → Pod postgres (conteneur postgres:16-alpine, port 5432)
  → lit/écrit sur le volume monté (PVC postgres-pvc, backé par local-path-provisioner)
```

Aucune étape de ce flux ne sort du cluster, et PostgreSQL n'a besoin d'aucune IP publique ni d'aucun port exposé sur le VPS pour fonctionner.
