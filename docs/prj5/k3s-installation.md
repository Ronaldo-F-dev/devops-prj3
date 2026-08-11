# Installation de k3s — Jour 1

Ce document trace, étape par étape, l'installation de k3s sur le VPS 1 et la configuration de `kubectl`. Chaque commande exécutée est notée avec son résultat.

## 1. Préparation du VPS (tâche 1) et vérification des ressources (tâche 2)

Vérifications faites avant d'installer quoi que ce soit :

| Vérification | Commande | Résultat |
|---|---|---|
| CPU disponible | `nproc` | 6 cœurs |
| RAM disponible | `free -h` | 11 Gi au total, ~10 Gi libres |
| Espace disque | `df -h /` | 96 Go au total, 88 Go libres (9% utilisés) |
| Swap actif | `swapon --show` | Aucun (rien affiché) — c'est la configuration attendue pour Kubernetes |
| Noyau | `uname -r` | `6.8.0-134-generic` |
| Ports clés déjà utilisés | `ss -tulpn` | Seul le port `8000` est occupé (application Docker Compose du Projet 4, encore active) ; les ports de k3s (`6443` API server, `10250` kubelet) sont libres |

**Conclusion** : le VPS a largement les ressources nécessaires pour k3s (qui peut tourner avec seulement 512 Mo de RAM). Aucune préparation supplémentaire n'est nécessaire — pas de swap à désactiver (déjà inactif), pas de conflit de port avec l'installation.

Le déploiement Docker Compose du Projet 4 reste actif pendant la migration, pour ne pas couper le service le temps que la version Kubernetes soit fonctionnelle. Il sera décommissionné une fois le Jour 2 validé.

## 2. Installation de k3s (tâche 3)

Installation via le script officiel, exécuté sur le VPS :

```bash
curl -sfL https://get.k3s.io | sh -
```

Ce script installe le binaire `k3s`, l'enregistre comme service `systemd` (`k3s.service`), et le démarre automatiquement en mode `server` (nœud control-plane unique — pas de cluster multi-nœud ici, un seul VPS).

## 3. Vérification du service (tâche 4)

```bash
systemctl status k3s
```

Résultat : `Active: active (running)`, version installée `v1.36.3+k3s1`.

## 4. Configuration de `kubectl` (tâche 5)

Point important, rencontré en le faisant : le `kubectl` fourni par k3s est en réalité un **lien symbolique vers le binaire `k3s` lui-même** (le script d'installation l'indique : `Creating /usr/local/bin/kubectl symlink to k3s`). Ce `kubectl`-là a un comportement différent d'un `kubectl` autonome classique : il cherche sa configuration par défaut dans `/etc/rancher/k3s/k3s.yaml`, pas dans `~/.kube/config`.

Or ce fichier appartient à `root` (`-rw------- root root`), car c'est le processus `k3s` (lancé par le service `systemd`, donc en `root`) qui le crée — peu importe quel utilisateur a lancé l'installation.

Deux étapes ont donc été nécessaires, avec `sudo` (une seule fois) :

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown ronaldo:ronaldo ~/.kube/config
chmod 600 ~/.kube/config
```

Puis, pour que `kubectl` utilise ce fichier copié plutôt que de retenter `/etc/rancher/k3s/k3s.yaml` :

```bash
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
```

Vérification après une nouvelle session (ou `export` manuel) :

```bash
kubectl get nodes
# NAME      STATUS   ROLES           AGE   VERSION
# kps-vps   Ready    control-plane   ...   v1.36.3+k3s1
```

## 5. Vérification des nœuds (tâche 6)

```bash
kubectl get nodes -o wide
```

Un seul nœud, `kps-vps`, à l'état **Ready**, rôle `control-plane` (normal : k3s installé en mode `server` sur une seule machine joue à la fois le rôle de control-plane et de worker). Preuve : `evidence/kubectl-get-nodes.txt`.

## 6. Vérification des namespaces existants (tâche 7)

```bash
kubectl get namespaces
```

Quatre namespaces présents dès l'installation, avant toute création manuelle : `default`, `kube-node-lease`, `kube-public`, `kube-system`.

## 7. Composants installés par k3s (tâche 8)

```bash
kubectl get pods -A
kubectl get svc -A
```

Tous dans le namespace `kube-system` (préfixe réservé aux composants internes du cluster, jamais utilisé pour une application) :

| Composant | Rôle |
|---|---|
| `coredns` | Résolution DNS interne au cluster — permet à un pod de joindre un Service par son nom plutôt que par son IP (utile dès le Jour 3, pour la connexion à PostgreSQL) |
| `local-path-provisioner` | Fournit automatiquement du stockage local pour les `PersistentVolumeClaim` (utilisé au Jour 3 pour PostgreSQL) |
| `metrics-server` | Collecte les métriques CPU/mémoire des pods et nœuds (utilisé par `kubectl top`, pas indispensable pour ce projet mais installé par défaut) |
| `traefik` + `svclb-traefik` | Contrôleur d'Ingress installé par défaut par k3s — routeur HTTP/HTTPS qui pourra exposer l'application depuis l'extérieur (pertinent au Jour 4 si l'option Ingress est utilisée plutôt que NodePort) |

Preuve : `evidence/kubectl-get-pods.txt`.

## 8. Création du namespace applicatif (tâche 9)

Namespace dédié créé de façon déclarative, avec un manifeste (`k8s/namespace.yaml`) plutôt qu'une commande impérative (`kubectl create namespace`) — pour que sa création soit tracée dans Git, reproductible, et cohérente avec les manifestes des jours suivants :

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: kps-tasks
```

```bash
kubectl apply -f k8s/namespace.yaml
kubectl get namespaces
# kps-tasks   Active   ...
```

Nom choisi : `kps-tasks` (cohérent avec le nom de l'application, `kps-tasks-api`), parmi les deux noms recommandés par le brief (`kps-tasks` ou `opsready-app`).
