#!/usr/bin/env bash
#
# iso-ingest — boîte de dépôt : un fichier déposé dans inbox/ devient un pin
# géolocalisé sur theo-picture.com/labs/360. Déclenché par un LaunchAgent
# (WatchPaths) ou lancé à la main. Mac Pro NAS headless → AUCUN popup :
# l'interaction se fait par les fichiers (inbox-corriger/) et le log.
#
# Usage : iso-ingest [--dry-run] [--no-push]
#
# Types détectés :  .mp4/.mov → video ;  image 2:1 → 360 ;  autre image → photo
# GPS : exiftool. Absent → nom de fichier ("lieu" ou "lat,lon"). Rien → quarantaine.

set -uo pipefail   # PAS -e : on gère les échecs par fichier sans tuer la boucle

# ─── Racine du repo (résolue depuis l'emplacement réel du script) ────────────
_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"; _src="$(readlink "$_src")"
  [[ "$_src" != /* ]] && _src="$_dir/$_src"
done
SCRIPT_DIR="$(cd -P "$(dirname "$_src")" && pwd)"

REPO="${ISO_NORD_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
MEDIA_ROOT="${ISO_NORD_MEDIA_ROOT:-/Volumes/SSD 1/iso-nord-media}"
INBOX="$MEDIA_ROOT/inbox"
CORRIGER="$MEDIA_ROOT/inbox-corriger"
PUBLIES="$MEDIA_ROOT/inbox-publies"
PROCESSING="$MEDIA_ROOT/inbox-processing"
LOGFILE="$MEDIA_ROOT/inbox.log"
LOCK="$MEDIA_ROOT/inbox.lock"

export MEDIA_BASE_URL="https://media.theo-picture.com"   # utilisé par core_commit_push
LIVE_PAGE="https://theo-picture.com/labs/360"
DATA_FILE="$REPO/src/data/labs360.ts"
PREVIEW_DIR="$REPO/public/assets/labs360/previews"

DRY=0; PUSH=1
if [[ "${ISO_NORD_INGEST_SOURCE_ONLY:-0}" != "1" ]]; then
  for a in "$@"; do
    case "$a" in
      --dry-run) DRY=1;;
      --no-push) PUSH=0;;
      *) echo "Option inconnue : $a" >&2; exit 2;;
    esac
  done
fi

source "$SCRIPT_DIR/iso360-core.sh"

log(){
  if [[ "$DRY" == "1" ]]; then
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
  else
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOGFILE" >&2
  fi
}

# ─── Verrou (traitement séquentiel) ──────────────────────────────────────────
LOCK_TOKEN=""

clean_stale_lock_copy() {
  local stale="$1"
  rm -f "$stale/owner" "$stale/pid" "$stale/token" "$stale/boot_id" \
    "$stale/process_start" "$stale/ready" 2>/dev/null || true
  rmdir "$stale" 2>/dev/null || true
}

lock_boot_id() {
  local value=""
  if [[ -n "${ISO_NORD_BOOT_ID:-}" ]]; then
    printf '%s\n' "$ISO_NORD_BOOT_ID"
    return
  fi
  if [[ -r /proc/sys/kernel/random/boot_id ]]; then
    tr -d '\n' < /proc/sys/kernel/random/boot_id
    printf '\n'
    return
  fi
  value=$(sysctl -n kern.boottime 2>/dev/null \
    | sed -E 's/.*sec = ([0-9]+).*/\1/' || true)
  [[ "$value" =~ ^[0-9]+$ ]] || value="boot-inconnu"
  printf '%s\n' "$value"
}

lock_process_start() {
  ps -p "$1" -o lstart= 2>/dev/null \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

lock_age_seconds() {
  local modified="" now=""
  modified=$(stat -f%m "$LOCK" 2>/dev/null \
    || stat -c%Y "$LOCK" 2>/dev/null \
    || echo 0)
  now=$(date +%s)
  if [[ "$modified" =~ ^[0-9]+$ && "$modified" -gt 0 ]]; then
    printf '%s\n' "$((now - modified))"
  else
    printf '0\n'
  fi
}

write_lock_owner() {
  local process_start="" boot_id=""
  process_start="$(lock_process_start "$$")"
  boot_id="$(lock_boot_id)"
  [[ -n "$process_start" && -n "$boot_id" ]] || return 1
  printf '%s\n' "$$" > "$LOCK/pid" || return 1
  printf '%s\n' "$LOCK_TOKEN" > "$LOCK/token" || return 1
  printf '%s\n' "$boot_id" > "$LOCK/boot_id" || return 1
  printf '%s\n' "$process_start" > "$LOCK/process_start" || return 1
  # `ready` est publié en dernier : avant lui, le lock est en initialisation.
  : > "$LOCK/ready" || return 1
}

lock_owner_is_alive() {
  local owner_pid="" owner_boot="" owner_start="" current_start=""
  [[ -f "$LOCK/ready" && -r "$LOCK/pid" && -r "$LOCK/boot_id" \
    && -r "$LOCK/process_start" ]] || return 1
  owner_pid=$(tr -d '\n' < "$LOCK/pid")
  owner_boot=$(tr -d '\n' < "$LOCK/boot_id")
  owner_start=$(cat "$LOCK/process_start")
  [[ "$owner_pid" =~ ^[0-9]+$ ]] || return 1
  [[ "$owner_boot" == "$(lock_boot_id)" ]] || return 1
  kill -0 "$owner_pid" 2>/dev/null || return 1
  current_start="$(lock_process_start "$owner_pid")"
  [[ -n "$current_start" && "$current_start" == "$owner_start" ]]
}

acquire_lock() {
  local stale="" age="" grace="${ISO_NORD_LOCK_INIT_GRACE:-30}"
  LOCK_TOKEN="$$-$(date +%s)-$RANDOM"
  if mkdir "$LOCK" 2>/dev/null; then
    if ! write_lock_owner; then
      clean_stale_lock_copy "$LOCK"
      LOCK_TOKEN=""
      return 1
    fi
    return 0
  fi

  if lock_owner_is_alive; then
    return 1
  fi
  if [[ ! -f "$LOCK/ready" ]]; then
    age="$(lock_age_seconds)"
    [[ "$age" =~ ^[0-9]+$ ]] || age=0
    [[ "$grace" =~ ^[0-9]+$ ]] || grace=30
    # Fenêtre mkdir → owner : un second processus ne peut pas voler ce lock.
    [[ "$age" -lt "$grace" ]] && return 1
  fi

  # Déplacer atomiquement le verrou mort avant de tenter de le recréer. Si une
  # autre instance gagne la course, son nouveau verrou n'est jamais supprimé.
  stale="${LOCK}.stale.$$.$RANDOM"
  mv "$LOCK" "$stale" 2>/dev/null || return 1
  if ! mkdir "$LOCK" 2>/dev/null; then
    clean_stale_lock_copy "$stale"
    return 1
  fi
  if ! write_lock_owner; then
    clean_stale_lock_copy "$LOCK"
    clean_stale_lock_copy "$stale"
    LOCK_TOKEN=""
    return 1
  fi
  clean_stale_lock_copy "$stale"
  return 0
}

release_lock() {
  local owner_pid="" owner_token=""
  [[ -n "$LOCK_TOKEN" && -r "$LOCK/pid" && -r "$LOCK/token" ]] || return 0
  owner_pid=$(tr -d '\n' < "$LOCK/pid")
  owner_token=$(tr -d '\n' < "$LOCK/token")
  [[ "$owner_pid" == "$$" && "$owner_token" == "$LOCK_TOKEN" ]] || return 0
  rm -f "$LOCK/pid" "$LOCK/token" "$LOCK/boot_id" \
    "$LOCK/process_start" "$LOCK/ready" 2>/dev/null || return 0
  rmdir "$LOCK" 2>/dev/null || true
}

# ─── État durable d'un fichier ────────────────────────────────────────────────
job_marker_path() {
  printf '%s.iso360-job\n' "$1"
}

ensure_job_marker() {
  local f="$1" marker="" tmp="" job_id=""
  if [[ "$DRY" == "1" ]]; then
    printf 'dry-run\n'
    return 0
  fi
  marker="$(job_marker_path "$f")"
  if [[ -s "$marker" ]]; then
    job_id=$(sed -n '1p' "$marker")
  else
    job_id="$(date +%s)-$$-$RANDOM"
    tmp="$marker.tmp.$$.$RANDOM"
    printf '%s\npush=%s\npublished=0\nphase=claimed\nbase_head=\n' \
      "$job_id" "$PUSH" > "$tmp" || return 1
    mv "$tmp" "$marker" || {
      rm -f "$tmp"
      return 1
    }
  fi
  [[ "$job_id" =~ ^[a-zA-Z0-9._-]+$ ]] || return 1
  printf '%s\n' "$job_id"
}

job_marker_value() {
  local f="$1" key="$2" marker=""
  marker="$(job_marker_path "$f")"
  sed -n "s/^${key}=//p" "$marker" 2>/dev/null | head -1
}

write_job_marker() {
  local f="$1" published="$2" phase="$3" base_head="$4"
  local marker="" tmp="" job_id="" push_mode=""
  marker="$(job_marker_path "$f")"
  job_id=$(sed -n '1p' "$marker" 2>/dev/null)
  push_mode=$(job_marker_value "$f" push)
  [[ "$job_id" =~ ^[a-zA-Z0-9._-]+$ && "$push_mode" =~ ^[01]$ ]] || return 1
  tmp="$marker.tmp.$$.$RANDOM"
  printf '%s\npush=%s\npublished=%s\nphase=%s\nbase_head=%s\n' \
    "$job_id" "$push_mode" "$published" "$phase" "$base_head" > "$tmp" || return 1
  mv "$tmp" "$marker" || {
    rm -f "$tmp"
    return 1
  }
}

mark_job_wiring() {
  local f="$1" base_head=""
  core_require_main_branch "$REPO" || return 1
  base_head="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)" || return 1
  write_job_marker "$f" 0 wiring "$base_head"
}

mark_job_claimed() {
  write_job_marker "$1" 0 claimed ""
}

mark_job_published() {
  local f="$1" base_head=""
  base_head=$(job_marker_value "$f" base_head)
  write_job_marker "$f" 1 published "$base_head"
}

# Retourne 0 si on peut archiver sans republier, 1 si le job est neuf, 2 si un
# ancien job est reconnu mais que son push ne peut pas être prouvé/récupéré.
job_ready_for_archive() {
  local f="$1" job_id="$2" push_mode="" published="" phase="" base_head=""
  local data_rel="" current_head=""
  [[ "$job_id" != "dry-run" ]] || return 1
  push_mode=$(job_marker_value "$f" push)
  published=$(job_marker_value "$f" published)
  phase=$(job_marker_value "$f" phase)
  base_head=$(job_marker_value "$f" base_head)
  [[ "$published" == "1" ]] && return 0
  [[ "$push_mode" =~ ^[01]$ ]] || return 2

  data_rel="${DATA_FILE#$REPO/}"
  if [[ "$push_mode" == "1" ]] \
    && git -C "$REPO" show "origin/main:$data_rel" 2>/dev/null \
    | grep -Fq "ingest-job:$job_id"; then
    return 0
  fi

  # Crash possible entre commit et push : si HEAD contient le job et que le
  # fichier est propre, reprendre uniquement le push explicite de HEAD vers main.
  if git -C "$REPO" diff --quiet -- "$DATA_FILE" \
    && git -C "$REPO" diff --cached --quiet -- "$DATA_FILE" \
    && git -C "$REPO" show "HEAD:$data_rel" 2>/dev/null \
      | grep -Fq "ingest-job:$job_id"; then
    [[ "$push_mode" == "0" ]] && return 0
    if core_require_main_branch "$REPO" \
      && git -C "$REPO" push -q origin HEAD:main; then
      return 0
    fi
    return 2
  fi

  # Crash entre wire/build et commit : le marqueur durable prouve que ce job a
  # commencé à modifier labs360.ts. Tant que HEAD n'a pas bougé, on restaure le
  # fichier suivi puis on rejoue le job; aucun dépôt sale ne bloque la reprise.
  if [[ "$phase" == "wiring" ]] \
    || { [[ -z "$phase" ]] \
      && grep -Fq "ingest-job:$job_id" "$DATA_FILE" 2>/dev/null; }; then
    current_head="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)" || return 2
    if [[ -n "$base_head" && "$current_head" != "$base_head" ]]; then
      return 2
    fi
    git -C "$REPO" reset -q -- "$data_rel" 2>/dev/null || return 2
    git -C "$REPO" checkout -- "$data_rel" 2>/dev/null || return 2
    mark_job_claimed "$f" || return 2
    return 1
  fi
  return 1
}

finalize_published_file() {
  local f="$1" base="" archive_target="" marker=""
  base=$(basename "$f")
  marker="$(job_marker_path "$f")"
  archive_target="$(core_unique_path "$PUBLIES/$base")"
  if ! mv "$f" "$archive_target"; then
    log "PUBLIÉ mais archivage impossible : $base reste dans inbox-processing/"
    return 1
  fi
  rm -f "$marker" 2>/dev/null \
    || log "⚠ marqueur de job orphelin à retirer : $marker"
  log "ARCHIVÉ : $base → $(basename "$archive_target")"
  return 0
}

claim_inbox_file() {
  local source="$1" target="" source_marker="" target_marker=""
  target="$(core_unique_path "$PROCESSING/$(basename "$source")")"
  source_marker="$(job_marker_path "$source")"
  target_marker="$(job_marker_path "$target")"
  mv "$source" "$target" || return 1
  if [[ -f "$source_marker" ]]; then
    if ! mv "$source_marker" "$target_marker"; then
      mv "$target" "$source" 2>/dev/null || true
      return 1
    fi
  fi
  if ! ensure_job_marker "$target" >/dev/null; then
    mv "$target" "$source" 2>/dev/null || true
    rm -f "$target_marker" 2>/dev/null || true
    return 1
  fi
  printf '%s\n' "$target"
}

# ─── Quarantaine ─────────────────────────────────────────────────────────────
quarantine(){  # <fichier> <raison>
  local f="$1" reason="$2" base target note_target
  base=$(basename "$f")
  if [[ "$DRY" == "1" ]]; then
    log "DRY-RUN quarantaine : $base — $reason (rien déplacé)"
    return
  fi
  target="$(core_unique_path "$CORRIGER/$base")"
  if ! mv "$f" "$target"; then
    log "ÉCHEC quarantaine : impossible de déplacer $base"
    return 1
  fi
  rm -f "$(job_marker_path "$f")" 2>/dev/null || true
  note_target="$(core_unique_path "$CORRIGER/${base%.*}.txt")"
  printf '%s\n\nRenomme ce fichier avec le lieu puis redépose-le dans inbox/.\nExemples : chute-montmorency.jpg  (nom, géocodé)  ou  46.89,-71.15.jpg  (coordonnées).\n' \
    "$reason" > "$note_target"
  log "QUARANTAINE : $(basename "$target") — $reason"
}

# ─── Détection du type ───────────────────────────────────────────────────────
detect_type(){  # <fichier> → echo video|360|photo|unknown
  local f="$1" ext; ext=$(echo "${f##*.}" | tr '[:upper:]' '[:lower:]')
  case "$ext" in
    mp4|mov|m4v) echo video; return;;
    jpg|jpeg|png|heic|heif|tif|tiff)
      local w h; w=$(sips -g pixelWidth "$f" 2>/dev/null | awk '/pixelWidth/{print $2}')
      h=$(sips -g pixelHeight "$f" 2>/dev/null | awk '/pixelHeight/{print $2}')
      if [[ -n "$w" && -n "$h" && "$h" -gt 0 ]] && awk "BEGIN{exit !($w/$h>1.8 && $w/$h<2.2)}"; then
        echo 360
      else
        echo photo
      fi;;
    *) echo unknown;;
  esac
}

