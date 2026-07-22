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
#   iso360 <dossier-session> [options]
#
# Options :
#   --name "Nom du lieu"    Force le nom (sinon déduit du géocodage)
#   --city quebec|montreal  Force la ville (sinon déduite du GPS)
#   --id slug               Force l'id/slug du lieu
#   --replace <id>          Met à jour le média d'un lieu EXISTANT au lieu d'en créer un
#   --no-push               Fait tout sauf le git push (commit local seulement)
#   --dry-run               Assemble + géolocalise + affiche, mais ne touche RIEN (ni média, ni repo)
#
# Exemples :
#   iso360 "/Volumes/SD_Card/DCIM/PANORAMA/001_0190"
#   iso360 "/Volumes/SD_Card/DCIM/PANORAMA/001_0190" --replace maizerets
#   iso360 ~/pano-session --name "Terrasse Dufferin" --city quebec

set -euo pipefail

# ─── Configuration (adapter ici si l'infra bouge) ────────────────────────────
REPO="$HOME/Desktop/Developer/iso-nord"
MEDIA_DIR="/Volumes/SSD 1/iso-nord-media/panoramas"
MEDIA_BASE_URL="https://media.theo-picture.com/panoramas"
LIVE_PAGE="https://theo-picture.com/labs/360"
DATA_FILE="$REPO/src/data/labs360.ts"
HUGIN="/Applications/Hugin/tools_mac"
CANVAS="6300x3150"           # taille du panorama de sortie (2:1)
SEG_WIDTH=2016               # downscale des segments avant cpfind (vitesse)

# ─── Couleurs / log ──────────────────────────────────────────────────────────
b(){ printf '\033[1m%s\033[0m\n' "$*"; }        # gras
ok(){ printf '\033[32m✓\033[0m %s\n' "$*"; }
info(){ printf '\033[36m•\033[0m %s\n' "$*"; }
die(){ printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ─── Arguments ───────────────────────────────────────────────────────────────
SESSION="" NAME="" CITY="" ID="" REPLACE="" PUSH=1 DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)    NAME="$2"; shift 2;;
    --city)    CITY="$2"; shift 2;;
    --id)      ID="$2"; shift 2;;
    --replace) REPLACE="$2"; shift 2;;
    --no-push) PUSH=0; shift;;
    --dry-run) DRY=1; shift;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    -*)        die "Option inconnue : $1";;
    *)         SESSION="$1"; shift;;
  esac
done

[[ -n "$SESSION" ]] || die "Usage : iso360 <dossier-session> [options]  (voir --help)"
[[ -d "$SESSION" ]] || die "Dossier introuvable : $SESSION"
[[ -x "$HUGIN/pto_gen" ]] || die "Hugin introuvable dans $HUGIN (brew install --cask hugin)"
count=$(find "$SESSION" -maxdepth 1 -iname 'PANO_*.JPG' ! -name '._*' | wc -l | tr -d ' ')
[[ "$count" -ge 4 ]] || die "Trop peu de segments PANO_*.JPG ($count) dans $SESSION"
export PATH="$HUGIN:$PATH"

b "iso360 — $count segments dans $(basename "$SESSION")"

# ─── 1. Espace de travail temporaire ─────────────────────────────────────────
WORK="$(mktemp -d "${TMPDIR:-/tmp}/iso360.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

info "Downscale des segments à ${SEG_WIDTH}px…"
i=0
for f in "$SESSION"/PANO_*.JPG "$SESSION"/PANO_*.jpg; do
  [[ -e "$f" ]] || continue
  [[ "$(basename "$f")" == ._* ]] && continue
  sips --resampleWidth "$SEG_WIDTH" "$f" --out "$WORK/$(printf 'seg%03d.jpg' "$i")" >/dev/null 2>&1
  i=$((i+1))
done
ok "$i segments préparés"

