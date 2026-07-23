#!/usr/bin/env bash

# Régressions ciblées du pipeline iso360/iso-ingest.
# Compatible avec le Bash 3.2 livré sur macOS.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/labs360-tests.XXXXXX")"
PASS=0
FAIL=0

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

pass() {
  PASS=$((PASS + 1))
  printf 'ok - %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'not ok - %s\n' "$1" >&2
}

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  if [ "$expected" = "$actual" ]; then
    return 0
  fi
  printf '  attendu: %s\n  obtenu:  %s\n' "$expected" "$actual" >&2
  fail "$message"
  return 1
}

test_extract_meta_preserves_empty_gps_and_spaced_date() {
  local case_dir="$TMP_ROOT/meta-empty-gps"
  mkdir -p "$case_dir/bin"
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf '\''[{"DateTimeOriginal":"2026:07:23 14:05:11"}]\n'\''' \
    > "$case_dir/bin/exiftool"
  chmod +x "$case_dir/bin/exiftool"

  local lat="" lon="" dt=""
  IFS='|' read -r lat lon dt <<EOF
$(
  PATH="$case_dir/bin:$PATH"
  . "$ROOT/scripts/iso360-core.sh"
  core_extract_meta "$case_dir/photo.jpg"
)
EOF
  if [ -z "$lat" ] && [ -z "$lon" ] && [ "$dt" = "2026:07:23 14:05:11" ]; then
    pass "les métadonnées gardent GPS vide et date complète sans ambiguïté"
  else
    printf '  lat=%s lon=%s date=%s\n' "$lat" "$lon" "$dt" >&2
    fail "les métadonnées gardent GPS vide et date complète sans ambiguïté"
  fi
}

test_photo_without_gps_or_date_uses_filename_fallback() {
  local case_dir="$TMP_ROOT/meta-filename-fallback"
  mkdir -p "$case_dir/inbox" "$case_dir/videos" "$case_dir/photos" \
    "$case_dir/bin" "$case_dir/repo/src/data"
  printf 'photo\n' > "$case_dir/inbox/chute-montmorency.jpg"
  printf '// iso360:insert\n' > "$case_dir/repo/src/data/labs360.ts"
  printf '%s\n' '#!/usr/bin/env bash' 'printf '\''[{}]\n'\''' \
    > "$case_dir/bin/exiftool"
  chmod +x "$case_dir/bin/exiftool"

  if (
    export PATH="$case_dir/bin:$PATH"
    export ISO_NORD_INGEST_SOURCE_ONLY=1
    export ISO_NORD_MEDIA_ROOT="$case_dir"
    export ISO_NORD_REPO="$case_dir/repo"
    . "$ROOT/scripts/iso-ingest.sh"
    DRY=1
    detect_type() { printf 'photo\n'; }
    core_forward_geocode() {
      [ "$1" = "chute-montmorency" ] || return 1
      printf '46.8900 -71.1500\n'
    }
    core_geocode() {
      [ "$LAT" = "46.8900" ] && [ "$LON" = "-71.1500" ] && [ -z "$DT" ] \
        || return 1
      printf '{"lat":46.89,"lon":-71.15,"dt":"","ym":"","name":"Chute Montmorency","city":"quebec","id":"chute-montmorency"}\n'
    }
    sips() {
      for last do :; done
      printf 'web\n' > "$last"
    }
    process "$case_dir/inbox/chute-montmorency.jpg" \
      >"$case_dir/process.log" 2>&1
  ); then
    pass "une photo sans GPS ni date utilise le nom de fichier"
  else
    cat "$case_dir/process.log" >&2
    fail "une photo sans GPS ni date utilise le nom de fichier"
  fi
}

test_geocode_outage_fails() {
  (
    . "$ROOT/scripts/iso360-core.sh"
    ISO_NORD_NOMINATIM_BASE_URL="http://127.0.0.1:1" \
    ISO_NORD_GEOCODE_RETRIES=1 \
    ISO_NORD_GEOCODE_TIMEOUT=0.1 \
    LAT=46.81 LON=-71.20 DT="2026:07:23 12:00:00" \
      core_geocode >/dev/null 2>&1
  )
  if [ "$?" -ne 0 ]; then
    pass "une panne Nominatim fait échouer le géocodage"
  else
    fail "une panne Nominatim fait échouer le géocodage"
  fi
}

