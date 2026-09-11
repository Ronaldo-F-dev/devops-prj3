# Rapport d'incident — Jour 5

## Date et heure

- **Déclenchement** : 2026-09-11, ~08:02 UTC
- **Détection** : ~08:03 UTC (alerte `KpsTaskApiPodNotReady` en `pending`)
- **Résolution** : ~08:07 UTC
- **Durée totale** : ~5 minutes

## Incident observé

Le déploiement `kps-tasks-api-green` (version standby du mécanisme blue/green, Projet 6) a été mis à jour par ArgoCD avec un tag d'image Docker inexistant (`v9.9.9-does-not-exist`), commité par erreur sur le dépôt GitOps. Le nouveau pod créé pour appliquer ce changement n'a jamais pu démarrer.

## Impact

**Aucun impact utilisateur.** Le `Service` Kubernetes `kps-tasks-api` route le trafic uniquement vers les pods portant le label `version=blue` (image `v1.3.0`, non concernée par cet incident) — voir le mécanisme blue/green documenté au Projet 6. L'impact réel est différé : la version `green`, censée servir de cible de bascule ou de rollback, était cassée et n'aurait été découverte qu'au moment d'un futur changement de version — exactement le scénario « Green non prêt après un switch » identifié dans le brief du projet.

## Symptôme

```
kubectl get pods -n kps-tasks -l version=green
kps-tasks-api-green-7cdf8c5548-w4s52   0/1   ImagePullBackOff
```

Le pod `green` existant (`kps-tasks-api-green-76dbbd8f48-t9fbz`) a continué de tourner sans interruption pendant tout l'incident — Kubernetes ne retire un ancien `ReplicaSet` qu'une fois le nouveau prêt (stratégie `RollingUpdate` par défaut), ce qui a évité toute coupure.

## Détection et outils utilisés

Démarche suivie dans l'ordre (voir preuve complète : [`evidence/incident-diagnostic.txt`](../../evidence/incident-diagnostic.txt)) :

1. **Dashboard application** (Grafana, panel « Disponibilité ») : `kube_pod_container_status_ready` à `0` pour le nouveau pod, `1` pour l'ancien — premier signal visuel.
2. **Dashboard infrastructure** : aucune anomalie côté nodes/CPU/RAM — élimine une cause infrastructure.
3. **Alertes** : `KpsTaskApiPodNotReady` passée en `pending` puis `firing` sur le pod concerné, confirmant que le problème est détecté automatiquement, pas seulement visible sur un dashboard.
4. **Logs Loki** : recherche des logs applicatifs du pod → 0 ligne. Ce n'est pas une panne de collecte : le conteneur n'a jamais démarré, donc il n'a jamais rien pu écrire dans ses logs. L'absence de logs est ici elle-même une information de diagnostic.
5. **État Kubernetes** (`kubectl describe pod`) : les événements donnent la cause exacte — `Failed to pull image ... : NotFound ... not found`, `Reason: ErrImagePull` puis `BackOff`.
6. **ArgoCD** : `kps-tasks-api-dev` → `Synced` / `Progressing`. `Synced` confirme que ce n'est pas une dérive manuelle (`kubectl edit` sauvage) : le manifeste erroné vient bien de Git. `Progressing` (au lieu de `Healthy`) reflète que la synchronisation ne peut pas se terminer tant que le nouveau pod n'est pas prêt.

## Cause probable

Un tag d'image Docker inexistant (`v9.9.9-does-not-exist`) a été commité sur le déploiement `kps-tasks-api-green` dans le dépôt GitOps (`kps-tasks-gitops`). ArgoCD, en synchronisation automatique, a appliqué ce changement sans le valider au préalable — GitOps synchronise fidèlement ce qui est dans Git, il ne vérifie pas que l'image référencée existe réellement dans le registre.

## Correctif appliqué

```bash
# Dans le dépôt GitOps (kps-tasks-gitops)
# apps/kps-tasks-api/deployment-green.yaml : image remise à v1.2.0
git commit -m "fix: revert green deployment to v1.2.0"
git push
```

ArgoCD a resynchronisé automatiquement. Le pod cassé a été retiré, l'ancien pod `green` (déjà `Running`, jamais interrompu) est resté en place. `kps-tasks-api-dev` est repassée `Synced` / `Healthy`.

## Preuve du retour à la normale

```
kubectl get pods -n kps-tasks -l version=green
kps-tasks-api-green-76dbbd8f48-t9fbz   1/1   Running   0
```

Observation complémentaire : l'alerte `KpsTaskApiPodNotReady` est restée visible quelques minutes après la correction, toujours associée au nom du pod supprimé — comportement normal de Prometheus (fenêtre de "staleness" avant qu'une série disparue soit officiellement marquée obsolète), pas un signe que le correctif n'a pas fonctionné.

## Action préventive proposée

Ajouter une étape de validation dans le pipeline CI (avant tout commit sur le dépôt GitOps) qui vérifie que le tag d'image référencé existe réellement dans le registre (`docker manifest inspect` ou équivalent), pour empêcher qu'un tag invalide n'atteigne jamais Git. En complément, une `PrometheusRule` spécifique sur `kube_pod_container_status_waiting_reason{reason="ImagePullBackOff"}` permettrait de distinguer ce cas précis d'un simple pod lent à démarrer, avec un message d'alerte plus direct.
