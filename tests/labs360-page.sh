#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="${DATA:-$ROOT/src/data/labs360.ts}"
PAGE="${PAGE:-$ROOT/src/components/pages/Labs360.astro}"
UI="${UI:-$ROOT/src/i18n/ui.ts}"
SCRIPT="${SCRIPT:-$ROOT/src/scripts/labs360.js}"
MAP_HELPER="${MAP_HELPER:-$ROOT/src/scripts/labs360-map.js}"
MAP_LOADER="${MAP_LOADER:-$ROOT/src/scripts/labs360-map-loader.js}"
MOTION_HELPER="${MOTION_HELPER:-$ROOT/src/scripts/labs360-motion.js}"
VIEW_HELPER="${VIEW_HELPER:-$ROOT/src/scripts/labs360-view.js}"
PASS=0
FAIL=0
pass(){ PASS=$((PASS + 1)); printf 'ok - %s\n' "$1"; }
fail(){ FAIL=$((FAIL + 1)); printf 'not ok - %s\n' "$1" >&2; }

has_exact_real_quebec_places() {
  local data="$1" expected removed id ids places quebec_city_count id_count
  expected="maizerets patro-roc-amadour giffard centre-monseigneur-marcoux limoilou colline-parlementaire"
  removed="vieux-quebec chute-montmorency ile-orleans vieux-port mont-royal centre-ville"
  places="$(sed -n '/^export const PLACES: Labs360Place\[\] = \[$/,/^[[:space:]]*\/\/ iso360:insert/p' "$data")"
  ids="$(printf '%s\n' "$places" | sed -n "s/^[[:space:]]*id: ['\"]\([^'\"]*\)['\"],$/\1/p")"
  quebec_city_count="$(printf '%s\n' "$places" | sed -n "s/^[[:space:]]*city: ['\"]quebec['\"],$/quebec/p" | awk 'NF { count++ } END { print count + 0 }')"
  id_count="$(printf '%s\n' "$ids" | awk 'NF { count++ } END { print count + 0 }')"

  [ "$quebec_city_count" -eq 6 ] && [ "$id_count" -eq 6 ] || return 1
  ! printf '%s\n' "$places" | rg -q "city: ['\"]montreal['\"]" || return 1

  for id in $expected; do
    printf '%s\n' "$ids" | rg -qx -- "$id" || return 1
  done
  for id in $removed; do
    ! printf '%s\n' "$ids" | rg -qx -- "$id" || return 1
  done
}