test_publish_never_overwrites() {
  local case_dir="$TMP_ROOT/publish-no-overwrite"
  mkdir -p "$case_dir/dest" "$case_dir/bin"
  printf 'nouveau\n' > "$case_dir/source"
  printf 'ancien\n' > "$case_dir/dest/media.jpg"
  printf '#!/usr/bin/env bash\nprintf 200\n' > "$case_dir/bin/curl"
  chmod +x "$case_dir/bin/curl"

  (
    PATH="$case_dir/bin:$PATH"
    . "$ROOT/scripts/iso360-core.sh"
    core_publish_verify "$case_dir/source" "$case_dir/dest" \
      "https://media.invalid/photos" "media.jpg" >/dev/null 2>&1
  )
  local status=$?
  local content
  content="$(tr -d '\n' < "$case_dir/dest/media.jpg")"
  if [ "$status" -ne 0 ] && [ "$content" = "ancien" ]; then
    pass "la publication immutable refuse une destination existante"
  else
    printf '  status=%s contenu=%s\n' "$status" "$content" >&2
    fail "la publication immutable refuse une destination existante"
  fi
}

test_publish_curl_is_bounded() {
  local case_dir="$TMP_ROOT/publish-timeouts"
  mkdir -p "$case_dir/dest" "$case_dir/bin"
  printf 'média\n' > "$case_dir/source"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" > "$ISO_TEST_CURL_ARGS"\nprintf 200\n' \
    > "$case_dir/bin/curl"
  chmod +x "$case_dir/bin/curl"

  (
    export ISO_TEST_CURL_ARGS="$case_dir/curl.args"
    PATH="$case_dir/bin:$PATH"
    . "$ROOT/scripts/iso360-core.sh"
    core_publish_verify "$case_dir/source" "$case_dir/dest" \
      "https://media.invalid/photos" "nouveau.jpg" >/dev/null 2>&1
  )
  local args=""
  [ -f "$case_dir/curl.args" ] && args="$(cat "$case_dir/curl.args")"
  case "$args" in
    *--connect-timeout*--max-time*)
      pass "les requêtes curl ont des délais maximaux"
      ;;
    *)
      printf '  args curl: %s\n' "$args" >&2
      fail "les requêtes curl ont des délais maximaux"
      ;;
  esac
}

test_published_media_is_world_readable() {
  local case_dir="$TMP_ROOT/publish-mode"
  mkdir -p "$case_dir/dest" "$case_dir/bin"
  printf 'média\n' > "$case_dir/source"
  printf '#!/usr/bin/env bash\nprintf 200\n' > "$case_dir/bin/curl"
  chmod +x "$case_dir/bin/curl"
  (
    PATH="$case_dir/bin:$PATH"
    . "$ROOT/scripts/iso360-core.sh"
    core_publish_verify "$case_dir/source" "$case_dir/dest" \
      "https://media.invalid/photos" "public.jpg" >/dev/null 2>&1
  )
  local mode
  mode="$(stat -f '%Lp' "$case_dir/dest/public.jpg")"
  if [ "$mode" = "644" ]; then
    pass "un média publié reste lisible par Caddy"
  else
    printf '  permissions: %s\n' "$mode" >&2
    fail "un média publié reste lisible par Caddy"
  fi
}

test_build_requires_exactly_ten_pages() {
  local case_dir="$TMP_ROOT/build-count"
  mkdir -p "$case_dir/bin"
  printf '#!/usr/bin/env bash\nprintf "[build] 9 page(s) built in 0.1s\\n"\n' > "$case_dir/bin/npm"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$case_dir/bin/git"
  chmod +x "$case_dir/bin/npm" "$case_dir/bin/git"
  printf 'data\n' > "$case_dir/labs360.ts"

  (
    PATH="$case_dir/bin:$PATH"
    . "$ROOT/scripts/iso360-core.sh"
    core_build_guard "$case_dir/labs360.ts" >/dev/null 2>&1
  )
  if [ "$?" -ne 0 ]; then
    pass "le garde-fou rejette un build qui ne produit pas 10 pages"
  else
    fail "le garde-fou rejette un build qui ne produit pas 10 pages"
  fi
}

