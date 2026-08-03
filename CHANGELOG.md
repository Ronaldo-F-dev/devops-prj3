# Changelog

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
