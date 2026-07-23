#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="${DATA:-$ROOT/src/data/labs360.ts}"
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

test_real_quebec_places_only
printf '\n%s réussite(s), %s échec(s)\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
