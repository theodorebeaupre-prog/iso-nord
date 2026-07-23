# Spec — Boîte de dépôt automatique pour la carte « Québec en 360 »

> Design validé le 2026-07-23. Étend le pipeline `iso360` en une **boîte de dépôt**
> surveillée : Théo glisse un clip, une photo ou un pano fini dans un dossier
> partagé du Mac Pro (NAS), et le lieu apparaît tout seul sur `theo-picture.com/labs/360`.

---

## 1. Problème & objectif

`iso360` (voir `scripts/iso360.sh`) fait déjà : géoloc EXIF → publie sur le tunnel →
câble `src/data/labs360.ts` → build garde-fou → commit/push. Mais :

1. Il faut **lancer la commande à la main** sur un chemin précis.
2. Il ne gère que les **panos 360** (`type: '360'`), pas les clips vidéo ni les photos.

Objectif : **déposer un fichier dans un dossier = pin sur la carte**, sans commande,
sur un Mac Pro **headless (NAS, accès par partage SMB)** — donc **sans aucun popup /
UI graphique** possible. L'interaction se fait uniquement par les fichiers.

## 2. Périmètre

**Inclus :**
- Un dossier de dépôt surveillé (`_inbox/`) sur le partage SMB.
- Surveillance automatique via `launchd` `WatchPaths` (natif macOS, rien à installer).
- Détection du type : vidéo / pano 360 / photo normale.
- Extraction GPS + date via `exiftool` (photos ET vidéos), reverse-geocode Nominatim.
- Génération de poster vidéo via `ffmpeg`.
- Nouveau **type `photo`** sur la carte (lightbox `<img>`).
- Publication tunnel + câblage `labs360.ts` + build garde-fou + commit/push (réutilise `iso360`).
- Gestion « GPS manquant » headless : quarantaine visible + reprise par le **nom de fichier**.

