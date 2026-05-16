# ISO Nord — Shared AI Workspace

## Project
- Brand: ISO Nord
- Domain: theo-picture.com
- Instagram: @theo_totk
- Stack: Astro v6 + GSAP + Tailwind CDN
- Node: ~/iso-nord/

## Design System
- Background: #09090b
- Text: #f5f5f5
- Accent: #c8ff00 (lime, utiliser avec parcimonie)
- Secondary text: #888888
- Font: Helvetica Neue, weight 200–400
- Style: Nordic minimalist, cinematic, slow

## Sections (dans l'ordre)
1. Hero — fullscreen, titre animé, sous-titre
2. Services — photo, vidéo, drone
3. Gallery — grid 3 colonnes, images lazy-loaded
4. About — texte minimaliste
5. Contact — email + Instagram

## Animation Rules (GSAP)
- Toutes les sections: fade-in + translateY(60px) → 0
- Hero title: opacity 0 → 1, durée 2s, delay 0.3s
- ScrollTrigger start: "top 80%"
- toggleActions: "play none none reverse"
- Ease: power3.out

## File Structure
- src/pages/index.astro → HTML + layout (Claude Code owns this)
- src/scripts/animations.js → GSAP logic only (Codex owns this)
- src/styles/global.css → CSS global (Claude Code owns this)
- public/assets/ → images et vidéos

## Handoff Protocol
- Claude Code écrit le HTML/structure dans index.astro
- Claude Code importe animations.js via <script src="/scripts/animations.js">
- Codex écrit UNIQUEMENT src/scripts/animations.js
- Aucun des deux ne touche au fichier de l'autre
- Les deux lisent claude.md pour rester alignés

## Status
- [ ] index.astro — structure HTML complète
- [ ] global.css — styles de base
- [x] animations.js — done by Codex
- [ ] Test scroll animations
- [ ] Mobile responsive
