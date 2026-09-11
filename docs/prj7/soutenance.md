# Support de mini-soutenance — Projet 7 (OpsReady-07)

Trame pour une présentation orale de 10 à 15 minutes. Chaque section correspond à un point attendu par le brief.

## 1. Contexte client

LogiCare Solutions a migré son application vers Kubernetes + ArgoCD (Projet 6) mais reste aveugle en cas d'incident : pas de dashboard, logs consultés à la main, aucune alerte, détection tardive, causes non documentées. Objectif de ce projet : mettre en place une première stack d'observabilité réelle et prouver qu'elle sert concrètement à diagnostiquer.

## 2. Architecture d'observabilité

```
Application Kubernetes (kps-tasks-api, blue/green)
  -> logs stdout/stderr -> Promtail -> Loki -> Grafana

Cluster Kubernetes (nodes/pods/deployments/services)
  -> kube-state-metrics + node-exporter -> Prometheus -> Grafana

Prometheus -> regles d'alerte -> Alertmanager -> preuve d'alerte

Formateur / utilisateur -> dashboards Grafana -> requetes Prometheus -> logs Loki -> diagnostic d'incident
```

Tout installé via Helm sur le cluster k3s existant (namespace `monitoring`, séparé de `kps-tasks` et `argocd`) : `kube-prometheus-stack` (Prometheus, Grafana, Alertmanager, kube-state-metrics) puis `loki-stack` (Loki + Promtail).

## 3. Le rôle de chaque brique

| Composant | Rôle en une phrase |
|---|---|
| Prometheus | Collecte et stocke des métriques (nombres datés) en interrogeant périodiquement le cluster |
| Grafana | Visualise ces métriques et les logs sous forme de dashboards |
| Loki | Centralise les logs de tous les pods, indexés par leurs labels (namespace, pod, app) |
| Promtail | Agent (DaemonSet) qui lit les logs de chaque nœud et les envoie à Loki |
| Alertmanager | Reçoit les alertes déclenchées par Prometheus, les regroupe et les route |

## 4. Dashboards créés

Deux dashboards volontairement ciblés (plutôt qu'un import générique) :
- **Infrastructure Kubernetes** — CPU/RAM/disque des nodes, nombre de pods, état des nodes, usage par namespace/workload
- **Application KPS Tasks API** — pods blue/green, redémarrages, readiness, CPU/RAM, replicas actifs par version

Chaque panel vérifié avec de vraies données avant d'être considéré fiable (Jour 2).

## 5. Alertes configurées

4 règles (3 obligatoires + 1 bonus), seuils justifiés par rapport à l'usage normal mesuré :
- `KpsTaskApiPodNotReady`, `KpsTaskApiPodRestarting` — santé des pods
- `KpsTaskApiUnavailable` (critical) — aucun pod blue/green prêt = application réellement indisponible
- `KpsTaskApiHighCPU` — au-delà de 5x l'usage normal

**Une alerte réellement déclenchée** (Jour 4) : charge HTTP générée sur le pod actif, CPU passé de 0,01 à 1,86 cœur, `KpsTaskApiHighCPU` observée `firing` dans Prometheus puis `active` dans Alertmanager.

## 6. L'incident diagnostiqué (Jour 5)

**Scénario** : tag d'image inexistant poussé sur le déploiement `green` via le dépôt GitOps.

**Démarche suivie, dans l'ordre** :
1. Dashboard application → readiness à 0 pour le nouveau pod
2. Dashboard infrastructure → rien d'anormal, écarte une cause infra
3. Alertes → `KpsTaskApiPodNotReady` en `firing`, confirme la détection automatique
4. Logs Loki → aucune ligne (normal : le conteneur n'a jamais démarré)
5. `kubectl describe pod` → cause exacte : `ErrImagePull`, image introuvable
6. ArgoCD → `Synced` (donc vient bien de Git, pas d'une dérive manuelle), `Progressing` (bloqué par le pod jamais prêt)

**Cause** : tag d'image invalide commité dans le dépôt GitOps. **Correctif** : revert du tag, push, resynchronisation ArgoCD. **Impact réel** : aucun côté utilisateur (le Service route vers `blue`, non affecté) — mais la version `green` (cible de rollback/bascule) était cassée, ce qui aurait posé problème lors d'un futur changement de version. Rapport complet : [`incident-report.md`](incident-report.md).

## 7. Limites de la solution actuelle

- Pas de notification externe configurée (email/Slack) — la preuve reste dans Prometheus/Alertmanager/Grafana, suffisante pour ce projet mais pas pour une astreinte réelle
- Rétention Prometheus limitée à 3 jours (contrainte du VPS, pas un choix de production)
- Pas de traces distribuées (troisième pilier de l'observabilité, hors périmètre de ce projet)
- Les seuils d'alerte sont calés sur l'usage observé, pas sur une charge de production réelle — à revoir avec plus de recul

## 8. Améliorations possibles

- Notification externe (Slack/email) sur les alertes `critical`
- `ServiceMonitor` + endpoint `/metrics` applicatif pour des métriques métier (nombre de tâches créées, latence par endpoint)
- Alerte dédiée sur `ImagePullBackOff` (plus explicite que la seule readiness)
- Étape de validation CI vérifiant l'existence du tag d'image avant tout commit GitOps (action préventive du rapport d'incident)
