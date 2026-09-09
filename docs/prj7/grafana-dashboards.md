# Jour 2 — Dashboards Grafana infrastructure et Kubernetes

Document détaillé du Jour 2. Résumé condensé dans [`RUNBOOK.md`](RUNBOOK.md).

## Objectif du jour

Créer deux dashboards Grafana exploitables : un pour l'infrastructure du cluster, un pour l'application `kps-tasks-api`. Un dashboard ne sert à rien si on ne sait pas ce qu'on regarde — chaque panel ci-dessous est donc accompagné de la métrique exacte et de ce qu'elle signifie.

## Étape 1 — Connexion à Grafana

`http://169.58.11.221:30030`, utilisateur `admin`, mot de passe lu sur le VPS (`~/.grafana-admin-password`, jamais affiché ni committé).

## Étape 2 — Vérification de la source de données Prometheus

Le chart `kube-prometheus-stack` provisionne automatiquement une source de données Prometheus au démarrage de Grafana — aucune configuration manuelle n'a été nécessaire.

```bash
curl -u admin:<mot de passe> http://localhost:30030/api/datasources
```

Résultat : une source `Prometheus` (`uid: prometheus`, `isDefault: true`) pointant vers `http://kube-prometheus-stack-prometheus.monitoring:9090/`, plus une source `Alertmanager` (utile au Jour 4).

À noter : le chart provisionne aussi, par défaut, une vingtaine de dashboards communautaires ("Kubernetes / Compute Resources / ...", "Node Exporter / Nodes", "CoreDNS", "etcd"...). Ils existent déjà et peuvent être consultés, mais ne couvrent pas spécifiquement l'application `kps-tasks-api` — d'où la création des deux dashboards ci-dessous, volontairement ciblés et légers plutôt qu'un import générique de plus.

## Étape 3-4 — Création des deux dashboards

Créés via l'API HTTP de Grafana (`POST /api/dashboards/db`) à partir de fichiers JSON versionnés dans ce dépôt — reproductible sans reclic manuel, et cohérent avec l'approche "tout est dans un fichier" du reste du projet.

- [`dashboards/infrastructure-dashboard.json`](../../dashboards/infrastructure-dashboard.json)
- [`dashboards/application-dashboard.json`](../../dashboards/application-dashboard.json)

### Dashboard 1 — Infrastructure Kubernetes

`http://169.58.11.221:30030/d/opsready07-infra/opsready-07-infrastructure-kubernetes`

| Panel | Requête PromQL | Ce que ça veut dire |
|---|---|---|
| CPU des nodes (%) | `100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` | Part du temps où le CPU n'est PAS inactif, moyennée sur 5 min. On calcule l'inverse de l'inactivité car Prometheus expose le temps *idle*, pas l'usage direct. |
| RAM des nodes (%) | `(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100` | Part de la mémoire totale du nœud qui n'est plus disponible. |
| Disque utilisé (%) sur `/` | `100 - ((node_filesystem_avail_bytes{mountpoint="/"} * 100) / node_filesystem_size_bytes{mountpoint="/"})` | Part de l'espace disque racine occupée. |
| Nombre de pods (Running) | `count(kube_pod_status_phase{phase="Running"})` | Combien de pods tournent actuellement, tous namespaces confondus. |
| État des nodes (Ready) | `kube_node_status_condition{condition="Ready", status="true"}` | Vaut 1 si le nœud est prêt à recevoir des pods, sinon 0/absent. |
| Usage CPU par namespace | `sum by (namespace) (rate(container_cpu_usage_seconds_total{namespace!=""}[5m]))` | Additionne la consommation CPU de tous les conteneurs d'un même namespace — permet de voir si `monitoring` consomme plus que `kps-tasks`. |
| Usage RAM par namespace | `sum by (namespace) (container_memory_working_set_bytes{namespace!=""})` | Même logique pour la mémoire réellement utilisée (pas juste réservée). |
| Usage CPU par workload (table) | `sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{namespace!="", pod!=""}[5m]))` | Détail pod par pod, pour repérer un workload anormalement gourmand. |

### Dashboard 2 — Application KPS Tasks API

`http://169.58.11.221:30030/d/opsready07-app/opsready-07-application-kps-tasks-api`

