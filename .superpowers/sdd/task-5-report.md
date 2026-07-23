# Task 5 — LaunchAgent `WatchPaths` + documentation

Statut : **DONE_WITH_CONCERNS**

## Portée exécutée

- Création de `launchd/com.iso-nord.inbox.plist`.
- Ajout de la section `5bis. Boîte de dépôt automatique (iso-ingest)` dans
  `docs/HANDOFF-codex.md`.
- Adaptation à l'architecture corrigée du handoff :
  - clone NAS : `/Volumes/SSD 1/iso-nord`;
  - inbox surveillée : `/Volumes/SSD 1/iso-nord-media/inbox`;
  - Mac Pro Intel / Homebrew : `/usr/local/bin`;
  - journaux launchd sous `/Volumes/SSD 1/iso-nord-media/`.

## Fichiers

- `launchd/com.iso-nord.inbox.plist` — nouveau LaunchAgent.
- `docs/HANDOFF-codex.md` — documentation d'installation, dossiers, types et dépannage.

## Vérifications et sorties

### État initial

Commande :

```text
git status --short --branch
git branch --show-current
```

Sortie :

```text
## feat/labs360-inbox...origin/feat/labs360-inbox
?? .superpowers/
feat/labs360-inbox
```

Le dossier `.superpowers/` préexistait et a été préservé.

### Validation plist

Commande :

```text
plutil -lint launchd/com.iso-nord.inbox.plist
```

Sortie :

```text
launchd/com.iso-nord.inbox.plist: OK
```

Valeurs relues avec `/usr/libexec/PlistBuddy` :

```text
com.iso-nord.inbox
/Volumes/SSD 1/iso-nord/scripts/iso-ingest.sh
/Volumes/SSD 1/iso-nord-media/inbox
/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
/Volumes/SSD 1/iso-nord-media/inbox-launchd.out.log
/Volumes/SSD 1/iso-nord-media/inbox-launchd.err.log
```

### Build

Commande :

```text
npm run build
```

Résultat :

```text
[build] 10 page(s) built in 3.42s
[build] Complete!
```

Exit code : `0`.

### Revue du diff

Commandes :

```text
git diff --check
git diff --cached --check
```

Résultat : aucune erreur ni espace fautif.

La revue manuelle confirme :

- `WatchPaths` surveille seulement `inbox/`;
- les archives, la quarantaine et les logs restent hors du dossier surveillé;
- `RunAtLoad` est désactivé;
- le PATH ne contient pas `/opt/homebrew/bin`;
- le script cible bien le clone du NAS;
- la documentation correspond au plist livré.

## Commit

```text
106a68a feat(labs360): LaunchAgent WatchPaths + doc boîte de dépôt
```

Le commit contient uniquement les deux fichiers de la Task 5 et le trailer demandé.

## Réserve

Le chargement du LaunchAgent et le test bout-en-bout réel n'ont pas été exécutés :
ils exigent le NAS avec la branche fusionnée dans `main` et un vrai média déposé.
Ils appartiennent aux étapes d'activation NAS décrites après la Task 5 dans le handoff.

## Correctif de revue — bootstrap du dossier surveillé

Le finding Important de la revue a été corrigé : puisque `RunAtLoad` reste désactivé,
le dossier déclaré dans `WatchPaths` doit exister avant le chargement du LaunchAgent.
La commande suivante précède maintenant `launchctl load` dans la procédure
d'installation principale et dans la commande d'activation NAS du handoff :

```bash
mkdir -p "/Volumes/SSD 1/iso-nord-media/inbox"
```

Vérifications fraîches :

```text
git diff --check
rg -n -U 'mkdir -p .*iso-nord-media/inbox.*\n(?:.*\n){0,3}.*launchctl load' \
  docs/HANDOFF-codex.md docs/HANDOFF-codex-labs360-inbox.md
npm run build
```

Résultats :

- `git diff --check` : exit `0`, aucune erreur;
- les deux séquences placent bien `mkdir -p` avant `launchctl load`;
- `npm run build` : exit `0`, 10 pages générées en 3,59 s;
- `RunAtLoad` n'a pas été modifié.
