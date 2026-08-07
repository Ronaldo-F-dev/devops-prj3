# Sécurité et qualité — Gitleaks et SonarCloud

Ce document couvre le Jour 4 du brief OpsReady-03 : détection de secrets avec Gitleaks et analyse de qualité avec SonarCloud, intégrées dans la CI (`.github/workflows/ci.yml`).

## 1. Gitleaks — détection de secrets

### Mise en place

Job `secret_scan` dans la CI, exécuté sur chaque push et chaque pull request :

```yaml
secret_scan:
  name: Gitleaks secret scan
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0
    - name: Run Gitleaks
      uses: gitleaks/gitleaks-action@v2
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

`fetch-depth: 0` est nécessaire pour que Gitleaks puisse scanner tout l'historique des commits du push/de la PR, pas seulement le dernier commit.

### Test réalisé

1. Ajout d'une fausse clé AWS non-allowlistée dans `.env.example` (commit `test: use non-allowlisted fake AWS key to trigger Gitleaks detection`)
2. Vérification que le job `secret_scan` détecte bien la fuite (voir `evidence/gitleaks-detection.txt` — log complet du job en échec, règle `aws-access-token`)
3. Suppression de la fausse clé une fois la détection confirmée (commit `test: remove fake secret after confirming Gitleaks detection`)

### Point important : l'historique reste marqué

Même après la suppression du secret du fichier, Gitleaks continue de le signaler tant qu'il scanne une plage de commits qui inclut le commit où le secret a été *ajouté* (le secret existe toujours dans le diff de ce commit-là). C'est le comportement attendu : **supprimer un secret du dernier commit ne l'efface pas de l'historique Git**.

Solution retenue : un fichier `.gitleaksignore` qui reconnaît explicitement cette découverte précise par son empreinte (fingerprint), au lieu de la cacher ou de réécrire l'historique :

```
08b002573e8f7942b5de739d16f2d7781e85445b:.env.example:aws-access-token:11
```

Ça documente que la découverte est connue, volontaire (test), et déjà corrigée — sans faire disparaître la preuve.

### Incident réel rencontré pendant ce projet

Un vrai identifiant (IP + mot de passe VPS) avait été accidentellement commité dans `.gitignore` dès le tout premier commit d'une branche de travail, restée non fusionnée mais toujours accessible publiquement via une Pull Request fermée sur GitHub. Actions prises :
1. Rotation immédiate de l'accès VPS concerné (avant tout nettoyage Git — un secret exposé publiquement doit être considéré comme compromis dès sa découverte)
2. Reconstruction d'une branche propre (`feature/quality-and-security`) ne reprenant que les commits sans le secret réel, plutôt que de retravailler la branche fuitée

## 2. SonarCloud — analyse de qualité

### Mise en place

- Compte SonarCloud lié à l'organisation GitHub `Ronaldo-F-dev`
- `sonar-project.properties` à la racine (organisation, clé de projet, chemins sources/tests, chemin du rapport de couverture)
- Job `sonar` dans la CI : installe les dépendances, lance `pytest --cov=app --cov-report=xml`, puis exécute `SonarSource/sonarqube-scan-action@v4` avec le secret `SONAR_TOKEN`

### Observations relevées dans le rapport

| # | Type | Sévérité | Constat | Statut |
|---|------|----------|---------|--------|
| 1 | Code Smell | Minor | Littéral `"Task not found"` dupliqué 3 fois dans `app/main.py` | ✅ Corrigé — extrait en constante `TASK_NOT_FOUND` |
| 2 | Code Smell | Minor | `response_model` redondant avec l'annotation de retour sur `root()` et `version()` | ✅ Corrigé — paramètre retiré, l'annotation de type suffit |
| 3 | Vulnerability | Major | `pip install` sans `--only-binary :all:` dans la CI et le `Dockerfile` : un paquet sans wheel prébuilt peut exécuter un `setup.py` arbitraire pendant l'installation | ✅ Corrigé — flag ajouté sur tous les `pip install`/`pip wheel` |
| 4 | Vulnerability | Major | Dépendances de `requirements.txt` non verrouillées à une version exacte (`>=`, `<`) : une mise à jour amont peut introduire un changement de comportement ou une version compromise sans qu'on s'en aperçoive | 📝 Identifié, non corrigé — nécessiterait un fichier de lock (ex. `pip-compile`), hors périmètre du Jour 4 |

Deux points minimum étaient demandés par le brief (point 37) ; quatre ont été identifiés, trois corrigés.

### État du dashboard après merge sur `main` (voir `evidence/sonar-report.txt`)

- Quality Gate : **Failed** (1 condition), Security rating **C**, Reliability **A**, Maintainability **A**, Duplications **0.0%**
- 12 issues ouvertes, toutes de type Vulnerability/Security — causées par les 5 lignes `pip install -r requirements.txt` (CI + Dockerfile) qui utilisent des plages de versions plutôt que des versions verrouillées (observation #4 ci-dessus, volontairement non corrigée)
- Maintainability à 0 issue confirme que les deux code smells (littéral dupliqué, `response_model` redondant) sont bien résolus

## 3. Questions intermédiaires (points 39-44 du brief)

### 39. Pourquoi scanner les secrets dans un pipeline ?

Parce qu'un secret commité arrive tôt ou tard sur un dépôt distant (souvent public, comme ici), et que le point de contrôle le plus fiable est automatique et systématique : personne ne relit ligne par ligne chaque diff avant de pousser. Un job Gitleaks qui tourne sur chaque push/PR détecte la fuite en quelques secondes, avant que le code ne soit fusionné ou même simplement consulté par quelqu'un d'autre.

### 40. Que faire si un vrai secret est commité ?

C'est arrivé concrètement pendant ce projet (IP + mot de passe VPS retrouvés dans l'historique d'une branche). La marche suivie :
1. **Faire tourner l'accès immédiatement** (changer le mot de passe / la clé), avant même de toucher à Git — un secret poussé sur un dépôt public doit être considéré comme compromis dès sa découverte, qu'on ait ou non la preuve qu'il ait été utilisé.
2. Vérifier les journaux d'accès (`last`, `journalctl`, `/var/log/auth.log`) pour repérer une éventuelle connexion suspecte pendant la période d'exposition.
3. Nettoyer ou isoler l'historique Git contenant le secret (ici : reconstruction d'une branche propre à partir des seuls commits sains, plutôt que réécriture de l'historique existant).
4. Documenter l'incident (ce document) pour que la leçon reste, même si le code, lui, ne garde plus la trace.

### 41. Supprimer le secret du fichier suffit-il toujours ?

Non. Le fichier au dernier commit est propre, mais le secret reste lisible dans l'historique Git (le commit qui l'a introduit existe toujours, accessible à quiconque clone le dépôt ou consulte un ancien commit/PR). C'est exactement ce qu'on a observé avec le job Gitleaks sur la fausse clé AWS : il continue de la signaler après sa suppression, tant qu'il scanne une plage de commits qui inclut celui où elle a été ajoutée. Un vrai nettoyage nécessite soit de traiter la cause (rotation de l'accès, ce qui rend le secret exposé sans valeur), soit de réécrire l'historique (`git filter-repo`/BFG + force-push), les deux étant complémentaires plutôt qu'alternatifs.

### 42. Sonar bloque-t-il toujours le merge ?

Non. Le Quality Gate SonarCloud est un statut de check GitHub comme un autre (`SonarCloud Code Analysis`) : il ne bloque le merge que si une règle de protection de branche l'exige explicitement. Par défaut, il informe — il ne décide pas à la place de l'équipe.

### 43. Quelle est la différence entre un bug, une vulnérabilité et un code smell ?

- **Bug** : le code fait quelque chose de différent de ce qui était prévu — un défaut de comportement, potentiellement reproductible par un test.
- **Vulnerability** : le code fonctionne comme prévu, mais ce comportement ouvre une faille exploitable (ex. injection, secret exposé, exécution de code non désirée comme le `pip install` sans `--only-binary :all:` trouvé ici).
- **Code smell** : le code fonctionne correctement, sans risque de sécurité, mais sa forme rend la maintenance plus difficile ou plus risquée à terme (ex. littéral dupliqué, paramètre redondant) — c'est un problème de qualité, pas de correction.

### 44. Pourquoi le contrôle qualité en CI ne remplace-t-il pas une revue de code ?

Parce que Sonar (comme Gitleaks) détecte des motifs connus et mesurables — duplication, complexité, règles de sécurité cataloguées — mais ne comprend ni l'intention métier, ni si la solution choisie est la bonne à l'échelle de l'architecture, ni le contexte d'une décision (pourquoi ce compromis, pour quel besoin). Un outil automatique est un filtre rapide et systématique en amont ; la revue humaine reste nécessaire pour juger ce que l'outil ne peut pas évaluer.
