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

### Sonar bloque-t-il toujours le merge ?

Non. Le Quality Gate SonarCloud est un statut de check GitHub comme un autre (`SonarCloud Code Analysis`) : il ne bloque le merge que si une règle de protection de branche l'exige explicitement. Par défaut, il informe — il ne décide pas à la place de l'équipe.

### Sonar remplace-t-il une revue de code humaine ?

Non. Sonar détecte des motifs connus (duplication, vulnérabilités classées, complexité) mais ne comprend ni l'intention métier ni les compromis d'architecture. Il sert de filet de sécurité automatique en amont d'une revue humaine, pas de substitut.
