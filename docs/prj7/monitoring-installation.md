# Jour 1 — Installation de la stack de supervision

Document détaillé du Jour 1. Le résumé condensé (celui à garder ouvert en soutenance) est dans [`RUNBOOK.md`](RUNBOOK.md).

## Objectif du jour

Installer sur le cluster k3s existant (celui utilisé depuis le Projet 5) une stack complète de supervision : Prometheus (métriques), Grafana (visualisation), Alertmanager (alertes) et kube-state-metrics (état des objets Kubernetes), via le chart Helm `kube-prometheus-stack` qui regroupe les quatre.

## Étape 1 — Namespace dédié

```bash
kubectl create namespace monitoring
```

Un namespace séparé (`monitoring`, distinct de `kps-tasks` et `argocd`) isole les objets de supervision : en cas de suppression ou de réinstallation de la stack, aucun risque d'impacter l'application ou ArgoCD.

## Étape 2 — Installation de Helm (sans sudo)

Le VPS ne permet pas `sudo` en session non interactive (le script d'installation officiel de Helm échoue avec `sudo: a terminal is required to read the password`). Solution déjà utilisée au Projet 6 pour la CLI ArgoCD : télécharger le binaire et le placer dans `~/bin`, un répertoire appartenant à l'utilisateur, ajouté au `PATH`.

```bash
curl -sL https://get.helm.sh/helm-v3.16.3-linux-amd64.tar.gz -o helm.tar.gz
tar -xzf helm.tar.gz
mkdir -p ~/bin
mv linux-amd64/helm ~/bin/helm
export PATH=$PATH:~/bin
helm version
```

Résultat : `version.BuildInfo{Version:"v3.16.3", ...}`.

## Étape 3 — Dépôts Helm

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

Un dépôt Helm est un catalogue de charts (paquets d'applications Kubernetes prêts à l'emploi). `prometheus-community` fournit le chart `kube-prometheus-stack` ; le dépôt `grafana` sera réutilisé au Jour 3 pour Loki/Promtail.

## Étape 4 — Fichier de valeurs

Fichier [`monitoring/values-kube-prometheus-stack.yaml`](../../monitoring/values-kube-prometheus-stack.yaml), committé dans ce dépôt (aucun secret dedans) :

```yaml
grafana:
  service:
    type: NodePort
    nodePort: 30030

alertmanager:
  service:
    type: NodePort
    nodePort: 30093

prometheus:
  service:
    type: NodePort
    nodePort: 30090
  prometheusSpec:
    retention: 3d
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
```

Choix expliqués :
- **NodePort** plutôt que `ClusterIP` (par défaut) ou `LoadBalancer` : le VPS est un unique nœud sans load balancer cloud devant lui — NodePort ouvre un port fixe directement sur l'IP du VPS, exactement le pattern déjà utilisé pour l'application (30080) et ArgoCD (30843).
- **Ports choisis** (30030 Grafana, 30090 Prometheus, 30093 Alertmanager) : dans la plage NodePort valide (30000-32767), non utilisés par les projets précédents.
- **`retention: 3d`** et **ressources réduites** pour Prometheus : le VPS est un unique petit nœud ; les valeurs par défaut du chart supposent un cluster plus large. 3 jours de rétention suffisent largement pour la durée du projet.

## Étape 5 — Mot de passe Grafana (jamais en clair)

Rappel de la règle établie après l'incident du Projet 6 (mot de passe ArgoCD exposé) : tout secret est généré et stocké **côté serveur uniquement**, jamais affiché ni committé.

```bash
umask 077
GRAFANA_PW=$(tr -dc "A-Za-z0-9" < /dev/urandom | head -c 20)
echo "$GRAFANA_PW" > ~/.grafana-admin-password
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f ~/values-kube-prometheus-stack.yaml \
  --set grafana.adminPassword="$GRAFANA_PW"
```

Tout se passe dans une seule invocation shell distante : la variable `$GRAFANA_PW` n'apparaît jamais dans la sortie de la commande ni dans cette documentation. Le mot de passe reste dans `~/.grafana-admin-password` sur le VPS (permissions `600`).

## Étape 6 — Vérification de l'installation

```bash
helm list -n monitoring
kubectl get pods -n monitoring -o wide
kubectl get svc -n monitoring
```

Résultat (voir [`evidence/monitoring-pods.txt`](../../evidence/monitoring-pods.txt)) :

| Pod | État |
|---|---|
| `alertmanager-kube-prometheus-stack-alertmanager-0` | `2/2 Running` |
| `kube-prometheus-stack-grafana-...` | `3/3 Running` |
| `kube-prometheus-stack-kube-state-metrics-...` | `1/1 Running` |
| `kube-prometheus-stack-operator-...` | `1/1 Running` |
| `kube-prometheus-stack-prometheus-node-exporter-...` | `1/1 Running` |
| `prometheus-kube-prometheus-stack-prometheus-0` | `2/2 Running` |

Release Helm : `STATUS: deployed`, chart `kube-prometheus-stack-90.0.0`, app version `v0.93.1`.

## Étape 7 — Accès externe

```bash
curl -s -o /dev/null -w "%{http_code}" http://169.58.11.221:30030/login   # Grafana  -> 200
curl -s -o /dev/null -w "%{http_code}" http://169.58.11.221:30090        # Prometheus -> 302 (redirection vers /graph, normal)
curl -s -o /dev/null -w "%{http_code}" http://169.58.11.221:30093        # Alertmanager -> 200
```

Les trois interfaces répondent (voir [`evidence/grafana-access.txt`](../../evidence/grafana-access.txt)). Connexion Grafana : utilisateur `admin`, mot de passe lu depuis `~/.grafana-admin-password` sur le VPS au moment de la démo (jamais affiché en avance).

## Questions intermédiaires (11-16)

**11. À quoi sert Prometheus ?**
C'est une base de données de séries temporelles spécialisée dans les métriques : il interroge périodiquement ("scrape") des cibles (pods, nœuds, kube-state-metrics...) via HTTP, stocke les valeurs numériques avec un horodatage, et permet de les interroger avec son langage `PromQL` (ex : évolution du CPU sur 1h).

**12. À quoi sert Grafana ?**
C'est l'interface de visualisation : il se connecte à une ou plusieurs sources de données (ici Prometheus, et Loki au Jour 3) et affiche les données sous forme de dashboards (graphiques, jauges, tableaux). Grafana ne stocke pas les métriques lui-même, il les interroge à la demande.

**13. À quoi sert Alertmanager ?**
Prometheus peut évaluer des règles d'alerte (ex : "CPU > 90% pendant 5 min") et, quand une règle est vraie, envoie une alerte à Alertmanager. Celui-ci ne décide pas *quand* alerter (c'est Prometheus), mais gère *ce qui se passe ensuite* : regrouper les alertes similaires, éviter les doublons, les envoyer vers un canal de notification (email, Slack, etc.).

