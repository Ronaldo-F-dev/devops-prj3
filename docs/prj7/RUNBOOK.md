# Projet 7 — Runbook unique (à suivre du Jour 1 au Jour 5)

**Ce document est LE seul fil à suivre pour la démo/soutenance.** Il se construit jour après jour, pas à la fin — chaque section ajoutée est déjà complète et vérifiée avant de passer à la suivante. Tous les autres fichiers `docs/prj7/*.md` existent aussi (un par jour, détaillé), mais si un seul document devait être ouvert pendant la présentation, c'est celui-ci.

**Toutes les réponses aux questions intermédiaires du brief (11 à 66) sont rassemblées en un seul endroit** : [`intermediate-questions.md`](intermediate-questions.md) — à consulter si le formateur pose une question théorique pendant la soutenance, plutôt que de chercher dans le document du jour concerné.

**Tout ce projet vit dans ce seul dépôt** (`devops-prj3`) — pas de second dépôt cette fois, contrairement au Projet 6, justement pour éviter d'avoir à jongler entre plusieurs sources en pleine présentation.

- `monitoring/` — fichiers `values.yaml` Helm, règles d'alerte
- `dashboards/` — exports JSON des dashboards Grafana
- `docs/prj7/` — un fichier par jour + ce runbook
- `evidence/` — preuves capturées (partagé avec les projets précédents)

---

## Jour 1 — Installation de la stack (terminé)

### Ce qu'on installe et pourquoi

| Outil | Rôle en une phrase |
|---|---|
| **Prometheus** | Collecte des métriques (nombres qui évoluent dans le temps : CPU, RAM, nombre de pods…) en interrogeant périodiquement le cluster |
| **Grafana** | Affiche ces métriques (et les logs) sous forme de dashboards visuels |
| **Alertmanager** | Reçoit les alertes déclenchées par Prometheus et décide quoi en faire (regrouper, notifier) |
| **kube-state-metrics** | Traduit l'état des objets Kubernetes (pods, deployments…) en métriques que Prometheus peut lire |
| **Loki** (Jour 3) | Centralise les logs de tous les pods, comme Prometheus mais pour du texte plutôt que des nombres |
| **Promtail** (Jour 3) | Agent qui lit les logs de chaque pod et les envoie à Loki |

### Namespace dédié

```bash
kubectl create namespace monitoring
```
Namespace `monitoring`, séparé de `kps-tasks` et `argocd` — isole les objets de supervision du reste, comme au Projet 5/6.

### Installation

Helm v3.16.3 installé sans sudo (binaire dans `~/bin`, même pattern que la CLI ArgoCD au Projet 6). Dépôts `prometheus-community` et `grafana` ajoutés. Chart `kube-prometheus-stack` installé avec le fichier [`monitoring/values-kube-prometheus-stack.yaml`](../../monitoring/values-kube-prometheus-stack.yaml) (NodePort 30030/30090/30093 pour Grafana/Prometheus/Alertmanager, ressources Prometheus réduites pour le VPS). Mot de passe admin Grafana généré et stocké côté serveur uniquement (`~/.grafana-admin-password`), jamais committé ni affiché.

Détail complet, étape par étape, avec justification de chaque choix : [`monitoring-installation.md`](monitoring-installation.md).

### Vérification

```bash
helm list -n monitoring
kubectl get pods -n monitoring -o wide
kubectl get svc -n monitoring
```

Résultat : release `deployed`, les 6 pods attendus tous `Running` — Alertmanager (2/2), Grafana (3/3), kube-state-metrics (1/1), prometheus-operator (1/1), node-exporter (1/1), Prometheus (2/2). Preuve : [`evidence/monitoring-pods.txt`](../../evidence/monitoring-pods.txt).

### Accès externe

| Interface | URL | Résultat |
|---|---|---|
| Grafana | http://169.58.11.221:30030/login | HTTP 200 |
| Prometheus | http://169.58.11.221:30090 | HTTP 302 (redirection normale vers `/graph`) |
| Alertmanager | http://169.58.11.221:30093 | HTTP 200 |

