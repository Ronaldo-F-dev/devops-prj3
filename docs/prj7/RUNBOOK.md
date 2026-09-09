# Projet 7 — Runbook unique (à suivre du Jour 1 au Jour 5)

**Ce document est LE seul fil à suivre pour la démo/soutenance.** Il se construit jour après jour, pas à la fin — chaque section ajoutée est déjà complète et vérifiée avant de passer à la suivante. Tous les autres fichiers `docs/prj7/*.md` existent aussi (un par jour, détaillé), mais si un seul document devait être ouvert pendant la présentation, c'est celui-ci.

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
