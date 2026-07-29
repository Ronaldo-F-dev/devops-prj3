# ADR-001 : Choix de la stratégie de branches Git

## Statut
Acceptée

## Contexte
L'équipe doit travailler simultanément sur plusieurs fonctionnalités tout en garantissant la stabilité de la branche principale.

## Décision
Nous adoptons une stratégie simple inspirée de GitHub Flow.

- `main` contient uniquement du code stable et prêt pour la production.
- Chaque nouvelle fonctionnalité est développée dans une branche dédiée nommée `feature/<nom>`.
- Les corrections de bugs utilisent des branches `fix/<nom>`.
- Les branches sont fusionnées dans `main` via une Pull Request après revue de code.

## Conséquences
### Avantages
- Historique Git clair.
- Développement parallèle facilité.
- Réduction des risques de casser la branche principale.
- Revue de code systématique.

### Inconvénients
- Nécessite de créer une branche pour chaque évolution.
- Demande une discipline lors des merges.