test_build_accepts_exactly_ten_pages() {
  local case_dir="$TMP_ROOT/build-ten"
  mkdir -p "$case_dir/bin"
  printf '#!/usr/bin/env bash\nprintf "[build] 10 page(s) built in 0.1s\\n"\n' > "$case_dir/bin/npm"
  chmod +x "$case_dir/bin/npm"
  printf 'data\n' > "$case_dir/labs360.ts"

  if (
    PATH="$case_dir/bin:$PATH"
    . "$ROOT/scripts/iso360-core.sh"
    core_build_guard "$case_dir/labs360.ts" >/dev/null 2>&1
  ); then
    pass "le garde-fou accepte exactement 10 pages"
  else
    fail "le garde-fou accepte exactement 10 pages"
  fi
}

test_git_commit_failure_propagates() {
  local case_dir="$TMP_ROOT/git-failure"
  mkdir -p "$case_dir/bin"
  printf '#!/usr/bin/env bash\nif [ "$1" = symbolic-ref ]; then printf "main\\n"; exit 0; fi\n[ "$1" != commit ]\n' > "$case_dir/bin/git"
  chmod +x "$case_dir/bin/git"
  printf 'data\n' > "$case_dir/labs360.ts"

  (
    PATH="$case_dir/bin:$PATH"
    . "$ROOT/scripts/iso360-core.sh"
    core_commit_push "$case_dir/labs360.ts" add "Test" 0 \
      "https://example.invalid/labs/360" "test.jpg" >/dev/null 2>&1
  )
  if [ "$?" -ne 0 ]; then
    pass "un échec git commit est propagé"
  else
    fail "un échec git commit est propagé"
  fi
}

test_git_add_and_push_failures_propagate() {
  local phase case_dir status ok=1
  for phase in add push; do
    case_dir="$TMP_ROOT/git-$phase"
    mkdir -p "$case_dir/bin"
    printf '#!/usr/bin/env bash\nphase="$ISO_TEST_GIT_PHASE"\ncase "$1" in\n  symbolic-ref) printf "main\\n";;\n  rev-parse) printf "deadbeef\\n";;\n  "$phase") exit 1;;\n  *) exit 0;;\nesac\n' > "$case_dir/bin/git"
    chmod +x "$case_dir/bin/git"
    printf 'data\n' > "$case_dir/labs360.ts"
    (
      export ISO_TEST_GIT_PHASE="$phase"
      PATH="$case_dir/bin:$PATH"
      . "$ROOT/scripts/iso360-core.sh"
      core_commit_push "$case_dir/labs360.ts" add "Test" 1 \
        "https://example.invalid/labs/360" "test.jpg" >/dev/null 2>&1
    )
    status=$?
    if [ "$status" -eq 0 ]; then
      printf '  phase non propagée: %s\n' "$phase" >&2
      ok=0
    fi
  done
  if [ "$ok" -eq 1 ]; then
    pass "les échecs git add et git push sont propagés"
  else
    fail "les échecs git add et git push sont propagés"
  fi
}

test_real_git_commit_succeeds() {
  local case_dir="$TMP_ROOT/git-real"
  mkdir -p "$case_dir/src/data"
  (
    cd "$case_dir"
    git init -q
    git config user.name "Test"
    git config user.email "test@example.invalid"
    printf 'avant\n' > src/data/labs360.ts
    git add src/data/labs360.ts
    git commit -qm initial
    printf 'après\n' > src/data/labs360.ts
    . "$ROOT/scripts/iso360-core.sh"
    core_commit_push "$case_dir/src/data/labs360.ts" add "Test" 0 \
      "https://example.invalid/labs/360" "test.jpg" >/dev/null 2>&1
  )
  if [ "$?" -eq 0 ] \
    && [ "$(git -C "$case_dir" rev-list --count HEAD)" = "2" ] \
    && [ "$(git -C "$case_dir" show HEAD:src/data/labs360.ts)" = "après" ]; then
    pass "le chemin Git réel add + commit fonctionne"
  else
    fail "le chemin Git réel add + commit fonctionne"
  fi
}

