# Labs 360 — Atlas cinématographique Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transformer Labs 360 en vitrine client cinématographique, bilingue, accessible et rapide, basée uniquement sur les six captations réelles de Québec.

**Architecture:** Astro rend le hero, la collection, le SEO et les états de repli côté serveur. Les données restent centralisées dans `labs360.ts`; de petits modules JavaScript testables ajoutent progressivement le chargement différé de MapKit, le viewer et sa navigation. Les aperçus WebP locaux empêchent les panoramas de 4–18 Mo de charger avant une action explicite.

**Tech Stack:** Astro 6, TypeScript, JavaScript ESM, MapKit JS, Pannellum, GSAP, Lenis, shell tests, Node `assert`, `cwebp`.

## Global Constraints

- Afficher exactement les six lieux réels : `maizerets`, `patro-roc-amadour`, `giffard`, `centre-monseigneur-marcoux`, `limoilou`, `colline-parlementaire`.
- Ne jamais publier Montréal ou un ancien ID fictif.
- Ne modifier aucun média distant sous son nom existant.
- Ne pousser aucun commit Intercom local.
- Garder FR à `/labs/360` et EN à `/en/labs/360`.
- Garder le build à exactement 10 pages.
- N’ajouter aucune dépendance npm.
- HTML initial inférieur à 35 Ko; JS Labs propre inférieur à 20 Ko non compressé.
- Aucun panorama, Pannellum ou MapKit dans les requêtes initiales.
- Somme des six aperçus inférieure à 1,8 Mo; chaque aperçu inférieur à 350 Ko.
- Toute modification fonctionnelle suit RED → GREEN → REFACTOR.

---

## File Structure

- `src/data/labs360.ts` — source unique des lieux, previews et métadonnées de captation.
- `public/assets/labs360/previews/*.webp` — six dérivés légers des médias réels.
- `src/i18n/ui.ts` — tous les textes et libellés FR/EN.
- `src/components/pages/Labs360.astro` — rendu SSR, collection, SEO, JSON-LD et styles.
- `src/scripts/labs360.js` — orchestration page/viewer.
- `src/scripts/labs360-map.js` — région et création des annotations.
- `src/scripts/labs360-map-loader.js` — chargement différé et borné de MapKit.
- `src/scripts/labs360-view.js` — navigation circulaire et fonctions pures du viewer.
- `src/scripts/labs360-motion.js` — politique de mouvement.
- `scripts/iso360-core.sh`, `scripts/iso360.sh`, `scripts/iso-ingest.sh` — refus Montréal et génération des nouveaux aperçus.
- `tests/labs360-page.sh` — contrat page/données/SEO/performance statique.
- `tests/labs360-pipeline.sh` — contrat d’ingestion Québec seulement.

---

### Task 1: Contrat de données réel et aperçus optimisés

**Files:**
- Modify: `tests/labs360-page.sh`
- Modify: `src/data/labs360.ts`
- Create: `public/assets/labs360/previews/maizerets.webp`
- Create: `public/assets/labs360/previews/patro-roc-amadour.webp`
- Create: `public/assets/labs360/previews/giffard.webp`
- Create: `public/assets/labs360/previews/centre-monseigneur-marcoux.webp`
- Create: `public/assets/labs360/previews/limoilou.webp`
- Create: `public/assets/labs360/previews/colline-parlementaire.webp`

**Interfaces:**
- Produces: chaque `Labs360Place` expose `capturedAt: string`, `preview: string`, `previewWidth: number`, `previewHeight: number`, `featured?: boolean`.
- Produces: exactement un lieu `featured`.
- Consumes: URLs réelles existantes dans `media`.

- [ ] **Step 1: Ajouter le test de schéma et de budget média**

Ajouter à `tests/labs360-page.sh` une fonction qui :

