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

# core_extract_meta <file> → "LAT|LON|DT" (champs vides si absents)
# Le séparateur non blanc est volontaire : `read` fusionne les espaces et ne peut
# pas distinguer « GPS vide + date avec espaces » sous le Bash 3.2 de macOS.
# exiftool lit le GPS des JPEG (drone/photo) ET des MP4/MOV. Sortie JSON avec
# labels → on ne dépend pas de l'ordre/du nombre de lignes.
core_extract_meta() {
  exiftool -n -j -GPSLatitude -GPSLongitude -DateTimeOriginal -CreateDate "$1" 2>/dev/null \
  | python3 -c '
import sys, json
try:
    d=json.load(sys.stdin)[0]
except Exception:
    print("||"); sys.exit(0)
lat=d.get("GPSLatitude",""); lon=d.get("GPSLongitude","")
dt=d.get("DateTimeOriginal") or d.get("CreateDate") or ""
print(f"{lat}|{lon}|{dt}")
'
}

# core_geocode : env LAT LON DT NAME_OVR CITY_OVR ID_OVR → GEO_JSON sur stdout
core_geocode() {
  python3 <<'PY'
import os, json, urllib.request, urllib.parse, re, sys, time, unicodedata
def slugify(s):
    s=unicodedata.normalize('NFKD',s).encode('ascii','ignore').decode()
    return re.sub(r'-+','-',re.sub(r'[^a-z0-9]+','-',s.lower())).strip('-')
def num(v):
    v=(v or '').strip()
    try: return float(v)
    except ValueError: return None
def fetch_json(path, params):
    base=os.environ.get('ISO_NORD_NOMINATIM_BASE_URL',
                        'https://nominatim.openstreetmap.org').rstrip('/')
    retries=max(1,int(os.environ.get('ISO_NORD_GEOCODE_RETRIES','3')))
    timeout=float(os.environ.get('ISO_NORD_GEOCODE_TIMEOUT','10'))
    delay=float(os.environ.get('ISO_NORD_GEOCODE_RETRY_DELAY','1'))
    error=None
    for attempt in range(retries):
        try:
            u=base+path+'?'+urllib.parse.urlencode(params)
            req=urllib.request.Request(
                u,headers={'User-Agent':'iso360/1.0 (theo-picture.com)'})
            with urllib.request.urlopen(req,timeout=timeout) as response:
                return json.load(response)
        except Exception as exc:
            error=exc
            if attempt+1<retries:
                time.sleep(delay)
    raise RuntimeError(f"Nominatim indisponible après {retries} tentative(s): {error}")
lat=num(os.environ.get('LAT')); lon=num(os.environ.get('LON'))
if lat is None or lon is None:
    print("Coordonnées GPS absentes ou invalides",file=sys.stderr)
    raise SystemExit(2)
dt=(os.environ.get('DT') or '').strip()
# ym = AAAA-MM, seulement si la date est plausible (année 2000+). Une date nulle
# ou aberrante (ex. 0000:00:00 d'un MP4 sans horodatage) → ym vide → l'appelant
# retombe sur le mois courant.
ym=''
m=re.match(r'(\d{4}):(\d{2})', dt)
if m and int(m.group(1))>=2000 and 1<=int(m.group(2))<=12:
    ym=f"{m.group(1)}-{m.group(2)}"
res={'lat':lat,'lon':lon,'dt':dt,'ym':ym}
name=os.environ.get('NAME_OVR','').strip()
city=os.environ.get('CITY_OVR','').strip()
try:
    g=fetch_json('/reverse',
        {'lat':lat,'lon':lon,'format':'json','accept-language':'fr','zoom':'17'})
except Exception as exc:
    print(str(exc),file=sys.stderr)
    raise SystemExit(2)
if not isinstance(g,dict) or g.get('error'):
    print(f"Réponse Nominatim inverse invalide: {g!r}",file=sys.stderr)
    raise SystemExit(2)
a=g.get('address') or {}
res['display']=g.get('display_name','')
if not name:
    for k in ('tourism','leisure','building','amenity','neighbourhood',
              'suburb','quarter','city_district','road','hamlet'):
        if a.get(k): name=a[k]; break
if not name:
    print("Nominatim n’a retourné aucun nom de lieu fiable",file=sys.stderr)
    raise SystemExit(2)
if not city:
    city='quebec' if lat>46.3 else 'montreal'
place_id=os.environ.get('ID_OVR','').strip() or slugify(name)
if not place_id:
    print("Impossible de produire un identifiant de lieu",file=sys.stderr)
    raise SystemExit(2)
res.update({'name':name,'city':city,
            'id':place_id})
print(json.dumps(res,ensure_ascii=False))
PY
}

