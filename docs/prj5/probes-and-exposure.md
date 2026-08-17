# Probes, exposition externe, rollout et rollback — Jour 4

## Choix des probes (tâches 41-42)

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 5
  periodSeconds: 10
  failureThreshold: 3
livenessProbe:
  httpGet:
    path: /
    port: 8000
  initialDelaySeconds: 10
  periodSeconds: 15
  failureThreshold: 3
```

**Décision volontaire, pas un oubli** : la `readinessProbe` interroge `/health` (qui vérifie la connexion à PostgreSQL), mais la `livenessProbe` interroge `/` (la racine, qui ne touche jamais la base de données).

Pourquoi deux endpoints différents : le brief avertit explicitement qu'"une `livenessProbe` mal configurée peut provoquer des redémarrages inutiles". Si la `livenessProbe` avait, elle aussi, interrogé `/health`, une panne temporaire de PostgreSQL (redémarrage, montée en charge) aurait fait échouer la `livenessProbe` — et Kubernetes aurait alors redémarré le conteneur applicatif, **ce qui ne répare rien** puisque le problème est côté base de données, pas côté application. Un redémarrage inutile de plus n'aide jamais à réparer une dépendance externe en panne.

- **`readinessProbe` sur `/health`** : correct, parce que retirer un pod du trafic quand sa base de données est injoignable est exactement le comportement voulu — pas de sens à router des requêtes vers une instance qui ne peut pas les servir correctement.
- **`livenessProbe` sur `/`** : correct, parce que ça vérifie uniquement "le processus est vivant et répond", indépendamment de ses dépendances externes — la seule chose qu'un redémarrage peut effectivement réparer (un processus bloqué, un deadlock).

## Test d'une probe correcte (tâche 43)

Après application, le pod passe à `1/1 Running` — les deux probes réussissent dès le démarrage (`kubectl describe pod` confirme `Readiness: ... #success=1`, `Liveness: ... #success=1`).

## Déclenchement d'une probe incorrecte et observation (tâches 44-45)

Deux tests séparés, pour bien distinguer les deux comportements.

### Test A — `readinessProbe` cassée (chemin inexistant)

```bash
kubectl apply -f k8s/app-deployment.yaml  # avec readinessProbe pointant vers /this-path-does-not-exist
```

**Observé** : le nouveau pod reste **`0/1 Running`** indéfiniment (jamais de crash, jamais de redémarrage — `RESTARTS: 0`). Comme la stratégie de rollout par défaut (`RollingUpdate`) attend qu'un nouveau pod soit *Ready* avant de retirer l'ancien, **le rollout reste bloqué et l'ancien pod, toujours sain, continue de servir tout le trafic** :

```
kubectl get endpoints kps-tasks-api -n kps-tasks
NAME            ENDPOINTS
kps-tasks-api   10.42.0.14:8000   ← une seule IP : celle de l'ANCIEN pod
```

Log d'événement : `Readiness probe failed: HTTP probe failed with statuscode: 404` (répété, sans jamais de `Killing`). Preuve complète : `evidence/day4-readiness-probe-failure.txt`.

**Leçon** : une `readinessProbe`, combinée à une stratégie `RollingUpdate`, protège automatiquement la production contre un déploiement cassé — la nouvelle version ne reçoit jamais de trafic tant qu'elle n'est pas prouvée saine.

### Test B — `livenessProbe` cassée (chemin inexistant)

```bash
kubectl apply -f k8s/app-deployment.yaml  # avec livenessProbe pointant vers /this-path-does-not-exist
```

**Observé** : comportement radicalement différent — le pod est recréé en boucle. Dès le premier échec de seuil (`failureThreshold: 3`), l'événement `Killing` apparaît :

```
Warning  Unhealthy  ...  Liveness probe failed: HTTP probe failed with statuscode: 404
Normal   Killing    ...  Container kps-tasks-api failed liveness probe, will be restarted
```

`RESTARTS` passe à 1, puis continue d'augmenter tant que la probe reste cassée. Preuve complète : `evidence/day4-liveness-probe-failure.txt`.

**Leçon** : contrairement à la `readinessProbe` (qui retire simplement le pod du trafic), la `livenessProbe` **tue et recrée** le conteneur — d'où l'importance de ne jamais y placer une dépendance externe qu'un redémarrage ne peut pas réparer.

Les deux probes ont été corrigées immédiatement après chaque test (retour à la configuration correcte ci-dessus).

## Exposition externe (tâches 46-47)

Option retenue : **NodePort** (recommandation obligatoire du brief, pour bien comprendre le Service et l'exposition avant d'envisager l'Ingress en bonus).

```yaml
spec:
  type: NodePort
  ports:
    - port: 8000
      targetPort: 8000
      nodePort: 30080
```

Vérifié depuis une machine externe au VPS (pas de SSH, requête HTTP directe) :

```bash
curl http://<IP-VPS>:30080/health
curl http://<IP-VPS>:30080/version
curl http://<IP-VPS>:30080/tasks
```

Les trois répondent normalement. Preuve : `evidence/app-health-nodeport.txt`. Le port `30080` est distinct du port `8000` utilisé par l'ancien déploiement Docker Compose (Projet 4), qui continue de tourner en parallèle sans conflit pendant la migration.

## Rollout et rollback (tâches 48-50)

```bash
# Changement d'image (edition du manifeste, puis apply)
kubectl apply -f k8s/app-deployment.yaml   # commit-ed490e5 -> commit-4b75ff8
kubectl rollout status deployment/kps-tasks-api -n kps-tasks
# deployment "kps-tasks-api" successfully rolled out

kubectl rollout history deployment/kps-tasks-api -n kps-tasks
# liste des révisions successives

# Rollback natif Kubernetes
kubectl rollout undo deployment/kps-tasks-api -n kps-tasks
kubectl rollout status deployment/kps-tasks-api -n kps-tasks
# deployment "kps-tasks-api" successfully rolled out
```

**Avertissement rencontré, à connaître** : `kubectl rollout undo` a émis ceci :

```
Warning: resource deployments/kps-tasks-api was previously managed with 'kubectl apply'.
Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration
annotation, which may cause unexpected behavior on future 'kubectl apply' operations.
```

En clair : `kubectl rollout undo` change l'état réel du cluster, mais **pas** le manifeste local ni l'annotation que `kubectl apply` utilise pour calculer ses futurs diffs. Après un rollback, le fichier YAML versionné doit être remis manuellement en cohérence avec l'état réel du cluster (ici : remettre `commit-ed490e5` dans `k8s/app-deployment.yaml`) — sinon, un futur `kubectl apply` réintroduirait sans le vouloir l'image qu'on venait d'annuler. C'est fait dans ce projet.

Vérification après rollback : image revenue à `commit-ed490e5`, `/health` toujours `ok`, et surtout **la tâche créée au Jour 3 est toujours là** — ni le rollout ni le rollback n'affectent les données, qui vivent dans un volume séparé (`postgres-pvc`), jamais touché par un changement d'image applicatif.

Preuve complète : `evidence/rollout-status.txt`.