| Panel | Requête PromQL | Ce que ça veut dire |
|---|---|---|
| Nombre de pods applicatifs | `count(kube_pod_info{namespace="kps-tasks", pod=~"kps-tasks-api-.*"})` | Compte les pods `kps-tasks-api-*` (blue + green) actuellement connus de Kubernetes. |
| État des pods (phase) | `kube_pod_status_phase{namespace="kps-tasks", pod=~"kps-tasks-api-.*", phase="Running"} == 1` | Liste les pods effectivement en phase `Running`. |
| Redémarrages (cumulés) | `kube_pod_container_status_restarts_total{namespace="kps-tasks", pod=~"kps-tasks-api-.*"}` | Compteur cumulé des redémarrages de conteneur depuis leur création — une valeur qui grimpe vite est un signal d'instabilité (`CrashLoopBackOff`). |
| Disponibilité (readiness) | `kube_pod_status_ready{namespace="kps-tasks", pod=~"kps-tasks-api-.*", condition="true"} == 1` | Un pod peut être `Running` sans être `Ready` (la probe de disponibilité échoue) — ce panel distingue les deux. |
| État des probes (containers ready) | `kube_pod_container_status_ready{namespace="kps-tasks", pod=~"kps-tasks-api-.*"} == 1` | Vue au niveau conteneur (et non pod) de la probe readiness. |
| Usage CPU par pod | `sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="kps-tasks", pod=~"kps-tasks-api-.*"}[5m]))` | Consommation CPU de chaque version (blue/green) — utile pour comparer leur charge réelle. |
| Usage RAM par pod | `sum by (pod) (container_memory_working_set_bytes{namespace="kps-tasks", pod=~"kps-tasks-api-.*"})` | Idem pour la mémoire. |
| Version active (replicas disponibles blue/green) | `kube_deployment_status_replicas_available{namespace="kps-tasks", deployment=~"kps-tasks-api-.*"}` | Indique combien de replicas sont disponibles pour chaque déploiement (`blue`/`green`) — se croise avec le sélecteur du Service `kps-tasks-api` (Projet 6) pour savoir laquelle des deux reçoit réellement le trafic. |

## Résultat observé (voir [`evidence/grafana-dashboards-queries.txt`](../../evidence/grafana-dashboards-queries.txt))

- CPU nodes : ~15,6 % — RAM nodes : ~32,2 % — disque `/` : ~17,8 % — 23 pods `Running` au total sur le cluster
- 2 pods applicatifs (`kps-tasks-api-blue`, `kps-tasks-api-green`), 0 redémarrage sur les deux, CPU ~0,01 cœur chacun, RAM ~125-126 Mi chacun
- Les deux déploiements ont 1/1 replica disponible — cohérent avec le mécanisme blue/green du Projet 6 (les deux versions tournent en parallèle, une seule reçoit le trafic via le sélecteur du Service)

## Questions intermédiaires (27-32)

**27. Quelle est la différence entre une métrique et un log ?**
Une métrique est un nombre daté (ex : "CPU à 15,6 % à 12h42"), compact et fait pour être agrégé/tracé dans le temps. Un log est un événement textuel daté (ex : "12h42 — erreur de connexion à la base"), riche en contexte mais impossible à agréger sous forme de courbe. Prometheus gère les métriques, Loki (Jour 3) gère les logs.

**28. Pourquoi suivre le CPU et la RAM ?**
Ce sont les deux ressources les plus souvent à l'origine d'une dégradation : un CPU saturé ralentit toutes les requêtes, une mémoire qui grimpe sans redescendre (fuite mémoire) finit par faire tuer le conteneur par Kubernetes (`OOMKilled`). Les suivre permet de voir venir un problème avant qu'il ne devienne un incident.

**29. Pourquoi suivre les redémarrages de pods ?**
Un pod qui redémarre régulièrement n'est presque jamais un hasard : cela signifie que le conteneur plante (bug, dépendance indisponible, probe qui échoue en boucle). Le compteur de redémarrages est souvent le premier signal visible d'une instabilité, avant même que l'utilisateur ne s'en plaigne.

**30. Quelle métrique peut indiquer un pod instable ?**
`kube_pod_container_status_restarts_total` qui augmente rapidement, combinée à `kube_pod_status_phase` qui alterne entre `Running` et autre chose, ou `kube_pod_container_status_ready` qui repasse à 0 régulièrement.

**31. Un dashboard suffit-il à détecter un incident ?**
Non. Un dashboard affiche un état à un instant donné mais ne prévient de rien tout seul — quelqu'un doit le regarder au bon moment. C'est le rôle des alertes (Jour 4, Alertmanager) : elles surveillent en continu et préviennent activement, le dashboard sert ensuite à comprendre et confirmer visuellement ce que l'alerte a détecté.

**32. Qu'est-ce qui rend une métrique utile pour une application ?**
Qu'elle soit directement reliée à un symptôme observable par l'utilisateur ou l'exploitant : le nombre de pods disponibles, les redémarrages, la latence ou le taux d'erreur en disent plus sur la santé réelle du service que, par exemple, une métrique bas niveau sans lien direct avec le comportement perçu.

## Résultat du jour

- Source de données Prometheus vérifiée (provisionnée automatiquement)
- Deux dashboards créés et fonctionnels, tous les panels vérifiés avec de vraies données
- Export JSON des deux dashboards versionné dans `dashboards/`
- **Prêt pour le Jour 3.**
