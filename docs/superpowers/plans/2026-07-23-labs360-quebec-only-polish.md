# Labs 360 — Québec seulement + polish ciblé Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Afficher uniquement les six vrais médias de Québec, retirer Montréal et tous les placeholders, puis raffiner la carte, la légende et la modale sans changer l’identité ISO Nord.

**Architecture:** `labs360.ts` reste la source de vérité et conserve `city` pour l’ingestion future. `Labs360.astro` filtre explicitement `city === 'quebec'` avant de produire le markup et le JSON runtime; `labs360.js` devient mono-région et cadre les annotations Québec réelles. Les tests shell existants gagnent des contrats de contenu/DOM/JavaScript avant chaque modification.

**Tech Stack:** Astro 6, TypeScript, JavaScript, MapKit JS, GSAP, Lenis, Pannellum, Bash 3.2.

## Global Constraints

- Conserver uniquement les vrais contenus Québec visibles : `maizerets`, `patro-roc-amadour`, `giffard`, `centre-monseigneur-marcoux`, `limoilou`, `colline-parlementaire`.
- Retirer : `vieux-quebec`, `chute-montmorency`, `ile-orleans`, `vieux-port`, `mont-royal`, `centre-ville`.
- Ne supprimer aucun vrai média de `media.theo-picture.com` ni aucun fichier du NAS.
- Conserver `City`, `PlaceType`, le champ `city` et `// iso360:insert` pour `iso-ingest`.
- Filtrer l’affichage et le JSON runtime à `city === 'quebec'`; les futures entrées Montréal restent versionnables mais invisibles.
- Retirer le sélecteur de ville, la gestion `#montreal` et les chaînes i18n devenues inutiles.
- Préserver FR/EN, MapKit, modal, Pannellum, photo lightbox, clavier, focus piégé, Échap, cibles tactiles ≥44 px et `prefers-reduced-motion`.
- Accent `#c8ff00` réservé aux signaux d’interaction; aucune nouvelle dépendance ou esthétique SaaS.
- `npm run build` doit produire exactement 10 pages.

---

## File Structure

- `tests/labs360-page.sh` — nouveaux contrats statiques de contenu, DOM, i18n et JavaScript mono-région.
- `src/data/labs360.ts` — uniquement les lieux réels; modèle et marqueur d’insertion conservés.
- `src/components/pages/Labs360.astro` — filtre Québec, carte/légende uniques et styles polis.
- `src/scripts/labs360.js` — MapKit Québec seulement, cadrage calculé sur les annotations, modale inchangée.
- `src/i18n/ui.ts` — copy FR/EN Québec seulement.
- `public/assets/labs360/` — suppression exclusive des panoramas synthétiques devenus non référencés.

---

### Task 1: Contrats de contenu réel + nettoyage des données

**Files:**
- Create: `tests/labs360-page.sh`
- Modify: `src/data/labs360.ts`
- Delete if unreferenced: `public/assets/labs360/pano-chute-montmorency.png`
- Delete if unreferenced: `public/assets/labs360/pano-vieux-port.png`

**Interfaces:**
- Consumes: `PLACES`, `City`, `PlaceType`, `// iso360:insert`.
- Produces: six entrées Québec réelles; test Bash réutilisable par les tâches suivantes.

- [ ] **Step 1: Écrire le test rouge des IDs**

Créer `tests/labs360-page.sh` :