**Exclus (hors périmètre, restent comme aujourd'hui) :**
- Le **stitch des 35 segments DJI bruts** reste sur la commande manuelle `iso360`
  (job CPU 3-4 min, trop lourd/risqué à déclencher sur un simple drop). `_inbox/`
  n'accepte que des **fichiers finis**.
- Toute vraie base de données (SQLite, serveur…). `labs360.ts` **reste la source de
  vérité** — un tableau TypeScript versionné dans git. Suffisant pour un site statique Astro.

## 3. Dépendances à installer

`brew install exiftool ffmpeg` (validé). Aucun des deux n'est présent aujourd'hui.
`fswatch` **non requis** : `launchd`/`WatchPaths` suffit. `sips` + `python3` déjà présents.

## 4. Architecture

**Watcher fin + moteur partagé.** On factorise le cœur commun (géoloc, publie,
câble, build, push) pour que `iso360` (manuel) et `iso-ingest` (auto) le partagent.

```
/Volumes/SSD 1/iso-nord-media/
├── inbox/            ◄── SURVEILLÉ (partage SMB, tu glisses ici)
├── inbox-corriger/       quarantaine GPS/type manquant  (frère, non surveillé)
├── inbox-publies/        archive des originaux publiés   (frère, non surveillé)
├── inbox.log            journal (frère, non surveillé)
├── panoramas/ videos/ photos/   ← médias servis par le tunnel

launchd (WatchPaths sur inbox/ SEUL)  ──►  scripts/iso-ingest.sh
        │  (débounce : attend la stabilité de taille = copie réseau finie)
        ▼
     traite CHAQUE fichier de inbox/ (voir §5)
```

**Important** : les dossiers de quarantaine/archive et le log sont des **frères** de
`inbox/`, pas dedans — sinon chaque écriture (déplacement, log) re-déclencherait
`WatchPaths` en boucle. Seul `inbox/` est surveillé.

### Fichiers créés / modifiés

| Fichier | Rôle |
|---|---|
| `scripts/iso-ingest.sh` | **Nouveau.** Watcher/ingesteur : détecte type, extrait GPS, prépare média, délègue au moteur partagé. Débounce copies réseau. |
| `scripts/iso360-core.sh` | **Nouveau.** Bibliothèque `source`-able : fonctions communes `geo_locate`, `publish_media`, `wire_place`, `build_guard`, `commit_push`. Extrait de `iso360.sh`. |
| `scripts/iso360.sh` | **Modifié.** `source iso360-core.sh` ; garde le stitch DJI + le mode fichier. Comportement inchangé côté utilisateur. |
| `launchd/com.iso-nord.inbox.plist` | **Nouveau.** LaunchAgent `WatchPaths` → lance `iso-ingest.sh`. Doc d'install dans le handoff. |
| `src/data/labs360.ts` | **Modifié.** `PlaceType = '360' \| 'video' \| 'photo'`. |
| `src/scripts/labs360.js` | **Modifié.** Branche lightbox `<img>` pour `photo` ; glyph carte `◆`. |
| `src/components/pages/Labs360.astro` | **Modifié.** Styles lightbox photo + badge « Photo ». |
| `src/i18n/ui.ts` | **Modifié.** `labs360.badgePhoto` (fr/en). |
| `docs/HANDOFF-codex.md` | **Modifié.** Section « boîte de dépôt » (install LaunchAgent, dossiers, dépannage). |

## 5. Flux d'ingestion (`iso-ingest.sh`)

Pour chaque fichier **de premier niveau** de `inbox/` (hors `.*`) :

1. **Débounce** — attendre que la taille du fichier soit stable ~2 s (copie SMB terminée).
   Un fichier encore en cours de copie est ignoré à ce tour (repris au prochain event).
2. **Type** :
   - extension `.mp4` / `.mov` (insensible casse) → `video`
   - image dont le ratio largeur/hauteur ∈ [1.8, 2.2] (via `sips`) → `360`
   - autre image (`.jpg/.jpeg/.png/.heic`) → `photo`
   - sinon → `inbox-corriger/` + `.txt` « type non reconnu » (STOP)
3. **GPS + date** via `exiftool -n` (GPSLatitude/GPSLongitude, DateTimeOriginal ou
   CreateDate). HEIC → converti en JPG (sips) pour le web, EXIF lu avant conversion.
   - GPS présent → reverse-geocode Nominatim (User-Agent `iso360/1.0`) → nom + ville.
   - GPS absent → interpréter le **nom du fichier** (sans extension) :
     - motif `LAT,LON` (ex. `46.89,-71.15`) → coordonnées directes ;
     - sinon texte → **forward-geocode** Nominatim, tirets convertis en espaces
       (ex. `chute-montmorency` → `chute montmorency` → lat/lon).
   - Toujours rien → déplacer vers `inbox-corriger/`, écrire `<nom>.txt` expliquant quoi
     faire (« renomme le fichier avec le lieu, ex. chute-montmorency.jpg, et redépose »). **STOP.**
   - Ville déduite du GPS (lat > 46.3 → `quebec`, sinon `montreal`), comme iso360.
4. **Préparer le média** :
   - `360` → normaliser JPG qualité 88, forcer 2:1 si besoin (sips) — comme le mode fichier de iso360.
   - `video` → copier le MP4 tel quel ; **poster** = frame à ~1 s via
     `ffmpeg -ss 1 -i in.mp4 -frames:v 1 poster.jpg` (publié à côté).
   - `photo` → normaliser JPG qualité 88, largeur max 2560 px (sips).
5. **Publier** sur le tunnel dans le sous-dossier selon le type
   (`panoramas/` | `videos/` | `photos/`), **nom versionné** `<id>-<AAAA-MM>.<ext>`
   (jamais écraser — cache 1 an, cf. handoff §3).
6. **Vérifier** l'URL publique (`curl` → 200, retries) — via `iso360-core`.
7. **Câbler** un nouveau lieu dans `labs360.ts` au marqueur `// iso360:insert`, avec
   le bon `type`, `lat`/`lon`, `poster` (vidéo), média absolu du tunnel — via `iso360-core`.
8. **Build garde-fou** : `npm run build` doit sortir 10 pages ; sinon `git checkout`
   du data file, rien poussé — via `iso360-core`.
9. **commit + push** → déploiement Vercel — via `iso360-core`.
10. **Archiver** l'original : déplacer de `inbox/` vers `inbox-publies/`. En cas d'échec à
    une étape ≥ 6, laisser le fichier dans `inbox/` et logger (pas de perte).

**Concurrence** : un **lockfile** (`inbox.lock`, frère de `inbox/`, via `mkdir` atomique)
empêche deux exécutions simultanées si plusieurs fichiers arrivent en rafale. Le watcher
traite la file séquentiellement (Nominatim = 1 req/s poli ; build = coûteux).

**Journal** : tout est loggué dans `/Volumes/SSD 1/iso-nord-media/inbox.log`
(frère de `inbox/`, visible dans le partage SMB — c'est la « notification » headless).

## 6. Le nouveau type `photo` sur la carte

- `labs360.ts` : `export type PlaceType = '360' | 'video' | 'photo';`
- `labs360.js` :
  - `mountMedia` : `360` → Pannellum (inchangé) ; `photo` → `<img>` dans `mediaHost`
    (lightbox, `loading="lazy"`, `alt` = nom) ; sinon (`video`) → `<video>` (inchangé).
  - glyph annotation carte : `360` → `◉`, `video` → `▶`, `photo` → `◆`.
  - `subtitle`/badge : `photo` → `DATA.badgePhoto`.
- `Labs360.astro` : styles `.l360-modal__panel img` (contain, max-height), badge « Photo ».
- `i18n/ui.ts` : `labs360.badgePhoto` = « Photo » (fr) / « Photo » (en).

## 7. Gestion d'erreurs (récapitulatif)

| Cas | Comportement |
|---|---|
| Copie réseau en cours | Ignoré ce tour (débounce), repris au prochain event |
| Type non reconnu | `inbox-corriger/` + `.txt`, STOP |
| GPS absent + nom inexploitable | `inbox-corriger/` + `.txt` (« renomme avec le lieu »), STOP |
| Nominatim en échec | Retry ; si KO → `inbox-corriger/` + `.txt`, STOP (pas de pin deviné) |
| Stitch/ratio douteux | Avertissement dans le log, continue (comme iso360) |
| URL publique ≠ 200 | STOP, fichier laissé dans `inbox/`, log (tunnel/Caddy down, cf handoff §3) |
| Build cassé | Rollback `labs360.ts`, rien poussé, log |
| Deux fichiers en rafale | Lockfile, traitement séquentiel |

**Principe directeur : ne jamais publier un pin à un endroit deviné.** Sans lieu fiable,
le fichier est mis en quarantaine visible plutôt que placé au hasard sur la carte satellite.

## 8. Tests / validation

- **Photo géotaguée** (téléphone) → pin `photo`, lightbox, bon lieu.
- **Photo sans GPS** → `inbox-corriger/` + `.txt` ; renommée `chute-montmorency.jpg` et
  redéposée → publie au bon lieu (forward-geocode).
- **Nom = coordonnées** (`46.89,-71.15.jpg`) → publie à ces coordonnées.
- **Clip .mp4 géotagué** → pin `video`, poster généré, lecture OK.
- **Pano 2:1 fini** → pin `360`, Pannellum OK.
- **Deux fichiers déposés ensemble** → les deux publiés, séquentiellement, sans collision.
- **iso360 (commande manuelle)** → comportement **inchangé** après refactor (non-régression).
- `npm run build` → **10 pages**, sans erreur, à chaque étape.

## 9. Sécurité / opérations

- Le LaunchAgent tourne sous le compte utilisateur (accès au repo + `git push` + SSD).
- Lecture des seuls fichiers de `_inbox/` ; écritures confinées au tunnel + repo.
- `git push` automatique : le build garde-fou empêche de pousser un site cassé.
- Doc d'installation/désinstallation du LaunchAgent ajoutée au handoff (`launchctl load`).
- Rappel handoff : ne jamais réutiliser un nom de fichier média (cache 1 an) → noms versionnés.
