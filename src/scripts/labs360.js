/**
 * Labs 360 — interactions de la page carte.
 *
 * - Lenis + reveals GSAP (mêmes réglages que labs.js)
 * - Carte satellite Apple Maps centrée sur les médias publiés à Québec
 * - Modal viewer : Pannellum (dynamic import, au 1er pin 360) ou <video>,
 *   focus piégé, Échap/backdrop, focus restitué au déclencheur.
 *
 * MapKit s'authentifie via /api/mapkit-token (fonction serverless Vercel qui
 * signe un token court restreint à theo-picture.com). L'auth ne fonctionne
 * donc PAS en local (localhost) : la liste des lieux ci-dessous reste le repli.
 */
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import Lenis from 'lenis';

gsap.registerPlugin(ScrollTrigger);

const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const DATA = JSON.parse(document.getElementById('l360-data').textContent);
const placeById = Object.fromEntries(DATA.places.map((p) => [p.id, p]));

/* ── Smooth scroll + curseur + reveals (repris de labs.js) ────────────────── */
let lenis = null;
if (!reducedMotion) {
  lenis = new Lenis({ lerp: 0.09, smoothWheel: true });
  lenis.on('scroll', ScrollTrigger.update);
  gsap.ticker.add((t) => lenis.raf(t * 1000));
  gsap.ticker.lagSmoothing(0);

  const progressBar = document.querySelector('.progress-bar');
  if (progressBar) {
    lenis.on('scroll', ({ progress }) => { progressBar.style.width = `${progress * 100}%`; });
  }

  const dot = document.querySelector('.cursor-dot');
  const ring = document.querySelector('.cursor-ring');
  if (dot && ring && window.matchMedia('(pointer: fine)').matches) {
    document.addEventListener('mousemove', (e) => {
      gsap.to(dot, { x: e.clientX, y: e.clientY, duration: 0.04, overwrite: true });
      gsap.to(ring, { x: e.clientX, y: e.clientY, duration: 0.34, ease: 'power2.out', overwrite: true });
    });
    document.querySelectorAll('a, button').forEach((el) => {
      el.addEventListener('mouseenter', () => {
        gsap.to(ring, { scale: 2.3, opacity: 0.4, duration: 0.3 });
        gsap.to(dot, { scale: 0, opacity: 0, duration: 0.2 });
      });
      el.addEventListener('mouseleave', () => {
        gsap.to(ring, { scale: 1, opacity: 1, duration: 0.38 });
        gsap.to(dot, { scale: 1, opacity: 1, duration: 0.28 });
      });
    });
  }

  const heroBits = gsap.utils.toArray('.l360-eyebrow, .l360-title, .l360-lede');
  gsap.set(heroBits, { opacity: 0, y: 40 });
  gsap.to(heroBits, { opacity: 1, y: 0, duration: 1.1, stagger: 0.12, ease: 'power3.out', delay: 0.15 });

  // NB : on n'anime PAS l'opacité du conteneur carte. iOS Safari laisse un
  // canvas WebGL créé sous un ancêtre `opacity:0` blanc de façon permanente
  // (les tuiles satellite ne s'affichaient jamais, seuls les pins DOM oui).
}

/* ── Carte satellite Apple Maps (MapKit JS) ───────────────────────────────── */
let map = null;

function regionForPlaces(places) {
  if (!places.length) {
    return new mapkit.CoordinateRegion(
      new mapkit.Coordinate(46.84, -71.22),
      new mapkit.CoordinateSpan(0.18, 0.24),
    );
  }
  const lats = places.map((p) => p.lat);
  const lons = places.map((p) => p.lon);
  const minLat = Math.min(...lats);
  const maxLat = Math.max(...lats);
  const minLon = Math.min(...lons);
  const maxLon = Math.max(...lons);
  const latSpan = Math.max((maxLat - minLat) * 1.8, 0.08);
  const lonSpan = Math.max((maxLon - minLon) * 1.8, 0.12);
  return new mapkit.CoordinateRegion(
    new mapkit.Coordinate((minLat + maxLat) / 2, (minLon + maxLon) / 2),
    new mapkit.CoordinateSpan(latSpan, lonSpan),
  );
}

