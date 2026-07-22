import { ui, type Lang } from './ui';

export const LOCALES: Lang[] = ['fr', 'en'];
export const DEFAULT_LOCALE: Lang = 'fr';
export const SITE = 'https://theo-picture.com';

/** Clés de page → chemin fr (racine) et en (préfixé /en). */
export const PAGES = {
  home:      { fr: '/',                en: '/en/' },
  labs:      { fr: '/labs',            en: '/en/labs' },
  portfolio: { fr: '/portfolio',       en: '/en/portfolio' },
  privacy:   { fr: '/privacy-isonord', en: '/en/privacy-isonord' },
} as const;

export type PageKey = keyof typeof PAGES;

/** Déduit la langue depuis l'URL courante (racine = fr, /en… = en). */
export function getLang(url: URL): Lang {
  const seg = url.pathname.split('/').filter(Boolean)[0];
  return seg === 'en' ? 'en' : 'fr';
}

export const other = (lang: Lang): Lang => (lang === 'fr' ? 'en' : 'fr');

/** Dictionnaire de la langue demandée. */
export function t(lang: Lang) {
  return ui[lang];
}

/** Chemin de `page` dans la langue voulue. */
export function pathFor(page: PageKey, lang: Lang): string {
  return PAGES[page][lang];
}

/** Liens hreflang (URL absolues) pour une page donnée. */
export function alternates(page: PageKey) {
  return [
    { hreflang: 'fr-CA', href: SITE + PAGES[page].fr },
    { hreflang: 'en', href: SITE + PAGES[page].en },
    { hreflang: 'x-default', href: SITE + PAGES[page].fr },
  ];
}
