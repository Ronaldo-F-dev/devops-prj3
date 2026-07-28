# Docker Networking

## Pourquoi un réseau Docker dédié

Dans cette stack, l’API et PostgreSQL ne doivent pas communiquer par l’IP publique du VPS.
Ils doivent échanger sur un réseau privé Docker.

## Réseau utilisé

Le fichier `docker-compose.yml` déclare un réseau bridge dédié :

```yaml
networks:
  kps_net:
    driver: bridge
```

Les services `app` et `db` sont reliés à ce réseau.

## Ce que cela permet

- L’application peut joindre PostgreSQL par le nom du service `db`
- PostgreSQL n’a pas besoin d’être exposé sur le port 5432 de l’hôte
- Le trafic entre services reste dans la couche Docker

## Résolution des noms

Docker Compose fournit un DNS interne.
Cela veut dire que le service `app` peut utiliser :

```text
postgresql+psycopg://kps_tasks_user:change_me@db:5432/kps_tasks_db
```

Ici, `db` est le nom du service PostgreSQL.

## Ports

- Le conteneur `app` expose le port 8000 vers l’hôte
- Le conteneur `db` ne publie aucun port sur l’hôte

## Vérifications utiles

```bash
docker compose ps
docker network ls
docker volume ls
docker inspect app-app-1
docker inspect app-db-1
```

## Conclusion

Le réseau Docker dédié est la bonne pratique dans ce projet parce qu’il garde PostgreSQL privé tout en laissant l’API être accessible depuis l’extérieur uniquement par le port choisi.