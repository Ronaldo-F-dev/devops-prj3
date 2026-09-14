# Questions intermédiaires — Projet 7 (toutes, questions 11 à 66)

Toutes les réponses aux questions intermédiaires du brief, rassemblées ici en un seul endroit pour la soutenance — chacune reste aussi disponible dans le document détaillé de son jour (lien en tête de section), mais ce fichier évite d'avoir à sauter entre plusieurs documents pendant la présentation.

---

## Jour 1 — Installation de la stack (questions 11-16)

Détail complet : [`monitoring-installation.md`](monitoring-installation.md)

**11. À quoi sert Prometheus ?**
C'est une base de données de séries temporelles spécialisée dans les métriques : il interroge périodiquement ("scrape") des cibles (pods, nœuds, kube-state-metrics...) via HTTP, stocke les valeurs numériques avec un horodatage, et permet de les interroger avec son langage `PromQL` (ex : évolution du CPU sur 1h).

**12. À quoi sert Grafana ?**
C'est l'interface de visualisation : il se connecte à une ou plusieurs sources de données (ici Prometheus, et Loki au Jour 3) et affiche les données sous forme de dashboards (graphiques, jauges, tableaux). Grafana ne stocke pas les métriques lui-même, il les interroge à la demande.

**13. À quoi sert Alertmanager ?**
Prometheus peut évaluer des règles d'alerte (ex : "CPU > 90% pendant 5 min") et, quand une règle est vraie, envoie une alerte à Alertmanager. Celui-ci ne décide pas *quand* alerter (c'est Prometheus), mais gère *ce qui se passe ensuite* : regrouper les alertes similaires, éviter les doublons, les envoyer vers un canal de notification (email, Slack, etc.).

**14. À quoi sert kube-state-metrics ?**
Prometheus sait scraper des métriques exposées en HTTP, mais l'API Kubernetes ne parle pas nativement le format Prometheus. kube-state-metrics fait le pont : il lit l'état des objets Kubernetes (pods, deployments, nombre de replicas désirés vs disponibles...) via l'API et les republie au format que Prometheus sait lire.

**15. Pourquoi utiliser un namespace dédié ?**
Isolation : séparer les objets de supervision de l'application (`kps-tasks`) et de GitOps (`argocd`), pour pouvoir gérer, mettre à jour ou supprimer la stack de supervision sans aucun risque de toucher au reste du cluster.

**16. Pourquoi utiliser Helm pour installer cette stack ?**
`kube-prometheus-stack` représente des dizaines de ressources Kubernetes interdépendantes (CRDs, Deployments, Services, ConfigMaps, RBAC...). Helm empaquette tout cela dans un "chart" versionné, avec des valeurs personnalisables (`values.yaml`) sans toucher aux manifestes bruts, et permet une désinstallation propre (`helm uninstall`) en une commande — écrire et maintenir cela à la main serait à la fois long et source d'erreurs.

---

## Jour 2 — Dashboards Grafana (questions 27-32)

Détail complet : [`grafana-dashboards.md`](grafana-dashboards.md)

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

---

## Jour 3 — Loki, Promtail et logs (questions 43-49)

Détail complet : [`loki-promtail-logs.md`](loki-promtail-logs.md)

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

---

## Jour 4 — Alertes Prometheus et Alertmanager (questions 60-66)

Détail complet : [`alerting-rules.md`](alerting-rules.md)

**60. Qu'est-ce qui rend une alerte utile ?**
Qu'elle soit liée à un symptôme réel et qu'elle implique une action claire quand elle se déclenche. Une alerte qu'on ignore systématiquement, ou dont on ne sait pas quoi faire, n'est pas utile — elle est juste du bruit.

**61. Pourquoi éviter trop d'alertes ?**
La fatigue d'alerte (« alert fatigue ») : à force de recevoir des alertes non pertinentes ou trop sensibles, on finit par toutes les ignorer, y compris les vraies urgences. Mieux vaut peu d'alertes bien choisies que beaucoup d'alertes approximatives.

**62. Quelle est la différence entre warning et critical ?**
`warning` signale une dérive à surveiller mais qui ne casse rien pour l'instant (ex : CPU élevé). `critical` signale un impact utilisateur réel et immédiat (ex : application indisponible). Dans ce projet, `KpsTaskApiUnavailable` est `critical`, les trois autres sont `warning`.

**63. Pourquoi une alerte doit-elle être actionnable ?**
Parce que le but d'une alerte n'est pas de constater un fait mais de déclencher une réaction humaine. Une alerte sans action possible (ou sans piste de diagnostic, comme le champ `description` de chaque règle ici) laisse la personne qui la reçoit démunie face à l'urgence.

**64. À quoi sert Alertmanager ?**
Une fois qu'une alerte est en `firing` côté Prometheus, Alertmanager reçoit cette information et gère tout ce qui concerne sa diffusion : regrouper les alertes similaires (éviter le spam), les faire taire temporairement (silence), les router vers le bon canal de notification. Prometheus décide *quand* alerter, Alertmanager décide *quoi en faire ensuite*.

**65. Que signifie le champ `for` dans une règle d'alerte ?**
La durée pendant laquelle la condition de l'alerte (`expr`) doit rester vraie sans interruption avant que Prometheus la fasse réellement passer en `firing`. Avant l'expiration de ce délai, l'alerte est visible en `pending` mais n'est pas encore transmise à Alertmanager.

**66. Pourquoi documenter les seuils ?**
Un seuil sans justification est arbitraire et personne (y compris soi-même six mois plus tard) ne sait s'il faut le resserrer, le desserrer, ou le supprimer. Documenter le "pourquoi" (ici : usage normal mesuré au Jour 2, comparé au seuil choisi) permet de faire évoluer les alertes en connaissance de cause plutôt qu'au hasard.

---

## Jour 5 — Incident : pas de "questions intermédiaires" séparées

Le brief remplace les questions par une démarche de diagnostic structurée en 10 étapes (numérotées 67-76 dans le brief), suivie et documentée pas à pas dans [`incident-report.md`](incident-report.md) : noter le symptôme, vérifier le dashboard application, le dashboard infrastructure, les alertes, les logs Loki, l'état Kubernetes, ArgoCD, identifier la cause probable, appliquer un correctif, rédiger le rapport. Le support de soutenance ([`soutenance.md`](soutenance.md)) reprend cette même démarche pour l'oral.

---

## Note sur la numérotation du brief

Les numéros ne sont pas continus (11-16, puis 27-32, etc.) parce que le brief numérote en réalité *toutes* les lignes de chaque jour dans un seul compteur global : les 10 "tâches attendues" de chaque jour occupent les numéros intermédiaires (17-26 pour le Jour 2, 33-42 pour le Jour 3, 50-59 pour le Jour 4) avant les questions proprement dites. Ces tâches ne sont pas des questions à répondre par écrit — ce sont les actions déjà réalisées et documentées dans le récit de chaque jour (`RUNBOOK.md` et le document détaillé correspondant).
