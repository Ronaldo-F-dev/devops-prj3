# Systemd vs Docker

## Objectif du document

Expliquer la différence entre un déploiement Linux classique avec `systemd` et un déploiement conteneurisé avec Docker Compose.

## Déploiement avec systemd

Dans le Projet 1, l’application FastAPI était lancée directement sur la machine Linux :

- Python et les dépendances étaient installés sur le VPS
- PostgreSQL tournait sur la machine hôte
- `systemd` lançait et surveillait le service applicatif
- Nginx pouvait servir de reverse proxy

### Avantages

- Très proche d’une installation serveur classique
- Facile à comprendre au début
- Intéressant pour apprendre Linux, `systemd` et les logs système

### Limites

- Reproduction plus difficile d’une machine à l’autre
- Risque de dépendances installées directement sur le serveur
- Mise à jour et restauration plus délicates
- Couplage fort entre l’application et le système hôte

## Déploiement avec Docker Compose

Dans le Projet 2, l’application est packagée dans une image Docker et lancée avec PostgreSQL dans un environnement Compose.

### Ce que Docker change

- L’application est isolée dans un conteneur
- PostgreSQL est dans un autre conteneur
- Les deux services communiquent via un réseau Docker dédié
- Les données PostgreSQL sont conservées dans un volume Docker

### Avantages

- Environnement reproductible
- Déploiement plus rapide sur une nouvelle machine
- Moins de dépendances installées sur le VPS
- Séparation plus nette entre l’application, la base de données et l’hôte

### Limites

- Il faut apprendre les concepts Docker
- Il faut surveiller les conteneurs, le réseau et les volumes
- Le diagnostic est différent de celui de `systemd`

## Lecture simple de la différence

- `systemd` gère un programme installé sur la machine
- Docker gère un programme emballé dans une image et exécuté dans un conteneur

## Conclusion

Le Projet 1 sert à comprendre le fonctionnement d’un serveur Linux classique.
Le Projet 2 sert à apprendre comment la conteneurisation simplifie la reproductibilité et la préparation d’une future chaîne CI/CD.