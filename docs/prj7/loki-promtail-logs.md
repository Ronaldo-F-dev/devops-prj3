# Jour 3 — Loki, Promtail et centralisation des logs

Document détaillé du Jour 3. Résumé condensé dans [`RUNBOOK.md`](RUNBOOK.md).

## Objectif du jour

Centraliser les logs de tous les pods (applicatifs et Kubernetes) dans Loki, les consulter depuis Grafana, et prouver qu'une erreur applicative réelle peut y être retrouvée.

## Choix technique

Le chart moderne `grafana/loki` (v7.x) est conçu pour un déploiement distribué avec stockage objet (S3/GCS) — trop lourd pour un VPS à un seul nœud. Le chart `grafana/loki-stack` regroupe Loki (en mode "single binary", stockage sur disque local via le `StorageClass` par défaut de k3s, `local-path`) et Promtail dans une seule installation, adapté à l'échelle de ce projet. `grafana.enabled=false` et `prometheus.enabled=false` dans les valeurs, car ces deux composants sont déjà installés (Jour 1) — on ne réinstalle pas ce qui existe déjà.

## Étape 1-2 — Installation de Loki et Promtail

```bash
helm install loki grafana/loki-stack -n monitoring \
  -f monitoring/values-loki.yaml \
  -f monitoring/values-promtail.yaml
```

Fichiers de valeurs (committés, aucun secret) :
- [`monitoring/values-loki.yaml`](../../monitoring/values-loki.yaml) — persistance activée (2Gi, `local-path`), `isDefault: false` (Prometheus reste la source par défaut de Grafana)
- [`monitoring/values-promtail.yaml`](../../monitoring/values-promtail.yaml) — configuration par défaut du chart (suffisante)

Résultat (voir [`evidence/loki-logs.txt`](../../evidence/loki-logs.txt)) : release `loki` `deployed`, chart `loki-stack-2.10.3`. Deux pods :
- `loki-0` (`1/1 Running`) — le serveur Loki lui-même, en StatefulSet (un seul réplica)
- `loki-promtail-<hash>` (`1/1 Running`) — DaemonSet, un pod par nœud (ici un seul nœud)

## Étape 3 — Vérification que Promtail collecte bien les logs

Promtail lit `/var/log/containers/*.log` sur le nœud (chemin standard où Kubernetes écrit les logs de tous les conteneurs) et enrichit chaque ligne avec les métadonnées Kubernetes (namespace, pod, container, nœud), puis les envoie à Loki via son API HTTP.

```bash
kubectl exec -n monitoring <pod-loki> -c loki -- wget -qO- http://localhost:3100/loki/api/v1/label/namespace/values
```

Résultat : `["argocd", "kps-tasks", "kube-system", "monitoring"]` — tous les namespaces actifs du cluster sont bien représentés, preuve que Promtail collecte sur l'ensemble du nœud et pas seulement un namespace choisi.

## Étape 4 — Loki comme source de données Grafana

```bash
curl -u admin:<mot de passe> -X POST -H "Content-Type: application/json" \
  -d '{"name":"Loki","type":"loki","access":"proxy","url":"http://loki:3100","isDefault":false}' \
  http://localhost:30030/api/datasources
```

`isDefault: false` : Prometheus reste la source par défaut (déjà utilisée par les deux dashboards du Jour 2) — Loki s'ajoute sans rien changer à l'existant. Vérifié ensuite via l'explorateur Grafana (`/explore`), source Loki sélectionnée.

## Étape 5-8 — Consultation et filtrage des logs applicatifs

Requêtes LogQL utilisées (LogQL = le langage de requête de Loki, même esprit que PromQL mais pour du texte : un sélecteur de labels entre accolades, puis des filtres optionnels) :

| Besoin | Requête LogQL | Résultat |
|---|---|---|
| Logs d'un namespace | `{namespace="kps-tasks"}` | Tous les logs des pods du namespace applicatif |
| Logs d'un pod précis | `{namespace="kps-tasks", pod="kps-tasks-api-blue-5fb6d8bdfb-xv7jt"}` | Uniquement la version `blue` |
| Logs d'une application | `{app="kps-tasks-api"}` | Les deux versions (blue + green) réunies via le label commun `app` |
| Logs contenant une erreur | `{namespace="kps-tasks"} \|= "404"` | Filtre les lignes contenant le texte `404`, peu importe le pod |

