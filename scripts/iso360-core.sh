#!/usr/bin/env bash
#
# iso360-core — fonctions partagées entre iso360 (manuel, stitch DJI) et
# iso-ingest (auto, boîte de dépôt). À `source` — ne s'exécute pas seul.
#
# Contrat : les fonctions écrivent leur résultat sur stdout et renvoient un
# code de sortie ≠ 0 en cas d'échec. Les logs vont sur stderr.

# ─── Log helpers ─────────────────────────────────────────────────────────────
core_b(){ printf '\033[1m%s\033[0m\n' "$*" >&2; }
core_ok(){ printf '\033[32m✓\033[0m %s\n' "$*" >&2; }
core_info(){ printf '\033[36m•\033[0m %s\n' "$*" >&2; }
core_warn(){ printf '\033[33m⚠ %s\033[0m\n' "$*" >&2; }

# core_extract_meta <file> → "LAT LON DT" (champs vides si absents)
# exiftool lit le GPS des JPEG (drone/photo) ET des MP4/MOV. Sortie JSON avec
# labels → on ne dépend pas de l'ordre/du nombre de lignes.
core_extract_meta() {
  exiftool -n -j -GPSLatitude -GPSLongitude -DateTimeOriginal -CreateDate "$1" 2>/dev/null \
  | python3 -c '
import sys, json
try:
    d=json.load(sys.stdin)[0]
except Exception:
    print("  "); sys.exit(0)
lat=d.get("GPSLatitude",""); lon=d.get("GPSLongitude","")
dt=d.get("DateTimeOriginal") or d.get("CreateDate") or ""
print(f"{lat} {lon} {dt}")
'
}

# core_geocode : env LAT LON DT NAME_OVR CITY_OVR ID_OVR → GEO_JSON sur stdout
core_geocode() {
  python3 <<'PY'
import os, json, urllib.request, urllib.parse, re, unicodedata
def slugify(s):
    s=unicodedata.normalize('NFKD',s).encode('ascii','ignore').decode()
    return re.sub(r'-+','-',re.sub(r'[^a-z0-9]+','-',s.lower())).strip('-')
def num(v):
    v=(v or '').strip()
    try: return float(v)
    except ValueError: return None
lat=num(os.environ.get('LAT')); lon=num(os.environ.get('LON'))
dt=(os.environ.get('DT') or '').strip()
ym=dt[:7].replace(':','-') if dt else ''
res={'lat':lat,'lon':lon,'dt':dt,'ym':ym}
name=os.environ.get('NAME_OVR','').strip()
city=os.environ.get('CITY_OVR','').strip()
if lat is not None and lon is not None:
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
            city='quebec' if lat>46.3 else 'montreal'
    except Exception as e:
        res['geo_error']=str(e)
if not city: city='quebec'
if not name: name='Lieu sans nom'
res.update({'name':name,'city':city,
            'id':os.environ.get('ID_OVR','').strip() or slugify(name)})
print(json.dumps(res,ensure_ascii=False))
PY
}

# core_forward_geocode <query> → "LAT LON" (vide si introuvable)
core_forward_geocode() {
  QUERY="$1" python3 <<'PY'
import os, json, urllib.request, urllib.parse
q=os.environ['QUERY'].replace('-',' ').strip()
if not q: raise SystemExit
u='https://nominatim.openstreetmap.org/search?'+urllib.parse.urlencode(
    {'q':q,'format':'json','limit':'1','accept-language':'fr','countrycodes':'ca'})
req=urllib.request.Request(u,headers={'User-Agent':'iso360/1.0 (theo-picture.com)'})
try:
    r=json.load(urllib.request.urlopen(req,timeout=20))
    if r: print(f"{r[0]['lat']} {r[0]['lon']}")
except Exception:
    pass
PY
}

# core_publish_verify <local> <destdir> <baseurl> <filename> → exit≠0 si échec
core_publish_verify() {
  local local_file="$1" destdir="$2" baseurl="$3" filename="$4"
  [[ -d "$destdir" ]] || { core_warn "Dossier média absent : $destdir (SSD monté ?)"; return 1; }
  cp "$local_file" "$destdir/$filename" || return 1
  core_ok "Copié dans $destdir/$filename"
  local code=""
  for _ in 1 2 3 4 5; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$baseurl/$filename" || true)
    [[ "$code" == "200" ]] && break
    sleep 3
  done
  [[ "$code" == "200" ]] || { core_warn "URL publique répond $code : $baseurl/$filename"; return 1; }
  core_ok "En ligne : $baseurl/$filename"
}

