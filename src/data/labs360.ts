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

export type City = 'quebec' | 'montreal';
export type PlaceType = '360' | 'video';

export interface Labs360Place {
  id: string;
  city: City;
  type: PlaceType;
  name: string;                       // nom propre — identique fr/en
  desc: { fr: string; en: string };
  credit: string;
  lat: number;                        // latitude GPS
  lon: number;                        // longitude GPS
  media: string;
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
    id: 'vieux-quebec',
    city: 'quebec',
    type: '360',
    name: 'Vieux-Québec',
    desc: {
      fr: "Les toits du Vieux-Québec et le Château Frontenac, captés à l'aube.",
      en: 'The rooftops of Old Québec and the Château Frontenac, captured at dawn.',
    },
    credit: '',
    lat: 46.8119, lon: -71.2056,
    // Servi depuis le Mac via Cloudflare Tunnel (SSD 1/iso-nord-media)
    media: 'https://media.theo-picture.com/panoramas/pano-vieux-quebec-demo.jpg',
  },
  {
    id: 'chute-montmorency',
    city: 'quebec',
    type: '360',
    name: 'Chute Montmorency',
    desc: {
      fr: 'La chute et son embrun, 83 mètres au-dessus du Saint-Laurent.',
      en: 'The falls and their mist, 83 metres above the St. Lawrence.',
    },
    credit: '',
    lat: 46.8906, lon: -71.1478,
    media: 'pano-chute-montmorency.png',
  },
  {
    id: 'ile-orleans',
    city: 'quebec',
    type: 'video',
    name: "Île d'Orléans",
    desc: {
      fr: "Survol des rives et des vergers de l'île, au fil des saisons.",
      en: "Flying over the island's shores and orchards, season by season.",
    },
    credit: '',
    lat: 46.9200, lon: -70.9700,
    media: '/assets/hero-camera.mp4',
    poster: '/assets/portfolio/chute-automne.jpeg',
  },
  {
    id: 'maizerets',
    city: 'quebec',
    type: '360',
    name: 'Domaine de Maizerets',
    desc: {
      fr: 'Le domaine et son arboretum, vus du ciel en fin de journée.',
      en: 'The estate and its arboretum, seen from above at dusk.',
    },
    credit: '',
    lat: 46.8360, lon: -71.2139,
    media: "https://media.theo-picture.com/panoramas/maizerets-2025-10.jpg",
  },
  {
    id: 'patro-roc-amadour',
    city: 'quebec',
    type: '360',
    name: 'Patro Roc-Amadour',
    desc: {
      fr: 'Le Patro et le quartier Lairet à 100 m d’altitude — le Centre Vidéotron et la skyline de Québec à l’horizon.',
      en: 'The Patro and the Lairet neighbourhood from 100 m up — Centre Vidéotron and the Québec City skyline on the horizon.',
    },
    credit: '',
    lat: 46.8327, lon: -71.2445,
    // Vrai pano drone (28 juin 2026, GPS 46.8327 N 71.2445 W, stitché des
    // 35 segments DJI avec Hugin), servi via Cloudflare Tunnel.
    media: 'https://media.theo-picture.com/panoramas/patro-roc-amadour-2026.jpg',
  },

  // ── Montréal ──────────────────────────────────────────────────────────────
  {
    id: 'vieux-port',
    city: 'montreal',
    type: '360',
    name: 'Vieux-Port de Montréal',
    desc: {
      fr: 'Les quais, la grande roue et le fleuve — panorama complet du Vieux-Port.',
      en: 'The docks, the Ferris wheel and the river — a full panorama of the Old Port.',
    },
    credit: '',
    lat: 45.5075, lon: -73.5470,
    media: 'pano-vieux-port.png',
  },
  {
    id: 'mont-royal',
    city: 'montreal',
    type: 'video',
    name: 'Mont-Royal',
    desc: {
      fr: 'La montagne et le belvédère Kondiaronk face au centre-ville.',
      en: 'The mountain and the Kondiaronk lookout facing downtown.',
    },
    credit: '',
    lat: 45.5045, lon: -73.5872,
    media: '/assets/hero-camera.mp4',
    poster: '/assets/portfolio/skyline-quebec.jpeg',
  },
  {
    id: 'centre-ville',
    city: 'montreal',
    type: 'video',
    name: 'Centre-ville de Montréal',
    desc: {
      fr: 'Les tours du centre-ville à l’heure bleue, en survol cinématique.',
      en: 'Downtown towers at blue hour, in a cinematic flyover.',
    },
    credit: '',
    lat: 45.5017, lon: -73.5673,
    media: '/assets/hero-camera.mp4',
    poster: '/assets/portfolio/ville-heure-bleue.jpeg',
  },
  {
    id: "giffard",
    city: "quebec",
    type: '360',
    name: "Giffard",
    desc: {
      fr: "Giffard \u2014 vue a\u00e9rienne capt\u00e9e au drone.",
      en: "Giffard \u2014 aerial view captured by drone.",
    },
    credit: '',
    lat: 46.849922222222226, lon: -71.21155555555556,
    // Pano drone auto-publié par iso360 (2025:10:25 13:07:26)
    media: "https://media.theo-picture.com/panoramas/giffard-2025-10.jpg",
  },
  // iso360:insert — les nouveaux lieux publiés par `iso360` s'insèrent au-dessus de cette ligne
];