function initMapKit() {
  if (!window.mapkit) return;
  mapkit.init({
    authorizationCallback(done) {
      fetch('/api/mapkit-token')
        .then((r) => (r.ok ? r.text() : Promise.reject(new Error('HTTP ' + r.status))))
        .then(done)
        .catch(() => { /* auth impossible (local/offline) → repli légende */ });
    },
    language: DATA.lang === 'fr' ? 'fr-CA' : 'en',
  });

  // Région passée au constructeur → cadrage initial fiable (sinon MapKit
  // retombe sur 0°,0° avant qu'un map.region tardif ne s'applique).
  map = new mapkit.Map('l360-mapkit', {
    region: regionForPlaces(DATA.places),
    mapType: mapkit.Map.MapTypes.Hybrid,          // satellite + libellés
    colorScheme: mapkit.Map.ColorSchemes.Dark,
    showsCompass: mapkit.FeatureVisibility.Hidden,
    showsScale: mapkit.FeatureVisibility.Hidden,
    showsMapTypeControl: false,
    showsZoomControl: true,
    showsUserLocationControl: false,
    isRotationEnabled: true,
  });

  const annotations = DATA.places.map((p) => {
    const glyph = p.type === '360' ? '◉' : p.type === 'photo' ? '◆' : '▶';
    const badge = p.type === '360' ? DATA.badge360 : p.type === 'photo' ? DATA.badgePhoto : DATA.badgeVideo;
    const ann = new mapkit.MarkerAnnotation(new mapkit.Coordinate(p.lat, p.lon), {
      color: '#c8ff00',
      glyphText: glyph,
      title: p.name,
      subtitle: badge,
    });
    ann.data = { id: p.id };
    ann.addEventListener('select', () => openModal(p.id, null));
    return ann;
  });
  map.addAnnotations(annotations);

  // iOS Safari : forcer MapKit à recalculer/repeindre son canvas une fois la
  // carte réellement visible (init sous le fold → tuiles parfois blanches).
  const nudge = () => window.dispatchEvent(new Event('resize'));
  requestAnimationFrame(nudge);
  const el = document.getElementById('l360-mapkit');
  const io = new IntersectionObserver((entries) => {
    if (!entries[0].isIntersecting) return;
    nudge();
    setTimeout(nudge, 300);   // second passage après la 1re salve de tuiles
    io.disconnect();
  }, { threshold: 0.1 });
  io.observe(el);
}

// MapKit charge en async : attendre son script avant d'initialiser.
if (window.mapkit) {
  initMapKit();
} else {
  const s = document.getElementById('mapkit-js');
  if (s) s.addEventListener('load', initMapKit, { once: true });
}

/* ── Modal viewer ─────────────────────────────────────────────────────────── */
const modal = document.getElementById('l360-modal');
const panel = modal.querySelector('.l360-modal__panel');
const backdrop = modal.querySelector('.l360-modal__backdrop');
const mediaHost = document.getElementById('l360-media');
const hintEl = modal.querySelector('.l360-modal__hint');
const fallbackEl = modal.querySelector('.l360-modal__fallback');
const titleEl = document.getElementById('l360-title');
const descEl = modal.querySelector('.l360-modal__desc');
const creditEl = modal.querySelector('.l360-modal__credit');

let viewer = null;          // instance Pannellum courante
let lastTrigger = null;     // élément à re-focus à la fermeture (null si clic carte)
let open = false;

function showFallback() {
  mediaHost.replaceChildren();
  fallbackEl.hidden = false;
  hintEl.hidden = true;
}