# core_wire : env GEO_JSON MEDIA_URL PTYPE POSTER_URL REPLACE WIRE_NOTE DATA
core_wire() {
  python3 <<'PY'
import os, json, re
g=json.loads(os.environ['GEO_JSON'])
url=os.environ['MEDIA_URL']; rep=os.environ.get('REPLACE','').strip()
path=os.environ['DATA']; typ=os.environ.get('PTYPE','360')
poster=os.environ.get('POSTER_URL','').strip()
note=os.environ.get('WIRE_NOTE','Auto-publié')
src=open(path,encoding='utf-8').read()
if rep:
    pat=re.compile(r"(\{\s*\n\s*id:\s*'"+re.escape(rep)+r"'.*?media:\s*)'[^']*'",re.S)
    if not pat.search(src): raise SystemExit(f"Lieu introuvable pour --replace {rep}")
    src=pat.sub(lambda m: m.group(1)+json.dumps(url), src, count=1)
    open(path,'w',encoding='utf-8').write(src); print(f"replaced:{rep}")
else:
    nm=json.dumps(g['name'])
    dfr=json.dumps(f"{g['name']} — vue aérienne captée au drone.")
    den=json.dumps(f"{g['name']} — aerial view captured by drone.")
    lat=g.get('lat') if g.get('lat') is not None else (46.85 if g['city']=='quebec' else 45.51)
    lon=g.get('lon') if g.get('lon') is not None else (-71.15 if g['city']=='quebec' else -73.57)
    poster_line=f"    poster: {json.dumps(poster)},\n" if poster else ""
    block=(f"  {{\n    id: {json.dumps(g['id'])},\n    city: {json.dumps(g['city'])},\n"
           f"    type: {json.dumps(typ)},\n    name: {nm},\n    desc: {{\n      fr: {dfr},\n      en: {den},\n    }},\n"
           f"    credit: '',\n    lat: {lat}, lon: {lon},\n"
           f"    // {note} ({g.get('dt','')})\n"
           f"    media: {json.dumps(url)},\n{poster_line}  }},\n")
    marker="  // iso360:insert"
    if marker not in src: raise SystemExit("Marqueur iso360:insert absent de labs360.ts")
    src=src.replace(marker, block+marker, 1)
    open(path,'w',encoding='utf-8').write(src); print(f"inserted:{g['id']}")
PY
}

# core_build_guard <data_file> → rollback + exit≠0 si le build casse
core_build_guard() {
  local data_file="$1"
  core_info "Build de validation…"
  if ! npm run build >/tmp/iso360-build.log 2>&1; then
    git checkout -- "$data_file"
    core_warn "Build échoué → $(basename "$data_file") restauré, rien poussé. Voir /tmp/iso360-build.log"
    return 1
  fi
  core_ok "Build OK (10 pages)"
}

# core_commit_push <data_file> <verb> <name> <push> <live_page> <filename>
# NB : MEDIA_BASE_URL doit être exporté par l'appelant (réchauffe le cache edge).
core_commit_push() {
  local data_file="$1" verb="$2" name="$3" push="$4" live_page="$5" filename="$6"
  git add "$data_file"
  git commit -q -m "feat(labs360): $verb '$name' (iso-ingest, auto-geo)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  core_ok "Commit créé"
  [[ "$push" == "1" ]] || { core_b "Commit local (pas de push)."; return 0; }
  git push -q origin main
  core_ok "Poussé → déploiement Vercel en cours"
  for _ in $(seq 1 18); do
    if curl -s -H 'Cookie: lang=fr' "$live_page" | grep -q "$filename"; then
      curl -s -o /dev/null "${MEDIA_BASE_URL:-}/$filename" 2>/dev/null || true
      core_b "🚁 EN LIGNE : $live_page"
      return 0
    fi
    sleep 10
  done
  core_b "Poussé ✓ — propagation en cours. Vérifie $live_page dans une minute."
}
