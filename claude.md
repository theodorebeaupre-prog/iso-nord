# ISO Nord — Shared AI Workspace (refonte)

## Project
- Brand: ISO Nord (jamais « Théo Picture » dans le contenu visible)
- Positionnement: studio photo / vidéo / drone pour entreprises locales au Québec
- Domain: theo-picture.com
- Instagram: @iso_nord
- Stack: Astro, Tailwind 4, GSAP + Lenis
- Node: ~/iso-nord-astro/ (copie indépendante — NE PAS toucher ~/iso-nord/)

## Agents
- **Agent 1** : améliore les pages existantes (layout, contenu, SEO)
- **Agent 2** : ajoute des composants UI depuis https://21st.dev/community/components

### Règle de coordination
- Ne pas modifier les mêmes fichiers en même temps
- Les deux agents lisent CLAUDE.md pour rester alignés

## Design System
- Background: #141318 — charcoal cinématique mesuré sur le champ sombre de la
  vidéo hero. UNIFORME sur toutes les sections (pas d'alternance de fonds).
- Text: oklch(97% 0.002 305) / Muted: oklch(69% 0.006 305) / Dim: oklch(58% 0.006 305)
- Accent: #c8ff00 (lime, hover et détails seulement)
- Surface: #1d1c23 (panneau vedette Tarifs uniquement) / Border: #2b2a32
- Font: Helvetica Neue 200–400 (display) + Barlow Condensed 300–400 (labels)
- Style: dark cinematic, premium studio, local Québec — PAS de look SaaS
- Cards: JAMAIS de bordures boîte « AI generated ». Hiérarchie par spacing,
  typographie et contrastes ; hairlines grises fines seulement si utiles.

## Sections (dans l'ordre)
1. Hero — vidéo produit épinglée (`HeroVideo.astro`) : la vidéo reste sticky
   ~5 écrans, le titre s'estompe au scroll, 4 chapitres défilent par-dessus
   (Photo commerciale, Vidéo courte, Drone, Contenu réseaux sociaux), puis un
   veil fond le clip dans --bg.
2. Marquee — bandeau défilant
3. Services — liste éditoriale numérotée (4 items)
4. Processus — 4 étapes en grille
5. Réalisations — galerie horizontale épinglée GSAP (grille sur mobile)
6. Pourquoi ISO Nord — déclaration + 4 preuves
7. Tarifs — 3 forfaits ouverts, vedette sur panneau surface.
   Prix « à partir de » : Essentiel 495 $, Signature 1 950 $, Sur mesure
   sur devis. Indicatifs — ajuster librement selon le marché.
8. Labs — Logiciels — liste éditoriale des projets dev du studio
   (Co/Pad, Garmin GCD Toolkit, app iOS ISO Nord). Formulation « le studio »,
   pas de nom personnel.
9. CTA final — backdrop poster hero estompé + liens contact géants
10. Footer — wordmark / nav ancres / meta

## Assets hero
- public/assets/hero-camera.mp4 — 1920×1080, 10 s, h264 optimisé (~1.9 Mo)
- public/assets/hero-camera-poster.jpg — poster fallback (1ʳᵉ frame)

## Animation Rules (GSAP)
- Sections: fade-in + translateY(55–60px) → 0, start "top 80–82%",
  toggleActions "play none none reverse", ease power3.out
- Hero pinned: scrubs sur .hero-inner (fade), .hero-exit-veil (sortie),
  reveal des .hero-chapter-inner
- prefers-reduced-motion: animations.js n'initialise NI Lenis NI GSAP ;
  les fallbacks CSS (@media dans global.css) rendent tout visible et
  masquent preloader/curseur custom. La vidéo hero reste en pause (poster).

## Composants
- `src/components/HeroVideo.astro` — hero vidéo pinned (voir Sections)
- `src/components/CompareSlider.astro`, `LensZoom.astro`, `Testimonials.astro`
  — hérités de l'ancienne version, PLUS UTILISÉS sur la page (conservés au
  besoin, contenu Testimonials placeholder).

## File Structure
- src/pages/ → pages Astro (Agent 1)
- src/components/ → composants UI (Agent 2)
- src/scripts/animations.js → GSAP logic
- src/styles/global.css → CSS global
- public/assets/ → images et vidéos