Exemple de logs applicatifs obtenus (voir [`evidence/loki-logs.txt`](../../evidence/loki-logs.txt)) :
```
2026-09-09 12:30:02,798 INFO app GET /health -> 200 24.18ms
INFO:     10.42.0.1:58848 - "GET /health HTTP/1.1" 200 OK
```
Chaque requête applicative produit deux lignes de log (le middleware maison de l'application, puis le log natif d'Uvicorn) — normal, ce sont deux loggers différents dans le même processus.

**Cas particulier — PostgreSQL** : aucune ligne de log sur la dernière heure (`kubectl logs postgres-... --since=1h` vide). Ce n'est pas un défaut de Promtail : PostgreSQL, par défaut, ne journalise pas chaque requête réussie — seulement les démarrages, arrêts et erreurs. L'absence de logs est donc le signe d'une base saine, pas d'une collecte cassée.

## Étape 9-10 — Déclencher une erreur applicative simple et la retrouver dans Loki

L'application expose `GET /tasks/{task_id}` qui répond `404 Not Found` si la tâche n'existe pas ([`app/main.py:109-118`](../../app/main.py)) — un moyen simple, sûr et réversible de générer une vraie erreur applicative sans rien casser.

```bash
curl http://169.58.11.221:30080/tasks/999999
# -> HTTP 404
```

Retrouvée dans Loki quelques secondes plus tard avec le filtre `{namespace="kps-tasks"} |= "404"` :
```
INFO:     10.42.0.1:43449 - "GET /tasks/999999 HTTP/1.1" 404 Not Found
2026-09-09 12:29:33,597 INFO app GET /tasks/999999 -> 404 136.88ms
```

## Questions intermédiaires (43-49)

**43. À quoi sert Loki ?**
C'est une base de données spécialisée dans le stockage et la recherche de logs. Contrairement à d'autres solutions (Elasticsearch), Loki n'indexe pas le contenu des logs lui-même, seulement leurs labels (namespace, pod, app...) — ce qui le rend beaucoup plus léger à faire tourner, au prix d'une recherche plein texte un peu plus lente sur de très gros volumes.

**44. À quoi sert Promtail ?**
C'est l'agent de collecte : installé en `DaemonSet` (un exemplaire par nœud), il lit les fichiers de logs de tous les conteneurs du nœud, ajoute les métadonnées Kubernetes utiles (namespace, pod, container) et pousse le tout vers Loki. Sans Promtail, Loki n'a rien à stocker.

**45. Quelle est la différence entre Prometheus et Loki ?**
Prometheus stocke des métriques (des nombres datés, ex : CPU à 15 %) ; Loki stocke des logs (du texte daté, ex : "GET /health -> 200"). Prometheus répond bien à "combien" et "quelle tendance", Loki répond bien à "que s'est-il passé exactement, avec quel message d'erreur".

**46. Pourquoi centraliser les logs ?**
Sans centralisation, il faut se connecter pod par pod (`kubectl logs`) pour chercher une erreur — impossible à grande échelle, et les logs disparaissent si le pod est recréé. Centralisés dans Loki, tous les logs de tous les pods (même ceux qui n'existent plus) restent consultables et filtrables depuis un seul endroit.

**47. Pourquoi les logs seuls ne suffisent-ils pas ?**
Les logs racontent des événements ponctuels mais ne montrent pas de tendance globale (ex : une dérive progressive de la mémoire) ni un signal continu pour déclencher une alerte automatique — c'est le rôle complémentaire des métriques (Prometheus) et des alertes (Alertmanager, Jour 4). Observabilité = métriques + logs + traces, chacun répondant à une question différente.

**48. Comment filtrer les logs d'un namespace ?**
Avec un sélecteur de label LogQL : `{namespace="kps-tasks"}`. C'est le filtre de base, quasi systématique en première ligne d'une requête LogQL.

**49. Comment retrouver une erreur applicative ?**
En combinant le sélecteur de namespace/pod/app avec un filtre de contenu : `{namespace="kps-tasks"} |= "ERROR"` ou, comme démontré ici, `|= "404"` — LogQL permet de chaîner plusieurs filtres (`|=` contient, `!=` ne contient pas) pour affiner la recherche.

## Résultat du jour

- Loki et Promtail installés et `Running`
- Source de données Loki ajoutée dans Grafana (Prometheus reste la source par défaut)
- Logs applicatifs consultables et filtrables par namespace, pod et application
- Une vraie erreur (`404` sur une tâche inexistante) déclenchée puis retrouvée dans Loki en quelques secondes
- **Prêt pour le Jour 4** (alertes Prometheus et Alertmanager).
