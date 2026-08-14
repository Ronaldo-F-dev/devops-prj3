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
