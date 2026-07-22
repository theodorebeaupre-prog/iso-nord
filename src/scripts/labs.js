import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import Lenis from 'lenis';

gsap.registerPlugin(ScrollTrigger);

const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

if (!reducedMotion) {

  // ── Smooth scroll ──────────────────────────────────────────────────────────
  const lenis = new Lenis({ lerp: 0.09, smoothWheel: true });
  lenis.on('scroll', ScrollTrigger.update);
  gsap.ticker.add(t => lenis.raf(t * 1000));
  gsap.ticker.lagSmoothing(0);

  const progressBar = document.querySelector('.progress-bar');
  if (progressBar) {
    lenis.on('scroll', ({ progress }) => {
      progressBar.style.width = `${progress * 100}%`;
    });
  }

  // ── Custom cursor (dark, pour fond clair) ──────────────────────────────────
  const dot = document.querySelector('.cursor-dot');
  const ring = document.querySelector('.cursor-ring');
  if (dot && ring && window.matchMedia('(pointer: fine)').matches) {
    document.addEventListener('mousemove', e => {
      gsap.to(dot,  { x: e.clientX, y: e.clientY, duration: 0.04, overwrite: true });
      gsap.to(ring, { x: e.clientX, y: e.clientY, duration: 0.34, ease: 'power2.out', overwrite: true });
    });
    document.querySelectorAll('a').forEach(el => {
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

  // ── Bloom parallax — le motif dérive doucement au scroll ────────────────────
  const bloom = document.querySelector('.labs-hero .bloom');
  if (bloom) {
    gsap.to(bloom, {
      yPercent: 12, ease: 'none',
      scrollTrigger: { trigger: '.labs-hero', start: 'top top', end: 'bottom top', scrub: 1.1 },
    });
  }

  // ── Hero — reveal masqué mot à mot du titre ─────────────────────────────────
  const heroBits = gsap.utils.toArray('.labs-eyebrow, .labs-title, .labs-lede');
  gsap.set(heroBits, { opacity: 0, y: 40 });
  gsap.to(heroBits, {
    opacity: 1, y: 0, duration: 1.1, stagger: 0.12, ease: 'power3.out', delay: 0.15,
  });

  // ── Projets — reveal clip-path à l'entrée ───────────────────────────────────
  gsap.utils.toArray('.labs-item').forEach(item => {
    gsap.set(item, { opacity: 0, y: 48 });
    gsap.to(item, {
      opacity: 1, y: 0, duration: 0.9, ease: 'power3.out',
      scrollTrigger: { trigger: item, start: 'top 88%', toggleActions: 'play none none reverse' },
    });
  });
}
