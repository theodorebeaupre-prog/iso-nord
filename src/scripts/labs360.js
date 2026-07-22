/**
 * Labs 360 — interactions de la page carte.
 *
 * - Lenis + reveals GSAP (mêmes réglages que labs.js)
 * - Sélecteur Québec/Montréal (cross-fade des pins, hash partageable)
 * - Modal viewer : Pannellum (dynamic import, seulement au premier pin 360)
 *   ou <video>, focus piégé, Échap/backdrop, focus restitué au déclencheur.
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

  // Reveal de la carte à l'entrée dans le viewport. IntersectionObserver
  // plutôt que ScrollTrigger : insensible aux sauts de scroll virtualisés
  // par Lenis, et l'état final (opacity 1) est garanti une fois joué.
  const mapEl = document.querySelector('.l360-map');
  gsap.set(mapEl, { opacity: 0, y: 32 });
  const io = new IntersectionObserver((entries) => {
    if (!entries[0].isIntersecting) return;
    io.disconnect();
    gsap.to(mapEl, { opacity: 1, y: 0, duration: 1, ease: 'power3.out' });
  }, { rootMargin: '0px 0px -15% 0px' });
  io.observe(mapEl);
}

/* ── Sélecteur de ville ───────────────────────────────────────────────────── */
const cityButtons = [...document.querySelectorAll('[data-city-btn]')];
const pinGroups = [...document.querySelectorAll('.l360-pins')];
const legends = [...document.querySelectorAll('[data-legend-city]')];

function showCity(city) {
  cityButtons.forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.cityBtn === city)));
  legends.forEach((leg) => { leg.hidden = leg.dataset.legendCity !== city; });
  pinGroups.forEach((g) => {
    const active = g.dataset.city === city;
    if (active === !g.hidden) return;               // déjà dans le bon état
    if (reducedMotion) { g.hidden = !active; return; }
    if (active) {
      g.hidden = false;
      gsap.fromTo(g.querySelectorAll('.l360-pin'),
        { opacity: 0, scale: 0.6 },
        { opacity: 1, scale: 1, duration: 0.4, stagger: 0.06, ease: 'back.out(1.7)' });
    } else {
      gsap.to(g.querySelectorAll('.l360-pin'), {
        opacity: 0, scale: 0.6, duration: 0.2, ease: 'power2.in',
        onComplete: () => { g.hidden = true; },
      });
    }
  });
  history.replaceState(null, '', `#${city}`);       // état partageable
}
cityButtons.forEach((b) => b.addEventListener('click', () => showCity(b.dataset.cityBtn)));
if (location.hash === '#montreal') showCity('montreal');

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
let lastTrigger = null;     // bouton à re-focus à la fermeture
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
      // L'indice disparaît au premier drag — mousedown ET touchstart, car
      // certains environnements n'émettent pas d'événements pointer.
      // capture: true — Pannellum consomme le mousedown sur son canvas ;
      // en phase capture on passe avant lui, garanti.
      const hideHint = () => { hintEl.hidden = true; };
      host.addEventListener('mousedown', hideHint, { once: true, capture: true });
      host.addEventListener('touchstart', hideHint, { once: true, capture: true, passive: true });
    } catch {
      showFallback();
    }
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

  if (reducedMotion) {
    gsap.set([backdrop, panel], { opacity: 1, scale: 1 });
  } else {
    // Le panneau émerge depuis le pin : origin = centre du déclencheur.
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
    lenis?.start();
    document.body.style.overflow = '';
    lastTrigger?.focus();
  };
  if (reducedMotion) return done();
  gsap.to(panel, { opacity: 0, scale: 0.92, duration: 0.28, ease: 'power2.in' });
  gsap.to(backdrop, { opacity: 0, duration: 0.3, delay: 0.05, onComplete: done });
}

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