# ─── Traitement d'UN fichier ─────────────────────────────────────────────────
process(){
  local f="$1" base ptype lat="" lon="" dt="" stem coords="" name_ovr=""
  local geo="" geo_error="" gname="" gid="" gym="" gcity=""
  local work="" destdir="" filename="" ext="" poster_url="" poster_local=""
  local outfile="" poster_file="" media_url="" snapshot="" job_id="" job_state=""
  local preview_source="" preview_file="" preview_path="" preview_dims="" preview_width="" preview_height=""
  base=$(basename "$f")
  if ! job_id="$(ensure_job_marker "$f")"; then
    log "ÉCHEC : impossible de créer/lire le marqueur durable pour $base"
    return 1
  fi
  job_ready_for_archive "$f" "$job_id"
  job_state=$?
  if [[ "$job_state" == "0" ]]; then
    mark_job_published "$f" 2>/dev/null || true
    log "REPRISE : job $job_id déjà publié; archivage seulement pour $base"
    finalize_published_file "$f"
    return $?
  elif [[ "$job_state" == "2" ]]; then
    log "ÉCHEC reprise : job $job_id reconnu, mais push non prouvé; aucune republication"
    return 1
  fi
  if [[ "$DRY" == "0" ]] && ! core_require_main_branch "$REPO"; then
    log "ÉCHEC : publication permise uniquement depuis la branche main"
    return 1
  fi
  ptype=$(detect_type "$f")
  [[ "$ptype" == "unknown" ]] && {
    quarantine "$f" "Type non reconnu (extension inattendue)."
    return $?
  }
  log "Traitement : $base (type=$ptype)"

  # GPS + date via exiftool
  IFS='|' read -r lat lon dt < <(core_extract_meta "$f")

  # Repli : nom de fichier (coordonnées ou lieu à géocoder)
  if [[ -z "$lat" || -z "$lon" ]]; then
    stem="${base%.*}"
    if [[ "$stem" =~ ^(-?[0-9]+\.[0-9]+),(-?[0-9]+\.[0-9]+)$ ]]; then
      lat="${BASH_REMATCH[1]}"; lon="${BASH_REMATCH[2]}"
      log "GPS depuis le nom de fichier : $lat,$lon"
    else
      if coords=$(core_forward_geocode "$stem" 2>&1); then
        read -r lat lon <<< "$coords"
        if [[ -n "$lat" && -n "$lon" ]]; then
          name_ovr="${stem//-/ }"
        fi
        log "Lieu géocodé depuis le nom : $stem → $lat,$lon"
      else
        quarantine "$f" "Géocodage Nominatim impossible : $coords"
        return $?
      fi
    fi
  fi
  if [[ -z "$lat" || -z "$lon" ]]; then
    quarantine "$f" "GPS introuvable (ni dans les métadonnées, ni via le nom de fichier)."
    return $?
  fi

  # Le reverse-geocode doit réussir : aucun nom ou pin de repli n'est inventé.
  geo_error="$(mktemp "${TMPDIR:-/tmp}/iso-ingest-geocode.XXXXXX")"
  if ! geo=$(LAT="$lat" LON="$lon" DT="$dt" NAME_OVR="$name_ovr" \
      core_geocode 2>"$geo_error"); then
    coords=$(tr '\n' ' ' < "$geo_error")
    rm -f "$geo_error"
    quarantine "$f" "Géocodage inverse Nominatim impossible : ${coords:-erreur inconnue}"
    return $?
  fi
  rm -f "$geo_error"

  gname=$(printf '%s' "$geo" | python3 -c 'import json,sys;print(json.load(sys.stdin)["name"])') || return 1
  gid=$(printf '%s' "$geo" | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])') || return 1
  gym=$(printf '%s' "$geo" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("ym") or "")') || return 1
  gcity=$(printf '%s' "$geo" | python3 -c 'import json,sys;print(json.load(sys.stdin)["city"])') || return 1
  if ! core_require_quebec "$gcity"; then
    quarantine "$f" "Labs 360 publie Québec seulement; destination refusée."
    return $?
  fi
  [[ -n "$gym" ]] || gym=$(date +%Y-%m)
  gid="$(core_unique_place_id "$DATA_FILE" "$gid")" || return 1
  geo="$(core_set_geo_id "$geo" "$gid")" || return 1

  # Préparer le média + choisir dossier/sous-domaine + poster éventuel
  work="$(mktemp -d "${TMPDIR:-/tmp}/iso-ingest.XXXXXX")"
  case "$ptype" in
    360)
      destdir="$MEDIA_ROOT/panoramas"; filename="${gid}-${gym}.jpg"
      sips -s format jpeg -s formatOptions 88 "$f" --out "$work/out.jpg" >/dev/null 2>&1;;
    photo)
      destdir="$MEDIA_ROOT/photos"; filename="${gid}-${gym}.jpg"
      sips -s format jpeg -s formatOptions 88 -Z 2560 "$f" --out "$work/out.jpg" >/dev/null 2>&1;;
    video)
      ext=$(echo "${f##*.}" | tr '[:upper:]' '[:lower:]')
      destdir="$MEDIA_ROOT/videos"; filename="${gid}-${gym}.${ext}"
      cp "$f" "$work/out.${ext}" 2>/dev/null
      # Poster = frame à ~1 s
      if ffmpeg -y -ss 1 -i "$f" -frames:v 1 -q:v 3 "$work/poster.jpg" >/dev/null 2>&1 \
         && [[ -s "$work/poster.jpg" ]]; then
        poster_local="$work/poster.jpg"
      else
        rm -rf "$work"
        quarantine "$f" "Génération du poster vidéo échouée (ffmpeg)."
        return $?
      fi;;
  esac

  outfile=$(find "$work" -maxdepth 1 -type f -name 'out.*' -print | head -1)
  if [[ -z "$outfile" || ! -s "$outfile" ]]; then
    rm -rf "$work"
    quarantine "$f" "Préparation du média échouée (fichier illisible ?)."
    return $?
  fi
  filename="$(core_unique_filename "$destdir" "$filename")" || {
    rm -rf "$work"
    return 1
  }

  if [[ "$DRY" == "1" ]]; then
    log "DRY-RUN : $base → type=$ptype lieu=«${gname}» ($gcity) fichier=$filename lat=$lat lon=$lon poster=$([[ -n "$poster_local" ]] && echo oui || echo non)"
    rm -rf "$work"; return
  fi

  if ! core_file_is_clean "$REPO" "$DATA_FILE"; then
    rm -rf "$work"
    log "ÉCHEC : labs360.ts contient déjà des changements; $base laissé dans inbox/"
    return 1
  fi

  preview_source="$outfile"
  [[ -n "$poster_local" ]] && preview_source="$poster_local"
  preview_file="${gid}-${gym}.webp"
  preview_path="$PREVIEW_DIR/$preview_file"
  mkdir -p "$PREVIEW_DIR" || {
    rm -rf "$work"
    log "ÉCHEC : dossier des aperçus inaccessible"
    return 1
  }
  if ! preview_dims="$(core_make_preview "$preview_source" "$preview_path")"; then
    rm -rf "$work"
    log "ÉCHEC : aperçu WebP impossible; $base laissé dans inbox/"
    return 1
  fi
  IFS='|' read -r preview_width preview_height <<< "$preview_dims"

  # Publier le média (+ poster vidéo)
  cd "$REPO"
  if ! core_publish_verify "$outfile" "$destdir" "$MEDIA_BASE_URL/$(basename "$destdir")" "$filename"; then
    rm -f "$preview_path"
    rm -rf "$work"
    log "ÉCHEC publication : $base laissé dans inbox/ (tunnel/Caddy ?)"
    return 1
  fi
  if [[ -n "$poster_local" ]]; then
    poster_file="$(core_unique_filename "$MEDIA_ROOT/photos" "${gid}-${gym}-poster.jpg")"
    if core_publish_verify "$poster_local" "$MEDIA_ROOT/photos" "$MEDIA_BASE_URL/photos" "$poster_file"; then
      poster_url="$MEDIA_BASE_URL/photos/$poster_file"
    else
      rm -f "$preview_path"
      rm -rf "$work"
      log "ÉCHEC publication poster : $base laissé dans inbox/"
      return 1
    fi
  fi
  rm -rf "$work"

  # Câbler labs360.ts
  snapshot="$(mktemp "${TMPDIR:-/tmp}/iso-ingest-data.XXXXXX")"
  cp "$DATA_FILE" "$snapshot" || {
    rm -f "$preview_path"
    rm -f "$snapshot"
    log "ÉCHEC sauvegarde de labs360.ts : $base laissé dans inbox/"
    return 1
  }
  if ! mark_job_wiring "$f"; then
    rm -f "$preview_path"
    rm -f "$snapshot"
    log "ÉCHEC état de reprise : $base laissé dans inbox-processing/"
    return 1
  fi
  media_url="$MEDIA_BASE_URL/$(basename "$destdir")/$filename"
  if ! GEO_JSON="$geo" MEDIA_URL="$media_url" PTYPE="$ptype" POSTER_URL="$poster_url" \
       PREVIEW_URL="/assets/labs360/previews/$preview_file" \
       PREVIEW_WIDTH="$preview_width" PREVIEW_HEIGHT="$preview_height" CAPTURED_AT="$gym" \
       REPLACE="" WIRE_NOTE="Auto-publié par iso-ingest; ingest-job:$job_id" \
       DATA="$DATA_FILE" core_wire; then
    cp "$snapshot" "$DATA_FILE"
    rm -f "$preview_path"
    rm -f "$snapshot"
    log "ÉCHEC câblage : $base (marqueur iso360:insert absent ?)"
    return 1
  fi

  # Build garde-fou
  if ! core_build_guard "$DATA_FILE" "$snapshot"; then
    rm -f "$preview_path"
    rm -f "$snapshot"
    log "ÉCHEC build : labs360.ts restauré, $base laissé dans inbox/"
    return 1
  fi

  # Commit + push
  if ! core_commit_push "$DATA_FILE" "add" "$gname" "$PUSH" "$LIVE_PAGE" "$filename" "$gcity" "$preview_path"; then
    git -C "$REPO" reset -q -- "$DATA_FILE" "$preview_path" 2>/dev/null || true
    cp "$snapshot" "$DATA_FILE"
    rm -f "$preview_path"
    rm -f "$snapshot"
    log "ÉCHEC commit/push : labs360.ts restauré, $base laissé dans inbox/"
    return 1
  fi
  if ! mark_job_published "$f"; then
    rm -f "$snapshot"
    log "PUBLIÉ mais état du job impossible à confirmer : $base reste dans inbox-processing/"
    return 1
  fi
  rm -f "$snapshot"

  # Archiver seulement après add + commit (+ push si demandé) réussis. Si le
  # déplacement rate, le job ID dans labs360.ts rend le prochain essai idempotent.
  finalize_published_file "$f" || return 1
  log "PUBLIÉ : $base → pin «$gname» ($media_url)"
  return 0
}

