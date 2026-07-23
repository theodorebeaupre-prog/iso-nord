# Handoff — ISO NORD / theo-picture.com (pour Codex)

> Document de passation. Écrit le 2026-07-22. Tout ce qui suit est vérifié en production
> au moment de l'écriture. Repo, machine locale et site live sont synchronisés.

---

## ⚡ Mise à jour 2026-07-22 (soir) — carte satellite + iso360

- La carte de `/labs/360` n'est plus stylisée : c'est **Apple Maps satellite (MapKit JS)**.
  Les lieux ont maintenant **`lat`/`lon` réelles** (plus de `x`/`y` en %). Le sélecteur
  de ville fait survoler la caméra entre Québec et Montréal.
- **Token MapKit** : fonction serverless `api/mapkit-token.js` (signe un JWT ES256 court,
  origine dérivée du header **Host**). Secrets en variables Vercel (`MAPKIT_KEY_ID`,
  `MAPKIT_TEAM_ID`, `MAPKIT_PRIVATE_KEY_B64`) + `.env` local gitignoré. La clé `.p8`
  n'est JAMAIS committée. L'auth ne marche pas en local (origine restreinte) → tester live.
- **Pièges résolus** (ne pas régresser) : (1) le matcher de `middleware.ts` doit exclure
  `/api` — sinon les visiteurs EN se font rediriger `/api/mapkit-token` → `/en/api/…`
  (404) et la carte ne charge jamais (c'était LE bug iPad) ; (2) dériver l'origine du
  token du header `Host`, pas `Origin` (Safari ne l'envoie pas sur www) ; (3) passer la
  région au **constructeur** `new mapkit.Map` sinon cadrage sur 0°,0°.
- **`iso360 <dossier-session-PANORAMA>`** : nouvelle commande (scripts/iso360.sh, symlink
  /usr/local/bin) qui fait tout — stitch Hugin → géoloc EXIF+Nominatim → tunnel → câblage
  `labs360.ts` (avec lat/lon) → build → push. Options `--replace <id>`, `--name`, `--city`,
  `--no-push`, `--dry-run`.

## TL;DR

`theo-picture.com` est le site vitrine du studio **ISO NORD** (photo/vidéo/drone, Québec).
Deux chantiers ont été menés aujourd'hui :

1. **Récupération de la source** — le repo GitHub était périmé de ~2 mois ; la vraie
   source de production a été récupérée via l'API Vercel et re-committée. GitHub =
   local = live, désormais synchronisés.
2. **Nouvelle page Labs « Québec en 360 »** (`/labs/360`) — carte interactive, pins
   Québec/Montréal, viewer 360 (Pannellum) + modales vidéo. Les panoramas réels sont
   servis **depuis le Mac de Théo** via un **tunnel Cloudflare** (`media.theo-picture.com`).

---

## 1. Environnement & accès

| Élément | Valeur |
|---|---|
| **Repo local** | `~/Desktop/Developer/iso-nord` (⚠️ PAS le disque `/Volumes/DISK THEO/...`) |
| **Remote** | `github.com/theodorebeaupre-prog/iso-nord`, branche `main` |
| **Stack** | Astro 6, Tailwind v4 (tokens CSS custom), GSAP + ScrollTrigger, Lenis, Pannellum 2.5.7 |
| **i18n** | FR (racine) / EN (`/en`), via `src/i18n/ui.ts` + `utils.ts`. Edge Middleware géo/cookie (`middleware.ts`) |
| **Deploy** | Projet Vercel `iso-nord`. Le repo est **connecté à Vercel** → `git push` sur `main` = déploiement auto. `npx vercel deploy --prod` fonctionne aussi. |
| **Dev local** | `npm run dev` → http://localhost:4321. `.claude/launch.json` a une config `iso-nord-dev`. |
| **Build** | `npm run build` → doit sortir **10 pages** sans erreur. |
| **Node** | `>=22.12.0` (voir `package.json`) |

### Comptes Cloudflare — IMPORTANT, il y en a deux
- **theodore.beaupre@icloud.com** → détient la zone **theo-picture.com** (c'est LE bon compte).
- Un **autre** compte détient **iso-nord.ca** + des tunnels `n8n` et `ai-software-shop`.
- Piège vécu : `cloudflared tunnel login` autorise une zone d'un compte ; un tunnel ne
  route que les zones de SON compte. Si un jour tu recrées le tunnel, connecte-toi au
  compte iCloud (celui de theo-picture.com).

### Registrar
Domaine acheté chez **IONOS** (mars 2026), nameservers délégués à Cloudflare.

---

## 2. La page « Québec en 360 » — carte des fichiers

| Fichier | Rôle |
|---|---|
| `src/pages/labs/360.astro` | Route FR (wrapper mince → `<Labs360 lang="fr" />`) |
| `src/pages/en/labs/360.astro` | Route EN |
| `src/components/pages/Labs360.astro` | **Page complète** : head, nav, hero, sélecteur ville, carte + pins, modale viewer, footer, tous les styles scoped |
| `src/data/labs360.ts` | **LE fichier de données** — c'est ici qu'on ajoute/édite les lieux et les URLs média. Le seul que Théo touche régulièrement. |
| `src/scripts/labs360.js` | Interactions : Lenis/GSAP, sélecteur ville (cross-fade + hash), modale, **Pannellum en dynamic import** (chargé au 1er pin 360), focus piégé |
| `src/i18n/ui.ts` | Section `labs360` (fr + en) : tout le chrome UI. Aussi le projet dans la liste `labs` (lien vers la page). |
| `src/i18n/utils.ts` | `PAGES.labs360` (routes + hreflang) |
| `public/assets/labs360/*.png` | Panoramas placeholder synthétiques (générés, pas des vrais) |
| `docs/superpowers/specs/2026-07-22-labs-360-map-design.md` | Spec de conception |
| `docs/superpowers/plans/2026-07-22-labs-360-map.md` | Plan d'implémentation détaillé |

### Modèle de données (`src/data/labs360.ts`)
```ts
interface Labs360Place {
  id: string;                    // slug stable
  city: 'quebec' | 'montreal';
  type: '360' | 'video';
  name: string;                  // identique fr/en
  desc: { fr: string; en: string };
  credit: string;                // '' = ligne crédit masquée (voir plus bas)
  x: number; y: number;          // position du pin en % sur la carte (0–100)
  media: string;                 // relatif → MEDIA_BASE ; absolu (/… ou https://) → tel quel
  poster?: string;               // affiche vidéo
}
export const MEDIA_BASE = import.meta.env.PUBLIC_MEDIA_BASE ?? '/assets/labs360';
```
- `mediaUrl(path)` : préfixe les chemins relatifs par `MEDIA_BASE`, laisse passer les absolus.
- **Crédits** : `credit: ''` → la ligne « Capté par … » est masquée. On remplit avec un
  nom réel quand une collaboration est confirmée (les placeholders `[contributeur]` ont
  été retirés exprès pour ne pas traîner en public).

### Contrat DOM (si tu touches au JS/markup)
`labs360.js` dépend de : `[data-city-btn]`, `.l360-pins[data-city]`,
`.l360-pin[data-place-id]`, `[data-legend-city]`, `#l360-modal`, `#l360-media`,
`#l360-title`, `.l360-modal__{desc,credit,hint,fallback}`, `[data-modal-close]`,
et un `<script type="application/json" id="l360-data">` injecté par le composant.

---

## 3. Infra média — le tunnel Cloudflare (à bien comprendre)

Le site charge les vrais panoramas/vidéos depuis le **Mac de Théo**, sans ouvrir de
port sur le routeur. Chaîne complète :

```
Visiteur → Cloudflare edge (cache) → tunnel `iso-nord-media`
        → cloudflared (LaunchDaemon, démarre au boot)
        → Caddy 127.0.0.1:8787 (LaunchDaemon brew, lecture seule, pas de listing)
        → /Volumes/SSD 1/iso-nord-media/{panoramas,videos}/
```

| Élément | Chemin / valeur |
|---|---|
| **Sous-domaine public** | `https://media.theo-picture.com` |
| **Dossier servi** | `/Volumes/SSD 1/iso-nord-media/` (sous-dossiers `panoramas/`, `videos/`) |
| **Tunnel ID** | `49d415fb-150d-4a2d-81ab-158176717e1d` (nom `iso-nord-media`) |
| **Config tunnel (user)** | `~/.cloudflared/config.yml` |
| **Config tunnel (daemon)** | `/usr/local/etc/cloudflared/config.yml` + credentials `.json` à côté |
| **LaunchDaemon tunnel** | `/Library/LaunchDaemons/com.cloudflare.cloudflared.plist` (lance `cloudflared tunnel --config … run`) |
| **Config Caddy** | `/usr/local/etc/Caddyfile` |
| **LaunchDaemon Caddy** | `/Library/LaunchDaemons/homebrew.mxcl.caddy.plist` |

### Pièges déjà rencontrés (ne pas refaire)
1. **Caddy doit matcher n'importe quel Host.** Le Caddyfile utilise `http://:8787` +
   `bind 127.0.0.1`. Ne PAS mettre `http://127.0.0.1:8787` comme adresse de site : le
   tunnel transmet le Host `media.theo-picture.com`, aucun site ne matcherait → Caddy
   renvoie des **200 vides**. (Symptôme trompeur : `curl` local marche car il envoie
   `Host: 127.0.0.1`.)
2. **cloudflared LaunchDaemon** : le plist généré par `cloudflared service install` ne
   passe PAS la sous-commande `tunnel … run` → le daemon boucle. Le plist a été corrigé
   à la main (voir `ProgramArguments`).

### Headers de cache (dans le Caddyfile)
- `Cache-Control: public, max-age=31536000, immutable`
- `Access-Control-Allow-Origin: *` ← **requis** par Pannellum (WebGL, sinon canvas tainté)
- **Règle d'or** : ne JAMAIS remplacer un fichier sous le même nom (cache 1 an). Versionne
  le nom (`vieux-quebec-v2.jpg`) ou purge le cache Cloudflare.
- ⚠️ **Les MP4 ne sont PAS cachés à l'edge par défaut** (Cloudflare cache surtout les
  images). Pour du volume vidéo, ajouter une Cache Rule (zone theo-picture.com → Rules →
  Cache Rules : hostname `media.theo-picture.com` → Eligible for cache), ou viser R2.

### Sécurité en place
Lecture seule, confiné à `/Volumes/SSD 1/iso-nord-media`, listing de répertoire → 404,
fichiers cachés (`.*`) → 404, Caddy écoute seulement le loopback (invisible du LAN),
IP résidentielle derrière le proxy Cloudflare.

---

## 4. Workflow — ajouter un vrai panorama

1. Obtenir un équirectangulaire 2:1 (voir §5 pour le stitching depuis les segments DJI).
2. Déposer dans `/Volumes/SSD 1/iso-nord-media/panoramas/` avec un **nom versionné**.
3. Vérifier public : `curl -sI https://media.theo-picture.com/panoramas/<nom>.jpg`
   → attendu `200`, `access-control-allow-origin: *`.
4. Mettre l'URL absolue dans le lieu concerné de `src/data/labs360.ts`.
5. `npm run build` (10 pages), puis `git push` → déploiement Vercel auto.

### Brancher toute la base sur le tunnel d'un coup (optionnel)
Au lieu d'URLs absolues par lieu, définir l'env Vercel
`PUBLIC_MEDIA_BASE=https://media.theo-picture.com/panoramas` et mettre des chemins
relatifs (`vieux-quebec.jpg`) dans les données. C'était l'intention de la variable.

---

## 5. Stitching de panoramas (Hugin CLI)

Le drone DJI **ne sauvegarde PAS le pano assemblé** sur la carte SD — seulement les 35
segments bruts dans `DCIM/PANORAMA/<session>/PANO_*.JPG`. Le pano fini reste dans l'app
DJI Fly. Donc on stitche nous-mêmes avec **Hugin** (`brew install --cask hugin`,
binaires dans `/Applications/Hugin/tools_mac`).

Pipeline (testé, ~3–4 min/pano sur cette machine) :
```bash
export PATH="/Applications/Hugin/tools_mac:$PATH"
# downscaler d'abord chaque segment à ~2016px accélère cpfind sans perte visible
pto_gen -o pano.pto *.jpg
cpfind --multirow --celeste -o pano.pto pano.pto      # étape longue (détection points)
cpclean -o pano.pto pano.pto
autooptimiser -a -m -l -s -o pano.pto pano.pto        # viser erreur < ~5 px
pano_modify --projection=2 --fov=360x180 --canvas=6300x3150 -o pano.pto pano.pto
nona -m TIFF_m -o seg_ pano.pto
enblend -o pano-stitched.tif seg_*.tif
sips -s format jpeg -s formatOptions 85 pano-stitched.tif --out pano.jpg
sips --padToHeightWidth 3150 6300 --padColor FFFFFF pano.jpg --out pano-2to1.jpg  # force 2:1
```

### ⚠️ Limite connue : les panos d'hiver échouent
Session `001_0307` (Maizerets, 14 déc 2025, neige) : `autooptimiser` a convergé à ~10 px
d'erreur et `enblend` a produit un TIFF vide (8 octets). La neige = trop peu de points de
contrôle distincts pour l'auto-matching. Pistes : ajouter des points manuels dans Hugin
GUI, ou baisser le seuil `celeste`, ou stitcher une session non-enneigée.

### Vérifier le lieu réel d'un pano (EXIF GPS)
Un script maison lit `DateTimeOriginal` + GPS d'un JPEG sans dépendance (utilisé pour
corriger l'attribution Patro↔Maizerets). Reverse-geocode via Nominatim :
```bash
curl -s "https://nominatim.openstreetmap.org/reverse?lat=<LAT>&lon=<LON>&format=json&accept-language=fr&zoom=17" \
  -H "User-Agent: iso-nord-check"
```

## 5bis. Boîte de dépôt automatique (iso-ingest)

Déposer un fichier dans le partage SMB `/Volumes/SSD 1/iso-nord-media/inbox/`
publie automatiquement un pin sur `/labs/360`. Sur le Mac Pro NAS **headless** :
aucun popup — tout passe par les fichiers et le log.

| Élément | Chemin |
|---|---|
| Dossier de dépôt (surveillé) | `/Volumes/SSD 1/iso-nord-media/inbox/` |
| Quarantaine (GPS/type manquant) | `/Volumes/SSD 1/iso-nord-media/inbox-corriger/` |
| Archive (originaux publiés) | `/Volumes/SSD 1/iso-nord-media/inbox-publies/` |
| Journal | `/Volumes/SSD 1/iso-nord-media/inbox.log` |
| Script | `scripts/iso-ingest.sh` (cœur partagé : `scripts/iso360-core.sh`) |
| LaunchAgent | `~/Library/LaunchAgents/com.iso-nord.inbox.plist` |

**Types :** `.mp4/.mov` → clip (poster ffmpeg) ; image ~2:1 → pano 360 ; autre
image → photo (lightbox). **GPS** via exiftool ; si absent, le **nom du fichier**
sert de repli (`chute-montmorency.jpg` géocodé, ou `46.89,-71.15.jpg` en coordonnées).
Sans lieu fiable → `inbox-corriger/` + un `.txt` explicatif (renommer + redéposer).
Une panne Nominatim est retentée avec timeout puis mène aussi en quarantaine : aucun
nom ou pin n'est inventé. Les collisions reçoivent un suffixe (`-2`, `-3`…) et une
publication média existante n'est jamais écrasée (cache immutable).

**Dépendances :** `brew install exiftool ffmpeg`. **Ne stitche PAS** les 35 segments
DJI bruts (ça reste la commande manuelle `iso360`) — l'inbox n'accepte que des
fichiers finis.

**(Ré)installer le watcher sur le NAS Intel :**
```bash
mkdir -p "/Volumes/SSD 1/iso-nord-media/inbox"
cp launchd/com.iso-nord.inbox.plist ~/Library/LaunchAgents/
launchctl unload ~/Library/LaunchAgents/com.iso-nord.inbox.plist 2>/dev/null
launchctl load ~/Library/LaunchAgents/com.iso-nord.inbox.plist
```

**Dépannage :** logs dans `inbox.log` (+ `inbox-launchd.err.log`). Rien ne se passe →
`launchctl list | grep iso-nord`. GPS manquant → voir `inbox-corriger/`. URL 200 KO →
tunnel/Caddy (cf §3). Le plist du Mac Pro Intel utilise `/usr/local/bin` pour
Homebrew. Son script pointe vers le clone NAS `/Volumes/SSD 1/iso-nord`.
Le verrou contient le PID et récupère automatiquement un lock laissé par un crash.
`--dry-run` reste en lecture seule (aucun dossier, lock, log, média ou changement git).
Avant l'archive, le pipeline exige build = 10 pages, commit et, sauf `--no-push`, push réussi.

---

## 6. État actuel des 8 lieux (`labs360.ts`)

| id | ville | type | média actuel | statut |
|---|---|---|---|---|
| `vieux-quebec` | QC | 360 | `…/pano-vieux-quebec-demo.jpg` (tunnel) | **placeholder synthétique** (généré, pas réel) |
| `chute-montmorency` | QC | 360 | `pano-chute-montmorency.png` (local) | placeholder |
| `ile-orleans` | QC | video | `/assets/hero-camera.mp4` | placeholder (clip réutilisé) |
| `maizerets` | QC | 360 | `pano-maizerets.png` (local) | placeholder (stitch hiver a échoué) |
| `patro-roc-amadour` | QC | 360 | `…/patro-roc-amadour-2026.jpg` (tunnel) | ✅ **VRAI pano drone** (28 juin 2026, Lairet/Limoilou) |
| `vieux-port` | MTL | 360 | `pano-vieux-port.png` (local) | placeholder |
| `mont-royal` | MTL | video | `/assets/hero-camera.mp4` | placeholder |
| `centre-ville` | MTL | video | `/assets/hero-camera.mp4` | placeholder |

Un seul lieu a du vrai contenu : **Patro Roc-Amadour**. Tout le reste attend des captations.

### Sessions PANORAMA encore dispos sur la carte SD (`/Volumes/SD_Card/DCIM/PANORAMA/`)
- `001_0190` — 13 oct 2025, Maizerets/Corridor du Littoral (35 seg)
- `001_0218` — 25 oct 2025, Beauport/Giffard, alt 414 m (35 seg)
- `001_0307` — 14 déc 2025, Maizerets rue Adjutor-Rivard, **hiver → stitch échoue** (35 seg)
- `001_0693` / `001_0694` — 28 juin 2026, Lairet (23 / 35 seg ; `0694` = le Patro déjà stitché)

---

## 7. Ménage / dette à traiter (non bloquant)

1. **Fichiers média orphelins** sur le tunnel (`/Volumes/SSD 1/iso-nord-media/panoramas/`) :
   - `maizerets-limoilou-2026.jpg` — ancien nom erroné du pano Patro, **plus référencé**
     par le code (le commit `d14b312` le mentionne encore dans l'historique). Supprimable.
   - `pano-test.png` — fichier de test de mise en place. Supprimable.
2. **DNS parasite** : dans la zone **iso-nord.ca** (l'autre compte Cloudflare), un
   enregistrement `media.theo-picture.com.iso-nord.ca` a été créé lors d'une 1re tentative
   ratée. À supprimer (DNS → Records).
3. **Commit `d14b312`** a un message trompeur (« pano for Maizerets ») — c'était en fait
   le Patro ; corrigé fonctionnellement par `5b36b36`, mais l'historique reste. Ne pas
   réécrire l'historique (déjà pushé/déployé).
4. **Reboot** : si « SSD 1 » monte après Caddy au démarrage, les fichiers répondent 404
   quelques secondes le temps du montage. Sans gravité.

---

## 8. Prochaines étapes suggérées

- Stitcher les sessions `0190` / `0218` / `0693`, identifier les lieux (EXIF GPS +
  Nominatim), et remplacer les placeholders `chute-montmorency` / `maizerets` /
  `vieux-port` par du vrai contenu.
- Régler le stitch hiver (points manuels Hugin) si on veut garder la vue enneigée de Maizerets.
- Quand des collaborateurs sont confirmés, remplir les `credit:` correspondants.
- Si les clips vidéo montent en trafic : Cache Rule Cloudflare pour les MP4, ou passer les
  médias lourds sur **Cloudflare R2** (l'archi est déjà prête via `PUBLIC_MEDIA_BASE`).

---

## Références rapides

- Historique récent : `git log --oneline` (tous les commits `feat(labs360)` / `fix(labs360)`)
- Vérifier le tunnel : `cloudflared tunnel info iso-nord-media`
- Logs daemon : `/Library/Logs/com.cloudflare.cloudflared.{out,err}.log`
- Recharger Caddy après édition : `caddy reload --config /usr/local/etc/Caddyfile`
- Le site live sert du FR par défaut au Québec (géo) ; forcer une langue au test :
  `curl -H "Cookie: lang=en" https://theo-picture.com/en/labs/360`
