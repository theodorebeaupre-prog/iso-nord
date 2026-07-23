# Handoff (Codex) — Boîte de dépôt auto « Québec en 360 » — À ACTIVER SUR LE NAS

> Écrit le 2026-07-23. Reprend le travail commencé dans la session Claude Code.
> **Branche : `feat/labs360-inbox`** (poussée sur GitHub). Objectif : déposer un
> clip / une photo / un pano fini dans un dossier partagé du **Mac Pro NAS** →
> pin géolocalisé publié tout seul sur `theo-picture.com/labs/360`.

## Documents de référence (à lire d'abord)
- **Spec** : `docs/superpowers/specs/2026-07-23-labs360-inbox-design.md`
- **Plan** : `docs/superpowers/plans/2026-07-23-labs360-inbox.md`
- Handoff d'origine (infra tunnel/MapKit/iso360) : `docs/HANDOFF-codex.md`
- Registre d'avancement : `.superpowers/sdd/progress.md`

---

## ⚠️ Changement d'architecture MAJEUR vs le plan

Le plan supposait que tout tournait depuis `~/Desktop/Developer/iso-nord`. **Faux
en réalité** : le repo est sur le **MacBook**, mais les médias + le tunnel sont sur
le **Mac Pro NAS** (`Pro-de-Theodore`, un Mac **Intel**, brew en `/usr/local`).

**Décision retenue (option A) : tout tourne sur le NAS.** Le repo a été **cloné sur
le SSD du NAS** à `/Volumes/SSD 1/iso-nord`, et c'est de là que `iso-ingest.sh`
publie (git push via une deploy key). Les scripts ne codent donc plus le chemin du
repo en dur : ils le **dérivent de leur propre emplacement** (résolution de symlinks).
Le NAS opère sur la branche **`main`** → **il faut merger `feat/labs360-inbox` dans
`main`** pour que le NAS puisse `git pull` le code fini.

---

## ✅ CE QUI EST FAIT (commits sur `feat/labs360-inbox`)

1. **Spec + plan** rédigés et commités.
2. **Task 2 — type `photo` sur le site** (commit `9a8bc0c`) :
   - `src/data/labs360.ts` : `PlaceType = '360' | 'video' | 'photo'`.
   - `src/i18n/ui.ts` : `labs360.badgePhoto` (fr + en) = « Photo ».
   - `src/components/pages/Labs360.astro` : runtime `badgePhoto`, badge légende 3 voies, CSS lightbox `img` (`object-fit: contain`).
   - `src/scripts/labs360.js` : glyph carte 3 voies (`◉` 360 / `▶` video / `◆` photo), `mountMedia` branche `photo` → `<img>`.
   - **Vérifié** : build 10 pages + lightbox testée au navigateur (entrée de test retirée).
3. **Task 3 — cœur partagé** (commit `7e52977`) :
   - `scripts/iso360-core.sh` (NOUVEAU) : `core_extract_meta` (exiftool JSON), `core_geocode` (reverse Nominatim, ym validé année ≥ 2000), `core_forward_geocode`, `core_publish_verify`, `core_wire` (insert/replace, gère `PTYPE`/`POSTER_URL`), `core_build_guard`, `core_commit_push`.
   - `scripts/iso360.sh` refactoré : `source` le cœur, REPO dérivé (symlink-safe), GPS via exiftool. **Non-régression `--dry-run` OK.**
4. **Task 4 — `iso-ingest.sh`** (commit `b4ca8c7`, NOUVEAU) :
   - Détection type (video/360/photo/unknown), GPS exiftool + repli nom de fichier
     (`lat,lon` direct ou texte forward-géocodé), poster ffmpeg pour les clips,
     quarantaine visible + lockfile + log. `--dry-run` ne touche à RIEN.
     `MEDIA_ROOT` surchargeable via `ISO_NORD_MEDIA_ROOT` (pour tester).
   - **Vérifié** en dry-run sur 4 fixtures (photo sans GPS→nom, vidéo→GPS MP4, type inconnu→quarantaine, 360 sans GPS→quarantaine).
5. **Task 5 — LaunchAgent + documentation** (commits `106a68a`, `241d922`) :
   - plist NAS Intel livré avec le bon repo, `WatchPaths`, PATH et journaux;
   - création de `inbox/` documentée avant `launchctl load`.
6. **Revue whole-branch + hardening final** :
   - échecs `git add` / `commit` / `push` propagés; original archivé seulement
     après succès;
   - Nominatim a des retries + timeouts et une panne mène en quarantaine, jamais
     à « Lieu sans nom » ni à des coordonnées inventées;
   - IDs, médias, posters, quarantaines et archives suffixés en cas de collision;
     la copie média refuse atomiquement tout écrasement sous cache immutable;
   - garde-fou build vérifie réellement **exactement 10 pages**;
   - verrou PID récupérable après crash, compatible Bash 3.2; curls bornés;
   - `iso-ingest --dry-run` ne crée ni dossier, lock, log, média ni changement repo;
   - tests reproductibles : `tests/labs360-pipeline.sh`.