```bash
#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="$ROOT/src/data/labs360.ts"
PAGE="$ROOT/src/components/pages/Labs360.astro"
SCRIPT="$ROOT/src/scripts/labs360.js"
UI="$ROOT/src/i18n/ui.ts"
PASS=0
FAIL=0
pass(){ PASS=$((PASS + 1)); printf 'ok - %s\n' "$1"; }
fail(){ FAIL=$((FAIL + 1)); printf 'not ok - %s\n' "$1" >&2; }

test_real_quebec_ids_only() {
  local kept removed id
  kept="maizerets patro-roc-amadour giffard centre-monseigneur-marcoux limoilou colline-parlementaire"
  removed="vieux-quebec chute-montmorency ile-orleans vieux-port mont-royal centre-ville"
  for id in $kept; do
    rg -q "id: ['\"]$id['\"]" "$DATA" || { fail "lieu réel présent: $id"; return; }
  done
  for id in $removed; do
    ! rg -q "id: ['\"]$id['\"]" "$DATA" || { fail "placeholder absent: $id"; return; }
  done
  pass "les données visibles ne gardent que les six vrais lieux Québec"
}

test_real_quebec_ids_only
printf '\n%s réussite(s), %s échec(s)\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Vérifier le rouge**

Run: `/bin/bash tests/labs360-page.sh`
Expected: FAIL sur au moins `placeholder absent: vieux-quebec`.

- [ ] **Step 3: Retirer exactement les six entrées**

Dans `src/data/labs360.ts`, supprimer les objets complets dont les IDs sont :

```text
vieux-quebec
chute-montmorency
ile-orleans
vieux-port
mont-royal
centre-ville
```

Ne modifier ni les six objets conservés, ni les types, ni `mediaUrl`, ni le marqueur `// iso360:insert`.

- [ ] **Step 4: Supprimer seulement les assets synthétiques orphelins**

Run:

```bash
rg -n 'pano-chute-montmorency|pano-vieux-port' src public --glob '!public/assets/labs360/pano-chute-montmorency.png' --glob '!public/assets/labs360/pano-vieux-port.png'
```

Expected: aucune référence. Supprimer alors les deux PNG. Ne pas supprimer `pano-vieux-quebec-demo.jpg` du NAS ni un média distant.

- [ ] **Step 5: Vérifier le vert et la non-régression ingestion**

Run:

```bash
/bin/bash tests/labs360-page.sh
/bin/bash tests/labs360-pipeline.sh
```

Expected: `1 réussite(s), 0 échec(s)` puis `26 réussite(s), 0 échec(s)`.

- [ ] **Step 6: Commit**

```bash
git add tests/labs360-page.sh src/data/labs360.ts public/assets/labs360
git commit -m "feat(labs360): keep real Québec media only"
```

---

### Task 2: Page mono-région + copy bilingue

**Files:**
- Modify: `tests/labs360-page.sh`
- Modify: `src/components/pages/Labs360.astro`
- Modify: `src/i18n/ui.ts`

**Interfaces:**
- Consumes: six lieux réels de Task 1.
- Produces: `visiblePlaces`, runtime filtré, une carte et une légende uniques, copy FR/EN sans choix de ville.

- [ ] **Step 1: Ajouter les tests rouges DOM/runtime/i18n**

Ajouter avant l’appel final dans `tests/labs360-page.sh` :

```bash
test_quebec_only_markup_and_copy() {
  rg -q "const visiblePlaces = PLACES.filter((p) => p.city === 'quebec')" "$PAGE" || {
    fail "le runtime filtre explicitement Québec"; return;
  }
  ! rg -q 'data-city-btn|data-legend-city|l360-cities|l360-city' "$PAGE" || {
    fail "le sélecteur de ville est retiré"; return;
  }
  ! rg -q 'choisissez une ville|pick a city|cityAria|cities:' "$UI" || {
    fail "la copy ne promet plus de choix de ville"; return;
  }
  pass "le markup et la copy sont Québec seulement"
}
```

Appeler `test_quebec_only_markup_and_copy` après `test_real_quebec_ids_only`.

- [ ] **Step 2: Vérifier le rouge**

Run: `/bin/bash tests/labs360-page.sh`
Expected: FAIL sur `le runtime filtre explicitement Québec`.

- [ ] **Step 3: Filtrer une seule fois dans le frontmatter**

Remplacer `CITIES` et `byCity` par :

```ts
const visiblePlaces = PLACES.filter((p) => p.city === 'quebec');
```

Dans `runtime`, remplacer `PLACES.map` par `visiblePlaces.map`.

- [ ] **Step 4: Remplacer le sélecteur et les légendes par une liste unique**

Supprimer entièrement `.l360-cities`. Remplacer le bloc `{CITIES.map(...)}` de légende par :

