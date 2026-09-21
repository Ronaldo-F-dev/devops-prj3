# Changelog

## v1.4.0 — 2026-09-18

Ajout d'un champ `uptime_seconds` à la réponse de `GET /health`, calculé depuis le démarrage du processus. Changement volontairement petit, développé pour démontrer la chaîne DevOps complète de bout en bout au Projet 8 (Jour 2) : branche → PR → pipeline CI → merge → tag → registre → GitOps → ArgoCD → Kubernetes → observabilité.

### Changements

- `GET /health` renvoie désormais `uptime_seconds` (voir [`app/main.py`](app/main.py), [`app/schemas.py`](app/schemas.py))
- Nouveau test `test_health_reports_uptime` (accepte `200` ou `503` — le endpoint peut légitimement renvoyer `503` si la base est injoignable, ce n'est pas un bug)

### Documentation

- Démo complète documentée : [OpsReady-08 capstone, Jour 2](https://github.com/Ronaldo-F-dev/opsready-08-capstone/blob/main/docs/day2-full-demo.md)

## v1.3.0 — 2026-09-07

Version de démonstration utilisée pour illustrer un changement de version piloté depuis Git au Projet 6 (GitOps/ArgoCD) — actuellement la version `blue` (active) du mécanisme blue/green.

## v1.2.0 — 2026-08-31

Version de référence pour la version `green` (standby) du mécanisme blue/green mis en place au Projet 6.

## v1.1.0 — 2026-08-31

Nouveau tag propre créé après la perte de l'image correspondant à `v1.0.0` dans le registre (package recréé pendant un dépannage du Projet 4) — référence de départ pour le dépôt GitOps du Projet 6.

### Principaux changements (Projets 4-6, résumé)

- Déploiement continu vers un VPS via Docker Compose, avec rollback automatique sur échec du healthcheck (Projet 4)
- Migration vers Kubernetes (k3s) : Deployment, Service, ConfigMap/Secret pour PostgreSQL, probes de disponibilité (Projet 5)
- Adoption de GitOps avec ArgoCD : dépôt GitOps séparé ([`kps-tasks-gitops`](https://github.com/Ronaldo-F-dev/kps-tasks-gitops)), synchronisation automatique, détection de drift, stratégie blue/green (Projet 6)

## v1.0.0 — 2026-08-03

Première version stable du projet : chaîne CI complète (lint, test, build Docker), sécurité et qualité intégrées (Gitleaks, SonarCloud).

### Principaux changements

- Job `secret_scan` (Gitleaks) intégré à la CI, avec test réel de détection d'un faux secret et suppression confirmée
- Job `sonar` (SonarCloud) intégré à la CI, avec rapport de couverture de tests (`pytest-cov`)
- Correction de 3 problèmes remontés par SonarCloud : littéral dupliqué extrait en constante, `response_model` redondant supprimé, `pip install` forcé en `--only-binary :all:` (CI + Dockerfile) pour éviter l'exécution de scripts d'installation arbitraires
- Nettoyage du dépôt : suppression de fichiers vides parasites, secret réel (identifiants VPS) retiré de l'historique de travail avant merge

### Amélioration CI

- Pipeline structuré en jobs indépendants et dépendants (`lint → test → build/sonar`, `secret_scan` en parallèle)
- Documentation complète de la chaîne CI : [docs/prj3/ci-pipeline.md](docs/prj3/ci-pipeline.md)

### Contrôles qualité ajoutés

- Gitleaks (détection de secrets) — [docs/prj3/security-and-quality.md](docs/prj3/security-and-quality.md)
- SonarCloud (bugs, vulnérabilités, code smells, duplication, couverture) — [docs/prj3/security-and-quality.md](docs/prj3/security-and-quality.md)

### Limites connues

- Quality Gate SonarCloud actuellement en échec : 12 issues de type Vulnerability liées à des dépendances non verrouillées à une version exacte dans `requirements.txt` (`>=`, `<`) — identifié, corrigé volontairement laissé de côté (nécessite l'introduction d'un fichier de lock, hors périmètre de cette version)
- Couverture de tests minimale (un seul test, sur l'endpoint racine) — le rapport de couverture est fonctionnel, mais peu représentatif
- Pas de déploiement automatisé : cette version couvre l'intégration continue (CI), pas le déploiement continu (CD), volontairement hors scope (voir Projet 4)
