# Labs — « Québec en 360 » (labs-360-map) — Design

**Date :** 2026-07-22 · **Statut :** approuvé (structure + lib validées par Théo)

## But

Une nouvelle page Labs, `/labs/360` (FR) et `/en/labs/360` (EN) : une carte stylisée
des lieux iconiques de Québec et Montréal. Chaque lieu est un pin ; au clic on ouvre
soit un panorama 360° équirectangulaire (drone) explorable en drag, soit un clip
vidéo court en modal. Mobile-first — l'audience principale est sur téléphone.

## Contraintes validées

- Stack existant : Astro 6 + Tailwind v4 (tokens CSS custom) + GSAP + Lenis.
- Direction artistique : fond sombre (token site `--bg` #141318, proche du #0b0d0c
  demandé), accent lime `--accent` (#c8ff00), labels Barlow Condensed (`--font-label`).
- **Viewer 360 : Pannellum** (~21 KB gzip, zéro dépendance), installé via npm et
  chargé en *lazy* (dynamic import) uniquement à l'ouverture d'un pin 360.
- Pas de vraie API carte — fond custom avec grille subtile, pins en coordonnées `%`.
- Pas de backend. Données mock en TS ; URLs médias swappables via
  `PUBLIC_MEDIA_BASE` (Cloudflare R2 plus tard), fallback local `/assets/labs360`.
- Code propre et commenté (FR, comme le reste du repo) — Théo continue dessus.

## Architecture (patterns existants du repo)

```
src/
├── pages/labs/360.astro              → wrapper <Labs360 lang="fr" />
├── pages/en/labs/360.astro           → wrapper <Labs360 lang="en" />
├── components/pages/Labs360.astro    → page complète : nav, hero court, sélecteur
│                                       ville, carte + pins, modal viewer, footer
├── data/labs360.ts                   → lieux + MEDIA_BASE (le fichier que Théo édite)
├── scripts/labs360.js                → Lenis/GSAP + interactions (villes, pins, modal)
└── i18n/
    ├── ui.ts                         → + section `labs360` (fr/en) : chrome UI
    └── utils.ts                      → + `labs360` dans PAGES (pathFor, hreflang)
```

- Une seule page composant bilingue, comme `Labs.astro`/`Portfolio.astro`.
- `LangSwitch page="labs360"`, canonical + hreflang via `alternates('labs360')`.
- Sitemap : généré automatiquement par `@astrojs/sitemap`.

## Données (`src/data/labs360.ts`)

```ts
type Labs360Place = {
  id: string;                    // slug stable
  city: 'quebec' | 'montreal';
  type: '360' | 'video';
  name: string;                  // nom propre, identique fr/en
  desc: { fr: string; en: string };
  credit: string;                // '' ou '[contributeur]' par défaut
  x: number; y: number;          // position % sur la carte (0–100)
  media: string;                 // chemin relatif, préfixé par MEDIA_BASE
  poster?: string;               // affiche vidéo (optionnel)
};
export const MEDIA_BASE = import.meta.env.PUBLIC_MEDIA_BASE ?? '/assets/labs360';
```

7 lieux mock : Québec — Vieux-Québec (360), Chute Montmorency (360),
Île d'Orléans (video), Domaine de Maizerets (360) ; Montréal — Vieux-Port (360),
Mont-Royal (video), Centre-ville (video). Placeholders : panoramas équirectangulaires
synthétiques générés (2:1, dégradé ciel/sol + repères), vidéo = `hero-camera.mp4`
existant réutilisé.

## UI / interactions

1. **Hero court** : eyebrow « ISO Nord — Labs / 360 », titre display, lede — mêmes
   reveals GSAP que la page Labs.
2. **Sélecteur de ville** : deux boutons Barlow Condensed uppercase (Québec /
   Montréal), état actif lime + soulignement ; bascule = cross-fade GSAP des pins
   (stagger). État persisté dans l'URL (`#montreal`) pour partage.
3. **Carte stylisée** : panneau `--surface` bordé `--border`, grille SVG subtile
   (lignes fines type relevé topographique), grain `--grain` réutilisé, lat/long
   décoratifs dans les coins (style InstrumentHud). Ratio 4/5 mobile, 16/10 desktop.
4. **Pins** : `<button>` positionnés en `%` — point lime + anneau pulsant, label
   au hover/focus (desktop) et sous forme de légende tapable (mobile). Cible
   tactile ≥ 44 px. Badge type (⟳ 360 / ▶ clip).
5. **Modal viewer** (un seul overlay réutilisé) :
   - Ouverture : GSAP — le panneau s'étend depuis le pin (scale + clip), fond
     assombri ; fermeture inverse. `prefers-reduced-motion` → fondu simple.
   - Type `360` : dynamic import de Pannellum (js + css), rendu équirectangulaire,
     drag/touch, auto-rotate lent au repos, hint « glisser pour explorer ».
   - Type `video` : `<video controls playsinline>` + poster, lecture directe.
   - Fiche lieu : nom, description (langue courante), crédit « Capté par … » si non vide.
   - A11y : `role="dialog"` + `aria-modal`, focus piégé, Échap + clic hors panneau
     ferment, focus restitué au pin d'origine. Lenis stoppé pendant l'ouverture.
6. **Footer** : même motif que Labs (retour studio, mailto, copyright).

## Gestion d'erreurs

- Média introuvable : le modal affiche la fiche + message discret « média à venir »
  (les vrais fichiers arrivent plus tard) — pas d'écran cassé.
- Échec du chargement Pannellum (offline) : même repli.
- JS désactivé : la carte et la légende des lieux restent visibles (contenu SSR),
  les pins sont inertes — noscript acceptable pour une page Labs.

## Tests / vérification

Pas de suite de tests dans le repo — vérification par build Astro (8 → 10 pages),
puis passage navigateur : pins des deux villes, ouverture 360 (drag), ouverture
vidéo, fermeture (Échap/clic), mobile 375 px, `/en/labs/360`, console propre.

## Hors périmètre

Vrais médias R2, analytics, deep-links par lieu, clustering de pins, géolocalisation.