# ─── 2. Stitch (Hugin) ───────────────────────────────────────────────────────
cd "$WORK"
info "Détection des points de contrôle (cpfind — l'étape longue, ~2-4 min)…"
pto_gen -o p.pto seg*.jpg >/dev/null 2>&1
cpfind --multirow --celeste -o p.pto p.pto >/dev/null 2>&1
cpclean -o p.pto p.pto >/dev/null 2>&1
info "Optimisation géométrique…"
opt_err=$(autooptimiser -a -m -l -s -o p.pto p.pto 2>&1 | grep -Eo 'error: [0-9.]+' | tail -1 | grep -Eo '[0-9.]+' || echo "?")
pano_modify --projection=2 --fov=360x180 --canvas="$CANVAS" -o p.pto p.pto >/dev/null 2>&1
info "Rendu + fusion (nona + enblend)…"
nona -m TIFF_m -o s_ p.pto >/dev/null 2>&1
enblend -o pano.tif s_*.tif >/dev/null 2>&1

# Garde-fou stitch : les panos d'hiver (neige) donnent un TIFF quasi vide.
tif_size=$(stat -f%z pano.tif 2>/dev/null || echo 0)
[[ "$tif_size" -gt 100000 ]] || die "Stitch échoué (TIFF ${tif_size} o, erreur opt=${opt_err}). Souvent la neige : trop peu de points de contrôle. Essaie une autre session ou des points manuels dans Hugin."
sips -s format jpeg -s formatOptions 85 pano.tif --out flat.jpg >/dev/null 2>&1
sips --padToHeightWidth "${CANVAS#*x}" "${CANVAS%x*}" --padColor FFFFFF flat.jpg --out pano.jpg >/dev/null 2>&1
ok "Panorama assemblé (erreur opt=${opt_err} px, $(du -h pano.jpg | cut -f1))"

# ─── 3. GPS EXIF + géolocalisation ───────────────────────────────────────────
FIRST=$(find "$SESSION" -maxdepth 1 -iname 'PANO_*.JPG' ! -name '._*' | sort | head -1)
GEO_JSON=$(SEG="$FIRST" NAME_OVR="$NAME" CITY_OVR="$CITY" ID_OVR="$ID" python3 <<'PY'
import os, struct, sys, json, urllib.request, urllib.parse, re, unicodedata

def exif(path):
    d = open(path,'rb').read(300000); i = d.find(b'Exif\x00\x00')
    if i < 0: return {}
    t = d[i+6:]; en = '<' if t[:2]==b'II' else '>'
    u16=lambda o: struct.unpack(en+'H',t[o:o+2])[0]
    u32=lambda o: struct.unpack(en+'I',t[o:o+4])[0]
    rat=lambda o: u32(o)/max(1,u32(o+4))
    out={}
    def ifd(off,depth=0):
        for k in range(u16(off)):
            e=off+2+k*12; tag,typ,cnt,val=u16(e),u16(e+2),u32(e+4),e+8; ov=u32(val)
            if tag in (0x8769,0x8825) and depth<2: ifd(ov,depth+1)
            elif tag==0x9003: out['dt']=t[ov:ov+cnt].rstrip(b'\x00').decode('ascii','replace')
            elif tag in (1,3): out['NS' if tag==1 else 'EW']=t[val:val+1].decode()
            elif tag in (2,4):
                deg=rat(ov)+rat(ov+8)/60+rat(ov+16)/3600
                out['lat' if tag==2 else 'lon']=deg
    ifd(u32(4))
    if out.get('NS')=='S': out['lat']=-out['lat']
    if out.get('EW')=='W': out['lon']=-out['lon']
    return out

def slugify(s):
    s=unicodedata.normalize('NFKD',s).encode('ascii','ignore').decode()
    return re.sub(r'-+','-',re.sub(r'[^a-z0-9]+','-',s.lower())).strip('-')

x=exif(os.environ['SEG'])
lat=x.get('lat'); lon=x.get('lon'); dt=x.get('dt','')
ym = dt[:7].replace(':','-') if dt else ''
res={'lat':lat,'lon':lon,'dt':dt,'ym':ym}

name=os.environ.get('NAME_OVR','').strip()
city=os.environ.get('CITY_OVR','').strip()
if lat and lon:
    try:
        u='https://nominatim.openstreetmap.org/reverse?'+urllib.parse.urlencode(
            {'lat':lat,'lon':lon,'format':'json','accept-language':'fr','zoom':'17'})
        req=urllib.request.Request(u,headers={'User-Agent':'iso360/1.0 (theo-picture.com)'})
        g=json.load(urllib.request.urlopen(req,timeout=20)); a=g.get('address',{})
        res['display']=g.get('display_name','')
        if not name:
            for k in ('tourism','leisure','building','amenity','neighbourhood',
                      'suburb','quarter','city_district','road','hamlet'):
                if a.get(k): name=a[k]; break
        if not city:
            city='quebec' if (lat and lat>46.3) else 'montreal'
        res['suburb']=a.get('suburb') or a.get('neighbourhood') or a.get('city_district') or ''
    except Exception as e:
        res['geo_error']=str(e)
if not city: city='quebec'
if not name: name='Lieu sans nom'

# position x/y approximative sur la carte stylisée (déduite du GPS, ajustable après)
def lerp(v,a,bb,lo,hi):
    if v is None: return 50
    return max(15,min(85,round(lo+(v-a)/(bb-a)*(hi-lo))))
if city=='quebec':
    xx=lerp(lon,-71.42,-71.02,15,85); yy=lerp(lat,46.92,46.74,15,85)
else:
    xx=lerp(lon,-73.78,-73.42,15,85); yy=lerp(lat,45.60,45.40,15,85)

res.update({'name':name,'city':city,
            'id':os.environ.get('ID_OVR','').strip() or slugify(name),
            'x':xx,'y':yy})
print(json.dumps(res,ensure_ascii=False))
PY
)

