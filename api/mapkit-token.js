// Fonction serverless Vercel — génère un token MapKit JS (Apple Maps) à la volée.
//
// La clé privée (.p8) reste côté serveur, dans MAPKIT_PRIVATE_KEY_B64 (base64).
// Le token est court (30 min) et restreint à l'origine appelante (allowlist) via
// le claim `origin` — MapKit refuse un token dont l'origine ne correspond pas à
// la page. C'est le mécanisme d'auth prévu par Apple pour MapKit JS.
//
// Variables d'environnement (Vercel + .env local) :
//   MAPKIT_KEY_ID          — Key ID de la clé MapKit JS (10 car.)
//   MAPKIT_TEAM_ID         — Team ID du compte Apple Developer (10 car.)
//   MAPKIT_PRIVATE_KEY_B64 — contenu du .p8, encodé en base64

import crypto from 'node:crypto';

// Hôtes autorisés à obtenir un token. On dérive l'origine du header `Host`
// (toujours présent, même sur un GET same-origin où Safari n'envoie PAS `Origin`)
// → le token correspond à la page, que ce soit theo-picture.com OU www.
const ALLOWED_HOSTS = ['theo-picture.com', 'www.theo-picture.com', 'localhost:4321'];

const b64url = (buf) =>
  Buffer.from(buf).toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

export default function handler(req, res) {
  const keyId = process.env.MAPKIT_KEY_ID;
  const teamId = process.env.MAPKIT_TEAM_ID;
  const keyB64 = process.env.MAPKIT_PRIVATE_KEY_B64;
  if (!keyId || !teamId || !keyB64) {
    res.status(500).send('MapKit non configuré (variables d’environnement manquantes)');
    return;
  }

  // Origine dérivée du Host de la page (couvre www / non-www / localhost).
  const host = (req.headers.host || '').toLowerCase();
  const proto = host.startsWith('localhost') ? 'http' : 'https';
  const origin = ALLOWED_HOSTS.includes(host) ? `${proto}://${host}` : 'https://theo-picture.com';

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'ES256', kid: keyId, typ: 'JWT' };
  const payload = { iss: teamId, iat: now, exp: now + 30 * 60, origin };

  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  const privateKey = Buffer.from(keyB64, 'base64').toString('utf8');

  // dsaEncoding ieee-p1363 → signature brute r||s exigée par JWT ES256 (pas du DER).
  const signature = crypto.sign('SHA256', Buffer.from(signingInput), {
    key: privateKey,
    dsaEncoding: 'ieee-p1363',
  });

  const token = `${signingInput}.${b64url(signature)}`;

  res.setHeader('Content-Type', 'text/plain');
  res.setHeader('Cache-Control', 'no-store');
  res.status(200).send(token);
}
