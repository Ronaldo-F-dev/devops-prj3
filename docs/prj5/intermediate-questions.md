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