```astro
<ol class="l360-legend" aria-label={l.legendAria}>
  {visiblePlaces.map((p, i) => (
    <li>
      <button type="button" class="l360-legend__item" data-place-id={p.id} aria-haspopup="dialog">
        <span class="l360-legend__num">{pad(i + 1)}</span>
        <span class="l360-legend__name">{p.name}</span>
        <em class="l360-legend__badge">
          {p.type === '360' ? l.badge360 : p.type === 'photo' ? l.badgePhoto : l.badgeVideo}
        </em>
      </button>
    </li>
  ))}
</ol>
```

Retirer l’import `type City` et les styles `.l360-cities` / `.l360-city`.

- [ ] **Step 5: Mettre la copy FR/EN au présent**

Dans `src/i18n/ui.ts`, utiliser :

```ts
// fr
description: "Québec en 360 — panoramas explorables et photographies aériennes captés par ISO Nord.",
ogDescription: 'Québec vu du ciel — panoramas 360° explorables et photographies aériennes.',
lede: "Québec vu du ciel — touchez un repère pour explorer un panorama ou ouvrir une photographie.",

// en
description: 'Québec in 360 — explorable panoramas and aerial photographs captured by ISO Nord.',
ogDescription: 'Québec from above — explorable 360° panoramas and aerial photographs.',
lede: 'Québec from above — tap a marker to explore a panorama or open a photograph.',
```

Retirer `cities` et `cityAria` des deux langues.

- [ ] **Step 6: Vérifier**

Run:

```bash
/bin/bash tests/labs360-page.sh
npm run build
```

Expected: tests verts; `[build] 10 page(s) built`.

- [ ] **Step 7: Commit**

```bash
git add tests/labs360-page.sh src/components/pages/Labs360.astro src/i18n/ui.ts
git commit -m "refactor(labs360): focus page on Québec"
```

---

### Task 3: MapKit mono-région + cadrage réel

**Files:**
- Modify: `tests/labs360-page.sh`
- Modify: `src/scripts/labs360.js`

**Interfaces:**
- Consumes: `DATA.places` déjà filtré Québec.
- Produces: `regionForPlaces(places)` et initialisation MapKit sans hash ni état de ville.

- [ ] **Step 1: Ajouter le test rouge JavaScript**

Ajouter :

```bash
test_quebec_only_map_logic() {
  ! rg -q 'REGIONS|currentCity|showCity|cityButtons|data-city-btn|#montreal|replaceState' "$SCRIPT" || {
    fail "le JavaScript ne gère plus les villes ni le hash"; return;
  }
  rg -q 'function regionForPlaces' "$SCRIPT" || {
    fail "la carte cadre les lieux visibles"; return;
  }
  pass "MapKit utilise une seule région calculée"
}
```

Appeler la fonction dans la suite.

- [ ] **Step 2: Vérifier le rouge**

Run: `/bin/bash tests/labs360-page.sh`
Expected: FAIL sur `le JavaScript ne gère plus les villes ni le hash`.

- [ ] **Step 3: Remplacer les régions fixes et le changement de ville**

Supprimer `REGIONS`, `cityButtons`, `legends`, `currentCity`, `regionFor(city)`,
`showCity` et leurs listeners. Ajouter :

```js
function regionForPlaces(places) {
  if (!places.length) {
    return new mapkit.CoordinateRegion(
      new mapkit.Coordinate(46.84, -71.22),
      new mapkit.CoordinateSpan(0.18, 0.24),
    );
  }
  const lats = places.map((p) => p.lat);
  const lons = places.map((p) => p.lon);
  const minLat = Math.min(...lats);
  const maxLat = Math.max(...lats);
  const minLon = Math.min(...lons);
  const maxLon = Math.max(...lons);
  const latSpan = Math.max((maxLat - minLat) * 1.8, 0.08);
  const lonSpan = Math.max((maxLon - minLon) * 1.8, 0.12);
  return new mapkit.CoordinateRegion(
    new mapkit.Coordinate((minLat + maxLat) / 2, (minLon + maxLon) / 2),
    new mapkit.CoordinateSpan(latSpan, lonSpan),
  );
}
```

Dans le constructeur MapKit :

```js
region: regionForPlaces(DATA.places),
```

- [ ] **Step 4: Mettre les commentaires à jour**

Le commentaire d’en-tête doit dire :

```js
 * - Carte satellite Apple Maps centrée sur les médias publiés à Québec
```