```bash
test_real_place_metadata_and_previews() {
  local preview total=0
  [ "$(rg -c 'featured: true' "$DATA")" -eq 1 ] || {
    fail "un seul lieu doit alimenter le hero"; return;
  }
  [ "$(rg -c 'capturedAt:' "$DATA")" -eq 6 ] || {
    fail "les six lieux doivent avoir une date de captation"; return;
  }
  [ "$(rg -c 'preview:' "$DATA")" -eq 6 ] || {
    fail "les six lieux doivent avoir un aperçu local"; return;
  }
  for preview in "$ROOT"/public/assets/labs360/previews/*.webp; do
    [ -f "$preview" ] || { fail "aperçu WebP manquant"; return; }
    size="$(stat -f%z "$preview")"
    [ "$size" -lt 358400 ] || { fail "$(basename "$preview") dépasse 350 Ko"; return; }
    total=$((total + size))
  done
  [ "$total" -lt 1887437 ] || { fail "les aperçus dépassent 1,8 Mo"; return; }
  pass "métadonnées et aperçus réels respectent le budget"
}
```

L’appeler avant le résumé final.

- [ ] **Step 2: Exécuter le test et confirmer RED**

Run: `bash tests/labs360-page.sh`  
Expected: FAIL sur `un seul lieu doit alimenter le hero`.

- [ ] **Step 3: Générer les six previews à partir des vrais médias**

Télécharger les six originaux dans un dossier `mktemp -d`, puis exécuter :

```bash
mkdir -p public/assets/labs360/previews
cwebp -quiet -resize 1600 0 -q 78 "$TMP/maizerets.jpg" -o public/assets/labs360/previews/maizerets.webp
cwebp -quiet -resize 1600 0 -q 78 "$TMP/patro.jpg" -o public/assets/labs360/previews/patro-roc-amadour.webp
cwebp -quiet -resize 1600 0 -q 76 "$TMP/giffard.jpg" -o public/assets/labs360/previews/giffard.webp
cwebp -quiet -resize 1600 0 -q 76 "$TMP/marcoux.jpg" -o public/assets/labs360/previews/centre-monseigneur-marcoux.webp
cwebp -quiet -resize 1600 0 -q 78 "$TMP/limoilou.jpg" -o public/assets/labs360/previews/limoilou.webp
cwebp -quiet -resize 1600 0 -q 78 "$TMP/colline.jpg" -o public/assets/labs360/previews/colline-parlementaire.webp
```

Si un fichier dépasse 350 Ko, réduire sa qualité par pas de 4 jusqu’au respect du
budget. Relever les dimensions réelles avec `sips -g pixelWidth -g pixelHeight`.

- [ ] **Step 4: Étendre le modèle de données**

Dans `src/data/labs360.ts` :

```ts
export type City = 'quebec';

export interface Labs360Place {
  id: string;
  city: City;
  type: PlaceType;
  name: string;
  desc: { fr: string; en: string };
  credit: string;
  capturedAt: string;
  lat: number;
  lon: number;
  media: string;
  preview: string;
  previewWidth: number;
  previewHeight: number;
  featured?: boolean;
  poster?: string;
}
```

Ajouter à chaque lieu `capturedAt`, `preview`, dimensions relevées, et seulement à
Maizerets `featured: true`.

- [ ] **Step 5: Vérifier GREEN**

Run: `bash tests/labs360-page.sh`  
Expected: 9 réussites, 0 échec.

- [ ] **Step 6: Commit**

```bash
git add tests/labs360-page.sh src/data/labs360.ts public/assets/labs360/previews
git commit -m "feat(labs360): add optimized real-media previews"
```

---

### Task 2: Pipeline Québec seulement

**Files:**
- Modify: `tests/labs360-pipeline.sh`
- Modify: `scripts/iso360-core.sh`
- Modify: `scripts/iso360.sh`
- Modify: `scripts/iso-ingest.sh`

**Interfaces:**
- Produces: `core_require_quebec <city>` retourne 0 uniquement pour `quebec`.
- Produces: le câblage d’un nouveau lieu écrit les champs preview et date requis.
- Consumes: sortie JSON de `core_geocode`.

- [ ] **Step 1: Remplacer le test Montréal invisible par un refus avant mutation**

Créer un test qui appelle le pipeline avec une sortie géocodée
`"city":"montreal"` et affirme :

