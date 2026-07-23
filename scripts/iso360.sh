#!/usr/bin/env bash
#
# iso360 — du drone au site en ligne, en une commande.
#
# Prend un dossier de session PANORAMA DJI (les 35 segments PANO_*.JPG), et :
#   1. assemble le panorama équirectangulaire (Hugin)
#   2. le convertit en JPG 2:1
#   3. lit le GPS EXIF et géolocalise le lieu (Nominatim / OpenStreetMap)
#   4. le publie sur /Volumes/SSD 1/iso-nord-media/panoramas (servi par le tunnel)
#   5. vérifie que l'URL publique répond
#   6. câble le lieu dans src/data/labs360.ts (insertion ou remplacement)
#   7. build (GARDE-FOU : si le TS est cassé, on annule avant de pousser)
#   8. commit + push → déploiement Vercel automatique
#
# Usage :
#   iso360 <dossier-session | pano.jpg> [options]
#
# Deux entrées possibles :
#   • un DOSSIER de segments DJI (PANO_*.JPG) → assemblage Hugin
#   • un FICHIER déjà équirectangulaire (ex. export DJI Fly) → pas d'assemblage
#
# Options :
#   --name "Nom du lieu"    Force le nom (sinon déduit du géocodage)
#   --city quebec|montreal  Force la ville (sinon déduite du GPS)
#   --id slug               Force l'id/slug du lieu
#   --lat <deg> --lon <deg> Force les coordonnées (si l'export a perdu le GPS EXIF)
#   --replace <id>          Met à jour le média d'un lieu EXISTANT au lieu d'en créer un
#   --no-push               Fait tout sauf le git push (commit local seulement)
#   --dry-run               Prépare + géolocalise sans publier; écrit seulement un aperçu sur le Bureau
#
# Exemples :
#   iso360 "/Volumes/SD_Card/DCIM/PANORAMA/001_0190"
#   iso360 ~/Downloads/pano-hiver.jpg --replace maizerets
#   iso360 ~/Downloads/pano.jpg --name "Terrasse Dufferin" --city quebec --lat 46.81 --lon -71.20

set -euo pipefail

