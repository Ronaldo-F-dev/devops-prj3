# Projet 5 — OpsReady-05 : migration Docker Compose vers Kubernetes (k3s)

Résumé général du brief (`Project5_OpsReady05_Brief_FR.pdf`), avant de commencer le travail jour par jour.

## Objectif

Passer d'un déploiement Docker Compose (Projet 4) à un déploiement Kubernetes simple, avec **k3s** (distribution Kubernetes légère). Pas encore d'ArgoCD ni de GitOps — ça viendra au Projet 6. L'objectif est une base solide sur les objets essentiels (Namespace, Deployment, Service, ConfigMap, Secret, probes) et les commandes de diagnostic, pas l'expertise Kubernetes complète.

## Contexte

Le déploiement Docker Compose actuel fonctionne mais reste limité : lié à un seul serveur, redémarrage manuel, pas de scalabilité structurée, self-healing faible, orchestration manuelle. Objectif du client : une première migration vers Kubernetes pour se rapprocher d'une architecture moderne.

## Application

Toujours KPS Tasks API — même image Docker, même registre (GHCR), mêmes endpoints `/health`/`/version`. **Contrainte importante : l'application ne doit plus tourner via Docker Compose**, elle doit être déployée avec des manifestes Kubernetes.

## Infrastructure

- **VPS 1** (le même que d'habitude, `169.58.11.221`) : héberge k3s, le cluster, l'application, PostgreSQL (dans Kubernetes pour ce lab).
- **VPS 2 / GitHub** : registre Docker (déjà en place, Projet 4), pipeline CI existant. Le déploiement Kubernetes reste manuel (`kubectl apply`) pour ce projet — ArgoCD viendra au Projet 6.

## Choix PostgreSQL : dans Kubernetes (recommandé par le brief)

Option A retenue : PostgreSQL déployé **à l'intérieur** de Kubernetes (Deployment + Service + Secret + volume), pour voir concrètement comment une application communique avec sa base à l'intérieur du cluster. Le brief est clair : c'est un choix pédagogique, pas nécessairement le bon choix de production (persistance, sauvegardes, monitoring à maîtriser d'abord).

## Contraintes non négociables

- Jamais de Pod autonome — toujours via un Deployment
- Namespace dédié obligatoire
- Jamais de secret en clair dans un manifeste versionné
- PostgreSQL jamais exposé publiquement
- Pas d'ArgoCD ni de Helm à ce stade (Helm en bonus seulement)
- Chaque objet Kubernetes documenté, chaque commande `kubectl` expliquée
- Prouver qu'un pod supprimé est recréé automatiquement (self-healing)
- Diagnostiquer au moins une vraie erreur de configuration

## Découpage des 5 jours

| Jour | Objectif |
|---|---|
| **1** | Installer k3s sur le VPS, configurer `kubectl`, créer le namespace applicatif |
| **2** | Premiers manifestes : Namespace, Deployment, Service pour l'application |
| **3** | ConfigMap, Secret, PostgreSQL dans Kubernetes, communication interne (DNS de service) |
| **4** | `readinessProbe`, `livenessProbe`, exposition externe (NodePort obligatoire, Ingress en bonus), rollout/rollback |
| **5** | Reconstruction complète depuis zéro, incident déclenché par le formateur, mini-soutenance |

## Livrables finaux attendus

- Manifestes dans `k8s/` : namespace, deployment/service app, configmap, secret, deployment/service/secret/pvc postgres, probes, NodePort/Ingress
- Docs dans `docs/prj5/` : installation k3s, déploiement app, configmap/secret/postgres, probes/exposition, diagnostic, rapport d'incident, soutenance
- Preuves dans `evidence/` : nodes, pods, health, recréation de pod, rollout, diagnostic d'incident

## Différence clé avec le Projet 4

Le Projet 4 automatisait le déploiement d'un **serveur unique** via Docker Compose (SSH, `docker compose up -d`, rollback maison via scripts). Le Projet 5 délègue cette orchestration à **Kubernetes lui-même** : c'est k3s qui recrée les pods, gère les probes, fait les rollouts/rollbacks nativement — on écrit des manifestes déclaratifs au lieu de scripts impératifs.