```bash
[ "$status" -ne 0 ]
rg -q 'Québec seulement' "$output"
[ ! -e "$case_dir/repo/public/assets/labs360/previews/montreal.webp" ]
[ "$(git -C "$case_dir/repo" rev-parse HEAD)" = "$before_head" ]
```

Ajouter aussi un test unitaire shell :

```bash
source "$ROOT/scripts/iso360-core.sh"
core_require_quebec quebec
! core_require_quebec montreal
```

- [ ] **Step 2: Exécuter et confirmer RED**

Run: `bash tests/labs360-pipeline.sh`  
Expected: FAIL parce que Montréal est actuellement toléré.

- [ ] **Step 3: Implémenter le garde Québec**

Dans `scripts/iso360-core.sh` :

```bash
core_require_quebec() {
  [[ "${1:-}" == "quebec" ]] || {
    err "Labs 360 publie Québec seulement; destination refusée."
    return 1
  }
}
```

L’appeler immédiatement après géocodage dans `iso360.sh` et `iso-ingest.sh`,
avant copie média, câblage, build ou commit. Retirer `montreal` de l’aide
`--city`.

- [ ] **Step 4: Câbler les nouveaux champs**

Faire écrire par `core_wire_data` :

```python
captured_at=g.get('ym') or '',
preview=f"/assets/labs360/previews/{g['id']}.webp",
```

Avant `core_wire_data`, générer l’aperçu via `cwebp -resize 1600 0 -q 78` dans le
repo et échouer si `cwebp` manque. Conserver l’original et l’aperçu dans le même
rollback transactionnel.

- [ ] **Step 5: Vérifier GREEN**

Run: `bash tests/labs360-pipeline.sh`  
Expected: toutes les réussites, 0 échec.

- [ ] **Step 6: Commit**

```bash
git add tests/labs360-pipeline.sh scripts/iso360-core.sh scripts/iso360.sh scripts/iso-ingest.sh
git commit -m "fix(labs360): restrict ingestion to real Quebec captures"
```

---

### Task 3: Copy bilingue, rendu éditorial et SEO

**Files:**
- Modify: `tests/labs360-page.sh`
- Modify: `src/i18n/ui.ts`
- Modify: `src/components/pages/Labs360.astro`

**Interfaces:**
- Consumes: les nouveaux champs `preview`, dimensions, `capturedAt`, `featured`.
- Produces: `.l360-collection [data-place-id]`, JSON-LD `CollectionPage`,
  `og:image`, `twitter:card`, CTA `#captures`.
- Produces: runtime localisé avec `previous`, `next`, `counter`, `mapError`.

- [ ] **Step 1: Écrire les tests SSR/SEO/accessibilité**

Tester dans `tests/labs360-page.sh` :

```bash
rg -Fq 'id="captures"' "$PAGE"
rg -Fq 'class="l360-card"' "$PAGE"
rg -Fq 'loading="lazy"' "$PAGE"
rg -Fq 'decoding="async"' "$PAGE"
rg -Fq 'application/ld+json' "$PAGE"
rg -Fq 'CollectionPage' "$PAGE"
rg -Fq 'twitter:card' "$PAGE"
rg -Fq 'og:image' "$PAGE"
rg -Fq '<noscript>' "$PAGE"
rg -Fq 'aria-live="polite"' "$PAGE"
rg -Fq 'data-view-previous' "$PAGE"
rg -Fq 'data-view-next' "$PAGE"
```

Après build, compter six `l360-card` et les six noms dans les HTML FR et EN.

- [ ] **Step 2: Exécuter et confirmer RED**

Run: `bash tests/labs360-page.sh`  
Expected: FAIL sur la collection ou les métadonnées sociales.

- [ ] **Step 3: Ajouter la copy FR/EN**

Ajouter dans chaque objet `labs360` :

```ts
heroKicker, titleLines, lede, exploreCta, captureCount, mediaKinds,
mapTitle, mapIntro, collectionEyebrow, collectionTitle, collectionIntro,
openCapture, previous, next, counter, captured, mapLoading, mapUnavailable,
noScript, shareDescription
```