async function mountMedia(place) {
  fallbackEl.hidden = true;
  hintEl.hidden = true;
  mediaHost.replaceChildren();
  if (!place.media) return showFallback();

  if (place.type === '360') {
    try {
      // Lazy : Pannellum (UMD → window.pannellum) + son CSS, au premier besoin.
      await Promise.all([
        import('pannellum/build/pannellum.js'),
        import('pannellum/build/pannellum.css'),
      ]);
      const host = document.createElement('div');
      mediaHost.append(host);
      viewer = window.pannellum.viewer(host, {
        type: 'equirectangular',
        panorama: place.media,
        autoLoad: true,
        autoRotate: reducedMotion ? 0 : -2,
        showControls: false,
        compass: false,
        friction: 0.12,
      });
      viewer.on('error', showFallback);
      hintEl.hidden = false;
      // L'indice disparaît au premier drag — capture: true pour passer avant
      // le handler de Pannellum sur son canvas.
      const hideHint = () => { hintEl.hidden = true; };
      host.addEventListener('mousedown', hideHint, { once: true, capture: true });
      host.addEventListener('touchstart', hideHint, { once: true, capture: true, passive: true });
    } catch {
      showFallback();
    }
  } else if (place.type === 'photo') {
    const img = document.createElement('img');
    img.loading = 'lazy';
    img.alt = place.name;
    img.src = place.media;
    img.addEventListener('error', showFallback, { once: true });
    mediaHost.append(img);
  } else {
    const video = document.createElement('video');
    video.controls = true;
    video.playsInline = true;
    video.preload = 'metadata';
    if (place.poster) video.poster = place.poster;
    video.src = place.media;
    video.addEventListener('error', showFallback, { once: true });
    mediaHost.append(video);
  }
}

function openModal(placeId, trigger) {
  const place = placeById[placeId];
  if (!place || open) return;
  open = true;
  lastTrigger = trigger;

  titleEl.textContent = place.name;
  descEl.textContent = place.desc;
  // Crédit affiché seulement s'il est renseigné (voir data/labs360.ts).
  creditEl.textContent = place.credit ? `${DATA.creditPrefix} ${place.credit}` : '';

  modal.hidden = false;
  lenis?.stop();
  document.body.style.overflow = 'hidden';
  mountMedia(place);

  if (reducedMotion || !trigger) {
    // Clic depuis la carte (pas d'élément d'origine) → simple fondu + zoom.
    gsap.fromTo(backdrop, { opacity: 0 }, { opacity: 0.92, duration: 0.3, ease: 'power2.out' });
    gsap.fromTo(panel, { opacity: 0, scale: 0.94 }, { opacity: 1, scale: 1, duration: 0.4, ease: 'power3.out' });
  } else {
    // Le panneau émerge depuis le déclencheur (item de légende).
    const r = trigger.getBoundingClientRect();
    const p = panel.getBoundingClientRect();
    panel.style.transformOrigin =
      `${r.left + r.width / 2 - p.left}px ${r.top + r.height / 2 - p.top}px`;
    gsap.fromTo(backdrop, { opacity: 0 }, { opacity: 0.92, duration: 0.35, ease: 'power2.out' });
    gsap.fromTo(panel,
      { opacity: 0, scale: 0.86 },
      { opacity: 1, scale: 1, duration: 0.5, ease: 'power3.out' });
  }
  modal.querySelector('.l360-modal__close').focus();
}

function closeModal() {
  if (!open) return;
  open = false;
  const done = () => {
    modal.hidden = true;
    viewer?.destroy();
    viewer = null;
    mediaHost.replaceChildren();          // stoppe la vidéo, libère Pannellum
    if (map) map.selectedAnnotation = null;  // désélectionne le pin de la carte
    lenis?.start();
    document.body.style.overflow = '';
    lastTrigger?.focus();
  };
  if (reducedMotion) return done();
  gsap.to(panel, { opacity: 0, scale: 0.92, duration: 0.28, ease: 'power2.in' });
  gsap.to(backdrop, { opacity: 0, duration: 0.3, delay: 0.05, onComplete: done });
}

// Les items de légende ouvrent la modale (accessibles + repli si la carte casse).
document.querySelectorAll('[data-place-id]').forEach((btn) => {
  btn.addEventListener('click', () => openModal(btn.dataset.placeId, btn));
});
modal.querySelectorAll('[data-modal-close]').forEach((el) => el.addEventListener('click', closeModal));

document.addEventListener('keydown', (e) => {
  if (!open) return;
  if (e.key === 'Escape') return closeModal();
  if (e.key !== 'Tab') return;
  // Focus piégé dans le modal.
  const focusables = [...modal.querySelectorAll('button, video, a[href], [tabindex]:not([tabindex="-1"])')]
    .filter((el) => !el.hidden && el.offsetParent !== null);
  if (!focusables.length) return;
  const first = focusables[0];
  const last = focusables[focusables.length - 1];
  if (e.shiftKey && document.activeElement === first) { last.focus(); e.preventDefault(); }
  else if (!e.shiftKey && document.activeElement === last) { first.focus(); e.preventDefault(); }
});