test_push_targets_head_to_main_explicitly() {
  local case_dir="$TMP_ROOT/git-push-target" real_git=""
  real_git="$(command -v git)"
  mkdir -p "$case_dir/repo/src/data" "$case_dir/bin"
  git init -q --bare "$case_dir/remote.git"
  (
    cd "$case_dir/repo"
    git init -q
    git symbolic-ref HEAD refs/heads/main
    git config user.name "Test"
    git config user.email "test@example.invalid"
    printf 'avant\n' > src/data/labs360.ts
    git add src/data/labs360.ts
    git commit -qm initial
    git remote add origin "$case_dir/remote.git"
    git push -q -u origin main
  )
  printf '%s\n' '#!/usr/bin/env bash' \
    'if [ "$1" = push ]; then printf "%s\n" "$*" > "$ISO_TEST_PUSH_ARGS"; fi' \
    'exec "$ISO_TEST_REAL_GIT" "$@"' > "$case_dir/bin/git"
  printf '%s\n' '#!/usr/bin/env bash' 'printf published' > "$case_dir/bin/curl"
  chmod +x "$case_dir/bin/git" "$case_dir/bin/curl"
  printf 'après\n' > "$case_dir/repo/src/data/labs360.ts"

  if (
    cd "$case_dir/repo"
    export ISO_TEST_REAL_GIT="$real_git"
    export ISO_TEST_PUSH_ARGS="$case_dir/push.args"
    export ISO_NORD_DEPLOY_ATTEMPTS=1
    PATH="$case_dir/bin:$PATH"
    . "$ROOT/scripts/iso360-core.sh"
    core_commit_push "$case_dir/repo/src/data/labs360.ts" add "Test" 1 \
      "https://example.invalid/labs/360" "published" >/dev/null 2>&1
  ) && [ "$(cat "$case_dir/push.args")" = "push -q origin HEAD:main" ]; then
    pass "le push cible explicitement HEAD:main"
  else
    printf '  push=%s\n' "$(cat "$case_dir/push.args" 2>/dev/null)" >&2
    fail "le push cible explicitement HEAD:main"
  fi
}

test_unique_helpers() {
  local case_dir="$TMP_ROOT/unique"
  mkdir -p "$case_dir/archive" "$case_dir/media"
  printf 'x\n' > "$case_dir/archive/photo.jpg"
  printf 'x\n' > "$case_dir/media/lieu-2026-07.jpg"
  printf "id: 'lieu'\n" > "$case_dir/labs360.ts"

  local path filename place_id
  path="$(
    . "$ROOT/scripts/iso360-core.sh"
    core_unique_path "$case_dir/archive/photo.jpg"
  )"
  filename="$(
    . "$ROOT/scripts/iso360-core.sh"
    core_unique_filename "$case_dir/media" "lieu-2026-07.jpg"
  )"
  place_id="$(
    . "$ROOT/scripts/iso360-core.sh"
    core_unique_place_id "$case_dir/labs360.ts" "lieu"
  )"

  local ok=1
  assert_eq "$case_dir/archive/photo-2.jpg" "$path" \
    "un nom d’archive existant reçoit un suffixe" || ok=0
  assert_eq "lieu-2026-07-2.jpg" "$filename" \
    "un nom média existant reçoit un suffixe" || ok=0
  assert_eq "lieu-2" "$place_id" \
    "un id de lieu existant reçoit un suffixe" || ok=0
  [ "$ok" -eq 1 ] && pass "les helpers produisent des identités uniques"
}

test_ingest_can_be_sourced_without_running() {
  local marker
  marker="$(
    ISO_NORD_INGEST_SOURCE_ONLY=1 \
    ISO_NORD_MEDIA_ROOT="$TMP_ROOT/source-only-missing" \
      bash -c '. "$1/scripts/iso-ingest.sh"; type acquire_lock >/dev/null; printf sourced' _ "$ROOT" 2>/dev/null
  )"
  assert_eq "sourced" "$marker" \
    "iso-ingest peut être sourcé pour tester ses fonctions" \
    && pass "iso-ingest peut être sourcé sans mutation"
}

test_stale_lock_is_recovered() {
  local case_dir="$TMP_ROOT/stale-lock"
  mkdir -p "$case_dir/inbox.lock"
  if (
    export ISO_NORD_INGEST_SOURCE_ONLY=1
    export ISO_NORD_MEDIA_ROOT="$case_dir"
    export ISO_NORD_LOCK_INIT_GRACE=0
    . "$ROOT/scripts/iso-ingest.sh"
    acquire_lock
    release_lock
  ) >/dev/null 2>&1 && [ ! -d "$case_dir/inbox.lock" ]; then
    pass "un verrou dont le processus est mort est récupéré"
  else
    fail "un verrou dont le processus est mort est récupéré"
  fi
}

