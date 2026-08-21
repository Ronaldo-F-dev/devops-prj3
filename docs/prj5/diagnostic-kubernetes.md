# Reconstruction et diagnostic — Jour 5

## Procédure de reconstruction complète (tâches 57-66)

Testée réellement : namespace `kps-tasks` supprimé entièrement, puis reconstruit uniquement à partir des fichiers versionnés dans `k8s/`.

```bash
# 1. Suppression complète (destructif — supprime pods, services, configmap,
#    secrets, et le PVC PostgreSQL avec ses données)
kubectl delete namespace kps-tasks

# 2. Reconstruction, dans l'ordre des dépendances
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/app-configmap.yaml

# 3. Les Secrets ne sont pas dans un fichier versionné (voir
#    docs/prj5/configmap-secret-postgres.md) — recréés en ligne de commande,
#    à partir des identifiants déjà utilisés par le déploiement Docker
#    Compose du Projet 4 (/opt/kps-tasks-api/.env sur le VPS) :
kubectl create secret generic postgres-secret -n kps-tasks \
  --from-literal=POSTGRES_USER="$POSTGRES_USER" \
  --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD"
kubectl create secret generic kps-tasks-api-secret -n kps-tasks \
  --from-literal=DATABASE_URL="postgresql+psycopg://$POSTGRES_USER:$POSTGRES_PASSWORD@postgres:5432/$POSTGRES_DB"

# 4. PostgreSQL, puis l'application
kubectl apply -f k8s/postgres-pvc.yaml
kubectl apply -f k8s/postgres-deployment.yaml
kubectl apply -f k8s/postgres-service.yaml
kubectl apply -f k8s/app-deployment.yaml
kubectl apply -f k8s/app-service.yaml

# 5. Vérification
kubectl get pods -n kps-tasks -o wide
kubectl get svc -n kps-tasks
kubectl get pvc -n kps-tasks
curl http://<IP-VPS>:30080/health
```

Résultat observé : les deux pods (`kps-tasks-api`, `postgres`) reviennent à l'état `Running 1/1` en moins d'une minute, l'application répond correctement (`/health` → `ok`), sans aucune intervention manuelle au-delà de l'application des manifestes et de la recréation des Secrets. Preuve complète : `evidence/day5-reconstruction.txt`.

**Ce que ça démontre** : l'intégralité de l'état applicatif (hors identifiants sensibles, volontairement exclus du dépôt) est reconstructible depuis Git seul. C'est l'argument central de l'infrastructure déclarative — un cluster détruit n'est pas une catastrophe si tout ce qui compte est versionné ailleurs que dans le cluster lui-même.

Une donnée créée après reconstruction (`POST /tasks`) a été relue avec succès, confirmant que le nouveau PostgreSQL (nouveau PVC, nouvelles données — l'ancien volume a été supprimé avec le namespace) fonctionne correctement de bout en bout.

## Suppression et recréation automatique d'un pod (tâches 63-65)

```bash
kubectl get pods -n kps-tasks -l app=kps-tasks-api
kubectl delete pod <nom-du-pod> -n kps-tasks
kubectl get pods -n kps-tasks -l app=kps-tasks-api -w   # observer la recréation en direct
```

Observé : le pod supprimé est remplacé par un nouveau (nom différent, même Deployment) en une vingtaine de secondes. L'application redevient accessible et les données créées avant la suppression sont toujours présentes — normal, PostgreSQL tourne dans un pod séparé, jamais touché par la suppression du pod applicatif. Preuve : `evidence/pod-recreation.txt`.

C'est le Deployment (pas le Pod lui-même) qui porte cette garantie : il vérifie en permanence que le nombre de pods correspondant à son `selector` correspond à `replicas`, et en recrée un dès que ce n'est plus le cas.

## Méthode de diagnostic générale (préparation Phase 2)

Le scénario exact déclenché par le formateur n'est pas connu à l'avance. Commandes de première intention, dans l'ordre où les utiliser :

```bash
kubectl get pods -n kps-tasks                    # état général : Running, CrashLoopBackOff, ImagePullBackOff, Pending...
kubectl describe pod <pod> -n kps-tasks           # section Events en bas : la cause y est presque toujours explicite
kubectl logs <pod> -n kps-tasks                   # logs de l'application elle-même
kubectl get events -n kps-tasks --sort-by=.lastTimestamp   # historique des événements du namespace, dans l'ordre chronologique
kubectl exec -it <pod> -n kps-tasks -- sh          # accès direct au conteneur si les logs ne suffisent pas
kubectl rollout status deployment/<nom> -n kps-tasks       # vérifie si un déploiement est bloqué
```

| Scénario possible (brief) | Ce que `kubectl get pods` montre en premier | Où creuser |
|---|---|---|
| Image inexistante / mauvais tag | `ErrImagePull` puis `ImagePullBackOff` | `kubectl describe pod` → section Events, message `manifest unknown` ou `not found` |
| Variable d'environnement manquante | Le pod peut démarrer puis planter, ou tourner en boucle | `kubectl logs` — l'application peut lever une erreur explicite (voir `app/config.py`, valeurs de repli) |
| Secret ou ConfigMap manquant/mal référencé | `CreateContainerConfigError` | `kubectl describe pod` → Events : `couldn't find key ... in Secret/ConfigMap` |
| Mauvais port dans le Service | Pod `Running`, mais rien n'arrive dessus | Comparer `targetPort` du Service et `containerPort` du Deployment (`kubectl get svc -o yaml`, `kubectl get deploy -o yaml`) |
| `readinessProbe` incorrecte | Pod `Running` mais `0/1` (jamais Ready) | `kubectl describe pod` → Events : `Readiness probe failed` avec le code retourné |
| `livenessProbe` trop agressive | `RESTARTS` qui augmente en boucle | `kubectl describe pod` → Events : `Liveness probe failed`, `Killing container` |
| PostgreSQL indisponible | `/health` renvoie `degraded` | `kubectl get pods -l app=postgres`, `kubectl logs` du pod postgres |
| Service PostgreSQL mal nommé | Erreur de résolution DNS dans les logs de l'app (`could not translate host name`) | Vérifier que `DATABASE_URL` référence bien le nom exact du Service (`kubectl get svc`) |
| Erreur de permission ou de volume | Pod bloqué en `Pending` ou `ContainerCreating` | `kubectl describe pod` → Events : `FailedMount`, `FailedScheduling` |
| `CrashLoopBackOff` | Redémarrages répétés, statut visible directement dans `kubectl get pods` | `kubectl logs <pod> --previous` (logs du conteneur précédent, avant le crash) |

Cette table reprend directement les scénarios listés dans le brief (Phase 2) — pas des cas abstraits, une grille de lecture pour aller vite le jour de la démonstration.