**14. À quoi sert kube-state-metrics ?**
Prometheus sait scraper des métriques exposées en HTTP, mais l'API Kubernetes ne parle pas nativement le format Prometheus. kube-state-metrics fait le pont : il lit l'état des objets Kubernetes (pods, deployments, nombre de replicas désirés vs disponibles...) via l'API et les republie au format que Prometheus sait lire.

**15. Pourquoi un namespace dédié (`monitoring`) ?**
Isolation : séparer les objets de supervision de l'application (`kps-tasks`) et de GitOps (`argocd`), pour pouvoir gérer, mettre à jour ou supprimer la stack de supervision sans aucun risque de toucher au reste du cluster.

**16. Pourquoi installer via Helm plutôt qu'avec des manifestes YAML manuels ?**
`kube-prometheus-stack` représente des dizaines de ressources Kubernetes interdépendantes (CRDs, Deployments, Services, ConfigMaps, RBAC...). Helm empaquette tout cela dans un "chart" versionné, avec des valeurs personnalisables (`values.yaml`) sans toucher aux manifestes bruts, et permet une désinstallation propre (`helm uninstall`) en une commande — écrire et maintenir cela à la main serait à la fois long et source d'erreurs.

## Résultat du jour

- Namespace `monitoring` créé
- Helm v3.16.3 installé (sans sudo)
- Stack `kube-prometheus-stack` déployée : Prometheus, Grafana, Alertmanager, kube-state-metrics, tous `Running`
- Accès externe confirmé sur les trois interfaces (NodePort 30030/30090/30093)
- Mot de passe Grafana généré et stocké côté serveur uniquement