test_real_quebec_places_only() {
  local fixture removed_id
  has_exact_real_quebec_places "$DATA" || {
    fail "PLACES doit exposer exactement les six vrais lieux Québec"; return;
  }
  fixture="$(mktemp)"
  cp "$DATA" "$fixture"
  sed -i.bak '/\/\/ iso360:insert/i\
  {\
    id: "futur-montreal",\
    city: "montreal",\
    type: "photo", name: "Test",\
    desc: { fr: "Test", en: "Test" }, credit: "", lat: 45.5, lon: -73.6, media: "test.jpg",\
  },' "$fixture"
  if has_exact_real_quebec_places "$fixture"; then
    rm -f "$fixture" "$fixture.bak"
    fail "une future entrée Montréal doit être refusée"; return;
  fi
  for removed_id in vieux-quebec chute-montmorency ile-orleans vieux-port mont-royal centre-ville; do
    cp "$DATA" "$fixture"
    sed -i.bak "/\\/\\/ iso360:insert/i\\
  {\\
    id: \"$removed_id\",\\
    city: \"montreal\",\\
    type: \"photo\", name: \"Ancien placeholder\",\\
    desc: { fr: \"Test\", en: \"Test\" }, credit: \"\", lat: 45.5, lon: -73.6, media: \"test.jpg\",\\
  }," "$fixture"
    if has_exact_real_quebec_places "$fixture"; then
      rm -f "$fixture" "$fixture.bak"
      fail "ancien ID explicitement refusé: $removed_id"; return;
    fi
  done
  cp "$DATA" "$fixture"
  sed -i.bak '/\/\/ iso360:insert/i\
  {\
    id: "septieme-quebec",\
    city: "quebec",\
    type: "photo", name: "Test",\
    desc: { fr: "Test", en: "Test" }, credit: "", lat: 46.8, lon: -71.2, media: "test.jpg",\
  },' "$fixture"
  if has_exact_real_quebec_places "$fixture"; then
    rm -f "$fixture" "$fixture.bak"
    fail "un septième lieu Québec doit faire échouer le contrat"; return;
  fi
  rm -f "$fixture" "$fixture.bak"
  pass "les lieux visibles sont exactement les six Québec; Montréal est refusé"
}

test_real_place_metadata_and_previews() {
  local preview size total=0 count=0 featured_count captured_count preview_count preview_width_count preview_height_count places
  places="$(sed -n '/^export const PLACES: Labs360Place\[\] = \[$/,/^[[:space:]]*\/\/ iso360:insert/p' "$DATA")"
  featured_count="$(printf '%s\n' "$places" | rg -c 'featured: true' || printf '0')"
  captured_count="$(printf '%s\n' "$places" | rg -c 'capturedAt:' || printf '0')"
  preview_count="$(printf '%s\n' "$places" | rg -c 'preview:' || printf '0')"
  preview_width_count="$(printf '%s\n' "$places" | rg -c 'previewWidth:' || printf '0')"
  preview_height_count="$(printf '%s\n' "$places" | rg -c 'previewHeight:' || printf '0')"
  [ "$featured_count" -eq 1 ] || {
    fail "un seul lieu doit alimenter le hero"; return;
  }
  [ "$captured_count" -eq 6 ] || {
    fail "les six lieux doivent avoir une date de captation"; return;
  }
  [ "$preview_count" -eq 6 ] || {
    fail "les six lieux doivent avoir un aperçu local"; return;
  }
  [ "$preview_width_count" -eq 6 ] &&
    [ "$preview_height_count" -eq 6 ] || {
      fail "les six aperçus doivent déclarer leurs dimensions"; return;
    }
  for preview in "$ROOT"/public/assets/labs360/previews/*.webp; do
    [ -f "$preview" ] || { fail "aperçu WebP manquant"; return; }
    size="$(stat -f%z "$preview")"
    [ "$size" -lt 358400 ] || {
      fail "$(basename "$preview") dépasse 350 Ko"; return;
    }
    total=$((total + size))
    count=$((count + 1))
  done
  [ "$count" -eq 6 ] || {
    fail "exactement six aperçus WebP sont requis"; return;
  }
  [ "$total" -lt 1887437 ] || {
    fail "les aperçus dépassent 1,8 Mo"; return;
  }
  pass "métadonnées et aperçus réels respectent le budget"
}

test_modal_badge_and_empty_state() {
  rg -Fq 'class="l360-modal__badge"' "$PAGE" &&
    rg -Fq 'const badgeEl = modal.querySelector(' "$SCRIPT" &&
    rg -Fq 'badgeEl.textContent = badgeForType(place.type, DATA);' "$SCRIPT" || {
      fail "la modale expose et remplit son badge depuis le type runtime"; return;
    }
  rg -Fq 'const hasPlaces = hasVisiblePlaces(visiblePlaces);' "$PAGE" &&
    rg -Fq '{!hasPlaces && (' "$PAGE" &&
    rg -Fq '{hasPlaces && (' "$PAGE" &&
    rg -Fq '<p class="l360-empty">{l.mediaSoon}</p>' "$PAGE" || {
      fail "l’état zéro bilingue réutilise mediaSoon"; return;
    }
  node --input-type=module - "$VIEW_HELPER" <<'NODE'
import assert from 'node:assert/strict';
const { badgeForType, hasVisiblePlaces } = await import(`file://${process.argv[2]}`);
const labels = { badge360: '360°', badgeVideo: 'Clip', badgePhoto: 'Photo' };
assert.equal(badgeForType('360', labels), '360°');
assert.equal(badgeForType('photo', labels), 'Photo');
assert.equal(badgeForType('video', labels), 'Clip');
assert.equal(hasVisiblePlaces([]), false);
assert.equal(hasVisiblePlaces([{ id: 'maizerets' }]), true);
NODE
  [ "$?" -eq 0 ] || { fail "le contrat badge/état zéro se comporte correctement"; return; }
  pass "badge modal et état zéro suivent les données runtime"
}

test_accessible_viewer_navigation() {
  node --input-type=module - "$VIEW_HELPER" <<'NODE'
import assert from 'node:assert/strict';
const { adjacentPlaceId, counterLabel } = await import(`file://${process.argv[2]}`);
const places = [{ id: 'a' }, { id: 'b' }, { id: 'c' }];
assert.equal(adjacentPlaceId(places, 'a', 1), 'b');
assert.equal(adjacentPlaceId(places, 'c', 1), 'a');
assert.equal(adjacentPlaceId(places, 'a', -1), 'c');
assert.equal(adjacentPlaceId(places, 'inconnu', 1), 'a');
assert.equal(counterLabel(0, 6, '{current} / {total}'), '01 / 06');
NODE
  [ "$?" -eq 0 ] || {
    fail "la navigation circulaire du viewer est déterministe"; return;
  }
  rg -Fq 'data-view-previous' "$PAGE" &&
    rg -Fq 'data-view-next' "$PAGE" &&
    rg -Fq 'aria-live="polite"' "$PAGE" &&
    rg -Fq 'aria-describedby="l360-description"' "$PAGE" &&
    rg -Fq "e.key === 'ArrowLeft'" "$SCRIPT" &&
    rg -Fq "e.key === 'ArrowRight'" "$SCRIPT" &&
    rg -Fq '.inert = true' "$SCRIPT" || {
      fail "la modale expose navigation, annonces et inert"; return;
    }
  pass "le viewer est navigable et annoncé au clavier"
}

test_quebec_only_markup_and_copy() {
  rg -Fq "const visiblePlaces = PLACES.filter((p) => p.city === 'quebec')" "$PAGE" || {
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

test_labs_project_copy_quebec_only() {
  local fr_project en_project
  fr_project="$(rg -F "{ name: 'Québec en 360'" "$UI")"
  en_project="$(rg -F "{ name: 'Québec in 360'" "$UI")"

  [ -n "$fr_project" ] && [ -n "$en_project" ] || {
    fail "les deux cartes projet Labs360 existent"; return;
  }
  ! printf '%s\n%s\n' "$fr_project" "$en_project" | rg -qi 'montréal|clips?' || {
    fail "les cartes projet Labs360 n'annoncent plus Montréal ou des clips"; return;
  }
  printf '%s\n' "$fr_project" | rg -qi 'québec.*panoramas?.*photograph' &&
    printf '%s\n' "$en_project" | rg -qi 'québec city.*panoramas?.*aerial photographs' || {
      fail "les cartes projet Labs360 décrivent Québec, panoramas et photos"; return;
    }
  pass "les cartes projet Labs360 sont Québec seulement"
}

test_cinematic_collection_and_seo() {
  rg -Fq 'id="captures"' "$PAGE" &&
    rg -Fq 'class="l360-card"' "$PAGE" &&
    rg -Fq 'data-place-id={place.id}' "$PAGE" &&
    rg -Fq 'loading="lazy"' "$PAGE" &&
    rg -Fq 'decoding="async"' "$PAGE" || {
      fail "la collection SSR expose les six captations optimisées"; return;
    }
  rg -Fq 'application/ld+json' "$PAGE" &&
    rg -Fq "'@type': 'CollectionPage'" "$PAGE" &&
    rg -Fq 'property="og:image"' "$PAGE" &&
    rg -Fq 'name="twitter:card"' "$PAGE" &&
    rg -Fq '<noscript>' "$PAGE" || {
      fail "le partage, les données structurées et le repli sans JS sont présents"; return;
    }
  rg -Fq 'const featured = visiblePlaces.find((place) => place.featured)' "$PAGE" &&
    rg -Fq 'const socialImage = SITE + featured.preview;' "$PAGE" || {
      fail "le hero et le partage utilisent un vrai aperçu vedette"; return;
    }
  pass "collection cinématographique et SEO sont rendus côté serveur"
}

test_quebec_only_map_logic() {
  ! rg -q 'REGIONS|currentCity|showCity|cityButtons|data-city-btn|#montreal|replaceState' "$SCRIPT" || {
    fail "le JavaScript ne gère plus les villes ni le hash"; return;
  }
  rg -q 'function regionForPlaces' "$MAP_HELPER" || {
    fail "la carte cadre les lieux visibles"; return;
  }
  pass "MapKit utilise une seule région calculée"
}

test_region_for_places() {
  rg -Fq 'region: regionForPlaces(places, mapkitApi)' "$MAP_HELPER" &&
    rg -Fq 'map = createMap({' "$SCRIPT" || {
    fail "le constructeur MapKit utilise les lieux publiés"; return;
  }
  node --input-type=module - "$MAP_HELPER" <<'NODE'
import assert from 'node:assert/strict';

class Coordinate {
  constructor(latitude, longitude) {
    this.latitude = latitude;
    this.longitude = longitude;
  }
}
class CoordinateSpan {
  constructor(latitudeDelta, longitudeDelta) {
    this.latitudeDelta = latitudeDelta;
    this.longitudeDelta = longitudeDelta;
  }
}
class CoordinateRegion {
  constructor(center, span) {
    this.center = center;
    this.span = span;
  }
}
globalThis.mapkit = { Coordinate, CoordinateSpan, CoordinateRegion };

const { regionForPlaces, createMap } = await import(`file://${process.argv[2]}`);
const closeTo = (actual, expected) => assert.ok(Math.abs(actual - expected) < 1e-9);
const assertRegion = (region, latitude, longitude, latitudeDelta, longitudeDelta) => {
  closeTo(region.center.latitude, latitude);
  closeTo(region.center.longitude, longitude);
  closeTo(region.span.latitudeDelta, latitudeDelta);
  closeTo(region.span.longitudeDelta, longitudeDelta);
};

assertRegion(regionForPlaces([]), 46.84, -71.22, 0.18, 0.24);
assertRegion(regionForPlaces([{ lat: 46.8, lon: -71.1 }]), 46.8, -71.1, 0.08, 0.12);
assertRegion(regionForPlaces([
  { lat: 46.7, lon: -71.5 }, { lat: 46.8, lon: -71.4 },
  { lat: 46.9, lon: -71.3 }, { lat: 47, lon: -71.2 },
  { lat: 46.75, lon: -71 }, { lat: 46.95, lon: -71.45 },
]), 46.85, -71.25, 0.54, 0.9);

let initialized = null;
let selected = null;
class MapClass {
  static MapTypes = { Hybrid: 'hybrid' };
  static ColorSchemes = { Dark: 'dark' };
  constructor(elementId, options) {
    this.elementId = elementId;
    this.options = options;
    this.annotations = [];
  }
  addAnnotations(annotations) { this.annotations = annotations; }
}
class MarkerAnnotation {
  constructor(coordinate, options) {
    this.coordinate = coordinate;
    this.options = options;
    this.listeners = {};
  }
  addEventListener(name, callback) { this.listeners[name] = callback; }
}
const mapkitApi = {
  Coordinate,
  CoordinateSpan,
  CoordinateRegion,
  Map: MapClass,
  MarkerAnnotation,
  FeatureVisibility: { Hidden: 'hidden' },
  init(options) { initialized = options; },
};
const places = [
  { id: 'a', type: '360', name: 'A', lat: 46.8, lon: -71.2 },
  { id: 'b', type: 'photo', name: 'B', lat: 46.9, lon: -71.3 },
];
const map = createMap({
  mapkitApi,
  elementId: 'map',
  places,
  labels: { badge360: '360°', badgePhoto: 'Photo', badgeVideo: 'Clip' },
  language: 'fr-CA',
  authorizationCallback() {},
  onSelect(id) { selected = id; },
});
assert.equal(initialized.language, 'fr-CA');
assert.equal(map.elementId, 'map');
closeTo(map.options.region.center.latitude, 46.85);
assert.equal(map.annotations.length, 2);
map.annotations[1].listeners.select();
assert.equal(selected, 'b');
NODE
  [ "$?" -eq 0 ] || { fail "regionForPlaces calcule les cadrages vide, seul et six lieux"; return; }
  pass "regionForPlaces calcule les cadrages vide, seul et six lieux"
}

test_deferred_mapkit_loader() {
  node --input-type=module - "$MAP_LOADER" <<'NODE'
import assert from 'node:assert/strict';
const {
  loadMapKit,
  observeMap,
  resetMapKitLoaderForTests,
} = await import(`file://${process.argv[2]}`);

const listeners = {};
const scripts = [];
const script = {
  dataset: {},
  addEventListener(type, callback) { listeners[type] = callback; },
};
const documentRef = {
  head: { append(node) { scripts.push(node); } },
  createElement() { return script; },
  querySelector() { return scripts[0] ?? null; },
};
const windowRef = {};
const first = loadMapKit({ documentRef, windowRef, timeoutMs: 50 });
const second = loadMapKit({ documentRef, windowRef, timeoutMs: 50 });
assert.equal(first, second);
assert.equal(scripts.length, 1);
assert.equal(script.dataset.mapkitLoader, '');
windowRef.mapkit = { loaded: true };
listeners.load();
assert.equal(await first, windowRef.mapkit);

let observed = null;
let disconnected = false;
let called = 0;
class FakeObserver {
  constructor(callback, options) {
    this.callback = callback;
    assert.equal(options.rootMargin, '500px 0px');
  }
  observe(element) { observed = element; }
  disconnect() { disconnected = true; }
}
const element = {};
const observer = observeMap(element, () => { called += 1; }, FakeObserver);
assert.equal(observed, element);
observer.callback([{ isIntersecting: false }]);
observer.callback([{ isIntersecting: true }]);
observer.callback([{ isIntersecting: true }]);
assert.equal(called, 1);
assert.equal(disconnected, true);

resetMapKitLoaderForTests();
NODE
  [ "$?" -eq 0 ] || {
    fail "le chargeur MapKit différé respecte cache et intersection"; return;
  }
  ! rg -Fq '<script id="mapkit-js"' "$PAGE" &&
    rg -Fq "from './labs360-map-loader.js'" "$SCRIPT" &&
    rg -Fq 'class="l360-map__loading"' "$PAGE" &&
    rg -Fq 'class="l360-map__fallback"' "$PAGE" &&
    rg -Fq ".l360-map[data-state='error'] .l360-mapkit" "$PAGE" || {
      fail "MapKit ne doit plus charger dans le head"; return;
    }
  pass "MapKit charge une seule fois à l’approche de la carte"
}

test_targeted_polish_contract() {
  rg -Uq '\.l360-hero \{[^}]*min-height: 88svh;[^}]*padding: clamp\(8rem, 18vh, 11rem\) 0 clamp\(3rem, 7vw, 5\.5rem\);' "$PAGE" || {
    fail "le hero cinématographique occupe le premier écran"; return;
  }
  rg -Uq '\.l360-map-section \{ padding: clamp\(4\.5rem, 9vw, 8rem\) 0; \}' "$PAGE" || {
    fail "la section carte garde un rythme fluide"; return;
  }
  rg -Uq '\.l360-map \{ min-height: clamp\(24rem, 56vh, 38rem\); \}' "$PAGE" || {
    fail "la carte reste utile sans repousser la collection"; return;
  }
  rg -Uq '\.l360-collection \{[^}]*grid-template-columns: repeat\(12, minmax\(0, 1fr\)\);' "$PAGE" || {
    fail "la collection utilise une grille éditoriale"; return;
  }
  rg -Uq '\.l360-card \{[^}]*min-height: 44px;[^}]*touch-action: manipulation;' "$PAGE" || {
    fail "les cartes ont une cible tactile confortable"; return;
  }
  rg -Uq '\.l360-card:focus-visible \{[^}]*outline: 1px solid var\(--accent\);[^}]*outline-offset: 6px;' "$PAGE" || {
    fail "le focus clavier des cartes est visible"; return;
  }
  rg -Fq '@media (max-width: 640px)' "$PAGE" &&
    rg -Fq '.l360-map { min-height: 26rem; height: 56svh; }' "$PAGE" || {
    fail "la carte mobile utilise le cadrage compact"; return;
  }
  rg -Uq '@media \(prefers-reduced-motion: reduce\)' "$PAGE" || {
    fail "le composant respecte reduced-motion"; return;
  }
  rg -Fq ':global(.l360-nav__link)' "$PAGE" || {
    fail "le LangSwitch enfant reçoit aussi la cible tactile de navigation"; return;
  }
  rg -Uq '\.l360-nav__home, \.l360-nav__link, :global\(\.l360-nav__link\) \{[^}]*min-width: 44px;[^}]*min-height: 44px;' "$PAGE" || {
    fail "tous les liens de navigation ont une cible 44 par 44"; return;
  }
  pass "le polish ciblé respecte tactile, focus et responsive"
}

test_motion_and_performance_budgets() {
  rg -Fq '@media (pointer: coarse)' "$PAGE" &&
    rg -Fq '.cursor-dot, .cursor-ring { display: none; }' "$PAGE" || {
      fail "le curseur custom doit disparaître sur écran tactile"; return;
    }
  rg -Fq "gsap.utils.toArray('.l360-card')" "$SCRIPT" &&
    rg -Fq 'scrollTrigger:' "$SCRIPT" || {
      fail "les cartes doivent utiliser un reveal progressif léger"; return;
    }
  ! rg -q 'filter:[[:space:]]*blur|backdrop-filter' "$PAGE" || {
    fail "le polish ne doit pas animer ou appliquer de blur coûteux"; return;
  }

  local html="$ROOT/dist/labs/360/index.html" labs_js=""
  [ -f "$html" ] || {
    fail "un build est requis pour mesurer les budgets"; return;
  }
  labs_js="$(find "$ROOT/dist/_astro" -maxdepth 1 -type f -name 'Labs360*.js' -print -quit)"
  [ -n "$labs_js" ] &&
    [ "$(stat -f%z "$html")" -lt 35840 ] &&
    [ "$(stat -f%z "$labs_js")" -lt 20480 ] || {
      fail "HTML ou JavaScript Labs dépasse son budget"; return;
    }
  ! rg -q '<script[^>]+cdn\.apple-mapkit\.com|<link[^>]+pannellum[^>]+\.css' "$html" || {
    fail "MapKit et Pannellum ne doivent pas être des ressources initiales"; return;
  }
  pass "mouvement et ressources initiales respectent les budgets"
}

test_reduced_motion_modal_opens_instantly() {
  rg -Fq "import { shouldAnimateModalOpen } from './labs360-motion.js';" "$SCRIPT" || {
    fail "la modale utilise la politique de mouvement testable"; return;
  }
  node --input-type=module - "$MOTION_HELPER" <<'NODE'
import assert from 'node:assert/strict';
const { shouldAnimateModalOpen } = await import(`file://${process.argv[2]}`);

assert.equal(shouldAnimateModalOpen(true, true), false);
assert.equal(shouldAnimateModalOpen(true, false), false);
assert.equal(shouldAnimateModalOpen(false, false), true);
assert.equal(shouldAnimateModalOpen(false, true), true);
NODE
  [ "$?" -eq 0 ] || {
    fail "reduced-motion ouvre la modale sans animation"; return;
  }
  rg -Fq 'if (!shouldAnimateModalOpen(reducedMotion, trigger)) {' "$SCRIPT" &&
    rg -Fq 'gsap.set(backdrop, { opacity: 0.92 });' "$SCRIPT" &&
    rg -Fq 'gsap.set(panel, { opacity: 1, scale: 1 });' "$SCRIPT" || {
    fail "la branche instantanée fixe directement l’état final"; return;
  }
  pass "reduced-motion ouvre réellement la modale instantanément"
}

test_real_quebec_places_only
test_real_place_metadata_and_previews
test_modal_badge_and_empty_state
test_accessible_viewer_navigation
test_quebec_only_markup_and_copy
test_labs_project_copy_quebec_only
test_cinematic_collection_and_seo
test_quebec_only_map_logic
test_region_for_places
test_deferred_mapkit_loader
test_targeted_polish_contract
test_motion_and_performance_budgets
test_reduced_motion_modal_opens_instantly
printf '\n%s réussite(s), %s échec(s)\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