test_active_lock_is_kept() {
  local case_dir="$TMP_ROOT/active-lock"
  if (
    export ISO_NORD_INGEST_SOURCE_ONLY=1
    export ISO_NORD_MEDIA_ROOT="$case_dir"
    . "$ROOT/scripts/iso-ingest.sh"
    mkdir -p "$LOCK"
    LOCK_TOKEN="active-token"
    write_lock_owner
    acquire_lock
  ) >/dev/null 2>&1; then
    fail "un verrou actif n’est pas volé"
  else
    pass "un verrou actif n’est pas volé"
  fi
}

test_pid_reuse_and_reboot_do_not_keep_stale_lock() {
  local mode case_dir ok=1
  for mode in reboot pid-reuse; do
    case_dir="$TMP_ROOT/lock-$mode"
    mkdir -p "$case_dir/inbox.lock"
    (
      export ISO_NORD_INGEST_SOURCE_ONLY=1
      export ISO_NORD_MEDIA_ROOT="$case_dir"
      export ISO_NORD_BOOT_ID="boot-actuel"
      . "$ROOT/scripts/iso-ingest.sh"
      printf '%s\n' "$$" > "$LOCK/pid"
      printf 'ancien-token\n' > "$LOCK/token"
      if [ "$mode" = "reboot" ]; then
        printf 'boot-précédent\n' > "$LOCK/boot_id"
        lock_process_start "$$" > "$LOCK/process_start"
      else
        printf 'boot-actuel\n' > "$LOCK/boot_id"
        printf 'date-de-départ-d’un-ancien-processus\n' > "$LOCK/process_start"
      fi
      : > "$LOCK/ready"
      acquire_lock
      release_lock
    ) >/dev/null 2>&1 || ok=0
    [ ! -d "$case_dir/inbox.lock" ] || ok=0
  done
  if [ "$ok" -eq 1 ]; then
    pass "boot différent et PID réutilisé rendent le lock stale"
  else
    fail "boot différent et PID réutilisé rendent le lock stale"
  fi
}

test_recent_ownerless_lock_is_not_stolen() {
  local case_dir="$TMP_ROOT/ownerless-lock"
  mkdir -p "$case_dir/inbox.lock"
  if (
    export ISO_NORD_INGEST_SOURCE_ONLY=1
    export ISO_NORD_MEDIA_ROOT="$case_dir"
    export ISO_NORD_LOCK_INIT_GRACE=30
    . "$ROOT/scripts/iso-ingest.sh"
    acquire_lock
  ) >/dev/null 2>&1; then
    fail "un lock récent sans owner n’est pas volé pendant son initialisation"
  elif [ -d "$case_dir/inbox.lock" ]; then
    pass "un lock récent sans owner n’est pas volé pendant son initialisation"
  else
    fail "un lock récent sans owner reste intact"
  fi
}

test_commit_failure_keeps_original() {
  local case_dir="$TMP_ROOT/archive-after-commit"
  mkdir -p "$case_dir/inbox" "$case_dir/inbox-publies" "$case_dir/videos" \
    "$case_dir/photos" "$case_dir/bin" "$case_dir/repo/src/data"
  printf 'vidéo\n' > "$case_dir/inbox/test.mp4"
  printf '// iso360:insert\n' > "$case_dir/repo/src/data/labs360.ts"
  (
    cd "$case_dir/repo"
    git init -q
    git symbolic-ref HEAD refs/heads/main
    git config user.name "Test"
    git config user.email "test@example.invalid"
    git add src/data/labs360.ts
    git commit -qm initial
  )
  printf '#!/usr/bin/env bash\nfor last do :; done\nprintf poster > "$last"\n' \
    > "$case_dir/bin/ffmpeg"
  chmod +x "$case_dir/bin/ffmpeg"

  (
    export PATH="$case_dir/bin:$PATH"
    export ISO_NORD_INGEST_SOURCE_ONLY=1
    export ISO_NORD_MEDIA_ROOT="$case_dir"
    export ISO_NORD_REPO="$case_dir/repo"
    . "$ROOT/scripts/iso-ingest.sh"
    detect_type() { printf 'video\n'; }
    core_extract_meta() { printf '46.81|-71.20|2026:07:23\n'; }
    core_geocode() {
      printf '{"lat":46.81,"lon":-71.20,"dt":"2026:07:23","ym":"2026-07","name":"Test","city":"quebec","id":"test"}\n'
    }
    core_publish_verify() { return 0; }
    core_wire() { return 0; }
    core_build_guard() { return 0; }
    core_commit_push() { return 1; }
    core_file_is_clean() { return 0; }
    process "$case_dir/inbox/test.mp4" >/dev/null 2>&1
  )
  if [ -f "$case_dir/inbox/test.mp4" ] \
    && [ ! -e "$case_dir/inbox-publies/test.mp4" ]; then
    pass "un échec commit/push laisse l’original dans inbox"
  else
    fail "un échec commit/push laisse l’original dans inbox"
  fi
}

