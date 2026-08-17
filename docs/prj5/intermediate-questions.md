# Questions intermédiaires — Projet 5

## Jour 2 — Déploiement Kubernetes de l'application

### 21. Quelle est la différence entre un Pod et un Deployment ?

Un **Pod** est l'unité d'exécution la plus petite de Kubernetes : un ou plusieurs conteneurs qui partagent le même réseau et le même stockage. Un Pod créé seul est **éphémère** : s'il est supprimé ou plante, rien ne le recrée.

Un **Deployment** est un objet de niveau supérieur qui décrit l'état désiré (quelle image, combien de réplicas) et **maintient** ce nombre de Pods en permanence — via un `ReplicaSet` créé automatiquement. C'est le Deployment qui recrée un Pod supprimé, gère les mises à jour progressives (rollout) et permet un retour en arrière (rollback).

### 22. Pourquoi ne pas créer uniquement un Pod ?

Un Pod seul n'a aucune capacité d'auto-réparation : s'il est supprimé (par erreur, par une panne de nœud, etc.), il disparaît définitivement. C'est justement une contrainte non négociable de ce projet ("Ne pas déployer de Pods autonomes directement") — tout doit passer par un Deployment pour bénéficier du self-healing, qui est l'une des raisons principales de migrer vers Kubernetes.

### 23. À quoi sert un Service ?