FR doit commencer par « Québec, vu autrement. » et EN par
« Québec, from another perspective. ». Aucun texte ne mentionne Montréal ou des
clips non publiés.

- [ ] **Step 4: Rendre hero, carte compacte et collection**

Dans `Labs360.astro`, calculer :

```ts
const visiblePlaces = PLACES;
const featured = visiblePlaces.find((place) => place.featured) ?? visiblePlaces[0];
const socialImage = SITE + featured.preview;
```

Rendre six boutons `.l360-card` avec image, type, date, nom et description. Ajouter
un CTA vers `#captures`, des statistiques dynamiques et un `<noscript>`.

- [ ] **Step 5: Ajouter les métadonnées**

Ajouter les balises Open Graph/Twitter avec dimensions du preview vedette, puis :

```ts
const structuredData = {
  '@context': 'https://schema.org',
  '@type': 'CollectionPage',
  name: l.title,
  description: l.description,
  url: canonical,
  inLanguage: lang === 'fr' ? 'fr-CA' : 'en-CA',
  mainEntity: {
    '@type': 'ItemList',
    numberOfItems: visiblePlaces.length,
    itemListElement: visiblePlaces.map((place, index) => ({
      '@type': 'ListItem',
      position: index + 1,
      item: {
        '@type': 'CreativeWork',
        name: place.name,
        description: place.desc[lang],
        contentUrl: mediaUrl(place.media),
        thumbnailUrl: SITE + place.preview,
        spatialCoverage: {
          '@type': 'Place',
          name: place.name,
          geo: { '@type': 'GeoCoordinates', latitude: place.lat, longitude: place.lon },
        },
      },
    })),
  },
};
```

- [ ] **Step 6: Vérifier GREEN et le build**

Run: `bash tests/labs360-page.sh && npm run build`  
Expected: tests verts et `10 page(s) built`.

- [ ] **Step 7: Commit**

```bash
git add tests/labs360-page.sh src/i18n/ui.ts src/components/pages/Labs360.astro
git commit -m "feat(labs360): build cinematic capture collection"
```

---

### Task 4: MapKit différé et repli fiable

**Files:**
- Create: `src/scripts/labs360-map-loader.js`
- Modify: `src/scripts/labs360-map.js`
- Modify: `src/scripts/labs360.js`
- Modify: `src/components/pages/Labs360.astro`
- Modify: `tests/labs360-page.sh`

**Interfaces:**
- Produces: `loadMapKit({ document, window, timeoutMs }): Promise<object>`.
- Produces: `observeMap(element, callback, IntersectionObserverClass)`.
- Produces: `createMap({ mapkit, elementId, places, onSelect })`.

- [ ] **Step 1: Écrire les tests Node du chargeur**

Ajouter un bloc Node qui vérifie :

```js
assert.equal(document.querySelectorAll('script[data-mapkit-loader]').length, 0);
const promiseA = loadMapKit(env);
const promiseB = loadMapKit(env);
assert.equal(promiseA, promiseB);
assert.equal(document.querySelectorAll('script[data-mapkit-loader]').length, 1);
script.dispatchEvent(new Event('load'));
assert.equal(await promiseA, window.mapkit);
```

Tester aussi rejet `MapKit indisponible` au timeout et appel unique de
`observeMap` lorsque l’intersection devient vraie.

- [ ] **Step 2: Exécuter et confirmer RED**

Run: `bash tests/labs360-page.sh`  
Expected: FAIL car `labs360-map-loader.js` n’existe pas.

- [ ] **Step 3: Implémenter le chargeur**

Créer un cache de promesse module-scoped, injecter :

```js
script.src = 'https://cdn.apple-mapkit.com/mk/5.x.x/mapkit.js';
script.crossOrigin = 'anonymous';
script.dataset.mapkitLoader = '';
```

Résoudre au `load`, rejeter au `error` ou après `timeoutMs`, et déconnecter
l’IntersectionObserver après la première intersection.

- [ ] **Step 4: Extraire la création de carte**

Déplacer l’initialisation MapKit dans `createMap`. Garder la région au
constructeur, les six annotations, la correction IntersectionObserver iOS et
`onSelect(place.id)`.

