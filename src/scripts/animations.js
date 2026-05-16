import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

gsap.registerPlugin(ScrollTrigger);

document.addEventListener('DOMContentLoaded', () => {

  // ── Hero text — fade + rise on load, no ScrollTrigger ──────────────────
  // Targets h1.hero-title and p.hero-subtitle (both have .gsap-hero-text)
  const heroEls = gsap.utils.toArray('.gsap-hero-text');

  heroEls.forEach((el, i) => {
    gsap.fromTo(
      el,
      { opacity: 0, y: 60 },
      {
        opacity: 1,
        y: 0,
        duration: 2,
        delay: i === 0 ? 0.3 : 0.8,
        ease: 'power3.out',
      }
    );
  });

  // ── Sections — scroll-triggered fade + rise ─────────────────────────────
  // Targets .service-item, .about-block, .contact-block (all have .gsap-section)
  gsap.utils.toArray('.gsap-section').forEach((el) => {
    gsap.fromTo(
      el,
      { opacity: 0, y: 60 },
      {
        opacity: 1,
        y: 0,
        duration: 1.2,
        ease: 'power3.out',
        scrollTrigger: {
          trigger: el,
          start: 'top 80%',
          toggleActions: 'play none none reverse',
        },
      }
    );
  });

  // ── Gallery items — staggered scroll-triggered fade + rise ──────────────
  // Targets the 6 .gallery-cell divs (all have .gsap-gallery-item)
  const galleryItems = gsap.utils.toArray('.gsap-gallery-item');

  if (galleryItems.length) {
    gsap.fromTo(
      galleryItems,
      { opacity: 0, y: 40, scale: 0.97 },
      {
        opacity: 1,
        y: 0,
        scale: 1,
        duration: 1,
        ease: 'power2.out',
        stagger: 0.08,
        scrollTrigger: {
          trigger: galleryItems[0].parentElement || galleryItems[0],
          start: 'top 85%',
          toggleActions: 'play none none reverse',
        },
      }
    );
  }

  // Refresh after all animations are registered so ScrollTrigger
  // recalculates positions with the final layout
  ScrollTrigger.refresh();
});
