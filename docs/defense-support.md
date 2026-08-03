# Support de mini-soutenance — Projet 3 : OpsReady-03 (CI, sécurité, qualité)

Support pour une présentation courte (5 à 10 minutes). Chaque section correspond à un point attendu du brief (Jour 5, points 52-54).

## 1. Contexte et objectif

- Prérequis : application KPS Tasks API (Projet 1), conteneurisée avec Docker Compose (Projet 2).
- Objectif du Projet 3 : sécuriser les changements avant intégration — CI complète, détection de secrets, analyse de qualité, versioning — **sans** toucher au déploiement (ça, c'est le Projet 4).

## 2. Stratégie de branches

- GitHub Flow : `main` toujours stable, développement dans des branches `feature/*`, fusion via Pull Request.
- Détail et justification : [docs/adr/0001-git-branching-strategy.md](adr/0001-git-branching-strategy.md).
- Convention de commits : préfixes `ci:`, `fix:`, `docs:`, `test:`, `style:`, `chore:` — visible dans tout l'historique du dépôt.

## 3. Pipeline CI

```
lint ──▶ test ──▶ build (Docker)
              └──▶ sonar (SonarCloud)
secret_scan (Gitleaks)   ← indépendant, en parallèle
```

- Détail complet, variables, comment lire les logs, comment diagnostiquer un échec : [docs/ci-pipeline.md](ci-pipeline.md).
- Preuve de pipeline vert : [evidence/pipeline-green.txt](../evidence/pipeline-green.txt).

## 4. Gitleaks — détection de secrets

- Test réel effectué : ajout d'une fausse clé AWS, détection confirmée, suppression propre. Preuve : [evidence/gitleaks-detection.txt](../evidence/gitleaks-detection.txt).
- Point clé compris : supprimer un secret du fichier ne l'efface pas de l'historique Git — le commit qui l'a introduit reste consultable tant qu'il n'est pas explicitement purgé.
- Incident réel traité pendant ce projet (pas un exercice) : un vrai identifiant VPS retrouvé dans l'historique d'une branche non fusionnée. Rotation de l'accès effectuée avant tout nettoyage Git. Détail complet : [docs/security-and-quality.md](security-and-quality.md).

## 5. SonarCloud — analyse de qualité

- 4 problèmes identifiés dans le rapport (2 code smells, 2 vulnérabilités), 3 corrigés en direct, 1 documenté et volontairement laissé de côté (dépendances non verrouillées — nécessiterait un fichier de lock, hors périmètre).
- État actuel du dashboard : [evidence/sonar-report.txt](../evidence/sonar-report.txt).
- Compris et à savoir expliquer : Sonar ne bloque pas le merge par défaut (c'est un choix d'équipe via les règles de protection de branche), et ne remplace pas une revue de code humaine — il détecte des motifs connus, pas l'intention métier. Détail : [docs/security-and-quality.md](security-and-quality.md).

## 6. Versioning et changelog

- Stratégie : [docs/versioning.md](versioning.md).
- Première version stable : `v1.0.0`, tag posé sur `main` une fois le pipeline complet vert.
- Contenu : [CHANGELOG.md](../CHANGELOG.md).

## 7. Incident et diagnostic vécus pendant ce projet

- **Fichiers vides parasites** : 6 fichiers de 0 octet créés par erreur (une sortie d'erreur `ruff` interprétée comme nom de fichier), repérés en revue de PR et supprimés avant merge — exemple concret de ce qu'une revue attentive de diff permet d'attraper.
- **Fuite de secret réel** : identifiants VPS trouvés dans l'historique d'une branche fermée non fusionnée mais toujours accessible publiquement sur GitHub. Traité comme un vrai incident : rotation immédiate de l'accès, reconstruction d'une branche propre plutôt que retravail de la branche compromise.
- **Pipeline manquant sur `main` après un premier merge** : une Pull Request mergée n'incluait pas les tout derniers commits poussés juste après — repéré en comparant `main` et la branche source, corrigé par une PR de rattrapage.

## 8. Limites et améliorations possibles

- Quality Gate SonarCloud actuellement en échec (dépendances non verrouillées) — assumé et documenté, pas un oubli.
- Couverture de tests minimale (un seul test) — le mécanisme fonctionne, le contenu est à enrichir.
- Pas de CD (déploiement continu) dans ce projet — volontairement hors scope, prévu au Projet 4.
- Amélioration possible : fichier de verrouillage des dépendances (`pip-compile` ou équivalent) pour fermer les 12 vulnérabilités restantes.

## 9. Questions probables et réponses courtes

Voir la section "Questions intermédiaires (39-44)" de [docs/security-and-quality.md](security-and-quality.md) pour les réponses détaillées à :
- Pourquoi scanner les secrets en pipeline, que faire face à un vrai secret commité, pourquoi supprimer le fichier ne suffit pas
- Sonar bloque-t-il le merge, différence bug/vulnérabilité/code smell, pourquoi la CI ne remplace pas une revue de code

Autres questions probables :
- **Différence CI / CD (livraison) / CD (déploiement) ?** CI = intégrer et valider chaque changement automatiquement (ce projet). CD-livraison = préparer automatiquement un artefact déployable (ex. image Docker taguée, prête à être promue). CD-déploiement = déployer automatiquement cet artefact en environnement réel (Projet 4) — c'est la seule étape non traitée ici, volontairement.
- **Pourquoi un merge commit plutôt qu'un squash ?** Choix fait pour garder l'historique détaillé des 25 commits (mise en place progressive de la CI, tests, correctifs) visible sur `main`, plutôt que de le compresser en un seul commit.