Preuve : [`evidence/grafana-access.txt`](../../evidence/grafana-access.txt). Connexion Grafana : `admin` / mot de passe lu depuis `~/.grafana-admin-password` sur le VPS au moment de la démo.

### Questions intermédiaires (11-16)

Rôle de chaque composant (Prometheus, Grafana, Alertmanager, kube-state-metrics), pourquoi un namespace dédié, pourquoi Helm — réponses complètes dans [`monitoring-installation.md`](monitoring-installation.md#questions-intermédiaires-11-16).

### Jour 1 — Résultat

Namespace créé, Helm installé, stack déployée et vérifiée, accès externe confirmé sur les 3 interfaces, mot de passe sécurisé. **Prêt pour le Jour 2.**

---

## Jour 2 — Dashboards Grafana (terminé)

Source de données Prometheus déjà provisionnée automatiquement par le chart (`uid: prometheus`, `isDefault: true`) — rien à configurer. Deux dashboards créés via l'API Grafana à partir de fichiers JSON versionnés :

- [`dashboards/infrastructure-dashboard.json`](../../dashboards/infrastructure-dashboard.json) — CPU/RAM/disque des nodes, nombre de pods, état des nodes, usage CPU/RAM par namespace et par workload
- [`dashboards/application-dashboard.json`](../../dashboards/application-dashboard.json) — pods `kps-tasks-api` (blue/green) : nombre, phase, redémarrages, readiness, CPU/RAM, replicas disponibles par version

Chaque panel a été vérifié en interrogeant Prometheus directement (`/api/v1/query`) pour confirmer qu'il renvoie de vraies données, pas un panel vide. Détail complet, chaque requête PromQL expliquée, réponses aux questions 27-32 : [`grafana-dashboards.md`](grafana-dashboards.md). Preuves : [`evidence/grafana-dashboards-queries.txt`](../../evidence/grafana-dashboards-queries.txt).

### Jour 2 — Résultat

Deux dashboards exploitables et vérifiés, CPU nodes ~15,6 %, RAM nodes ~32,2 %, 2 pods applicatifs sains (0 redémarrage). **Prêt pour le Jour 3.**

---

## Jour 3 — Loki, Promtail et centralisation des logs (terminé)

Installés ensemble via le chart `grafana/loki-stack` (Loki en mode single-binary + Promtail), `grafana.enabled=false`/`prometheus.enabled=false` pour ne pas dupliquer ce qui existe déjà depuis le Jour 1 :

```bash
helm install loki grafana/loki-stack -n monitoring \
  -f monitoring/values-loki.yaml -f monitoring/values-promtail.yaml
```

- [`monitoring/values-loki.yaml`](../../monitoring/values-loki.yaml) — persistance 2Gi (`local-path`), pas de source par défaut
- [`monitoring/values-promtail.yaml`](../../monitoring/values-promtail.yaml) — configuration par défaut (DaemonSet, un pod par nœud)

Résultat : `loki-0` et `loki-promtail-...` tous deux `Running`. Loki ajouté comme source de données Grafana (Prometheus reste la source par défaut). Namespaces vus par Loki : `argocd`, `kps-tasks`, `kube-system`, `monitoring` — preuve que la collecte couvre tout le cluster.

**Preuve de bout en bout** : une vraie erreur applicative déclenchée (`GET /tasks/999999` → `404`, endpoint existant de l'application) puis retrouvée dans Loki en quelques secondes avec le filtre LogQL `{namespace="kps-tasks"} |= "404"`.

Détail complet (requêtes LogQL, cas PostgreSQL sans logs expliqué, réponses aux questions 43-49) : [`loki-promtail-logs.md`](loki-promtail-logs.md). Preuves : [`evidence/loki-logs.txt`](../../evidence/loki-logs.txt).

### Jour 3 — Résultat

Logs centralisés, filtrables par namespace/pod/application, erreur réelle déclenchée et retrouvée. **Prêt pour le Jour 4** (alertes Prometheus/Alertmanager).

---

## Jour 4 — Alertes Prometheus et Alertmanager (terminé)

4 règles d'alerte (`PrometheusRule`, label obligatoire `release: kube-prometheus-stack` pour être prises en compte) appliquées par `kubectl apply` :

- [`monitoring/alerts/pod-alerts.yaml`](../../monitoring/alerts/pod-alerts.yaml) — `KpsTaskApiPodNotReady`, `KpsTaskApiPodRestarting`
- [`monitoring/alerts/app-alerts.yaml`](../../monitoring/alerts/app-alerts.yaml) — `KpsTaskApiUnavailable` (critical, aucun pod blue/green prêt)
- [`monitoring/alerts/resource-alerts.yaml`](../../monitoring/alerts/resource-alerts.yaml) — `KpsTaskApiHighCPU` (> 50 millicoeurs, seuil justifié par rapport à l'usage normal ~10m mesuré au Jour 2)

Les 4 règles chargées et `health: ok` dans Prometheus. **Alerte réellement déclenchée** : une charge HTTP concurrente sur `GET /tasks` a fait passer le CPU du pod actif (`blue`) de ~0,01 à ~1,86 cœur ; `KpsTaskApiHighCPU` est passée `inactive` → `pending` → `firing` dans Prometheus, puis `active` dans Alertmanager (`/api/v2/alerts`). Aucun pod n'a redémarré pendant le test — l'application encaisse la charge.

Détail complet (fonctionnement d'une règle, justification de chaque seuil, réponses aux questions 60-66) : [`alerting-rules.md`](alerting-rules.md). Preuve : [`evidence/alert-triggered.txt`](../../evidence/alert-triggered.txt).

### Jour 4 — Résultat

4 alertes utiles configurées et vérifiées, chaîne complète Prometheus → Alertmanager prouvée avec une vraie alerte déclenchée. **Prêt pour le Jour 5** (incident, diagnostic, rapport, mini-soutenance).

---

## Jour 5 — Incident, diagnostic et mini-soutenance (terminé)

**Incident déclenché réellement** (pas simulé) : un tag d'image inexistant (`v9.9.9-does-not-exist`) commité sur `deployment-green.yaml` dans le dépôt GitOps (`kps-tasks-gitops`), synchronisé automatiquement par ArgoCD.

**Démarche de diagnostic suivie** (dans l'ordre, sans commande au hasard) :
1. Dashboard application → readiness à 0 sur le nouveau pod
2. Dashboard infrastructure → rien d'anormal côté nodes
3. Alertes → `KpsTaskApiPodNotReady` `firing`
4. Logs Loki → 0 ligne (normal, le conteneur n'a jamais démarré)
5. `kubectl describe pod` → cause exacte : `ErrImagePull`, image introuvable
6. ArgoCD → `Synced` (vient de Git, pas une dérive manuelle) / `Progressing` (bloqué)

**Cause** : tag d'image invalide dans le dépôt GitOps. **Correctif** : revert du tag (commit + push), resynchronisation ArgoCD. **Impact réel** : aucun côté utilisateur (le Service route vers `blue`, non affecté) — la version `green` (cible de rollback) était cassée, aurait posé problème lors d'un futur switch.

Rapport complet : [`incident-report.md`](incident-report.md). Support de présentation : [`soutenance.md`](soutenance.md). Preuve : [`evidence/incident-diagnostic.txt`](../../evidence/incident-diagnostic.txt).

### Jour 5 — Résultat

Incident réel déclenché, diagnostiqué avec la stack complète (dashboards, alertes, logs, kubectl, ArgoCD), corrigé, documenté. **Projet 7 terminé.**

---

## Bilan du projet

Les 5 jours sont complets, un seul dépôt du début à la fin, documentation construite au fil de l'eau (pas assemblée à la fin) — correction directe de ce qui avait posé problème au Projet 6.

| Jour | Documents détaillés |
|---|---|
| 1 — Installation stack | [`monitoring-installation.md`](monitoring-installation.md) |
| 2 — Dashboards Grafana | [`grafana-dashboards.md`](grafana-dashboards.md) |
| 3 — Loki/Promtail | [`loki-promtail-logs.md`](loki-promtail-logs.md) |
| 4 — Alertes | [`alerting-rules.md`](alerting-rules.md) |
| 5 — Incident | [`incident-report.md`](incident-report.md), [`soutenance.md`](soutenance.md) |
