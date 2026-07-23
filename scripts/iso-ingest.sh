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
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1;;
    --no-push) PUSH=0;;
    *) echo "Option inconnue : $a" >&2; exit 2;;
  esac
done

source "$SCRIPT_DIR/iso360-core.sh"

log(){ printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOGFILE" >&2; }

# ─── Verrou (traitement séquentiel) ──────────────────────────────────────────
[[ -d "$MEDIA_ROOT" ]] || { echo "SSD non monté : $MEDIA_ROOT" >&2; exit 0; }
mkdir -p "$INBOX" "$CORRIGER" "$PUBLIES" "$MEDIA_ROOT/panoramas" "$MEDIA_ROOT/videos" "$MEDIA_ROOT/photos"
if ! mkdir "$LOCK" 2>/dev/null; then
  log "Déjà en cours (lock présent) — sortie."
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# Garder le clone à jour avec origin/main (best-effort, pour pouvoir pousser).
# Pas en dry-run : un dry-run ne touche à rien, ni médias ni repo.
if [[ "$DRY" == "0" ]]; then
  git -C "$REPO" pull --ff-only origin main >/dev/null 2>&1 \
    || log "⚠ git pull --ff-only a échoué (clone divergé ?) — le push pourrait rater."
fi

# ─── Quarantaine ─────────────────────────────────────────────────────────────
quarantine(){  # <fichier> <raison>
  local f="$1" reason="$2" base; base=$(basename "$f")
  if [[ "$DRY" == "1" ]]; then
    log "DRY-RUN quarantaine : $base — $reason (rien déplacé)"
    return
  fi
  mv "$f" "$CORRIGER/$base" 2>/dev/null
  printf '%s\n\nRenomme ce fichier avec le lieu puis redépose-le dans inbox/.\nExemples : chute-montmorency.jpg  (nom, géocodé)  ou  46.89,-71.15.jpg  (coordonnées).\n' \
    "$reason" > "$CORRIGER/${base%.*}.txt"
  log "QUARANTAINE : $base — $reason"
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
  local f="$1" base; base=$(basename "$f")
  local ptype; ptype=$(detect_type "$f")
  [[ "$ptype" == "unknown" ]] && { quarantine "$f" "Type non reconnu (extension inattendue)."; return; }
  log "Traitement : $base (type=$ptype)"

  # GPS + date via exiftool
  local lat lon dt; read -r lat lon dt < <(core_extract_meta "$f")

  # Repli : nom de fichier (coordonnées ou lieu à géocoder)
  local name_ovr=""
  if [[ -z "$lat" || -z "$lon" ]]; then
    local stem="${base%.*}"
    if [[ "$stem" =~ ^(-?[0-9]+\.[0-9]+),(-?[0-9]+\.[0-9]+)$ ]]; then
      lat="${BASH_REMATCH[1]}"; lon="${BASH_REMATCH[2]}"
      log "GPS depuis le nom de fichier : $lat,$lon"
    else
      local flat flon; read -r flat flon < <(core_forward_geocode "$stem")
      if [[ -n "${flat:-}" && -n "${flon:-}" ]]; then
        lat="$flat"; lon="$flon"; name_ovr="${stem//-/ }"
        log "Lieu géocodé depuis le nom : $stem → $lat,$lon"
      fi
    fi
  fi
  if [[ -z "$lat" || -z "$lon" ]]; then
    quarantine "$f" "GPS introuvable (ni dans les métadonnées, ni via le nom de fichier)."
    return
  fi

  # Géolocalisation (nom + ville + id + ym)
  local geo; geo=$(LAT="$lat" LON="$lon" DT="$dt" NAME_OVR="$name_ovr" core_geocode)
  local gname gid gym gcity
  gname=$(echo "$geo" | python3 -c 'import json,sys;print(json.load(sys.stdin)["name"])')
  gid=$(echo   "$geo" | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
  gym=$(echo   "$geo" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("ym") or "")')
  gcity=$(echo "$geo" | python3 -c 'import json,sys;print(json.load(sys.stdin)["city"])')
  [[ -n "$gym" ]] || gym=$(date +%Y-%m)

  # Préparer le média + choisir dossier/sous-domaine + poster éventuel
  local work destdir filename ext poster_url="" poster_local=""
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
      cp "$f" "$work/out.${ext}"
      # Poster = frame à ~1 s
      if ffmpeg -y -ss 1 -i "$f" -frames:v 1 -q:v 3 "$work/poster.jpg" >/dev/null 2>&1 \
         && [[ -s "$work/poster.jpg" ]]; then
        poster_local="$work/poster.jpg"
      fi;;
  esac

  local outfile; outfile=$(ls "$work"/out.* 2>/dev/null | head -1)
  if [[ -z "$outfile" || ! -s "$outfile" ]]; then
    rm -rf "$work"; quarantine "$f" "Préparation du média échouée (fichier illisible ?)."; return
  fi

  if [[ "$DRY" == "1" ]]; then
    log "DRY-RUN : $base → type=$ptype lieu=«$gname» ($gcity) fichier=$filename lat=$lat lon=$lon poster=$([[ -n "$poster_local" ]] && echo oui || echo non)"
    rm -rf "$work"; return
  fi

  # Publier le média (+ poster vidéo)
  cd "$REPO"
  if ! core_publish_verify "$outfile" "$destdir" "$MEDIA_BASE_URL/$(basename "$destdir")" "$filename"; then
    rm -rf "$work"; log "ÉCHEC publication : $base laissé dans inbox/ (tunnel/Caddy ?)"; return
  fi
  if [[ -n "$poster_local" ]]; then
    local poster_file="${gid}-${gym}-poster.jpg"
    if core_publish_verify "$poster_local" "$MEDIA_ROOT/photos" "$MEDIA_BASE_URL/photos" "$poster_file"; then
      poster_url="$MEDIA_BASE_URL/photos/$poster_file"
    fi
  fi
  rm -rf "$work"

  # Câbler labs360.ts
  local media_url="$MEDIA_BASE_URL/$(basename "$destdir")/$filename"
  if ! GEO_JSON="$geo" MEDIA_URL="$media_url" PTYPE="$ptype" POSTER_URL="$poster_url" \
       REPLACE="" WIRE_NOTE="Auto-publié par iso-ingest" DATA="$DATA_FILE" core_wire; then
    log "ÉCHEC câblage : $base (marqueur iso360:insert absent ?)"; return
  fi

  # Build garde-fou
  if ! core_build_guard "$DATA_FILE"; then
    log "ÉCHEC build : labs360.ts restauré, $base laissé dans inbox/"; return
  fi

  # Commit + push
  core_commit_push "$DATA_FILE" "add" "$gname" "$PUSH" "$LIVE_PAGE" "$filename"

  # Archiver l'original
  mv "$f" "$PUBLIES/$base" 2>/dev/null
  log "PUBLIÉ : $base → pin «$gname» ($media_url)"
}

# ─── Boucle : chaque fichier de premier niveau de inbox/ ─────────────────────
shopt -s nullglob
found=0
for f in "$INBOX"/*; do
  [[ -f "$f" ]] || continue
  b=$(basename "$f")
  [[ "$b" == .* ]] && continue
  # Débounce : taille stable = copie réseau terminée
  s1=$(stat -f%z "$f" 2>/dev/null || echo 0); sleep 2
  s2=$(stat -f%z "$f" 2>/dev/null || echo 0)
  [[ "$s1" == "$s2" && "$s1" != "0" ]] || { log "En cours de copie, ignoré ce tour : $b"; continue; }
  found=1
  process "$f"
done
[[ "$found" == "0" ]] && log "Aucun fichier à traiter."
exit 0
