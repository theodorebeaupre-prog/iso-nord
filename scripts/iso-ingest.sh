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
LOGFILE="$MEDIA_ROOT/inbox.log"
LOCK="$MEDIA_ROOT/inbox.lock"

export MEDIA_BASE_URL="https://media.theo-picture.com"   # utilisé par core_commit_push
LIVE_PAGE="https://theo-picture.com/labs/360"
DATA_FILE="$REPO/src/data/labs360.ts"

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
  rm -f "$stale/owner" 2>/dev/null || true
  rmdir "$stale" 2>/dev/null || true
}

acquire_lock() {
  local owner_pid="" owner_token="" stale=""
  LOCK_TOKEN="$$-$(date +%s)-$RANDOM"
  if mkdir "$LOCK" 2>/dev/null; then
    printf '%s %s\n' "$$" "$LOCK_TOKEN" > "$LOCK/owner"
    return 0
  fi

  if [[ -r "$LOCK/owner" ]]; then
    read -r owner_pid owner_token < "$LOCK/owner" || true
  fi
  if [[ "$owner_pid" =~ ^[0-9]+$ ]] && kill -0 "$owner_pid" 2>/dev/null; then
    return 1
  fi

  # Déplacer atomiquement le verrou mort avant de tenter de le recréer. Si une
  # autre instance gagne la course, son nouveau verrou n'est jamais supprimé.
  stale="${LOCK}.stale.$$.$RANDOM"
  mv "$LOCK" "$stale" 2>/dev/null || return 1
  if ! mkdir "$LOCK" 2>/dev/null; then
    clean_stale_lock_copy "$stale"
    return 1
  fi
  printf '%s %s\n' "$$" "$LOCK_TOKEN" > "$LOCK/owner"
  clean_stale_lock_copy "$stale"
  return 0
}

