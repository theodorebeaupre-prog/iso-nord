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
import pannellumCssUrl from 'pannellum/build/pannellum.css?url';
import { createMap } from './labs360-map.js';
import { loadMapKit, observeMap } from './labs360-map-loader.js';
import { shouldAnimateModalOpen } from './labs360-motion.js';
import {
  adjacentPlaceId,
  badgeForType,
  counterLabel,
} from './labs360-view.js';

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

  const cards = gsap.utils.toArray('.l360-card');
  cards.forEach((card) => {
    gsap.fromTo(
      card,
      { opacity: 0, y: 28 },
      {
        opacity: 1,
        y: 0,
        duration: 0.75,
        ease: 'power3.out',
        scrollTrigger: {
          trigger: card,
          start: 'top 88%',
          toggleActions: 'play none none none',
        },
      },
    );
  });

  // NB : on n'anime PAS l'opacité du conteneur carte. iOS Safari laisse un
  // canvas WebGL créé sous un ancêtre `opacity:0` blanc de façon permanente
  // (les tuiles satellite ne s'affichaient jamais, seuls les pins DOM oui).
}

/* ── Carte satellite Apple Maps (MapKit JS) ───────────────────────────────── */
let map = null;

function initMapKit(mapkitApi) {
  map = createMap({
    mapkitApi,
    elementId: 'l360-mapkit',
    places: DATA.places,
    labels: DATA,
    language: DATA.lang === 'fr' ? 'fr-CA' : 'en',
    authorizationCallback(done) {
      fetch('/api/mapkit-token')
        .then((r) => (r.ok ? r.text() : Promise.reject(new Error('HTTP ' + r.status))))
        .then(done)
        .catch(() => { /* auth impossible (local/offline) → repli légende */ });
    },
    onSelect(placeId) {
      openModal(placeId, null);
    },
  });

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

// MapKit est totalement absent du chargement initial. La collection reste
// utilisable si Apple, le jeton ou le réseau échoue.
const mapRegion = document.querySelector('.l360-map');
if (mapRegion && DATA.places.length) {
  observeMap(mapRegion, async () => {
    mapRegion.dataset.state = 'loading';
    try {
      const mapkitApi = await loadMapKit();
      initMapKit(mapkitApi);
      mapRegion.dataset.state = 'ready';
    } catch {
      mapRegion.dataset.state = 'error';
    }
  });
}

/* ── Modal viewer ─────────────────────────────────────────────────────────── */
const modal = document.getElementById('l360-modal');
const panel = modal.querySelector('.l360-modal__panel');
const backdrop = modal.querySelector('.l360-modal__backdrop');
const mediaHost = document.getElementById('l360-media');
const hintEl = modal.querySelector('.l360-modal__hint');
const fallbackEl = modal.querySelector('.l360-modal__fallback');
const badgeEl = modal.querySelector('.l360-modal__badge');
const titleEl = document.getElementById('l360-title');
const descEl = modal.querySelector('.l360-modal__desc');
const creditEl = modal.querySelector('.l360-modal__credit');
const counterEl = modal.querySelector('.l360-modal__counter');
const previousButton = modal.querySelector('[data-view-previous]');
const nextButton = modal.querySelector('[data-view-next]');
const backgroundRegions = document.querySelectorAll('main, .l360-nav, .l360-footer');

let viewer = null;          // instance Pannellum courante
let lastTrigger = null;     // élément à re-focus à la fermeture (null si clic carte)
let open = false;
let currentPlaceId = '';
let mediaRequest = 0;

function setBackgroundInert(value) {
  backgroundRegions.forEach((element) => {
    if (value) {
      element.inert = true;
      element.setAttribute('aria-hidden', 'true');
    } else {
      element.inert = false;
      element.removeAttribute('aria-hidden');
    }
  });
}

function destroyMedia() {
  mediaRequest += 1;
  viewer?.destroy();
  viewer = null;
  mediaHost.replaceChildren();
}

function ensurePannellumStyles() {
  const existing = document.querySelector('link[data-pannellum-styles]');
  if (existing) return Promise.resolve();
  return new Promise((resolve, reject) => {
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = pannellumCssUrl;
    link.dataset.pannellumStyles = '';
    link.addEventListener('load', resolve, { once: true });
    link.addEventListener('error', reject, { once: true });
    document.head.append(link);
  });
}

function showFallback() {
  mediaHost.replaceChildren();
  fallbackEl.hidden = false;
  hintEl.hidden = true;
}

async function mountMedia(place) {
  destroyMedia();
  const request = mediaRequest;
  fallbackEl.hidden = true;
  hintEl.hidden = true;
  if (!place.media) return showFallback();

  if (place.type === '360') {
    try {
      // Lazy : Pannellum (UMD → window.pannellum) + son CSS, au premier besoin.
      await Promise.all([
        import('pannellum/build/pannellum.js'),
        ensurePannellumStyles(),
      ]);
      if (request !== mediaRequest) return;
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
      if (request === mediaRequest) showFallback();
    }
  } else if (place.type === 'photo') {
    const img = document.createElement('img');
    img.loading = 'eager';
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

function renderPlace(placeId) {
  const place = placeById[placeId];
  if (!place) return;
  currentPlaceId = place.id;
  const index = DATA.places.findIndex((candidate) => candidate.id === place.id);
  titleEl.textContent = place.name;
  badgeEl.textContent = badgeForType(place.type, DATA);
  descEl.textContent = place.desc;
  creditEl.textContent = place.credit ? `${DATA.creditPrefix} ${place.credit}` : '';
  counterEl.textContent = counterLabel(index, DATA.places.length, DATA.counter);
  mountMedia(place);
}

function navigateViewer(direction) {
  const nextId = adjacentPlaceId(DATA.places, currentPlaceId, direction);
  if (nextId) renderPlace(nextId);
}

function openModal(placeId, trigger) {
  const place = placeById[placeId];
  if (!place || open) return;
  open = true;
  lastTrigger = trigger;

  modal.hidden = false;
  setBackgroundInert(true);
  lenis?.stop();
  document.body.style.overflow = 'hidden';
  renderPlace(place.id);

  if (!shouldAnimateModalOpen(reducedMotion, trigger)) {
    gsap.set(backdrop, { opacity: 0.92 });
    gsap.set(panel, { opacity: 1, scale: 1 });
  } else if (!trigger) {
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
    destroyMedia();                       // stoppe la vidéo, libère Pannellum
    if (map) map.selectedAnnotation = null;  // désélectionne le pin de la carte
    setBackgroundInert(false);
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
previousButton.addEventListener('click', () => navigateViewer(-1));
nextButton.addEventListener('click', () => navigateViewer(1));

document.addEventListener('keydown', (e) => {
  if (!open) return;
  if (e.key === 'Escape') return closeModal();
  if (e.target.matches('input, textarea, select, video')) return;
  if (e.key === 'ArrowLeft') {
    e.preventDefault();
    navigateViewer(-1);
    return;
  }
  if (e.key === 'ArrowRight') {
    e.preventDefault();
    navigateViewer(1);
    return;
  }
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