test_archive_retry_does_not_republish() {
  local case_dir="$TMP_ROOT/archive-retry"
  mkdir -p "$case_dir/inbox-processing" "$case_dir/inbox-publies" \
    "$case_dir/videos" "$case_dir/photos" "$case_dir/bin" "$case_dir/repo/src/data"
  printf 'vidéo\n' > "$case_dir/inbox-processing/test.mp4"
  printf '// iso360:insert\n' > "$case_dir/repo/src/data/labs360.ts"
  (
    cd "$case_dir/repo"
    git init -q
    git symbolic-ref HEAD refs/heads/main
    git config user.name "Test"
    git config user.email "test@example.invalid"
    git add src/data/labs360.ts
    git commit -qm initial
  )
  printf '#!/usr/bin/env bash\nfor last do :; done\nprintf poster > "$last"\n' \
    > "$case_dir/bin/ffmpeg"
  chmod +x "$case_dir/bin/ffmpeg"

  (
    export PATH="$case_dir/bin:$PATH"
    export ISO_NORD_INGEST_SOURCE_ONLY=1
    export ISO_NORD_MEDIA_ROOT="$case_dir"
    export ISO_NORD_REPO="$case_dir/repo"
    . "$ROOT/scripts/iso-ingest.sh"
    detect_type() { printf 'video\n'; }
    core_extract_meta() { printf '46.81|-71.20|2026:07:23\n'; }
    core_geocode() {
      printf '{"lat":46.81,"lon":-71.20,"dt":"2026:07:23","ym":"2026-07","name":"Test","city":"quebec","id":"test"}\n'
    }
    core_publish_verify() {
      printf 'publish\n' >> "$case_dir/publish.count"
      return 0
    }
    core_wire() {
      printf '// %s\n' "$WIRE_NOTE" >> "$DATA"
      return 0
    }
    core_build_guard() { return 0; }
    core_commit_push() { return 0; }
    core_file_is_clean() { return 0; }
    archive_fail_once=1
    mv() {
      if [ "$archive_fail_once" -eq 1 ] && [[ "${2:-}" == "$PUBLIES/"* ]]; then
        archive_fail_once=0
        return 1
      fi
      command mv "$@"
    }
    process "$case_dir/inbox-processing/test.mp4" >/dev/null 2>&1 || true
    process "$case_dir/inbox-processing/test.mp4" >/dev/null 2>&1
  )
  local publish_count=0
  [ -f "$case_dir/publish.count" ] \
    && publish_count="$(wc -l < "$case_dir/publish.count" | tr -d ' ')"
  if [ "$publish_count" = "2" ] \
    && [ -f "$case_dir/inbox-publies/test.mp4" ] \
    && [ ! -f "$case_dir/inbox-processing/test.mp4" ]; then
    pass "un retry d’archive après push ne republie ni média ni pin"
  else
    printf '  publications=%s archive=%s processing=%s\n' \
      "$publish_count" \
      "$([ -f "$case_dir/inbox-publies/test.mp4" ] && printf oui || printf non)" \
      "$([ -f "$case_dir/inbox-processing/test.mp4" ] && printf oui || printf non)" >&2
    fail "un retry d’archive après push ne republie ni média ni pin"
  fi
}

