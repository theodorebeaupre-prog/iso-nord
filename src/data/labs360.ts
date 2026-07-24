/**
 * Labs « Québec en 360 » — données des lieux.
 *
 * C'EST LE FICHIER À ÉDITER pour ajouter/retirer des lieux ou brancher les
 * vrais médias. Les chemins relatifs sont préfixés par MEDIA_BASE (variable
 * d'environnement PUBLIC_MEDIA_BASE → bucket Cloudflare R2 en production) ;
 * les chemins absolus (`/…` ou `https://…`) passent tels quels.
 *
 * Panorama 360 : image équirectangulaire 2:1 (drone). Vidéo : clip court MP4.
 * `lat`/`lon` : vraies coordonnées GPS du lieu — le pin se pose dessus sur la
 * carte satellite Apple Maps (MapKit JS). `iso360` les remplit automatiquement
 * depuis l'EXIF du panorama ; pour les autres, ce sont les coordonnées du lieu.
 * `credit` : contributeur de la capture — laisser '' tant que la collaboration
 * n'est pas confirmée (la ligne crédit est alors masquée dans le viewer).
 */

export type City = 'quebec';
export type PlaceType = '360' | 'video' | 'photo';

export interface Labs360Place {
  id: string;
  city: City;
  type: PlaceType;
  name: { fr: string; en: string };   // titre éditorial bilingue
  desc: { fr: string; en: string };
  credit: string;
  capturedAt: string;                  // mois de captation, format YYYY-MM
  lat: number;                        // latitude GPS
  lon: number;                        // longitude GPS
  media: string;
  preview: string;                    // dérivé WebP léger pour hero/collection
  previewWidth: number;
  previewHeight: number;
  featured?: boolean;
  poster?: string;                    // affiche (vidéo surtout)
}

/** Base des médias — surchargée par PUBLIC_MEDIA_BASE (Cloudflare R2). */
export const MEDIA_BASE: string =
  import.meta.env.PUBLIC_MEDIA_BASE ?? '/assets/labs360';

/** Résout un chemin média : relatif → MEDIA_BASE, absolu → inchangé. */
export const mediaUrl = (path: string): string =>
  !path || path.startsWith('http') || path.startsWith('/')
    ? path
    : `${MEDIA_BASE}/${path}`;