release_lock() {
  local owner_pid="" owner_token=""
  [[ -n "$LOCK_TOKEN" && -r "$LOCK/owner" ]] || return 0
  read -r owner_pid owner_token < "$LOCK/owner" || return 0
  [[ "$owner_pid" == "$$" && "$owner_token" == "$LOCK_TOKEN" ]] || return 0
  rm -f "$LOCK/owner" 2>/dev/null || return 0
  rmdir "$LOCK" 2>/dev/null || true
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
  local outfile="" poster_file="" media_url="" snapshot="" archive_target=""
  base=$(basename "$f")
  ptype=$(detect_type "$f")
  [[ "$ptype" == "unknown" ]] && {
    quarantine "$f" "Type non reconnu (extension inattendue)."
    return $?
  }
  log "Traitement : $base (type=$ptype)"

  # GPS + date via exiftool
  read -r lat lon dt < <(core_extract_meta "$f")

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
    log "DRY-RUN : $base → type=$ptype lieu=«$gname» ($gcity) fichier=$filename lat=$lat lon=$lon poster=$([[ -n "$poster_local" ]] && echo oui || echo non)"
    rm -rf "$work"; return
  fi

  if ! core_file_is_clean "$REPO" "$DATA_FILE"; then
    rm -rf "$work"
    log "ÉCHEC : labs360.ts contient déjà des changements; $base laissé dans inbox/"
    return 1
  fi

  # Publier le média (+ poster vidéo)
  cd "$REPO"
  if ! core_publish_verify "$outfile" "$destdir" "$MEDIA_BASE_URL/$(basename "$destdir")" "$filename"; then
    rm -rf "$work"
    log "ÉCHEC publication : $base laissé dans inbox/ (tunnel/Caddy ?)"
    return 1
  fi
  if [[ -n "$poster_local" ]]; then
    poster_file="$(core_unique_filename "$MEDIA_ROOT/photos" "${gid}-${gym}-poster.jpg")"
    if core_publish_verify "$poster_local" "$MEDIA_ROOT/photos" "$MEDIA_BASE_URL/photos" "$poster_file"; then
      poster_url="$MEDIA_BASE_URL/photos/$poster_file"
    else
      rm -rf "$work"
      log "ÉCHEC publication poster : $base laissé dans inbox/"
      return 1
    fi
  fi
  rm -rf "$work"

  # Câbler labs360.ts
  snapshot="$(mktemp "${TMPDIR:-/tmp}/iso-ingest-data.XXXXXX")"
  cp "$DATA_FILE" "$snapshot" || {
    rm -f "$snapshot"
    log "ÉCHEC sauvegarde de labs360.ts : $base laissé dans inbox/"
    return 1
  }
  media_url="$MEDIA_BASE_URL/$(basename "$destdir")/$filename"
  if ! GEO_JSON="$geo" MEDIA_URL="$media_url" PTYPE="$ptype" POSTER_URL="$poster_url" \
       REPLACE="" WIRE_NOTE="Auto-publié par iso-ingest" DATA="$DATA_FILE" core_wire; then
    cp "$snapshot" "$DATA_FILE"
    rm -f "$snapshot"
    log "ÉCHEC câblage : $base (marqueur iso360:insert absent ?)"
    return 1
  fi

  # Build garde-fou
  if ! core_build_guard "$DATA_FILE" "$snapshot"; then
    rm -f "$snapshot"
    log "ÉCHEC build : labs360.ts restauré, $base laissé dans inbox/"
    return 1
  fi

  # Commit + push
  if ! core_commit_push "$DATA_FILE" "add" "$gname" "$PUSH" "$LIVE_PAGE" "$filename"; then
    git -C "$REPO" reset -q -- "$DATA_FILE" 2>/dev/null || true
    cp "$snapshot" "$DATA_FILE"
    rm -f "$snapshot"
    log "ÉCHEC commit/push : labs360.ts restauré, $base laissé dans inbox/"
    return 1
  fi
  rm -f "$snapshot"

  # Archiver seulement après add + commit (+ push si demandé) réussis.
  archive_target="$(core_unique_path "$PUBLIES/$base")"
  if ! mv "$f" "$archive_target"; then
    log "PUBLIÉ mais archivage impossible : $base reste dans inbox/"
    return 1
  fi
  log "PUBLIÉ : $base → pin «$gname» ($media_url)"
  return 0
}

# ─── Boucle : chaque fichier de premier niveau de inbox/ ─────────────────────
main() {
  local found=0 failed=0 f="" b="" s1="" s2=""
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
    mkdir -p "$INBOX" "$CORRIGER" "$PUBLIES" \
      "$MEDIA_ROOT/panoramas" "$MEDIA_ROOT/videos" "$MEDIA_ROOT/photos" || return 1
    if ! acquire_lock; then
      log "Déjà en cours (verrou actif) — sortie."
      return 0
    fi
    trap release_lock EXIT
    trap 'release_lock; exit 130' HUP INT TERM

    # Un pull raté rendrait le push non fiable : ne publier aucun média dans ce cas.
    if ! git -C "$REPO" pull --ff-only origin main >/dev/null 2>&1; then
      log "ÉCHEC git pull --ff-only : aucun fichier traité."
      return 1
    fi
  fi

  shopt -s nullglob
  for f in "$INBOX"/*; do
    [[ -f "$f" ]] || continue
    b=$(basename "$f")
    [[ "$b" == .* ]] && continue
    # Débounce : taille stable = copie réseau terminée
    s1=$(stat -f%z "$f" 2>/dev/null || echo 0)
    sleep 2
    s2=$(stat -f%z "$f" 2>/dev/null || echo 0)
    [[ "$s1" == "$s2" && "$s1" != "0" ]] || {
      log "En cours de copie, ignoré ce tour : $b"
      continue
    }
    found=1
    process "$f" || failed=1
  done
  [[ "$found" == "0" ]] && log "Aucun fichier à traiter."
  return "$failed"
}

if [[ "${ISO_NORD_INGEST_SOURCE_ONLY:-0}" != "1" ]]; then
  main "$@"
  exit $?
fi
