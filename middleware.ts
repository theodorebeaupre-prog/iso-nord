import { geolocation } from '@vercel/edge';

/**
 * Vercel Edge Middleware — routage de langue par géolocalisation IP.
 *
 * Règle : région Québec (CA/QC) → français (racine) ; tout le reste → anglais (/en).
 * Un cookie `lang` (posé côté client au chargement de page et par le sélecteur
 * FR/EN) prime toujours sur la géo → le visiteur n'est jamais piégé et peut
 * changer de langue librement. La géo ne s'applique qu'à la toute première
 * visite, sans cookie.
 */
export const config = {
  // Ne tourne que sur les routes de page ; exclut assets, fichiers et statiques.
  matcher: ['/((?!_astro|assets|favicon|robots|sitemap|.*\\.).*)'],
};

export default function middleware(request: Request) {
  const url = new URL(request.url);
  const { pathname } = url;
  const urlLang: 'fr' | 'en' =
    pathname === '/en' || pathname.startsWith('/en/') ? 'en' : 'fr';

  const cookie = request.headers.get('cookie') || '';
  const match = cookie.match(/(?:^|;\s*)lang=(fr|en)\b/);

  let lang: 'fr' | 'en';
  if (match) {
    lang = match[1] as 'fr' | 'en';
  } else {
    const { country, countryRegion } = geolocation(request);
    lang = country === 'CA' && countryRegion === 'QC' ? 'fr' : 'en';
  }

  if (lang === urlLang) return; // langue déjà correcte → on sert la page

  if (lang === 'en') {
    url.pathname = pathname === '/' ? '/en/' : '/en' + pathname;
  } else {
    url.pathname = pathname.replace(/^\/en/, '') || '/';
  }
  return Response.redirect(url, 307);
}