export const PLACES: Labs360Place[] = [
  // ── Québec ────────────────────────────────────────────────────────────────
  {
    id: 'maizerets',
    city: 'quebec',
    type: '360',
    name: {
      fr: 'Domaine de Maizerets — Le fleuve au couchant',
      en: 'Domaine de Maizerets — River at sunset',
    },
    desc: {
      fr: 'Le domaine et son arboretum, vus du ciel en fin de journée.',
      en: 'The estate and its arboretum, seen from above at dusk.',
    },
    credit: '',
    capturedAt: '2025-10',
    lat: 46.8360, lon: -71.2139,
    media: 'https://media.theo-picture.com/panoramas/maizerets-2025-10.jpg',
    preview: '/assets/labs360/previews/maizerets.webp',
    previewWidth: 1600,
    previewHeight: 800,
    featured: true,
  },
  {
    id: 'patro-roc-amadour',
    city: 'quebec',
    type: '360',
    name: {
      fr: 'Patro Roc-Amadour — Du terrain à la skyline',
      en: 'Patro Roc-Amadour — From the field to the skyline',
    },
    desc: {
      fr: 'Le Patro et le quartier Lairet à 100 m d’altitude — le Centre Vidéotron et la skyline de Québec à l’horizon.',
      en: 'The Patro and the Lairet neighbourhood from 100 m up — Centre Vidéotron and the Québec City skyline on the horizon.',
    },
    credit: '',
    capturedAt: '2026-06',
    lat: 46.8327, lon: -71.2445,
    // Vrai pano drone (28 juin 2026, GPS 46.8327 N 71.2445 W, stitché des
    // 35 segments DJI avec Hugin), servi via Cloudflare Tunnel.
    media: 'https://media.theo-picture.com/panoramas/patro-roc-amadour-2026.jpg',
    preview: '/assets/labs360/previews/patro-roc-amadour.webp',
    previewWidth: 1600,
    previewHeight: 800,
  },

  {
    id: "giffard",
    city: "quebec",
    type: '360',
    name: {
      fr: 'Giffard — Entre deux rives',
      en: 'Giffard — Between two shores',
    },
    desc: {
      fr: 'Giffard et Beauport \u00e0 400 m d\u2019altitude \u2014 le fleuve, l\u2019\u00eele d\u2019Orl\u00e9ans et Qu\u00e9bec \u00e0 l\u2019horizon.',
      en: 'Giffard and Beauport from 400 m up \u2014 the river, \u00cele d\u2019Orl\u00e9ans and Qu\u00e9bec City on the horizon.',
    },
    credit: '',
    capturedAt: '2025-10',
    lat: 46.849922222222226, lon: -71.21155555555556,
    // Pano drone auto-publié par iso360 (2025:10:25 13:07:26)
    media: "https://media.theo-picture.com/panoramas/giffard-2025-10.jpg",
    preview: '/assets/labs360/previews/giffard.webp',
    previewWidth: 1600,
    previewHeight: 800,
  },
  {
    id: 'centre-monseigneur-marcoux',
    city: 'quebec',
    type: '360',
    name: {
      fr: 'Monseigneur-Marcoux — Limoilou sous la neige',
      en: 'Monseigneur-Marcoux — Limoilou under snow',
    },
    desc: {
      fr: 'Le centre et le quartier Limoilou sous la neige, au coucher du soleil d’hiver.',
      en: 'The centre and the Limoilou neighbourhood under snow, at winter sunset.',
    },
    credit: '',
    capturedAt: '2025-12',
    lat: 46.8436, lon: -71.2235,
    // Pano drone DJI (14 déc 2025), servi via Cloudflare Tunnel.
    media: 'https://media.theo-picture.com/panoramas/centre-monseigneur-marcoux-2025-12.jpg',
    preview: '/assets/labs360/previews/centre-monseigneur-marcoux.webp',
    previewWidth: 1600,
    previewHeight: 800,
  },
  {
    id: "limoilou",
    city: "quebec",
    type: "photo",
    name: { fr: 'Limoilou', en: 'Limoilou' },
    desc: {
      fr: "Limoilou \u2014 vue a\u00e9rienne capt\u00e9e au drone.",
      en: "Limoilou \u2014 aerial view captured by drone.",
    },
    credit: '',
    capturedAt: '2025-12',
    lat: 46.8258833333333, lon: -71.2177472222222,
    // Auto-publié par iso-ingest; ingest-job:1784828331-25308-6138 (2025:12:01 16:40:02)
    media: "https://media.theo-picture.com/photos/limoilou-2025-12.jpg",
    preview: '/assets/labs360/previews/limoilou.webp',
    previewWidth: 1600,
    previewHeight: 1200,
  },
  {
    id: "colline-parlementaire",
    city: "quebec",
    type: "photo",
    name: { fr: 'Colline Parlementaire', en: 'Colline Parlementaire' },
    desc: {
      fr: "Colline Parlementaire \u2014 vue a\u00e9rienne capt\u00e9e au drone.",
      en: "Colline Parlementaire \u2014 aerial view captured by drone.",
    },
    credit: '',
    capturedAt: '2025-10',
    lat: 46.8030111111111, lon: -71.2182055555556,
    // Auto-publié par iso-ingest; ingest-job:1784829279-25791-17325 (2025:10:20 18:50:55)
    media: "https://media.theo-picture.com/photos/colline-parlementaire-2025-10.jpg",
    preview: '/assets/labs360/previews/colline-parlementaire.webp',
    previewWidth: 1600,
    previewHeight: 900,
  },
  {
    id: "maizerets-2",
    city: "quebec",
    type: "360",
    name: {
      fr: 'La Canardière — Vers le cœur de Québec',
      en: 'La Canardière — Toward the heart of Québec',
    },
    desc: {
      fr: "Maizerets \u2014 vue a\u00e9rienne capt\u00e9e au drone.",
      en: "Maizerets \u2014 aerial view captured by drone.",
    },
    credit: '',
    capturedAt: "2026-07",
    lat: 46.8322444444444, lon: -71.2243611111111,
    // Auto-publié par iso-ingest; ingest-job:1784850144-29389-20409 (2026:07:23 19:06:36)
    media: "https://media.theo-picture.com/panoramas/maizerets-2-2026-07-3.jpg",
    preview: "/assets/labs360/previews/maizerets-2-2026-07.webp",
    previewWidth: 1600,
    previewHeight: 800,
  },
  {
    id: "maizerets-3",
    city: "quebec",
    type: "360",
    name: {
      fr: 'D’Estimauville — Entre ville et fleuve',
      en: 'D’Estimauville — Between city and river',
    },
    desc: {
      fr: "Maizerets \u2014 vue a\u00e9rienne capt\u00e9e au drone.",
      en: "Maizerets \u2014 aerial view captured by drone.",
    },
    credit: '',
    capturedAt: "2026-07",
    lat: 46.8446138888889, lon: -71.2150694444444,
    // Auto-publié par iso-ingest; ingest-job:1784850164-29389-21964 (2026:07:23 19:16:30)
    media: "https://media.theo-picture.com/panoramas/maizerets-3-2026-07.jpg",
    preview: "/assets/labs360/previews/maizerets-3-2026-07.webp",
    previewWidth: 1600,
    previewHeight: 800,
  },
  // iso360:insert — les nouveaux lieux publiés par `iso360` s'insèrent au-dessus de cette ligne
];
