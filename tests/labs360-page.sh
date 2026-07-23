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