Un Service donne un point d'accès **stable** (IP et nom DNS fixes) vers un ensemble de Pods sélectionnés par leurs labels. Les Pods, eux, changent d'IP à chaque redémarrage — sans Service, il faudrait retrouver la nouvelle IP à chaque fois. Le Service résout aussi ce problème pour la communication interne au cluster (ex. l'application vers PostgreSQL, au Jour 3), via la résolution DNS interne.

### 24. Pourquoi l'image doit-elle être taguée ?

Mêmes raisons qu'au Projet 4 (voir `docs/prj4/intermediate-questions.md`, question 21) : un tag précis (ici `commit-ed490e5`) garantit que Kubernetes déploie exactement la version voulue, de façon reproductible — jamais `latest`, qui ne permet ni de savoir quelle version tourne, ni de revenir en arrière de façon fiable.

### 25. Comment vérifier les logs d'un Pod ?

```bash
kubectl logs <nom-du-pod> -n <namespace>
# ou, en ciblant par label plutôt que par nom exact (utile si le nom change à chaque redéploiement) :
kubectl logs -n <namespace> -l app=<label>
```

C'est la première commande à utiliser pour diagnostiquer un Pod qui ne répond pas comme prévu — avant `describe`, avant `exec`, les logs de l'application elle-même donnent souvent directement la cause (voir le cas réel de ce Jour 2 : `/health` en `degraded`, avec le message d'erreur PostgreSQL explicite dans les logs).

## Jour 3 — ConfigMap, Secret, PostgreSQL et communication interne

### 36. Quelle est la différence entre un ConfigMap et un Secret ?

Les deux stockent de la configuration en dehors de l'image et du code, mais un `ConfigMap` est pensé pour des valeurs **non sensibles**, stockées en clair et lisibles directement (`kubectl get configmap -o yaml` les affiche telles quelles). Un `Secret` est pensé pour des valeurs **sensibles** (mots de passe, tokens) : ses valeurs sont encodées en base64 dans l'API — voir question 39 pour la nuance importante sur ce que ça protège vraiment.

### 37. Pourquoi PostgreSQL ne doit-il pas être exposé publiquement ?

Une base de données accessible directement depuis Internet est une cible directe pour des tentatives de connexion automatisées (scan de ports, brute-force). Elle ne devrait être joignable que par les services qui en ont réellement besoin — ici, uniquement l'application, depuis l'intérieur du cluster. C'est pour ça que le Service `postgres` est resté en `ClusterIP` (le type par défaut) plutôt qu'en `NodePort` ou `LoadBalancer`.

### 38. Pourquoi l'application utilise-t-elle le nom du Service PostgreSQL plutôt qu'une IP ?

Parce que l'IP d'un Pod change à chaque fois qu'il est recréé (redémarrage, mise à jour, panne), alors que le nom du Service, lui, ne change jamais. Coder une IP en dur casserait la connexion au premier redémarrage du pod PostgreSQL. Le nom du Service, résolu via DNS interne, reste une référence stable quoi qu'il arrive aux pods derrière.

### 39. Un Secret Kubernetes est-il automatiquement sécurisé ?

Non — c'est un point que le brief souligne explicitement. Un `Secret` encode ses valeurs en **base64**, pas en chiffrement : n'importe qui avec un accès en lecture à l'objet peut décoder la valeur instantanément (`echo <valeur> | base64 -d`). La protection réelle vient des permissions RBAC de Kubernetes (qui peut lire quel Secret), pas du format de stockage. Pour une vraie confidentialité en production, il faut une solution de chiffrement au repos (chiffrement de l'`etcd` sous-jacent) ou un gestionnaire de secrets externe (Vault, par exemple) — un `Secret` reste préférable à un `ConfigMap` pour ce type de donnée, mais il ne suffit pas seul.

### 40. Comment vérifier qu'une variable d'environnement est correctement injectée dans un pod ?

```bash
kubectl exec <pod> -n <namespace> -- env | grep <NOM_VARIABLE>
# ou, sans lister toutes les variables (utile pour ne pas afficher un secret en clair dans un terminal partagé) :
kubectl exec <pod> -n <namespace> -- printenv <NOM_VARIABLE>
```

On peut aussi remonter à la source, avant même de regarder dans le pod : `kubectl describe pod <pod> -n <namespace>` affiche la section `Environment`, qui montre d'où vient chaque variable (valeur en dur, `ConfigMapKeyRef`, `SecretKeyRef`) — utile pour vérifier la configuration sans avoir besoin d'un accès `exec` au conteneur.

## Jour 4 — Probes, exposition externe, rollout et rollback

### 51. Quelle est la différence entre `readinessProbe` et `livenessProbe` ?

La `readinessProbe` répond à la question *"ce pod peut-il recevoir du trafic maintenant ?"* — si elle échoue, le pod est retiré des endpoints du Service, sans redémarrage. La `livenessProbe` répond à *"ce processus est-il encore vivant, ou faut-il le redémarrer ?"* — si elle échoue de façon répétée, Kubernetes tue et recrée le conteneur. Testé en conditions réelles dans ce projet (voir `docs/prj5/probes-and-exposure.md`) : les deux échouent de façon visiblement différente — l'une bloque un rollout sans rien casser, l'autre déclenche des redémarrages en boucle.

### 52. Que se passe-t-il si la `readinessProbe` échoue ?

Le pod reste `Running`, mais passe à `0/1` (`NOT READY`) et est retiré des `endpoints` du Service — il ne reçoit plus aucune requête. S'il s'agit d'un nouveau pod en cours de rollout, l'ancien pod (encore sain) continue de servir tout le trafic tant que le nouveau n'est pas devenu `Ready` : le rollout reste bloqué, mais la production n'est jamais interrompue.

### 53. Que se passe-t-il si la `livenessProbe` échoue ?

Une fois le nombre d'échecs consécutifs atteint (`failureThreshold`), Kubernetes tue le conteneur et le recrée (événement `Killing` puis `Started`) — le compteur `RESTARTS` du pod augmente. Si la cause de l'échec persiste (comme dans le test de ce projet, un chemin d'URL inexistant), le pod redémarre en boucle sans jamais se stabiliser.

### 54. Quelle est la différence entre `ClusterIP`, `NodePort` et `Ingress` ?

- **`ClusterIP`** (par défaut) : accessible uniquement depuis l'intérieur du cluster. Utilisé ici pour PostgreSQL (Jour 3) — jamais exposé à l'extérieur.
- **`NodePort`** : ouvre un port fixe (30000-32767) sur **chaque nœud** du cluster, redirigé vers le Service. Simple à comprendre, mais peu élégant en production (port non standard, pas de nom de domaine, pas de TLS natif). Utilisé ici pour exposer l'application (port `30080`).
- **`Ingress`** : un routeur HTTP/HTTPS de niveau supérieur (Traefik, déjà présent dans k3s par défaut — vu au Jour 1), qui permet de router plusieurs applications sur les ports standards 80/443 via des noms de domaine ou des chemins, avec gestion de certificats TLS. Plus proche d'un modèle de production, mais plus de concepts à maîtriser — non utilisé dans ce projet (NodePort imposé), réservé en bonus.

### 55. Comment vérifier un rollout ?

```bash
kubectl rollout status deployment/<nom> -n <namespace>
kubectl rollout history deployment/<nom> -n <namespace>
```

La première commande suit l'avancement en direct (utile juste après un `kubectl apply` qui change l'image). La seconde liste les révisions passées — utile pour savoir vers quelle révision revenir avant un rollback.

### 56. Comment effectuer un rollback Kubernetes ?

```bash
kubectl rollout undo deployment/<nom> -n <namespace>
# ou vers une révision précise :
kubectl rollout undo deployment/<nom> -n <namespace> --to-revision=<numéro>
```

Point important découvert en le testant (voir `docs/prj5/probes-and-exposure.md`) : `kubectl rollout undo` change l'état réel du cluster mais **pas** le fichier manifeste local ni l'annotation utilisée par `kubectl apply` — il faut penser à remettre le fichier versionné en cohérence avec l'état réel après coup, sinon un futur `apply` réintroduirait la version qu'on vient d'annuler.