# core_forward_geocode <query> → "LAT LON" (vide si introuvable)
core_forward_geocode() {
  QUERY="$1" python3 <<'PY'
import os, json, urllib.request, urllib.parse, sys, time
q=os.environ['QUERY'].replace('-',' ').strip()
if not q:
    print("Requête de géocodage vide",file=sys.stderr)
    raise SystemExit(2)
base=os.environ.get('ISO_NORD_NOMINATIM_BASE_URL',
                    'https://nominatim.openstreetmap.org').rstrip('/')
retries=max(1,int(os.environ.get('ISO_NORD_GEOCODE_RETRIES','3')))
timeout=float(os.environ.get('ISO_NORD_GEOCODE_TIMEOUT','10'))
delay=float(os.environ.get('ISO_NORD_GEOCODE_RETRY_DELAY','1'))
params={'q':q,'format':'json','limit':'1','accept-language':'fr','countrycodes':'ca'}
error=None
for attempt in range(retries):
    try:
        u=base+'/search?'+urllib.parse.urlencode(params)
        req=urllib.request.Request(
            u,headers={'User-Agent':'iso360/1.0 (theo-picture.com)'})
        with urllib.request.urlopen(req,timeout=timeout) as response:
            result=json.load(response)
        if result:
            print(f"{result[0]['lat']} {result[0]['lon']}")
            raise SystemExit(0)
        print(f"Aucun résultat Nominatim pour «{q}»",file=sys.stderr)
        raise SystemExit(3)
    except SystemExit:
        raise
    except Exception as exc:
        error=exc
        if attempt+1<retries:
            time.sleep(delay)
print(f"Nominatim indisponible après {retries} tentative(s): {error}",file=sys.stderr)
raise SystemExit(2)
PY
}

# core_unique_path <path> → un chemin libre, suffixé -2, -3… si nécessaire
core_unique_path() {
  local target="$1" dir base stem ext candidate suffix
  dir="$(dirname "$target")"
  base="$(basename "$target")"
  case "$base" in
    *.*) stem="${base%.*}"; ext=".${base##*.}";;
    *) stem="$base"; ext="";;
  esac
  candidate="$target"
  suffix=2
  while [[ -e "$candidate" ]]; do
    candidate="$dir/$stem-$suffix$ext"
    suffix=$((suffix + 1))
  done
  printf '%s\n' "$candidate"
}

# core_unique_filename <destdir> <filename> → un nom libre dans destdir
core_unique_filename() {
  local destdir="$1" filename="$2"
  basename "$(core_unique_path "$destdir/$filename")"
}

# core_unique_place_id <data_file> <id> → un id absent de labs360.ts
core_unique_place_id() {
  DATA_PATH="$1" BASE_ID="$2" python3 <<'PY'
import os,re
src=open(os.environ['DATA_PATH'],encoding='utf-8').read()
base=os.environ['BASE_ID']
candidate=base
suffix=2
def exists(value):
    return re.search(r"\bid:\s*(['\"])" + re.escape(value) + r"\1",src) is not None
while exists(candidate):
    candidate=f"{base}-{suffix}"
    suffix+=1
print(candidate)
PY
}

# core_set_geo_id <geo_json> <id> → même JSON avec l'id remplacé
core_set_geo_id() {
  GEO_INPUT="$1" UNIQUE_ID="$2" python3 <<'PY'
import json,os
data=json.loads(os.environ['GEO_INPUT'])
data['id']=os.environ['UNIQUE_ID']
print(json.dumps(data,ensure_ascii=False))
PY
}

# core_file_is_clean <repo> <file> → refuse d'écraser des changements humains
core_file_is_clean() {
  local repo="$1" file="$2"
  git -C "$repo" diff --quiet -- "$file" \
    && git -C "$repo" diff --cached --quiet -- "$file"
}

# core_require_main_branch [repo] → refuse toute publication hors de main
core_require_main_branch() {
  local repo="${1:-.}" branch=""
  branch="$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null)" || {
    core_warn "Publication refusée : HEAD détachée"
    return 1
  }
  [[ "$branch" == "main" ]] || {
    core_warn "Publication refusée : branche '$branch' (main requise)"
    return 1
  }
}