- [ ] **Step 5: Brancher le chargement progressif**

Retirer le `<script id="mapkit-js">` du `<head>`. Observer la carte avec une
`rootMargin: '500px 0px'`, afficher l’état chargement, puis carte ou erreur.

- [ ] **Step 6: Vérifier GREEN**

Run: `bash tests/labs360-page.sh && npm run build`  
Expected: tests verts; aucun `cdn.apple-mapkit.com` dans le `<head>` construit.

- [ ] **Step 7: Commit**

```bash
git add tests/labs360-page.sh src/scripts/labs360-map-loader.js src/scripts/labs360-map.js src/scripts/labs360.js src/components/pages/Labs360.astro
git commit -m "perf(labs360): defer MapKit until the map is near"
```

---

### Task 5: Viewer accessible avec navigation

**Files:**
- Modify: `src/scripts/labs360-view.js`
- Modify: `src/scripts/labs360.js`
- Modify: `src/components/pages/Labs360.astro`
- Modify: `tests/labs360-page.sh`

**Interfaces:**
- Produces: `adjacentPlaceId(places, currentId, direction)`.
- Produces: `counterLabel(index, total, pattern)`.
- Consumes: runtime localisé et IDs `[data-view-previous]`, `[data-view-next]`.

- [ ] **Step 1: Écrire les tests purs**

```js
assert.equal(adjacentPlaceId(places, 'a', 1), 'b');
assert.equal(adjacentPlaceId(places, 'c', 1), 'a');
assert.equal(adjacentPlaceId(places, 'a', -1), 'c');
assert.equal(counterLabel(0, 6, '{current} / {total}'), '01 / 06');
```

Tester aussi ID inconnu → premier lieu.

- [ ] **Step 2: Exécuter et confirmer RED**

Run: `bash tests/labs360-page.sh`  
Expected: FAIL parce que les fonctions n’existent pas.

- [ ] **Step 3: Implémenter navigation et compteur**

Ajouter les fonctions pures dans `labs360-view.js`. Dans la modale, ajouter
précédent, compteur `aria-live`, suivant. Mettre à jour le contenu sans fermer le
dialogue.

- [ ] **Step 4: Ajouter clavier, inert et nettoyage**

- `ArrowLeft`/`ArrowRight` changent de lieu hors champ de formulaire;
- `Escape` ferme;
- Tab reste piégé;
- `main`, nav et footer deviennent `inert` pendant l’ouverture puis sont restaurés;
- un changement de lieu détruit Pannellum ou arrête la vidéo précédente;
- une erreur média conserve les contrôles;
- le focus revient au bouton initial à la fermeture.

- [ ] **Step 5: Empêcher le chargement initial de Pannellum**

Conserver ses imports dynamiques uniquement dans la branche `type === '360'`.
Vérifier que le CSS Pannellum n’est plus émis comme stylesheet initial; si Astro
l’extrait encore, remplacer l’import CSS dynamique par une injection `<link>`
créée au même moment que le premier panorama.

- [ ] **Step 6: Vérifier GREEN**

Run: `bash tests/labs360-page.sh && npm run build`  
Expected: tests verts et aucun lien `pannellum*.css` dans les HTML construits.

- [ ] **Step 7: Commit**

```bash
git add tests/labs360-page.sh src/scripts/labs360-view.js src/scripts/labs360.js src/components/pages/Labs360.astro
git commit -m "feat(labs360): add accessible capture navigation"
```

---

### Task 6: Polish responsive, mouvement et budgets

**Files:**
- Modify: `src/components/pages/Labs360.astro`
- Modify: `src/scripts/labs360.js`
- Modify: `src/scripts/labs360-motion.js`
- Modify: `tests/labs360-page.sh`

**Interfaces:**
- Consumes: markup des tâches 3–5.
- Produces: layout sans overflow à 390, 820 et 1440 px.

- [ ] **Step 1: Écrire les contrats statiques de polish**

Tester :