GEO_NAME=$(echo "$GEO_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["name"])')
GEO_CITY=$(echo "$GEO_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["city"])')
GEO_ID=$(echo "$GEO_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
GEO_YM=$(echo "$GEO_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("ym") or "")')
GEO_DISPLAY=$(echo "$GEO_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("display",""))')
[[ -n "$GEO_YM" ]] || GEO_YM=$(date +%Y-%m)
FILE="${GEO_ID}-${GEO_YM}.jpg"

ok "Lieu : $GEO_NAME  ($GEO_CITY)"
[[ -n "$GEO_DISPLAY" ]] && info "Adresse : $GEO_DISPLAY"
info "Fichier média : $FILE"

if [[ "$DRY" == "1" ]]; then
  cp "$WORK/pano.jpg" "$HOME/Desktop/iso360-apercu-$GEO_ID.jpg"
  b "DRY-RUN — rien publié. Aperçu : ~/Desktop/iso360-apercu-$GEO_ID.jpg"
  echo "$GEO_JSON" | python3 -m json.tool
  exit 0
fi

# ─── 4-5. Publication sur le tunnel + vérification ───────────────────────────
[[ -d "$MEDIA_DIR" ]] || die "Dossier média absent : $MEDIA_DIR (le SSD est-il monté ?)"
cp "$WORK/pano.jpg" "$MEDIA_DIR/$FILE"
ok "Copié dans $MEDIA_DIR"
info "Vérification de l'URL publique…"
for attempt in 1 2 3 4 5; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$MEDIA_BASE_URL/$FILE" || true)
  [[ "$code" == "200" ]] && break
  sleep 3
done
[[ "$code" == "200" ]] || die "L'URL publique répond $code (tunnel/Caddy arrêté ? cf handoff §3)"
ok "En ligne : $MEDIA_BASE_URL/$FILE"

# ─── 6. Câblage dans labs360.ts (insertion ou remplacement) ──────────────────
cd "$REPO"
MEDIA_URL="$MEDIA_BASE_URL/$FILE"
GEO_JSON="$GEO_JSON" MEDIA_URL="$MEDIA_URL" REPLACE="$REPLACE" DATA="$DATA_FILE" python3 <<'PY'
import os, json, re, io
g=json.loads(os.environ['GEO_JSON'])
url=os.environ['MEDIA_URL']; rep=os.environ['REPLACE'].strip(); path=os.environ['DATA']
src=open(path,encoding='utf-8').read()

if rep:
    # Remplace le média du lieu existant `id: '<rep>'`
    pat=re.compile(r"(\{\s*\n\s*id:\s*'"+re.escape(rep)+r"'.*?media:\s*)'[^']*'",re.S)
    if not pat.search(src):
        raise SystemExit(f"Lieu introuvable pour --replace {rep}")
    src=pat.sub(lambda m: m.group(1)+json.dumps(url), src, count=1)
    open(path,'w',encoding='utf-8').write(src)
    print(f"replaced:{rep}")
else:
    nm=json.dumps(g['name']); dfr=json.dumps(f"{g['name']} — vue aérienne captée au drone.")
    den=json.dumps(f"{g['name']} — aerial view captured by drone.")
    lat=g.get('lat') if g.get('lat') is not None else (46.85 if g['city']=='quebec' else 45.51)
    lon=g.get('lon') if g.get('lon') is not None else (-71.15 if g['city']=='quebec' else -73.57)
    block=(f"  {{\n    id: {json.dumps(g['id'])},\n    city: {json.dumps(g['city'])},\n"
           f"    type: '360',\n    name: {nm},\n    desc: {{\n      fr: {dfr},\n      en: {den},\n    }},\n"
           f"    credit: '',\n    lat: {lat}, lon: {lon},\n"
           f"    // Pano drone auto-publié par iso360 ({g.get('dt','')})\n"
           f"    media: {json.dumps(url)},\n  }},\n")
    marker="  // iso360:insert"
    if marker not in src:
        raise SystemExit("Marqueur iso360:insert absent de labs360.ts")
    src=src.replace(marker, block+marker, 1)
    open(path,'w',encoding='utf-8').write(src)
    print(f"inserted:{g['id']}")
PY
ok "labs360.ts câblé"

# ─── 7. Garde-fou : build avant de pousser ───────────────────────────────────
info "Build de validation…"
if ! npm run build >/tmp/iso360-build.log 2>&1; then
  git checkout -- "$DATA_FILE"
  die "Build échoué → labs360.ts restauré, rien poussé. Voir /tmp/iso360-build.log"
fi
ok "Build OK (10 pages)"

# ─── 8. Commit + push ────────────────────────────────────────────────────────
git add "$DATA_FILE"
verb=$([[ -n "$REPLACE" ]] && echo "update" || echo "add")
git commit -q -m "feat(labs360): $verb '$GEO_NAME' pano (iso360, auto-stitch + geo)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
ok "Commit créé"

if [[ "$PUSH" == "1" ]]; then
  git push -q origin main
  ok "Poussé → déploiement Vercel en cours"
  info "Attente de la mise en ligne (jusqu'à 3 min)…"
  for attempt in $(seq 1 18); do
    if curl -s -H 'Cookie: lang=fr' "$LIVE_PAGE" | grep -q "$FILE"; then
      curl -s -o /dev/null "$MEDIA_URL"   # réchauffe le cache edge
      b "🚁 EN LIGNE : $LIVE_PAGE  →  pin « $GEO_NAME »"
      exit 0
    fi
    sleep 10
  done
  b "Poussé ✓ — le déploiement finit de propager. Vérifie $LIVE_PAGE dans une minute."
else
  b "Commit local créé (--no-push). Fais 'git push' quand tu es prêt."
fi
