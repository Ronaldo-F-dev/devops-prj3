# Jour 4 — Alertes Prometheus et Alertmanager

Document détaillé du Jour 4. Résumé condensé dans [`RUNBOOK.md`](RUNBOOK.md).

## Objectif du jour

Créer des alertes réellement utiles (pas juste présentes), vérifier qu'elles remontent jusqu'à Alertmanager, et en déclencher au moins une pour de vrai.

## Comment fonctionne une règle d'alerte (question 1)

Une règle d'alerte Prometheus a trois parties :
1. Une requête PromQL (`expr`) qui renvoie une valeur — l'alerte est candidate dès que cette requête renvoie un résultat.
2. Une durée (`for`) — la requête doit rester vraie pendant *toute* cette durée avant que l'alerte passe réellement en `firing`. Avant ça, elle est en `pending`. Ce délai évite de déclencher une alerte pour un pic d'une seconde sans conséquence.
3. Prometheus évalue ces règles en continu et transmet toute alerte en `firing` à Alertmanager, qui décide ensuite quoi en faire (regrouper, notifier, ou ne rien faire de plus si aucun récepteur externe n'est configuré).

## Où vivent les règles : PrometheusRule

Le chart `kube-prometheus-stack` utilise l'opérateur Prometheus, qui charge ses règles depuis des ressources Kubernetes `PrometheusRule` (pas des fichiers YAML directement sur disque). Condition impérative : chaque `PrometheusRule` doit porter le label `release: kube-prometheus-stack`, car c'est exactement le `ruleSelector` configuré sur l'objet `Prometheus` :

```bash
kubectl get prometheus -n monitoring -o jsonpath='{.items[0].spec.ruleSelector}'
# {"matchLabels":{"release":"kube-prometheus-stack"}}
```

Sans ce label, la règle est créée dans Kubernetes mais silencieusement ignorée par Prometheus — piège classique.

## Les 4 règles créées (3 obligatoires + 1 bonus)

Appliquées directement avec `kubectl apply` (pas via ArgoCD/GitOps : la stack de supervision, comme au Jour 1-3, est gérée hors du dépôt GitOps du Projet 6, qui ne couvre que l'application).

### [`monitoring/alerts/pod-alerts.yaml`](../../monitoring/alerts/pod-alerts.yaml)

| Alerte | Requête | Seuil | Pourquoi ce seuil |
|---|---|---|---|
| `KpsTaskApiPodNotReady` | `kube_pod_status_ready{namespace="kps-tasks", pod=~"kps-tasks-api-.*", condition="true"} == 0` | `for: 2m` | 2 minutes laisse le temps à un redémarrage normal de passer sans fausse alerte, tout en restant assez court pour réagir vite à un vrai problème. |
| `KpsTaskApiPodRestarting` | `increase(kube_pod_container_status_restarts_total{...}[15m]) > 0` | `for: 1m` | Un seul redémarrage suffit à être un signal ; la fenêtre de 15 min est celle recommandée pour ce type de compteur cumulatif (`increase`), le `for: 1m` évite juste un faux déclenchement sur une évaluation isolée. |

### [`monitoring/alerts/app-alerts.yaml`](../../monitoring/alerts/app-alerts.yaml)

| Alerte | Requête | Seuil | Pourquoi ce seuil |
|---|---|---|---|
| `KpsTaskApiUnavailable` | `sum(kube_pod_status_ready{namespace="kps-tasks", pod=~"kps-tasks-api-.*", condition="true"}) == 0` | `for: 1m`, `severity: critical` | Différence volontaire avec `PodNotReady` : ici on somme *tous* les pods (blue + green) — l'alerte ne se déclenche que si aucun des deux n'est prêt, c'est-à-dire que l'application entière est injoignable, pas juste une version. `critical` plutôt que `warning` car c'est une vraie panne utilisateur. |

### [`monitoring/alerts/resource-alerts.yaml`](../../monitoring/alerts/resource-alerts.yaml)

| Alerte | Requête | Seuil | Pourquoi ce seuil |
|---|---|---|---|
| `KpsTaskApiHighCPU` | `sum by (pod) (rate(container_cpu_usage_seconds_total{...}[5m])) > 0.05` | `for: 2m` | L'usage normal mesuré au Jour 2 est d'environ 10 millicoeurs (0.01) par pod. Un seuil à 50 millicoeurs (0.05) représente déjà 5x la normale — assez sensible pour être démontrable avec une charge simple, tout en restant nettement au-dessus du bruit de fond. Dans un contexte de production réel, ce seuil serait calé sur les limites de ressources du déploiement plutôt que sur l'usage observé. |

## Vérification dans Prometheus (tâche 6)

```bash
curl -s http://localhost:30090/api/v1/rules
```

Les 4 règles apparaissent, groupées par fichier (`kps-tasks-api.pods`, `kps-tasks-api.availability`, `kps-tasks-api.resources`), toutes `health: ok`, `state: inactive` avant tout déclenchement — c'est-à-dire chargées sans erreur de syntaxe et prêtes à évaluer.

## Vérification qu'elles atteignent Alertmanager (tâche 7)

```bash
curl -s http://localhost:30093/api/v2/status
```

Alertmanager répond (`cluster.status: disabled` — normal en instance unique, pas de cluster HA nécessaire ici) et détient déjà une configuration active. Aucun récepteur externe (email/Slack) n'a été configuré — optionnel selon le brief, la preuve dans Prometheus/Alertmanager suffit pour ce projet.

## Déclenchement volontaire d'une alerte réelle (tâches 8-9)

Plutôt qu'une simulation artificielle, une vraie charge a été générée sur l'endpoint `GET /tasks` du pod actif (`blue`, celui que sélectionne le Service — voir Projet 6) :

```bash
for i in $(seq 1 40); do ( for j in $(seq 1 200); do curl -s -o /dev/null http://169.58.11.221:30080/tasks; done ) & done; wait
```

Résultat observé :

| Moment | CPU pod `blue` (rate 2-5m) |
|---|---|
| Avant charge | ~0,010 cœur (normal) |
| Pendant la charge | ~1,86 puis 1,23 cœur |
| Après arrêt de la charge | retour progressif vers la normale |

`KpsTaskApiHighCPU` est passée `inactive` → `pending` → **`firing`** dans Prometheus, puis apparaît `active` dans `GET /api/v2/alerts` d'Alertmanager (`receivers: [{"name": "null"}]` — le récepteur par défaut du chart, aucune notification externe configurée). Détail complet (JSON de l'alerte) : [`evidence/alert-triggered.txt`](../../evidence/alert-triggered.txt).

Ce test a aussi validé, en négatif, un point important : la charge générée n'a fait redémarrer aucun pod (0 redémarrage avant/après) — l'application encaisse cette charge sans planter, ce qui est en soi une observation positive sur sa robustesse.

## Questions intermédiaires (60-66)

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

## Résultat du jour

- 4 règles d'alerte créées et chargées sans erreur (3 obligatoires + 1 bonus)
- Vérifiées dans Prometheus (`/api/v1/rules`) et Alertmanager (`/api/v2/status`)
- Une alerte réellement déclenchée par une charge applicative réelle, observée `firing` dans Prometheus puis `active` dans Alertmanager
- Seuils documentés et justifiés
- **Prêt pour le Jour 5** (incident déclenché par le formateur, diagnostic, rapport, mini-soutenance).