test_crash_between_commit_and_push_resumes_push_only() {
  local case_dir="$TMP_ROOT/commit-before-push" job_id=""
  mkdir -p "$case_dir/media/inbox-processing" "$case_dir/repo/src/data"
  git init -q --bare "$case_dir/remote.git"
  (
    cd "$case_dir/repo"
    git init -q
    git symbolic-ref HEAD refs/heads/main
    git config user.name "Test"
    git config user.email "test@example.invalid"
    printf '// iso360:insert\n' > src/data/labs360.ts
    git add src/data/labs360.ts
    git commit -qm initial
    git remote add origin "$case_dir/remote.git"
    git push -q -u origin main
  )
  printf 'vidéo\n' > "$case_dir/media/inbox-processing/test.mp4"
  (
    export ISO_NORD_INGEST_SOURCE_ONLY=1
    export ISO_NORD_MEDIA_ROOT="$case_dir/media"
    export ISO_NORD_REPO="$case_dir/repo"
    . "$ROOT/scripts/iso-ingest.sh"
    job_id="$(ensure_job_marker "$case_dir/media/inbox-processing/test.mp4")"
    printf '// ingest-job:%s\n' "$job_id" >> "$DATA_FILE"
    git -C "$REPO" add "$DATA_FILE"
    git -C "$REPO" commit -qm "pending ingest"
    job_ready_for_archive "$case_dir/media/inbox-processing/test.mp4" "$job_id"
    printf '%s\n' "$job_id" > "$case_dir/job-id"
  )
  job_id="$(cat "$case_dir/job-id")"
  if git --git-dir="$case_dir/remote.git" show main:src/data/labs360.ts \
      | grep -Fq "ingest-job:$job_id"; then
    pass "un crash entre commit et push reprend le push sans republier"
  else
    fail "un crash entre commit et push reprend le push sans republier"
  fi
}

test_crash_after_wire_rolls_back_dirty_repo_for_replay() {
  local case_dir="$TMP_ROOT/wire-before-commit" job_id="" status=0
  mkdir -p "$case_dir/media/inbox-processing" "$case_dir/repo/src/data"
  (
    cd "$case_dir/repo"
    git init -q
    git symbolic-ref HEAD refs/heads/main
    git config user.name "Test"
    git config user.email "test@example.invalid"
    printf '// iso360:insert\n' > src/data/labs360.ts
    git add src/data/labs360.ts
    git commit -qm initial
  )
  printf 'photo\n' > "$case_dir/media/inbox-processing/test.jpg"
  (
    export ISO_NORD_INGEST_SOURCE_ONLY=1
    export ISO_NORD_MEDIA_ROOT="$case_dir/media"
    export ISO_NORD_REPO="$case_dir/repo"
    . "$ROOT/scripts/iso-ingest.sh"
    job_id="$(ensure_job_marker "$case_dir/media/inbox-processing/test.jpg")"
    mark_job_wiring "$case_dir/media/inbox-processing/test.jpg"
    printf '// ingest-job:%s\n' "$job_id" >> "$DATA_FILE"
    job_ready_for_archive "$case_dir/media/inbox-processing/test.jpg" "$job_id"
    status=$?
    printf '%s\n%s\n' "$job_id" "$status" > "$case_dir/result"
  )
  job_id="$(sed -n '1p' "$case_dir/result")"
  status="$(sed -n '2p' "$case_dir/result")"
  if [ "$status" = "1" ] \
    && git -C "$case_dir/repo" diff --quiet -- src/data/labs360.ts \
    && git -C "$case_dir/repo" diff --cached --quiet -- src/data/labs360.ts \
    && ! grep -Fq "ingest-job:$job_id" "$case_dir/repo/src/data/labs360.ts"; then
    pass "un crash après wire rollback le dépôt réel pour rejouer"
  else
    git -C "$case_dir/repo" status --short >&2
    fail "un crash après wire rollback le dépôt réel pour rejouer"
  fi
}

test_feature_branch_is_rejected_before_publication() {
  local case_dir="$TMP_ROOT/feature-branch"
  mkdir -p "$case_dir/media/inbox" "$case_dir/repo/src/data"
  git init -q --bare "$case_dir/remote.git"
  (
    cd "$case_dir/repo"
    git init -q
    git symbolic-ref HEAD refs/heads/main
    git config user.name "Test"
    git config user.email "test@example.invalid"
    printf '// iso360:insert\n' > src/data/labs360.ts
    git add src/data/labs360.ts
    git commit -qm initial
    git remote add origin "$case_dir/remote.git"
    git push -q -u origin main
    git checkout -qb feature/test
  )
  printf 'photo\n' > "$case_dir/media/inbox/test.jpg"

  if ! ISO_NORD_MEDIA_ROOT="$case_dir/media" \
      ISO_NORD_REPO="$case_dir/repo" \
      "$ROOT/scripts/iso-ingest.sh" >/dev/null 2>&1 \
    && [ -f "$case_dir/media/inbox/test.jpg" ] \
    && [ ! -e "$case_dir/media/inbox-publies/test.jpg" ] \
    && [ -z "$(find "$case_dir/media/panoramas" "$case_dir/media/videos" \
      "$case_dir/media/photos" -type f -print 2>/dev/null)" ]; then
    pass "une branche feature échoue avant publication et archivage"
  else
    fail "une branche feature échoue avant publication et archivage"
  fi
}