### Environnement déjà provisionné
- **MacBook** : exiftool + ffmpeg installés (pour tests). `gh` connecté à `theodorebeaupre-prog` (proprio du repo).
- **NAS** (`Pro-de-Theodore`, joignable en SSH depuis le MacBook :
  `ssh -i ~/.ssh/id_ed25519_macpro theodorebeaupre@100.99.244.24`) :
  - **Deploy key** créée (`~/.ssh/id_ed25519_isonord_deploy`), alias SSH `github-isonord`
    dans `~/.ssh/config`, **ajoutée à GitHub en read-write** (« iso-nord-nas (auto-publish) », id 158141078).
  - **Repo cloné** : `/Volumes/SSD 1/iso-nord` (branche `main`, remote via `github-isonord`,
    identité git « iso-nord NAS » / theodore.beaupre@icloud.com). **`npm install` fait.**
  - **`brew install exiftool ffmpeg`** : lancé, **ffmpeg installé, exiftool en cours** au
    moment de l'arrêt → **À VÉRIFIER/FINIR** (voir ci-dessous).

---

## ⛔ CE QUI RESTE À FAIRE

### A. Terminer l'install NAS (probablement déjà fini)
```bash
ssh -i ~/.ssh/id_ed25519_macpro theodorebeaupre@100.99.244.24 \
  'bash -lc "command -v exiftool && command -v ffmpeg || brew install exiftool ffmpeg"'
```
Attendu : les deux binaires présents dans `/usr/local/bin`.

### B. Fusionner et déployer le code sur `main`
- La revue whole-branch est faite. **Merger `feat/labs360-inbox` → `main`** et
  `git push origin main`.
- ⚠️ **Rien n'est encore poussé sur `main`** : le site en prod n'a PAS le type `photo` tant que ce n'est pas mergé.

### C. Activer + tester sur le NAS (bout-en-bout réel)
```bash
ssh -i ~/.ssh/id_ed25519_macpro theodorebeaupre@100.99.244.24 'bash -lc "
  cd \"/Volumes/SSD 1/iso-nord\" && git pull --ff-only origin main   # récupère le code fini
  mkdir -p \"/Volumes/SSD 1/iso-nord-media/inbox\"
  cp launchd/com.iso-nord.inbox.plist ~/Library/LaunchAgents/
  launchctl unload ~/Library/LaunchAgents/com.iso-nord.inbox.plist 2>/dev/null
  launchctl load  ~/Library/LaunchAgents/com.iso-nord.inbox.plist
  launchctl list | grep iso-nord
"'
```
- Puis déposer une vraie photo/clip géotagué de Québec dans le partage SMB → dossier
  `inbox/`, et suivre `/Volumes/SSD 1/iso-nord-media/inbox.log`. Attendu : `PUBLIÉ : … →
  pin «<lieu>»`, original déplacé dans `inbox-publies/`, pin en ligne après propagation Vercel.
- Tester aussi un fichier sans GPS mal nommé → doit atterrir dans `inbox-corriger/` + `.txt`.

### D. Vérification réelle restante
- **Publish/wire/build/push réels de `iso-ingest`** (nécessitaient le SSD) : jamais exécutés
  end-to-end — à valider en C avec `--no-push` d'abord (`./scripts/iso-ingest.sh --no-push`)
  puis en réel.

---

## Pièges / points d'attention
- **Deux clones du même repo** (MacBook + NAS). En régime normal le **NAS est le seul
  à auto-pousser**. Après ça, faire `git pull` sur le MacBook avant tout dev. `iso-ingest`
  exige un `git pull --ff-only origin main` réussi en tête de lot avant de publier.
- **Cache média 1 an** : jamais réutiliser un nom de fichier média publié (noms versionnés
  `<id>-<AAAA-MM>[-N].<ext>`); la publication refuse tout chemin déjà présent.
- **Dossiers frères** de `inbox/` (`inbox-corriger/`, `inbox-publies/`, `inbox.log`,
  `inbox.lock`) : hors du dossier surveillé, pour ne pas boucler `WatchPaths`. Créés
  automatiquement par `iso-ingest.sh` au 1er run.
- **exiftool lit le GPS des MP4/MOV DJI** (pas seulement JPEG) → clips supportés.
- Build attendu : **exactement 10 pages**. Compte différent ou build cassé →
  `labs360.ts` restauré, rien poussé.
