#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="${DATA:-$ROOT/src/data/labs360.ts}"
PAGE="${PAGE:-$ROOT/src/components/pages/Labs360.astro}"
UI="${UI:-$ROOT/src/i18n/ui.ts}"
SCRIPT="${SCRIPT:-$ROOT/src/scripts/labs360.js}"
MAP_HELPER="${MAP_HELPER:-$ROOT/src/scripts/labs360-map.js}"
PASS=0
FAIL=0
pass(){ PASS=$((PASS + 1)); printf 'ok - %s\n' "$1"; }
fail(){ FAIL=$((FAIL + 1)); printf 'not ok - %s\n' "$1" >&2; }

test_real_quebec_places_only() {
  local expected id ids id_count places quebec_city_count
  expected="maizerets patro-roc-amadour giffard centre-monseigneur-marcoux limoilou colline-parlementaire"
  places="$(sed -n '/^export const PLACES: Labs360Place\[\] = \[$/,/^[[:space:]]*\/\/ iso360:insert/p' "$DATA")"
  ids="$(printf '%s\n' "$places" | sed -n "s/^[[:space:]]*id: ['\"]\([^'\"]*\)['\"],$/\1/p")"
  id_count="$(printf '%s\n' "$ids" | awk 'NF { count++ } END { print count + 0 }')"
  quebec_city_count="$(printf '%s\n' "$places" | sed -n "s/^[[:space:]]*city: ['\"]quebec['\"],$/quebec/p" | awk 'NF { count++ } END { print count + 0 }')"

  [ "$id_count" -eq 6 ] || { fail "exactement six IDs dans PLACES (reçu: $id_count)"; return; }
  [ "$quebec_city_count" -eq 6 ] || { fail "les six lieux sont tous à Québec (reçu: $quebec_city_count)"; return; }

  for id in $expected; do
    printf '%s\n' "$ids" | rg -qx -- "$id" || { fail "lieu réel présent: $id"; return; }
  done
  pass "PLACES contient exactement les six vrais lieux Québec"
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

test_real_quebec_places_only
test_quebec_only_markup_and_copy
test_labs_project_copy_quebec_only
test_quebec_only_map_logic
test_region_for_places
printf '\n%s réussite(s), %s échec(s)\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
