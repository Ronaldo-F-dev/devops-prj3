# Projet 6 — OpsReady-06 : GitOps avec ArgoCD

Résumé général du brief (`Projet6_OpsReady06_Brief_FR.pdf`), avant de commencer le travail jour par jour.

## Objectif

Arrêter de piloter Kubernetes à la main avec `kubectl apply` (Projet 5) et laisser **Git devenir la source de vérité** : ArgoCD surveille un dépôt Git et synchronise en permanence le cluster avec ce qu'il y trouve. Comprendre concrètement la différence entre un pipeline qui *pousse* (`kubectl apply` depuis la CI) et un outil GitOps qui *tire* (ArgoCD observe Git, applique lui-même).

## Contexte

Le déploiement Kubernetes du Projet 5 fonctionne, mais personne n'est jamais sûr de la version réellement déployée, des changements sont faits directement dans le cluster (dérive possible entre Git et la réalité), et les rollbacks restent mal structurés. Objectif client : adopter GitOps pour que Git seul décide de l'état du cluster.

## Changement structurel majeur : deux dépôts distincts

- **Dépôt applicatif** (celui-ci, `devops-prj3`) : code, `Dockerfile`, tests, pipeline CI — construit et pousse toujours l'image Docker, exactement comme au Projet 4.
- **Nouveau dépôt GitOps** (`kps-tasks-gitops`, à créer) : uniquement les manifestes Kubernetes, organisés par environnement, plus la configuration blue/green. C'est ce dépôt qu'ArgoCD surveille — **plus aucun `kubectl apply` manuel pour les changements applicatifs courants** une fois ArgoCD en place.

## Contraintes non négociables

- Jamais de `kubectl apply` pour un changement applicatif courant une fois ArgoCD en place (seule exception : provoquer un drift volontairement, pour la démonstration)
- Jamais de modification directe du cluster, sauf pour démontrer un drift
- Dépôt applicatif et dépôt GitOps strictement séparés
- Images toujours taguées, jamais `latest`
- Jamais de vrai secret en clair dans Git (même dans le dépôt GitOps)
- Savoir expliquer *push vs pull*, ce qu'est un *drift*, démontrer synchronisation, blue/green et rollback

## Découpage des 5 jours

| Jour | Objectif |
|---|---|
| **1** | Concepts GitOps, création du dépôt GitOps, installation d'ArgoCD sur k3s |
| **2** | Connexion d'ArgoCD au dépôt GitOps, création de l'Application ArgoCD, première synchronisation manuelle |
| **3** | Changement de version piloté depuis Git, synchronisation automatisée, provoquer et corriger un drift |
| **4** | Blue/green simple : deux Deployments (blue/green) dans le même namespace, bascule via le sélecteur du Service |
| **5** | Démo complète + drift déclenché par le formateur + démo blue/green + incident + mini-soutenance |

## Livrables finaux attendus

- Dépôt GitOps séparé, manifestes organisés
- Installation et Application ArgoCD documentées
- Preuves : synchronisation, changement de version, drift détecté/corrigé, bascule blue/green, rollback
- ADR blue/green (`docs/adr/ADR-002-blue-green-strategy.md`)
- Rapport d'incident, support de soutenance

## Différence clé avec le Projet 5

Le Projet 5 déployait manuellement (`kubectl apply -f k8s/`) — chaque changement était un acte volontaire et immédiat. Le Projet 6 délègue cet acte à ArgoCD : **committer dans Git devient le seul geste de déploiement**, et un écart entre Git et le cluster (drift) devient quelque chose qu'on peut désormais détecter et corriger, plutôt qu'une réalité invisible.
