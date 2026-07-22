import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import Lenis from 'lenis';

gsap.registerPlugin(ScrollTrigger);

const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

let lenis = null;

if (!reducedMotion) {
  // ── Smooth scroll ──────────────────────────────────────────────────────────
  lenis = new Lenis({ lerp: 0.09, smoothWheel: true });
  lenis.on('scroll', ScrollTrigger.update);
  gsap.ticker.add(t => lenis.raf(t * 1000));
  gsap.ticker.lagSmoothing(0);

  const progressBar = document.querySelector('.progress-bar');
  if (progressBar) {
    lenis.on('scroll', ({ progress }) => {
      progressBar.style.width = `${progress * 100}%`;
    });
  }

  // ── Nav — bandeau flou dès qu'on quitte le haut ─────────────────────────────
  const nav = document.querySelector('.pf-nav');
  if (nav) {
    const onScroll = ({ scroll }) => nav.classList.toggle('nav--scrolled', (scroll ?? window.scrollY) > 40);
    lenis.on('scroll', onScroll);
    onScroll({ scroll: window.scrollY });
  }

  // ── Custom cursor ───────────────────────────────────────────────────────────
  const dot = document.querySelector('.cursor-dot');
  const ring = document.querySelector('.cursor-ring');
  if (dot && ring && window.matchMedia('(pointer: fine)').matches) {
    document.addEventListener('mousemove', e => {
      gsap.to(dot,  { x: e.clientX, y: e.clientY, duration: 0.04, overwrite: true });
      gsap.to(ring, { x: e.clientX, y: e.clientY, duration: 0.34, ease: 'power2.out', overwrite: true });
    });
    document.querySelectorAll('a, button').forEach(el => {
      el.addEventListener('mouseenter', () => {
        gsap.to(ring, { scale: 2.3, opacity: 0.4, duration: 0.3 });
        gsap.to(dot,  { scale: 0, opacity: 0, duration: 0.2 });
      });
      el.addEventListener('mouseleave', () => {
        gsap.to(ring, { scale: 1, opacity: 1, duration: 0.38 });
        gsap.to(dot,  { scale: 1, opacity: 1, duration: 0.28 });
      });
    });
  }

  // ── Hero reveal ─────────────────────────────────────────────────────────────
  const heroBits = gsap.utils.toArray('.pf-eyebrow, .pf-title, .pf-lede, .pf-count');
  gsap.set(heroBits, { opacity: 0, y: 40 });
  gsap.to(heroBits, {
    opacity: 1, y: 0, duration: 1.1, stagger: 0.1, ease: 'power3.out', delay: 0.15,
  });

  // ── Frames reveal au scroll ─────────────────────────────────────────────────
  gsap.utils.toArray('.pf-frame').forEach(frame => {
    gsap.set(frame, { opacity: 0, y: 54 });
    gsap.to(frame, {
      opacity: 1, y: 0, duration: 1.0, ease: 'power3.out',
      scrollTrigger: { trigger: frame, start: 'top 90%', toggleActions: 'play none none reverse' },
    });
  });

  // ── CTA reveal ──────────────────────────────────────────────────────────────
  gsap.utils.toArray('.pf-cta__eyebrow, .pf-cta__link').forEach(el => {
    gsap.set(el, { opacity: 0, y: 30 });
    gsap.to(el, {
      opacity: 1, y: 0, duration: 0.9, ease: 'power3.out',
      scrollTrigger: { trigger: '.pf-cta', start: 'top 85%', toggleActions: 'play none none reverse' },
    });
  });
}

// ── Lightbox (toujours actif — c'est de l'interaction, pas de l'animation) ────
(() => {
  const lightbox = document.querySelector('.pf-lightbox');
  const frames = Array.from(document.querySelectorAll('.pf-frame'));
  if (!lightbox || frames.length === 0) return;

  const lbImg = lightbox.querySelector('.pf-lb__img');
  const lbCat = lightbox.querySelector('.pf-lb__cat');
  const lbNum = lightbox.querySelector('.pf-lb__num');
  const btnClose = lightbox.querySelector('.pf-lb__close');
  const btnPrev = lightbox.querySelector('.pf-lb__nav--prev');
  const btnNext = lightbox.querySelector('.pf-lb__nav--next');

  let current = 0;
  let lastFocus = null;

  const render = (i) => {
    current = (i + frames.length) % frames.length;
    const img = frames[current].querySelector('img');
    lbImg.src = img.src;
    lbImg.alt = img.alt;
    if (lbCat) lbCat.textContent = img.dataset.cat || '';
    if (lbNum) lbNum.textContent = img.dataset.num || '';
  };

  const open = (i) => {
    lastFocus = document.activeElement;
    render(i);
    lightbox.hidden = false;
    requestAnimationFrame(() => lightbox.classList.add('is-open'));
    document.body.style.overflow = 'hidden';
    if (lenis) lenis.stop();
    btnClose.focus();
  };

  const close = () => {
    lightbox.classList.remove('is-open');
    document.body.style.overflow = '';
    if (lenis) lenis.start();
    const done = () => { lightbox.hidden = true; lightbox.removeEventListener('transitionend', done); };
    lightbox.addEventListener('transitionend', done);
    // fallback si la transition ne se déclenche pas
    setTimeout(() => { if (lightbox.classList.contains('is-open') === false) lightbox.hidden = true; }, 400);
    if (lastFocus && lastFocus.focus) lastFocus.focus();
  };

  frames.forEach((frame, i) => frame.addEventListener('click', () => open(i)));
  btnClose.addEventListener('click', close);
  btnPrev.addEventListener('click', () => render(current - 1));
  btnNext.addEventListener('click', () => render(current + 1));
  lightbox.addEventListener('click', (e) => { if (e.target === lightbox) close(); });

  document.addEventListener('keydown', (e) => {
    if (lightbox.hidden) return;
    if (e.key === 'Escape') close();
    else if (e.key === 'ArrowLeft') render(current - 1);
    else if (e.key === 'ArrowRight') render(current + 1);
  });
})();