- hero avec `min-height: 80svh`;
- cartes avec ratio stable et images `object-fit: cover`;
- carte limitée à `clamp(24rem, 56vh, 38rem)`;
- toutes les cibles interactives `min-height: 44px`;
- focus `:focus-visible`;
- curseur custom masqué sous `(pointer: coarse)`;
- règle `prefers-reduced-motion`;
- absence de `filter: blur()` animé.

- [ ] **Step 2: Exécuter et confirmer RED**

Run: `bash tests/labs360-page.sh`  
Expected: FAIL sur les nouveaux contrats visuels.

- [ ] **Step 3: Implémenter les styles**

Créer un hero avec overlay statique, grille de cartes asymétrique seulement à
partir de 900 px, une colonne sous 700 px et modale plein écran. Utiliser
`clamp()` pour espacements et typographie, sans breakpoint lié à un appareil.

- [ ] **Step 4: Ajuster les reveals**

Révéler hero et cartes avec translation/opacity courtes. Avec mouvement réduit,
appliquer directement les états finaux et désactiver Lenis/autoRotate.

- [ ] **Step 5: Mesurer les budgets construits**

Ajouter au test :

```bash
[ "$(stat -f%z "$ROOT/dist/labs/360/index.html")" -lt 35840 ]
labs_js="$(find "$ROOT/dist/_astro" -name 'Labs360*.js' -print -quit)"
[ "$(stat -f%z "$labs_js")" -lt 20480 ]
! rg -q 'cdn.apple-mapkit.com|pannellum.*css' "$ROOT/dist/labs/360/index.html"
```

- [ ] **Step 6: Vérifier GREEN**

Run: `npm run build && bash tests/labs360-page.sh`  
Expected: 10 pages, tous les budgets verts.

- [ ] **Step 7: Commit**

```bash
git add tests/labs360-page.sh src/components/pages/Labs360.astro src/scripts/labs360.js src/scripts/labs360-motion.js
git commit -m "style(labs360): polish the cinematic atlas"
```

---

### Task 7: Audit final, QA visuelle et publication

**Files:**
- Modify only if a verified defect requires it.

- [ ] **Step 1: Lancer la suite complète**

```bash
bash tests/labs360-page.sh
bash tests/labs360-pipeline.sh
npm run build
git diff --check origin/main...HEAD
```

Expected: 0 échec, 10 pages, diff check vide.

- [ ] **Step 2: Auditer chaque exigence de la spec**

Créer une matrice temporaire avec une preuve pour : six lieux, aucun Montréal,
hero, carte, collection, viewer, navigation, FR/EN, SEO, accessibilité,
performance, erreurs, pipeline, tests et build. Toute preuve manquante bloque la
publication.

- [ ] **Step 3: Vérifier localement aux trois viewports**

Lancer `npm run dev -- --host 127.0.0.1`, puis vérifier à 390 × 844, 820 × 1180 et
1440 × 1000 :

- FR et EN;
- hero, carte et six cartes;
- panorama et photo;
- précédent/suivant, clavier et fermeture;
- mouvement réduit;
- MapKit disponible et simulé en erreur;
- aucun overflow horizontal ni erreur console applicative.

Capturer au moins un screenshot mobile FR et un desktop EN.

- [ ] **Step 4: Vérifier le scope Git**

```bash
git diff --name-status origin/main...HEAD
git log --oneline origin/main..HEAD
```

Confirmer l’absence des fichiers Intercom et de changements hors Labs 360.

- [ ] **Step 5: Publier**

```bash
git push origin HEAD:main
```

Attendre que `https://theo-picture.com/labs/360` serve le nouveau commit.

- [ ] **Step 6: Vérifier la production**

Rejouer FR/EN mobile/desktop et vérifier :

- HTTP 200;
- six lieux et aucun Montréal;
- MapKit et six annotations;
- panorama/photo et navigation;
- métadonnées sociales/JSON-LD;
- aucune erreur console applicative;
- aucun panorama dans les requêtes avant ouverture.

- [ ] **Step 7: Nettoyer le worktree**

Après preuve de production, retirer le worktree et sa branche temporaire sans
modifier la branche locale `main`.