# core_publish_verify <local> <destdir> <baseurl> <filename> → exit≠0 si échec
core_publish_verify() {
  local local_file="$1" destdir="$2" baseurl="$3" filename="$4" target tmp_file
  [[ -d "$destdir" ]] || { core_warn "Dossier média absent : $destdir (SSD monté ?)"; return 1; }
  [[ -s "$local_file" ]] || { core_warn "Média source absent ou vide : $local_file"; return 1; }
  target="$destdir/$filename"
  [[ ! -e "$target" ]] || { core_warn "Refus d’écraser le média immutable : $target"; return 1; }
  tmp_file="$(mktemp "$destdir/.iso360-publish.XXXXXX")" || return 1
  if ! cp "$local_file" "$tmp_file" \
    || ! chmod 0644 "$tmp_file" \
    || ! ln "$tmp_file" "$target"; then
    rm -f "$tmp_file"
    core_warn "Copie atomique échouée : $target"
    return 1
  fi
  rm -f "$tmp_file"
  core_ok "Copié dans $target"
  local code="" attempt=1 attempts="${ISO_NORD_CURL_ATTEMPTS:-3}"
  while [[ "$attempt" -le "$attempts" ]]; do
    code=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
      --connect-timeout "${ISO_NORD_CURL_CONNECT_TIMEOUT:-5}" \
      --max-time "${ISO_NORD_CURL_MAX_TIME:-15}" \
      "$baseurl/$filename" 2>/dev/null || true)
    [[ "$code" == "200" ]] && break
    [[ "$attempt" -lt "$attempts" ]] && sleep 3
    attempt=$((attempt + 1))
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

# core_build_guard <data_file> [snapshot] → rollback + exit≠0 si build != 10 pages
core_build_guard() {
  local data_file="$1" snapshot="${2:-}" build_log="${ISO_NORD_BUILD_LOG:-/tmp/iso360-build.log}"
  local page_count=""
  core_info "Build de validation…"
  if npm run build >"$build_log" 2>&1; then
    page_count=$(grep -Eo '[0-9]+ page\(s\) built' "$build_log" \
      | tail -1 | awk '{print $1}')
  fi
  if [[ "$page_count" != "10" ]]; then
    if [[ -n "$snapshot" && -f "$snapshot" ]]; then
      cp "$snapshot" "$data_file" || core_warn "Restauration échouée : $data_file"
    else
      git checkout -- "$data_file" 2>/dev/null \
        || core_warn "Restauration git échouée : $data_file"
    fi
    core_warn "Build invalide (${page_count:-échec}, attendu 10 pages) → $(basename "$data_file") restauré. Voir $build_log"
    return 1
  fi
  core_ok "Build OK (10 pages)"
}

# core_commit_push <data_file> <verb> <name> <push> <live_page> <filename> [city]
# NB : MEDIA_BASE_URL doit être exporté par l'appelant (réchauffe le cache edge).
core_commit_push() {
  local data_file="$1" verb="$2" name="$3" push="$4" live_page="$5" filename="$6" city="${7:-quebec}"
  local before_head attempt body
  core_require_main_branch . || return 1
  before_head="$(git rev-parse HEAD)" || { core_warn "Impossible de lire HEAD"; return 1; }
  git add -- "$data_file" || { core_warn "git add a échoué"; return 1; }
  if ! git commit -q --only -m "feat(labs360): $verb '$name' (iso-ingest, auto-geo)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" -- "$data_file"; then
    git reset -q -- "$data_file" 2>/dev/null || true
    core_warn "git commit a échoué"
    return 1
  fi
  core_ok "Commit créé"
  [[ "$push" == "1" ]] || { core_b "Commit local (pas de push)."; return 0; }
  if ! git push -q origin HEAD:main; then
    git reset --soft "$before_head" 2>/dev/null || true
    core_warn "git push a échoué; le commit automatique a été annulé"
    return 1
  fi
  core_ok "Poussé → déploiement Vercel en cours"
  if [[ "$city" == "montreal" ]]; then
    core_b "Média Montréal invisible sur la page actuelle : push confirmé, mais pas de preuve de déploiement live possible."
    return 0
  fi
  attempt=1
  while [[ "$attempt" -le "${ISO_NORD_DEPLOY_ATTEMPTS:-18}" ]]; do
    body=$(curl --silent --show-error --connect-timeout "${ISO_NORD_CURL_CONNECT_TIMEOUT:-5}" \
      --max-time "${ISO_NORD_CURL_MAX_TIME:-15}" \
      -H 'Cookie: lang=fr' "$live_page" 2>/dev/null || true)
    if printf '%s' "$body" | grep -q "$filename"; then
      core_b "🚁 EN LIGNE : $live_page"
      return 0
    fi
    [[ "$attempt" -lt "${ISO_NORD_DEPLOY_ATTEMPTS:-18}" ]] && sleep 10
    attempt=$((attempt + 1))
  done
  core_b "Poussé ✓ — propagation en cours. Vérifie $live_page dans une minute."
  return 0
}