# ─── Boucle : chaque fichier de premier niveau de inbox/ ─────────────────────
main() {
  local found=0 failed=0 f="" b="" s1="" s2="" claimed=""
  [[ -d "$MEDIA_ROOT" ]] || {
    printf 'SSD non monté : %s\n' "$MEDIA_ROOT" >&2
    return 0
  }

  if [[ "$DRY" == "1" ]]; then
    # Lecture seule : pas de mkdir, lock, log persistant, pull, média ou repo.
    [[ -d "$INBOX" ]] || {
      printf 'Inbox absente : %s\n' "$INBOX" >&2
      return 0
    }
  else
    mkdir -p "$INBOX" "$CORRIGER" "$PUBLIES" "$PROCESSING" \
      "$MEDIA_ROOT/panoramas" "$MEDIA_ROOT/videos" "$MEDIA_ROOT/photos" || return 1
    if ! acquire_lock; then
      log "Déjà en cours (verrou actif) — sortie."
      return 0
    fi
    trap release_lock EXIT
    trap 'release_lock; exit 130' HUP INT TERM

    # Une branche différente pourrait pousser le mauvais contenu sur main.
    if ! core_require_main_branch "$REPO"; then
      log "ÉCHEC : branche main requise; aucun fichier traité."
      return 1
    fi
    # Un pull raté rendrait le push non fiable : ne publier aucun média dans ce cas.
    if ! git -C "$REPO" pull --ff-only origin main >/dev/null 2>&1; then
      log "ÉCHEC git pull --ff-only : aucun fichier traité."
      return 1
    fi
  fi

  shopt -s nullglob
  if [[ "$DRY" == "0" ]]; then
    # Reprendre d'abord les fichiers déjà réclamés. Un job présent dans
    # labs360.ts saute directement à l'archive, sans republier.
    for f in "$PROCESSING"/*; do
      [[ -f "$f" ]] || continue
      [[ "$f" == *.iso360-job || "$f" == *.iso360-job.tmp.* ]] && continue
      found=1
      process "$f" || failed=1
    done
    # Un marqueur sans fichier ne sert plus à rien (mv archive déjà réussi).
    for f in "$PROCESSING"/*.iso360-job; do
      [[ -f "$f" ]] || continue
      [[ -f "${f%.iso360-job}" ]] || rm -f "$f"
    done
  fi

  for f in "$INBOX"/*; do
    [[ -f "$f" ]] || continue
    b=$(basename "$f")
    [[ "$b" == .* || "$b" == *.iso360-job ]] && continue
    # Débounce : taille stable = copie réseau terminée
    s1=$(stat -f%z "$f" 2>/dev/null || echo 0)
    sleep 2
    s2=$(stat -f%z "$f" 2>/dev/null || echo 0)
    [[ "$s1" == "$s2" && "$s1" != "0" ]] || {
      log "En cours de copie, ignoré ce tour : $b"
      continue
    }
    found=1
    if [[ "$DRY" == "1" ]]; then
      process "$f" || failed=1
    else
      claimed="$(claim_inbox_file "$f")" || {
        log "ÉCHEC : impossible de réclamer $b vers inbox-processing/"
        failed=1
        continue
      }
      process "$claimed" || failed=1
    fi
  done
  [[ "$found" == "0" ]] && log "Aucun fichier à traiter."
  return "$failed"
}

if [[ "${ISO_NORD_INGEST_SOURCE_ONLY:-0}" != "1" ]]; then
  main "$@"
  exit $?
fi
