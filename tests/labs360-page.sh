#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="${DATA:-$ROOT/src/data/labs360.ts}"
PAGE="${PAGE:-$ROOT/src/components/pages/Labs360.astro}"
UI="${UI:-$ROOT/src/i18n/ui.ts}"
SCRIPT="${SCRIPT:-$ROOT/src/scripts/labs360.js}"
MAP_HELPER="${MAP_HELPER:-$ROOT/src/scripts/labs360-map.js}"
MOTION_HELPER="${MOTION_HELPER:-$ROOT/src/scripts/labs360-motion.js}"
VIEW_HELPER="${VIEW_HELPER:-$ROOT/src/scripts/labs360-view.js}"
PASS=0
FAIL=0
pass(){ PASS=$((PASS + 1)); printf 'ok - %s\n' "$1"; }
fail(){ FAIL=$((FAIL + 1)); printf 'not ok - %s\n' "$1" >&2; }

has_exact_real_quebec_places() {
  local data="$1" expected removed id ids places quebec_city_count
  expected="maizerets patro-roc-amadour giffard centre-monseigneur-marcoux limoilou colline-parlementaire"
  removed="vieux-quebec chute-montmorency ile-orleans vieux-port mont-royal centre-ville"
  places="$(sed -n '/^export const PLACES: Labs360Place\[\] = \[$/,/^[[:space:]]*\/\/ iso360:insert/p' "$data")"
  ids="$(printf '%s\n' "$places" | sed -n "s/^[[:space:]]*id: ['\"]\([^'\"]*\)['\"],$/\1/p")"
  quebec_city_count="$(printf '%s\n' "$places" | sed -n "s/^[[:space:]]*city: ['\"]quebec['\"],$/quebec/p" | awk 'NF { count++ } END { print count + 0 }')"

  [ "$quebec_city_count" -eq 6 ] || return 1

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
  has_exact_real_quebec_places "$fixture" || {
    rm -f "$fixture" "$fixture.bak"
    fail "une future entrée Montréal demeure permise"; return;
  }
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
  pass "les lieux visibles sont exactement les six Québec; Montréal futur est permis"
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
  rg -Fq 'region: regionForPlaces(DATA.places)' "$SCRIPT" || {
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

const { regionForPlaces } = await import(`file://${process.argv[2]}`);
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
NODE
  [ "$?" -eq 0 ] || { fail "regionForPlaces calcule les cadrages vide, seul et six lieux"; return; }
  pass "regionForPlaces calcule les cadrages vide, seul et six lieux"
}

test_targeted_polish_contract() {
  rg -Uq '\.l360-hero \{[^}]*padding: clamp\(7rem, 16vh, 10rem\) 0 clamp\(2rem, 5vw, 3\.5rem\);' "$PAGE" || {
    fail "le hero utilise le rythme vertical ciblé"; return;
  }
  rg -Uq '\.l360-map-section \{[^}]*padding-bottom: clamp\(5rem, 10vw, 9rem\);' "$PAGE" || {
    fail "la section carte garde un dégagement final fluide"; return;
  }
  rg -Uq '\.l360-map \{[^}]*width: 100%;[^}]*min-height: clamp\(30rem, 68vh, 48rem\);' "$PAGE" || {
    fail "la carte desktop conserve une hauteur utile"; return;
  }
  rg -Uq '\.l360-legend \{[^}]*margin: clamp\(1\.25rem, 3vw, 2rem\) 0 0;' "$PAGE" || {
    fail "la légende utilise un espacement fluide"; return;
  }
  rg -Uq '\.l360-legend__item \{[^}]*min-height: 4rem;[^}]*touch-action: manipulation;' "$PAGE" || {
    fail "les lignes de légende ont une cible tactile confortable"; return;
  }
  rg -Uq '\.l360-legend__item:focus-visible \{[^}]*outline: 1px solid var\(--accent\);[^}]*outline-offset: 4px;' "$PAGE" || {
    fail "le focus clavier de la légende est visible"; return;
  }
  rg -Uq '@media \(max-width: 640px\) \{[^}]*\.l360-map \{ min-height: 28rem; height: 62svh; \}' "$PAGE" || {
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
test_quebec_only_markup_and_copy
test_labs_project_copy_quebec_only
test_quebec_only_map_logic
test_region_for_places
test_targeted_polish_contract
test_reduced_motion_modal_opens_instantly
printf '\n%s réussite(s), %s échec(s)\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
