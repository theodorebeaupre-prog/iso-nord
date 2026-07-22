# AGENTS.md — ISO NORD / theo-picture.com

**Lis d'abord [`docs/HANDOFF-codex.md`](docs/HANDOFF-codex.md)** — passation complète :
récupération de la source, page Labs « Québec en 360 », et l'infra média (tunnel
Cloudflare qui sert les panoramas depuis le Mac).

## L'essentiel
- Site vitrine du studio **ISO NORD** (photo/vidéo/drone, Québec). Marque = « ISO Nord »,
  **jamais** « Théo Picture » dans le contenu visible.
- Stack : Astro 6 · Tailwind v4 · GSAP + Lenis · Pannellum. i18n FR (racine) / EN (`/en`).
- Repo de travail : ce dossier (`~/Desktop/Developer/iso-nord`). Remote `main`.
- **Deploy** : `git push` sur `main` = déploiement Vercel auto. Build attendu : **10 pages**.
- Vérifier avant de pousser : `npm run build` doit passer sans erreur.

## Conventions
- Commentaires de code **en français**, dans la voix du repo.
- Données de la page 360 : `src/data/labs360.ts` (le fichier à éditer pour les lieux/médias).
- Panoramas réels servis via `https://media.theo-picture.com/...` (voir le handoff §3).
- Ne jamais remplacer un média sous le même nom (cache immutable 1 an) — versionne le nom.

## Notes historiques dans le repo
`claude.md` / `CLAUDE.md` datent d'une phase antérieure (workspace multi-agents, chemins
`~/iso-nord-astro/` obsolètes). En cas de conflit, **`docs/HANDOFF-codex.md` fait foi.**
