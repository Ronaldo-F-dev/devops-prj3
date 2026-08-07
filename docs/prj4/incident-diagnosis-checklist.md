# Check-list de diagnostic — incident déclenché par le formateur (Phase 3)

Le scénario exact n'est pas connu à l'avance. Cette check-list donne, pour chaque scénario possible listé dans le brief, le premier réflexe de diagnostic — pas la solution automatique, juste où regarder en premier pour comprendre vite.

## Méthode générale, quel que soit l'incident

1. **Regarder le pipeline avant de toucher au VPS** : onglet Actions → dernier run → quel job a échoué, à quelle étape précise ?
2. **Lire le dernier message d'erreur**, pas le début du log — la cause est presque toujours juste avant l'arrêt.
3. **Distinguer un problème de pipeline (CI) d'un problème d'infrastructure (VPS)** : un job qui échoue avant `Deploy to VPS` est un problème de code/config ; un échec dans `Deploy to VPS` ou une application qui ne répond plus est un problème d'infrastructure ou de déploiement.
4. **Ne jamais supposer, vérifier** : chaque ligne ci-dessous donne la commande qui confirme ou infirme l'hypothèse.

## Par scénario

| Scénario | Où regarder en premier | Commande de diagnostic |
|---|---|---|
| **Registre injoignable** | Étape "Push image" ou "Log in to GitHub Container Registry" du job `docker_build` | `docker login ghcr.io` en local ; `curl -I https://ghcr.io` |
| **Variable CI/CD manquante** | Le job échoue tôt, souvent avec un message `required` (nos scripts utilisent `${VAR:?message}`, qui échoue explicitement) | `gh secret list --repo Ronaldo-F-dev/devops-prj3` — comparer avec `docs/prj4/ci-cd-variables.md` |
| **Clé SSH invalide** | Étape "Set up SSH" ou premier appel `ssh`/`scp` du job `deploy`, erreur `Permission denied (publickey)` | `ssh -i ~/.ssh/id_ed25519 ronaldo@<VPS> whoami` en local pour confirmer si la clé locale fonctionne encore |
| **Mauvais tag d'image** | Le job `deploy` réussit à se connecter mais `docker compose pull` échoue (`manifest unknown`) ou tire une image inattendue | `cat /opt/kps-tasks-api/.env \| grep IMAGE_TAG` sur le VPS, comparer avec le tag attendu (voir `docs/prj4/image-versioning.md`) |
| **VPS injoignable** | Le job `deploy` timeout dès la connexion SSH | `ping <VPS>` ou `ssh -o ConnectTimeout=5 ronaldo@<VPS> true` en local |
| **Mauvais fichier `.env`** | L'application démarre mais répond incorrectement (mauvaise base de données, mauvais port) | `cat /opt/kps-tasks-api/.env` sur le VPS — comparer chaque valeur avec ce qui est attendu |
| **`docker-compose.prod.yml` manquant** | Le job `deploy` échoue à l'étape "Run deployment" avec `no such file` | `ls -la /opt/kps-tasks-api/` sur le VPS |
| **Conteneur en boucle de redémarrage** | `docker ps` montre `Restarting` au lieu de `Up` | `docker logs <container> --tail 50` sur le VPS — la cause est presque toujours dans les dernières lignes |
| **Volume PostgreSQL mal référencé** | Le conteneur `db` démarre mais l'application ne trouve pas ses données (ou les recrée à vide) | `docker volume ls` puis `docker inspect kps-tasks-api-db-1 --format '{{json .Mounts}}'` sur le VPS — comparer avec `app_postgres_data` attendu (voir `docs/prj4/deployment-process.md`, question 45) |

## Commandes de premier réflexe, toujours utiles

```bash
# État du pipeline
gh run list --repo Ronaldo-F-dev/devops-prj3 --branch main --limit 3
gh run view <run-id> --log-failed

# État du VPS
ssh -i ~/.ssh/id_ed25519 ronaldo@<VPS> "docker ps -a; cat /opt/kps-tasks-api/.env; cat /opt/kps-tasks-api/current-version.txt"

# État de l'application
curl http://<VPS>:8000/health
curl http://<VPS>:8000/version
```

## Ce qu'on a déjà appris en le vivant pour de vrai

Trois des quatre incidents de `docs/prj4/incident-report.md` correspondent directement à des catégories de cette liste (registre/permissions, tag d'image via variable d'environnement, VPS/déploiement) — pas des scénarios abstraits, des vrais problèmes déjà diagnostiqués et corrigés pendant ce projet.
