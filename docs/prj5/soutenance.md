# Support de soutenance — Projet 5 : OpsReady-05

Support pour une présentation de 10 à 15 minutes (Jour 5, Phase 3). Chaque section correspond à un point attendu du brief.

## 1. Contexte client

LogiCare Solutions a déjà une application conteneurisée avec CI/CD et déploiement automatisé (Projet 4), mais l'architecture reste limitée à un seul serveur, avec un self-healing faible et une orchestration manuelle. Objectif de ce projet : une première migration vers Kubernetes (k3s), pour disposer des bases essentielles avant d'introduire GitOps (Projet 6). Détail : `docs/prj5/overview.md`.

## 2. Architecture Kubernetes

```
Utilisateur externe
  → IP publique du VPS
  → NodePort (30080)
  → Service kps-tasks-api (ClusterIP + NodePort)
  → Pod kps-tasks-api
  → Service postgres (ClusterIP uniquement)
  → Pod postgres
  → PersistentVolumeClaim (local-path-provisioner)
```

Un seul nœud (`kps-vps`, control-plane), k3s comme distribution. Détail : `docs/prj5/k3s-installation.md`.

## 3. Objets créés et leur rôle

| Objet | Rôle |
|---|---|
| `Namespace kps-tasks` | Isole tous les objets du projet des namespaces système et de `default` |
| `Deployment kps-tasks-api` | Maintient le pod applicatif en état désiré, gère le self-healing et les rollouts |
| `Service kps-tasks-api` (NodePort) | Point d'accès stable, exposé à l'extérieur du cluster sur le port `30080` |
| `ConfigMap kps-tasks-api-config` | Configuration non sensible (nom de l'app, environnement, niveau de log, coordonnées PostgreSQL) |
| `Secret kps-tasks-api-secret` | `DATABASE_URL`, jamais en clair dans un fichier versionné |
| `Deployment postgres` | Base de données, à l'intérieur du cluster (choix pédagogique du brief) |
| `Service postgres` (ClusterIP) | Accès interne uniquement — jamais exposé publiquement |
| `Secret postgres-secret` | Identifiants PostgreSQL |
| `PersistentVolumeClaim postgres-pvc` | Stockage persistant des données, indépendant du cycle de vie des pods |

Explication ligne par ligne de chaque manifeste : `docs/prj5/k8s-manifests-reference.md`.

## 4. Rôle du Namespace

Isolation logique — sépare les objets applicatifs du reste du cluster (composants système de k3s : CoreDNS, Traefik, etc.), sans isolation réseau stricte par défaut. Toutes les commandes `kubectl` de ce projet ciblent explicitement `-n kps-tasks`.

## 5. Rôle du Deployment

Garantit qu'un nombre défini de pods (ici, 1 réplica) tourne en permanence : recrée automatiquement un pod supprimé ou en échec, gère les mises à jour progressives (rollout) et permet un retour en arrière (rollback). C'est ce qui distingue un déploiement Kubernetes d'un simple `Pod` autonome — contrainte non négociable du projet.

## 6. Rôle du Service

Fournit une adresse et un nom DNS stables vers un ensemble de pods, alors que les pods eux-mêmes changent d'IP à chaque recréation. Deux Services dans ce projet, avec des types différents et volontaires : `ClusterIP` pour PostgreSQL (interne uniquement), `NodePort` pour l'application (accès externe).

## 7. Gestion de la configuration

Séparation stricte entre non sensible (`ConfigMap`) et sensible (`Secret`) — détail et raisons : `docs/prj5/configmap-secret-postgres.md`.

## 8. Gestion des Secrets

Deux Secrets réels créés directement sur le cluster (`kubectl create secret`), jamais écrits en clair dans un fichier versionné — seuls des fichiers `.example.yaml` avec des valeurs `REPLACE_ME` sont commités. Point important à savoir expliquer : un `Secret` Kubernetes encode en base64, ce n'est pas un chiffrement (question 39, `docs/prj5/intermediate-questions.md`).

## 9. Probes

`readinessProbe` sur `/health` (retire le pod du trafic si la base de données ne répond pas) et `livenessProbe` sur `/` (vérifie seulement que le processus répond, volontairement indépendant de la base de données — pour éviter des redémarrages inutiles en cas de panne PostgreSQL passagère). Les deux ont été testées en les cassant volontairement : détail complet, avec les comportements observés, dans `docs/prj5/probes-and-exposure.md`.

## 10. Exposition externe

`NodePort` (port `30080`), choisi plutôt qu'`Ingress` conformément à la recommandation du brief pour bien comprendre le `Service` avant d'ajouter une couche de routage supplémentaire.

## 11. Incident diagnostiqué

Trois incidents réels rencontrés et corrigés pendant le projet (comportement de `kubectl` sous k3s, concaténation YAML invalide, absence d'initialisation du schéma PostgreSQL) : `docs/prj5/incident-report.md`. Le scénario déclenché par le formateur (Phase 2) sera diagnostiqué en direct avec la méthode et la grille de lecture de `docs/prj5/diagnostic-kubernetes.md`.

## 12. Limites de ce premier déploiement Kubernetes

- Un seul nœud : aucune haute disponibilité réelle, une panne du VPS arrête tout
- PostgreSQL dans Kubernetes, avec un stockage `local-path` — pas de sauvegarde automatisée, pas de réplication
- Déploiement manuel (`kubectl apply`), pas encore de synchronisation automatique avec Git
- Un seul niveau d'historique de rollback (celui de Kubernetes lui-même, limité par `revisionHistoryLimit`)
- `NodePort` plutôt qu'`Ingress` : pas de nom de domaine, pas de TLS, pas de règles de routage par chemin

## 13. Améliorations possibles avant le GitOps

- **Ingress** avec Traefik (déjà installé par k3s) pour un routage HTTP propre et un futur support TLS
- **Synchronisation automatique** des manifestes depuis Git — exactement ce qu'apporte ArgoCD (Projet 6)
- **Sauvegardes régulières** du volume PostgreSQL, indépendantes du cluster
- **Helm** pour packager les manifestes si leur nombre augmente (explicitement hors périmètre de ce projet, autorisé en bonus)
- **Limites de ressources** (`requests`/`limits`) sur les conteneurs, absentes ici par simplicité, indispensables dès qu'un cluster héberge plusieurs applications
