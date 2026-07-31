# Build Docker : local vs CI

## Pourquoi ça compte

Un build Docker qui fonctionne sur son poste peut échouer en CI, et inversement.
Comprendre ce qui diffère entre les deux évite les surprises et les "ça marche
pourtant chez moi".

## Différences principales

| Aspect | Build local | Build CI (GitHub Actions) |
|---|---|---|
| Environnement | Poste du développeur, état souvent "sale" (containers, images, cache déjà présents) | Runner éphémère, propre à chaque run |
| Cache Docker | Persiste entre les builds (couches réutilisées d'une fois sur l'autre) | Repart de zéro par défaut à chaque run (pas de cache partagé sans configuration explicite, ex. `actions/cache` ou un registre de cache) |
| Fichiers présents | Tout le répertoire de travail, y compris fichiers non commités, `.env`, artefacts locaux | Uniquement ce qui est commité et récupéré par `actions/checkout` — un fichier non versionné (oublié dans `.gitignore` ou jamais ajouté) casse le build en CI alors qu'il fonctionne en local |
| Contexte de build | Peut contenir des fichiers non trackés qui polluent involontairement le `COPY` | Contexte strictement égal à l'état du commit poussé — reproductible |
| Réseau / proxy | Dépend de la config réseau du poste (VPN, proxy d'entreprise, DNS local) | Réseau du runner GitHub, généralement sans restriction particulière |
| Droits / OS | Dépend de l'OS du développeur (macOS, Windows+WSL, Linux) et de la version Docker installée | Toujours Linux (`ubuntu-latest`), version Docker fixée par l'image du runner |
| Détection d'erreurs | Dépend de la discipline du développeur (peut oublier de tester le build avant de push) | Systématique : chaque push/PR déclenche le build, aucune erreur ne passe silencieusement |

## Ce que ça implique concrètement

- **Un `COPY` qui référence un fichier non commité** fonctionnera en local (le
  fichier est sur le disque) mais échouera en CI (le fichier n'existe pas dans
  le contexte checkouté). C'est exactement le type d'erreur volontairement
  provoquée puis corrigée dans ce projet (voir commits `04ebf3f` /
  `541352a` — `COPY requirements-typo.txt` inexistant).
- **Le cache local peut masquer un problème** : une couche déjà construite en
  local peut cacher une erreur qui n'apparaîtra qu'au premier build sur un
  runner CI sans cache.
- **La CI est la source de vérité** : un build qui passe en CI est reproductible
  pour n'importe qui (ou n'importe quelle machine) qui checkoute le même
  commit, contrairement à un build local qui dépend de l'état du poste.

## Preuve

- Run CI en échec (Dockerfile cassé intentionnellement) :
  https://github.com/Ronaldo-F-dev/devops-prj3/actions/runs/30613425958
- Run CI en succès (correction appliquée) :
  https://github.com/Ronaldo-F-dev/devops-prj3/actions/runs/30613517733