# ─── Racine du repo (résolue depuis l'emplacement réel du script) ────────────
# iso360 est souvent lancé via un symlink /usr/local/bin → on suit la chaîne de
# symlinks pour retrouver scripts/iso360.sh, puis on remonte à la racine du repo.
_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"; _src="$(readlink "$_src")"
  [[ "$_src" != /* ]] && _src="$_dir/$_src"
done
SCRIPT_DIR="$(cd -P "$(dirname "$_src")" && pwd)"

# ─── Configuration (adapter ici si l'infra bouge) ────────────────────────────
REPO="${ISO_NORD_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
MEDIA_DIR="/Volumes/SSD 1/iso-nord-media/panoramas"
export MEDIA_BASE_URL="https://media.theo-picture.com/panoramas"  # exporté pour core_commit_push
LIVE_PAGE="https://theo-picture.com/labs/360"
DATA_FILE="$REPO/src/data/labs360.ts"
HUGIN="/Applications/Hugin/tools_mac"
CANVAS="6300x3150"           # taille du panorama de sortie (2:1)
SEG_WIDTH=2016               # downscale des segments avant cpfind (vitesse)

# ─── Cœur partagé (géoloc, publie, câble, build, push) ───────────────────────
source "$SCRIPT_DIR/iso360-core.sh"

# ─── Couleurs / log ──────────────────────────────────────────────────────────
b(){ printf '\033[1m%s\033[0m\n' "$*"; }        # gras
ok(){ printf '\033[32m✓\033[0m %s\n' "$*"; }
info(){ printf '\033[36m•\033[0m %s\n' "$*"; }
die(){ printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ─── Arguments ───────────────────────────────────────────────────────────────
SESSION="" NAME="" CITY="" ID="" REPLACE="" PUSH=1 DRY=0 LAT="" LON=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)    NAME="$2"; shift 2;;
    --city)    CITY="$2"; shift 2;;
    --id)      ID="$2"; shift 2;;
    --lat)     LAT="$2"; shift 2;;
    --lon)     LON="$2"; shift 2;;
    --replace) REPLACE="$2"; shift 2;;
    --no-push) PUSH=0; shift;;
    --dry-run) DRY=1; shift;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    -*)        die "Option inconnue : $1";;
    *)         SESSION="$1"; shift;;
  esac
done

[[ -n "$SESSION" ]] || die "Usage : iso360 <dossier-session | pano.jpg> [options]  (voir --help)"

# Deux modes : dossier de segments (stitch Hugin) OU pano déjà stitché (fichier).
FILE_MODE=0
if [[ -f "$SESSION" ]]; then
  FILE_MODE=1
  b "iso360 — pano déjà assemblé : $(basename "$SESSION")"
elif [[ -d "$SESSION" ]]; then
  [[ -x "$HUGIN/pto_gen" ]] || die "Hugin introuvable dans $HUGIN (brew install --cask hugin)"
  count=$(find "$SESSION" -maxdepth 1 -iname 'PANO_*.JPG' ! -name '._*' | wc -l | tr -d ' ')
  [[ "$count" -ge 4 ]] || die "Trop peu de segments PANO_*.JPG ($count) dans $SESSION"
  export PATH="$HUGIN:$PATH"
  b "iso360 — $count segments dans $(basename "$SESSION")"
else
  die "Introuvable : $SESSION"
fi

# ─── 1-2. Espace de travail + obtention du panorama (pano.jpg) ───────────────
WORK="$(mktemp -d "${TMPDIR:-/tmp}/iso360.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

if [[ "$FILE_MODE" == "1" ]]; then
  # Pano déjà équirectangulaire (ex. export DJI Fly) → on l'utilise tel quel.
  info "Préparation du pano fourni…"
  sips -s format jpeg -s formatOptions 88 "$SESSION" --out pano.jpg >/dev/null 2>&1 || die "Image illisible : $SESSION"
  rw=$(sips -g pixelWidth pano.jpg 2>/dev/null | awk '/pixelWidth/{print $2}')
  rh=$(sips -g pixelHeight pano.jpg 2>/dev/null | awk '/pixelHeight/{print $2}')
  opt_err="n/a"
  ok "Pano prêt (${rw}x${rh}, $(du -h pano.jpg | cut -f1))"
  awk "BEGIN{exit !($rw/$rh>1.8 && $rw/$rh<2.2)}" || info "⚠ ratio ${rw}x${rh} loin du 2:1 — vérifie que c'est bien un équirectangulaire."
else
  info "Downscale des segments à ${SEG_WIDTH}px…"
  i=0
  for f in "$SESSION"/PANO_*.JPG "$SESSION"/PANO_*.jpg; do
    [[ -e "$f" ]] || continue
    [[ "$(basename "$f")" == ._* ]] && continue
    sips --resampleWidth "$SEG_WIDTH" "$f" --out "$WORK/$(printf 'seg%03d.jpg' "$i")" >/dev/null 2>&1
    i=$((i+1))
  done
  ok "$i segments préparés"

  info "Détection des points de contrôle (cpfind — l'étape longue, ~2-4 min)…"
  pto_gen -o p.pto seg*.jpg >/dev/null 2>&1
  cpfind --multirow --celeste -o p.pto p.pto >/dev/null 2>&1
  cpclean -o p.pto p.pto >/dev/null 2>&1
  info "Optimisation géométrique…"
  opt_err=$(autooptimiser -a -m -l -s -o p.pto p.pto 2>&1 | grep -Eo 'error: [0-9.]+' | tail -1 | grep -Eo '[0-9.]+' || echo "?")
  pano_modify --projection=2 --fov=360x180 --canvas="$CANVAS" -o p.pto p.pto >/dev/null 2>&1
  info "Rendu + fusion (nona + enblend)…"
  # `|| true` : ne pas laisser set -e couper ici — on juge le résultat via la
  # taille du TIFF ci-dessous (message d'échec propre plutôt qu'exit opaque).
  nona -m TIFF_m -o s_ p.pto >/dev/null 2>&1 || true
  enblend -o pano.tif s_*.tif >/dev/null 2>&1 || true

  # Garde-fou stitch : panos d'hiver / recouvrement faible → TIFF absent ou minuscule.
  tif_size=$(stat -f%z pano.tif 2>/dev/null || echo 0)
  [[ "$tif_size" -gt 100000 ]] || die "Stitch échoué (TIFF ${tif_size} o, erreur opt=${opt_err}). Souvent la neige ou trop peu de recouvrement : trop peu de points de contrôle. Essaie une autre session ou des points manuels dans Hugin."
  sips -s format jpeg -s formatOptions 85 pano.tif --out flat.jpg >/dev/null 2>&1
  sips --padToHeightWidth "${CANVAS#*x}" "${CANVAS%x*}" --padColor FFFFFF flat.jpg --out pano.jpg >/dev/null 2>&1
  ok "Panorama assemblé (erreur opt=${opt_err} px, $(du -h pano.jpg | cut -f1))"
fi

# ─── 3. GPS EXIF + géolocalisation (via le cœur : exiftool + Nominatim) ──────
if [[ "$FILE_MODE" == "1" ]]; then FIRST="$SESSION"; else
  FIRST=$(find "$SESSION" -maxdepth 1 -iname 'PANO_*.JPG' ! -name '._*' | sort | head -1)
fi
read -r M_LAT M_LON M_DT < <(core_extract_meta "$FIRST")
# Overrides manuels --lat/--lon (utile si l'export DJI a perdu le GPS EXIF).
[[ -n "$LAT" ]] && M_LAT="$LAT"
[[ -n "$LON" ]] && M_LON="$LON"
if ! GEO_JSON=$(LAT="$M_LAT" LON="$M_LON" DT="$M_DT" NAME_OVR="$NAME" \
    CITY_OVR="$CITY" ID_OVR="$ID" core_geocode); then
  die "Géocodage Nominatim échoué — aucun lieu inventé ni publié."
fi

GEO_NAME=$(echo "$GEO_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["name"])')
GEO_CITY=$(echo "$GEO_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["city"])')
GEO_ID=$(echo "$GEO_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
GEO_YM=$(echo "$GEO_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("ym") or "")')
GEO_DISPLAY=$(echo "$GEO_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("display",""))')
[[ -n "$GEO_YM" ]] || GEO_YM=$(date +%Y-%m)
if [[ -z "$REPLACE" ]]; then
  GEO_ID="$(core_unique_place_id "$DATA_FILE" "$GEO_ID")"
  GEO_JSON="$(core_set_geo_id "$GEO_JSON" "$GEO_ID")"
fi
FILE="$(core_unique_filename "$MEDIA_DIR" "${GEO_ID}-${GEO_YM}.jpg")"

ok "Lieu : $GEO_NAME  ($GEO_CITY)"
[[ -n "$GEO_DISPLAY" ]] && info "Adresse : $GEO_DISPLAY"
info "Fichier média : $FILE"

if [[ "$DRY" == "1" ]]; then
  cp "$WORK/pano.jpg" "$HOME/Desktop/iso360-apercu-$GEO_ID.jpg"
  b "DRY-RUN — rien publié. Aperçu : ~/Desktop/iso360-apercu-$GEO_ID.jpg"
  echo "$GEO_JSON" | python3 -m json.tool
  exit 0
fi

# ─── 4-5. Publication sur le tunnel + vérification (via le cœur) ─────────────
cd "$REPO"
core_file_is_clean "$REPO" "$DATA_FILE" \
  || die "labs360.ts contient déjà des changements — publication annulée pour ne rien écraser."
core_publish_verify "$WORK/pano.jpg" "$MEDIA_DIR" "$MEDIA_BASE_URL" "$FILE" \
  || die "Publication/vérification échouée (tunnel/Caddy arrêté ? cf handoff §3)"

# ─── 6. Câblage dans labs360.ts (via le cœur : insertion ou remplacement) ────
DATA_SNAPSHOT="$(mktemp "${TMPDIR:-/tmp}/iso360-data.XXXXXX")"
cp "$DATA_FILE" "$DATA_SNAPSHOT" || die "Impossible de sauvegarder labs360.ts"
GEO_JSON="$GEO_JSON" MEDIA_URL="$MEDIA_BASE_URL/$FILE" PTYPE='360' POSTER_URL='' \
  REPLACE="$REPLACE" WIRE_NOTE='Pano drone auto-publié par iso360' DATA="$DATA_FILE" \
  core_wire || {
    cp "$DATA_SNAPSHOT" "$DATA_FILE"
    rm -f "$DATA_SNAPSHOT"
    die "Câblage labs360.ts échoué"
  }
ok "labs360.ts câblé"

# ─── 7. Garde-fou : build avant de pousser (via le cœur) ─────────────────────
core_build_guard "$DATA_FILE" "$DATA_SNAPSHOT" || {
  rm -f "$DATA_SNAPSHOT"
  die "Build échoué → rien poussé. Voir /tmp/iso360-build.log"
}

# ─── 8. Commit + push (via le cœur) ──────────────────────────────────────────
verb=$([[ -n "$REPLACE" ]] && echo "update" || echo "add")
if ! core_commit_push "$DATA_FILE" "$verb" "$GEO_NAME" "$PUSH" "$LIVE_PAGE" "$FILE"; then
  git -C "$REPO" reset -q -- "$DATA_FILE" 2>/dev/null || true
  cp "$DATA_SNAPSHOT" "$DATA_FILE"
  rm -f "$DATA_SNAPSHOT"
  die "Commit/push échoué → labs360.ts restauré, original conservé."
fi
rm -f "$DATA_SNAPSHOT"