test_dry_run_creates_no_persistent_state() {
  local case_dir="$TMP_ROOT/dry-run"
  mkdir -p "$case_dir/inbox"
  if ISO_NORD_MEDIA_ROOT="$case_dir" \
    ISO_NORD_REPO="$ROOT" \
    "$ROOT/scripts/iso-ingest.sh" --dry-run >/dev/null 2>&1 \
    && [ ! -e "$case_dir/inbox.log" ] \
    && [ ! -e "$case_dir/inbox.lock" ] \
    && [ ! -e "$case_dir/inbox-corriger" ] \
    && [ ! -e "$case_dir/inbox-publies" ] \
    && [ ! -e "$case_dir/photos" ]; then
    pass "le dry-run ne crée ni lock, log, dossiers ni publication"
  else
    fail "le dry-run ne crée ni lock, log, dossiers ni publication"
  fi
}

test_dry_run_processes_without_publishing() {
  local case_dir="$TMP_ROOT/dry-run-file"
  mkdir -p "$case_dir/inbox" "$case_dir/videos" "$case_dir/photos" \
    "$case_dir/bin" "$case_dir/repo/src/data"
  printf 'vidéo\n' > "$case_dir/inbox/test.mp4"
  printf '// iso360:insert\n' > "$case_dir/repo/src/data/labs360.ts"
  printf '#!/usr/bin/env bash\nfor last do :; done\nprintf poster > "$last"\n' \
    > "$case_dir/bin/ffmpeg"
  chmod +x "$case_dir/bin/ffmpeg"
  (
    export PATH="$case_dir/bin:$PATH"
    export ISO_NORD_INGEST_SOURCE_ONLY=1
    export ISO_NORD_MEDIA_ROOT="$case_dir"
    export ISO_NORD_REPO="$case_dir/repo"
    . "$ROOT/scripts/iso-ingest.sh"
    DRY=1
    detect_type() { printf 'video\n'; }
    core_extract_meta() { printf '46.81|-71.20|2026:07:23\n'; }
    core_geocode() {
      printf '{"lat":46.81,"lon":-71.20,"dt":"2026:07:23","ym":"2026-07","name":"Test","city":"quebec","id":"test"}\n'
    }
    process "$case_dir/inbox/test.mp4" >/dev/null 2>&1
  )
  if [ -f "$case_dir/inbox/test.mp4" ] \
    && [ ! -e "$case_dir/inbox.log" ] \
    && [ -z "$(find "$case_dir/videos" "$case_dir/photos" -type f -print)" ] \
    && [ "$(cat "$case_dir/repo/src/data/labs360.ts")" = "// iso360:insert" ]; then
    pass "le dry-run d’un fichier prépare sans publier ni câbler"
  else
    fail "le dry-run d’un fichier prépare sans publier ni câbler"
  fi
}

test_extract_meta_preserves_empty_gps_and_spaced_date
test_photo_without_gps_or_date_uses_filename_fallback
test_geocode_outage_fails
test_publish_never_overwrites
test_publish_curl_is_bounded
test_published_media_is_world_readable
test_build_requires_exactly_ten_pages
test_build_accepts_exactly_ten_pages
test_git_commit_failure_propagates
test_git_add_and_push_failures_propagate
test_real_git_commit_succeeds
test_push_targets_head_to_main_explicitly
test_unique_helpers
test_ingest_can_be_sourced_without_running
test_stale_lock_is_recovered
test_active_lock_is_kept
test_recent_ownerless_lock_is_not_stolen
test_pid_reuse_and_reboot_do_not_keep_stale_lock
test_commit_failure_keeps_original
test_archive_retry_does_not_republish
test_crash_between_commit_and_push_resumes_push_only
test_crash_after_wire_rolls_back_dirty_repo_for_replay
test_feature_branch_is_rejected_before_publication
test_dry_run_creates_no_persistent_state
test_dry_run_processes_without_publishing

printf '\n%s réussite(s), %s échec(s)\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