Retirer toute mention active du sélecteur Québec/Montréal.

- [ ] **Step 5: Vérifier**

Run:

```bash
/bin/bash tests/labs360-page.sh
/bin/bash tests/labs360-pipeline.sh
npm run build
```

Expected: suites vertes et 10 pages.

- [ ] **Step 6: Commit**

```bash
git add tests/labs360-page.sh src/scripts/labs360.js
git commit -m "refactor(labs360): frame published Québec places"
```

---

### Task 4: Polish ciblé + vérification visuelle

**Files:**
- Modify: `src/components/pages/Labs360.astro`
- Modify if required by verified copy: `src/i18n/ui.ts`

**Interfaces:**
- Consumes: markup mono-région et logique MapKit des Tasks 2–3.
- Produces: expérience finale mobile/desktop sans nouvelle dépendance.

- [ ] **Step 1: Appliquer les ajustements CSS ciblés**

Dans les styles scoped :

```css
.l360-hero {
  padding: clamp(7rem, 16vh, 10rem) 0 clamp(2rem, 5vw, 3.5rem);
}
.l360-map-section {
  padding-bottom: clamp(5rem, 10vw, 9rem);
}
.l360-map {
  min-height: clamp(30rem, 68vh, 48rem);
}
.l360-legend {
  margin-top: clamp(1.25rem, 3vw, 2rem);
}
.l360-legend__item {
  min-height: 4rem;
}
.l360-legend__item:focus-visible {
  outline: 1px solid var(--accent);
  outline-offset: 4px;
}
```

Fusionner ces déclarations avec les règles existantes plutôt que créer des
doublons. Sur mobile ≤640 px, limiter la carte à :

```css
.l360-map { min-height: 28rem; height: 62svh; }
```

- [ ] **Step 2: Vérifier les états réduits et tactiles**

Inspecter les règles existantes et confirmer :

- chaque `.l360-legend__item` a une cible ≥44 px;
- `:focus-visible` est visible;
- aucun élément essentiel ne dépend seulement de `:hover`;
- le bloc `@media (prefers-reduced-motion: reduce)` garde tout visible.

Si une condition manque, l’ajouter dans le même bloc CSS scoped.

- [ ] **Step 3: Vérification automatisée complète**

Run:

```bash
/bin/bash tests/labs360-page.sh
/bin/bash tests/labs360-pipeline.sh
npm run build
git diff --check
```

Expected: toutes les suites vertes, 10 pages, aucune erreur whitespace.

- [ ] **Step 4: Vérification navigateur**

Lancer `npm run dev`, puis vérifier `/labs/360` et `/en/labs/360` à 390×844 et
1440×1000 :

- six pins et six lignes de légende;
- aucun sélecteur ni mention Montréal;
- ancien `#montreal` charge Québec normalement;
- cadrage carte contient les six lieux;
- ouvrir Maizerets (360) et Limoilou (photo);
- fermer par Échap, backdrop et bouton;
- tabulation/focus restauré;
- mode `prefers-reduced-motion`;
- console sans erreur.

- [ ] **Step 5: Commit**

```bash
git add src/components/pages/Labs360.astro src/i18n/ui.ts
git commit -m "style(labs360): polish Québec map experience"
```

---

### Task 5: Revue finale et publication

**Files:**
- Review: all changes from merge base to HEAD

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: branche approuvée, `main` poussé et NAS synchronisable.

- [ ] **Step 1: Revue whole-branch**

Comparer la branche à son merge base et vérifier la spec complète, sans élargir
le scope. Corriger tout finding Critical/Important et revalider.

- [ ] **Step 2: Gate final**

Run:

```bash
/bin/bash tests/labs360-page.sh
/bin/bash tests/labs360-pipeline.sh
npm run build
git diff --check
git status --short
```

Expected: tests verts, `10 page(s) built`, diff propre, aucun changement non suivi inattendu.

- [ ] **Step 3: Push**

Sur `main` propre et synchronisée :

```bash
git push origin main
```

Expected: `origin/main` pointe sur le commit final. Le NAS récupérera les
changements au prochain lot via son `git pull --ff-only`, ou par pull manuel
si une validation immédiate est souhaitée.
