import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import Lenis from 'lenis';

gsap.registerPlugin(ScrollTrigger);

// ── Reduced motion — site entièrement statique ─────────────────────────────
// Ni Lenis ni GSAP : les fallbacks CSS (@media prefers-reduced-motion dans
// global.css) rendent tout visible et masquent preloader/curseur custom.
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

if (!reducedMotion) {

// ── Lenis smooth scroll ─────────────────────────────────────────────────────
const lenis = new Lenis({ lerp: 0.08, smoothWheel: true });
lenis.on('scroll', ScrollTrigger.update);
gsap.ticker.add(time => lenis.raf(time * 1000));
gsap.ticker.lagSmoothing(0);

// ── Scroll progress bar ─────────────────────────────────────────────────────
const progressBarEl = document.querySelector('.progress-bar');
if (progressBarEl) {
  lenis.on('scroll', ({ progress }) => {
    progressBarEl.style.width = `${progress * 100}%`;
  });
}

// ── Image velocity warp — images skew with scroll momentum ─────────────────
// (la vidéo hero est exclue : son mouvement vient du clip lui-même)
lenis.on('scroll', ({ velocity }) => {
  gsap.to('.gallery-frame img', {
    skewY: velocity * 0.22,
    ease: 'power3.out',
    duration: 0.9,
    overwrite: 'auto',
  });
});

// ── Nav glass on scroll ─────────────────────────────────────────────────────
const nav = document.querySelector('.nav');
ScrollTrigger.create({
  start: 'top -60px',
  onEnter:     () => nav?.classList.add('nav--scrolled'),
  onLeaveBack: () => nav?.classList.remove('nav--scrolled'),
});

// ── Custom cursor ───────────────────────────────────────────────────────────
const cursorDot   = document.querySelector('.cursor-dot');
const cursorRing  = document.querySelector('.cursor-ring');
const cursorLabel = document.querySelector('.cursor-label');

if (cursorDot && cursorRing && window.matchMedia('(pointer: fine)').matches) {
  document.addEventListener('mousemove', e => {
    gsap.to(cursorDot,  { x: e.clientX, y: e.clientY, duration: 0.04, overwrite: true });
    gsap.to(cursorRing, { x: e.clientX, y: e.clientY, duration: 0.32, ease: 'power2.out', overwrite: true });
    if (cursorLabel) gsap.to(cursorLabel, { x: e.clientX, y: e.clientY, duration: 0.04, overwrite: true });
  });

  document.querySelectorAll('a, .gallery-frame').forEach(el => {
    const isGallery = el.classList.contains('gallery-frame');
    el.addEventListener('mouseenter', () => {
      gsap.to(cursorRing, { scale: 2.4, opacity: 0.45, borderColor: 'oklch(94% 0.29 128)', duration: 0.3 });
      gsap.to(cursorDot,  { opacity: 0, scale: 0, duration: 0.2 });
      if (cursorLabel && isGallery) gsap.to(cursorLabel, { opacity: 1, duration: 0.25 });
    });
    el.addEventListener('mouseleave', () => {
      gsap.to(cursorRing, { scale: 1, opacity: 1, borderColor: 'oklch(97% 0.003 130 / 0.28)', duration: 0.38 });
      gsap.to(cursorDot,  { opacity: 1, scale: 1, duration: 0.28 });
      if (cursorLabel) gsap.to(cursorLabel, { opacity: 0, duration: 0.2 });
    });
  });
}

// ── Text scramble ───────────────────────────────────────────────────────────
const SCRAMBLE_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@.-_';

function scramble(el, duration = 0.72) {
  const original = el.dataset.original ?? el.textContent;
  el.dataset.original = original;
  const start = performance.now();
  let raf;
  const tick = () => {
    const t = Math.min(1, (performance.now() - start) / (duration * 1000));
    el.textContent = [...original].map((ch, i) => {
      if (ch === ' ') return ' ';
      return i / original.length < t
        ? ch
        : SCRAMBLE_CHARS[Math.floor(Math.random() * SCRAMBLE_CHARS.length)];
    }).join('');
    if (t < 1) { raf = requestAnimationFrame(tick); }
    else        { el.textContent = original; }
  };
  cancelAnimationFrame(raf);
  raf = requestAnimationFrame(tick);
}

// ── Utility: split into char spans ─────────────────────────────────────────
function splitChars(el) {
  const text = el.textContent ?? '';
  el.textContent = '';
  el.setAttribute('aria-label', text);
  return [...text].map(char => {
    const s = document.createElement('span');
    s.textContent = char === ' ' ? ' ' : char;
    s.style.display = 'inline-block';
    s.setAttribute('aria-hidden', 'true');
    el.appendChild(s);
    return s;
  });
}

// ── Utility: split into masked word spans (preserves <br> elements) ─────────
function splitWords(el) {
  // Walk child nodes so <br> elements are preserved as actual DOM nodes
  const segments = [];
  el.childNodes.forEach(node => {
    if (node.nodeType === Node.TEXT_NODE) {
      node.textContent.split(/(\s+)/).forEach(chunk => {
        if (!chunk) return;
        segments.push({ type: /^\s+$/.test(chunk) ? 'space' : 'word', value: chunk });
      });
    } else if (node.nodeName === 'BR') {
      segments.push({ type: 'br' });
    }
  });

  const fullText = segments.map(s => s.type === 'br' ? '\n' : s.value).join('');
  el.textContent = '';
  el.setAttribute('aria-label', fullText.trim().replace(/\n/g, ' '));

  const inners = [];
  segments.forEach(seg => {
    if (seg.type === 'br') {
      el.appendChild(document.createElement('br'));
    } else if (seg.type === 'space') {
      el.appendChild(document.createTextNode(seg.value));
    } else {
      const outer = document.createElement('span');
      outer.style.cssText = 'display:inline-block;overflow:hidden;vertical-align:bottom;line-height:1.1;padding-bottom:0.05em;';
      const inner = document.createElement('span');
      inner.style.display = 'inline-block';
      inner.setAttribute('aria-hidden', 'true');
      inner.textContent = seg.value;
      outer.appendChild(inner);
      el.appendChild(outer);
      inners.push(inner);
    }
  });

  return inners;
}

// ── Preloader + Hero sequence ────────────────────────────────────────────────
const preloader     = document.querySelector('.preloader');
const preloaderIso  = document.querySelector('.preloader-iso');
const preloaderNord = document.querySelector('.preloader-nord');
const preloaderNum  = document.querySelector('.preloader-num');
const heroBgMedia   = document.querySelector('.hero-bg video, .hero-bg img');

lenis.stop();

const heroTitle     = document.querySelector('.hero-title');
const heroSubtitle  = document.querySelector('.hero-subtitle');
const titleChars    = heroTitle    ? splitChars(heroTitle)    : [];
const subtitleWords = heroSubtitle ? splitWords(heroSubtitle) : [];

gsap.set(titleChars,    { opacity: 0, y: 65, rotateX: -65, transformPerspective: 450, transformOrigin: '50% 100%' });
gsap.set(subtitleWords, { y: '115%' });
// Les parents .gsap-hero-text démarrent à opacity 0 en CSS (anti-FOUC) ;
// une fois les chars/words masqués individuellement, on peut les révéler.
gsap.set([heroTitle, heroSubtitle].filter(Boolean), { opacity: 1 });
gsap.set('.hero-coords',      { opacity: 0, x: 14 });
gsap.set('.hero-scroll-hint', { opacity: 0 });
gsap.set('.nav',              { yPercent: -120, opacity: 0 });
if (heroBgMedia) gsap.set(heroBgMedia, { scale: 1.06 });

// Preloader intro: ISO slides from top, NORD from bottom
if (preloaderIso && preloaderNord) {
  gsap.set(preloaderIso,  { y: -30, opacity: 0 });
  gsap.set(preloaderNord, { y: 30, opacity: 0 });
  gsap.timeline()
    .to(preloaderIso,  { y: 0, opacity: 1, duration: 0.62, ease: 'power3.out' })
    .to(preloaderNord, { y: 0, opacity: 1, duration: 0.62, ease: 'power3.out' }, '<+0.08');
}

const masterTL = gsap.timeline({
  onComplete: () => { lenis.start(); ScrollTrigger.refresh(); },
});

// Counter 000 → 100
if (preloaderNum) {
  const numObj = { v: 0 };
  gsap.to(numObj, {
    v: 100, duration: 1.15, ease: 'power2.inOut', delay: 0.12,
    onUpdate() { preloaderNum.textContent = String(Math.round(numObj.v)).padStart(3, '0'); },
  });
}

if (preloader) {
  masterTL
    .to(preloaderIso  ?? [], { opacity: 0, y: -32, duration: 0.42, ease: 'power2.in' }, 0.68)
    .to(preloaderNord ?? [], { opacity: 0, y: 32,  duration: 0.42, ease: 'power2.in' }, 0.68)
    .to(preloader, { yPercent: -100, duration: 0.82, ease: 'expo.inOut' }, 0.98)
    .set(preloader, { display: 'none' })
    .addLabel('heroEnter', '-=0.48');
}

const heroEnterPos = preloader ? 'heroEnter' : 0.1;

masterTL
  .to('.nav', { yPercent: 0, opacity: 1, duration: 0.65, ease: 'power3.out' }, heroEnterPos)
  .to(titleChars, {
    opacity: 1, y: 0, rotateX: 0,
    duration: 1.45, stagger: 0.042, ease: 'power4.out',
  }, heroEnterPos)
  .to(subtitleWords, {
    y: '0%', duration: 0.75, stagger: 0.048, ease: 'power3.out',
  }, '-=1.05')
  .to('.hero-coords', {
    opacity: 1, x: 0, duration: 0.9, ease: 'power2.out',
  }, '-=0.8')
  .to('.hero-scroll-hint', {
    opacity: 1, duration: 0.9, ease: 'power2.out',
  }, '-=0.55');

// Settle d'entrée — léger dézoom pendant le reveal
// (doux : la vidéo porte déjà son propre push-in cinématique)
if (heroBgMedia) {
  masterTL.to(heroBgMedia, { scale: 1.0, duration: 2.8, ease: 'power3.out' }, 0.2);
}

// Subtle hero title float after load
masterTL.call(() => {
  gsap.to(heroTitle, {
    y: '-=7',
    duration: 4.2,
    ease: 'sine.inOut',
    yoyo: true,
    repeat: -1,
  });
}, [], '+=0.4');

// ── Hero pinned — la vidéo reste sticky, le titre s'estompe au scroll ──────
// (immediateRender: false pour ne pas écraser l'animation d'entrée au refresh)
gsap.fromTo('.hero-inner',
  { opacity: 1, y: 0 },
  {
    opacity: 0, y: -46, ease: 'none', immediateRender: false,
    scrollTrigger: { trigger: '.hero-section', start: 'top top', end: '+=55%', scrub: 1.2 },
  }
);

gsap.fromTo(['.hero-coords', '.hero-scroll-hint'],
  { opacity: 1 },
  {
    opacity: 0, ease: 'none', immediateRender: false,
    scrollTrigger: { trigger: '.hero-section', start: 'top top', end: '+=35%', scrub: 1 },
  }
);

// ── Chapitres — reveal par-dessus la vidéo épinglée ─────────────────────────
document.querySelectorAll('.hero-chapter-inner').forEach(el => {
  gsap.to(el, {
    opacity: 1, y: 0, duration: 1.1, ease: 'power3.out',
    scrollTrigger: { trigger: el.parentElement, start: 'top 80%', toggleActions: 'play none none reverse' },
  });
});

// ── Veil de sortie — fond la vidéo dans --bg avant la fin de la section ─────
gsap.to('.hero-exit-veil', {
  opacity: 1, ease: 'none',
  scrollTrigger: { trigger: '.hero-section', start: 'bottom 165%', end: 'bottom 100%', scrub: 1 },
});

// ── Section labels — staggered char reveal ───────────────────────────────────
document.querySelectorAll('.section-label').forEach(el => {
  const chars = splitChars(el);
  gsap.set(chars, { opacity: 0, y: 10 });
  gsap.to(chars, {
    opacity: 1, y: 0,
    duration: 0.45, stagger: 0.038, ease: 'power2.out',
    scrollTrigger: { trigger: el, start: 'top 90%', once: true },
  });
});

// ── Sections — scroll-triggered reveal ──────────────────────────────────────
gsap.utils.toArray('.gsap-section').forEach(el => {
  const isAboutBlock  = el.classList.contains('about-block');
  const isServiceItem = el.classList.contains('service-item');

  if (isServiceItem) {
    gsap.set(el, { opacity: 1, y: 0, clipPath: 'inset(0 0 100% 0)' });
    gsap.to(el, {
      clipPath: 'inset(0 0 0% 0)',
      duration: 0.88, ease: 'power3.inOut',
      scrollTrigger: { trigger: el, start: 'top 90%', toggleActions: 'play none none reverse' },
    });
    return;
  }

  gsap.fromTo(el,
    { opacity: 0, y: isAboutBlock ? 0 : 55 },
    {
      opacity: 1, y: 0,
      duration: isAboutBlock ? 0.7 : 1.1, ease: 'power3.out',
      scrollTrigger: { trigger: el, start: 'top 82%', toggleActions: 'play none none reverse' },
    }
  );
});

// ── Pourquoi — word-by-word masked reveal ───────────────────────────────────
const whyStatementEl = document.querySelector('.why-statement');
if (whyStatementEl) {
  const words = splitWords(whyStatementEl);
  gsap.set(words, { y: '115%' });
  gsap.to(words, {
    y: '0%', duration: 0.62, stagger: 0.022, ease: 'power3.out',
    scrollTrigger: { trigger: whyStatementEl, start: 'top 78%', toggleActions: 'play none none reverse' },
  });
}

// ── Contact CTA — masked word reveal ────────────────────────────────────────
const contactCtaEl = document.querySelector('.contact-cta');
if (contactCtaEl) {
  const words = splitWords(contactCtaEl);
  gsap.set(words, { y: '115%' });
  gsap.to(words, {
    y: '0%', duration: 0.88, stagger: 0.12, ease: 'power3.out',
    scrollTrigger: { trigger: contactCtaEl, start: 'top 84%', once: true },
  });
}

// ── Contact links — scramble hover + magnetic ────────────────────────────────
document.querySelectorAll('.contact-link').forEach(link => {
  link.addEventListener('mouseenter', () => scramble(link));
  link.addEventListener('mousemove', e => {
    const r = link.getBoundingClientRect();
    const x = (e.clientX - r.left - r.width  / 2) * 0.28;
    const y = (e.clientY - r.top  - r.height / 2) * 0.28;
    gsap.to(link, { x, y, duration: 0.38, ease: 'power2.out', overwrite: true });
  });
  link.addEventListener('mouseleave', () => {
    gsap.to(link, { x: 0, y: 0, duration: 0.65, ease: 'elastic.out(1, 0.45)', overwrite: true });
  });
});

// ── Gallery — horizontal pin (desktop) / vertical grid (mobile) ─────────────
const galleryFrames = gsap.utils.toArray('.gallery-frame');
const galleryTrack  = document.querySelector('.gallery-track');
const galleryPin    = document.querySelector('.gallery-pin');
const isDesktop     = window.matchMedia('(min-width: 769px)').matches;

if (galleryTrack && galleryPin && galleryFrames.length && isDesktop) {

  // Gallery progress bar
  const galleryProgress = document.createElement('div');
  galleryProgress.className = 'gallery-progress';
  const galleryProgressFill = document.createElement('div');
  galleryProgressFill.className = 'gallery-progress-fill';
  galleryProgress.appendChild(galleryProgressFill);
  galleryPin.appendChild(galleryProgress);

  gsap.set(galleryFrames, { clipPath: 'inset(0 0 0 100%)' });

  galleryFrames.forEach(frame => {
    const img = frame.querySelector('img');
    if (img) gsap.set(img, { scale: 1.12, xPercent: -7 });
  });

  const getScrollAmt = () => -(galleryTrack.scrollWidth - window.innerWidth);

  const hScroll = gsap.to(galleryTrack, {
    x: getScrollAmt,
    ease: 'none',
    scrollTrigger: {
      trigger: galleryPin,
      start: 'top top',
      end: () => `+=${galleryTrack.scrollWidth - window.innerWidth}`,
      pin: true,
      scrub: 1.2,
      anticipatePin: 1,
      invalidateOnRefresh: true,
      onUpdate: self => {
        galleryProgressFill.style.width = `${self.progress * 100}%`;
      },
    },
  });

  // Clip-path reveal per frame
  galleryFrames.forEach(frame => {
    const img = frame.querySelector('img');
    ScrollTrigger.create({
      trigger: frame,
      containerAnimation: hScroll,
      start: 'left 95%',
      once: true,
      onEnter: () => {
        gsap.to(frame, { clipPath: 'inset(0 0 0 0%)', duration: 0.92, ease: 'power3.inOut' });
        if (img) gsap.to(img, { scale: 1.0, duration: 1.5, ease: 'power2.out' });
      },
    });
  });

  // Active frame — scale up frame centered in viewport
  galleryFrames.forEach(frame => {
    ScrollTrigger.create({
      trigger: frame,
      containerAnimation: hScroll,
      start: 'left 55%',
      end: 'right 55%',
      onToggle: ({ isActive }) => {
        gsap.to(frame, {
          scale: isActive ? 1.028 : 1,
          duration: 0.55,
          ease: 'power2.out',
          overwrite: true,
        });
      },
    });
  });

  // Image parallax
  galleryFrames.forEach(frame => {
    const img = frame.querySelector('img');
    if (!img) return;
    gsap.to(img, {
      xPercent: 7, ease: 'none',
      scrollTrigger: {
        trigger: frame,
        containerAnimation: hScroll,
        start: 'left right',
        end: 'right left',
        scrub: 1.6,
      },
    });
  });

  // 3D tilt on hover
  galleryFrames.forEach(frame => {
    frame.addEventListener('mousemove', e => {
      const r = frame.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width  - 0.5;
      const y = (e.clientY - r.top)  / r.height - 0.5;
      gsap.to(frame, {
        rotateX: -y * 10,
        rotateY:  x * 10,
        transformPerspective: 900,
        duration: 0.4,
        ease: 'power2.out',
        overwrite: true,
      });
    });
    frame.addEventListener('mouseleave', () => {
      gsap.to(frame, {
        rotateX: 0, rotateY: 0,
        duration: 0.85,
        ease: 'power3.out',
        overwrite: true,
      });
    });
  });

  const countEl = document.querySelector('.gallery-count');
  if (countEl) {
    const obj = { v: 0 };
    gsap.to(obj, {
      v: 10, duration: 1.5, ease: 'power2.out',
      scrollTrigger: { trigger: galleryPin, start: 'top 88%', once: true },
      onUpdate() { countEl.textContent = `${String(Math.round(obj.v)).padStart(3, '0')} frames`; },
    });
  }

} else if (galleryFrames.length && !isDesktop) {

  gsap.set(galleryFrames, { clipPath: 'inset(0 0 100% 0)' });
  galleryFrames.forEach(frame => {
    const img = frame.querySelector('img');
    if (img) gsap.set(img, { scale: 1.12 });
  });

  ScrollTrigger.batch(galleryFrames, {
    start: 'top 90%',
    onEnter: batch => {
      gsap.to(batch, { clipPath: 'inset(0 0 0% 0)', duration: 1.05, ease: 'power3.inOut', stagger: 0.1 });
      batch.forEach(frame => {
        const img = frame.querySelector('img');
        if (img) gsap.to(img, { scale: 1.0, duration: 1.4, ease: 'power2.out' });
      });
    },
  });

  galleryFrames.forEach(frame => {
    const img = frame.querySelector('img');
    if (!img) return;
    gsap.fromTo(img,
      { yPercent: -7 },
      {
        yPercent: 7, ease: 'none',
        scrollTrigger: { trigger: frame, start: 'top bottom', end: 'bottom top', scrub: 1.6 },
      }
    );
  });

  const countEl = document.querySelector('.gallery-count');
  if (countEl) {
    const obj = { v: 0 };
    gsap.to(obj, {
      v: 10, duration: 1.5, ease: 'power2.out',
      scrollTrigger: { trigger: countEl, start: 'top 88%', once: true },
      onUpdate() { countEl.textContent = `${String(Math.round(obj.v)).padStart(3, '0')} frames`; },
    });
  }
}

// ── Marquee — speed tied to scroll velocity ───────────────────────────────────
const marqueeTrack = document.querySelector('.marquee-track');
if (marqueeTrack) {
  lenis.on('scroll', ({ velocity }) => {
    const speed = Math.max(8, 22 - Math.abs(velocity) * 5);
    marqueeTrack.style.animationDuration = `${speed}s`;
  });
}

} // fin du garde prefers-reduced-motion
