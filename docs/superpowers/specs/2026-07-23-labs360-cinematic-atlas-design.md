# Labs 360 — Atlas cinématographique

**Date :** 2026-07-23  
**Statut :** approuvé par le mandat autonome  
**Cible :** `/labs/360` et `/en/labs/360`

## Objectif

Transformer Labs 360 en vitrine client premium d’ISO NORD : une expérience
cinématographique, crédible et rapide qui montre les captations aériennes réelles
de Québec sans ressembler à une démo technique.

La page doit rester utile si Apple Maps, JavaScript ou un média distant échoue.
Elle ne publie que les six lieux réels déjà validés et ne réintroduit ni Montréal
ni destination fictive.

## Direction créative

### Concept

La page devient un « atlas cinématographique » composé de trois temps :

1. un hero éditorial qui présente clairement la valeur de l’expérience;
2. une carte satellite compacte qui situe les captations;
3. une collection visuelle qui permet d’ouvrir chaque média sans dépendre de la
   carte.

L’identité existante est conservée : fond nuit, crème, lime comme accent
fonctionnel, typographies Archivo et Archivo Expanded. Le polish vient surtout de
la hiérarchie, du rythme, des images et des transitions, pas de nouveaux effets
décoratifs.

### Hero

- Eyebrow « ISO NORD LABS / QUÉBEC ».
- Titre court et bilingue qui met l’exploration au premier plan.
- Texte expliquant que chaque vue est une vraie captation aérienne ISO NORD.
- Deux données de confiance visibles : nombre de lieux publiés et types de médias.
- Un appel « Explorer les captations » descend vers la collection.
- Une vraie captation existante sert de fond visuel léger grâce à un aperçu local
  optimisé; le panorama complet n’est jamais téléchargé pour le hero.

### Carte

- MapKit demeure satellite hybride et affiche exactement les six lieux Québec.
- La carte devient plus compacte que dans la version actuelle afin que la
  collection apparaisse plus tôt.
- MapKit n’est chargé que lorsque la carte approche du viewport.
- Chaque annotation conserve un nom et un type lisibles.
- Si MapKit ou son jeton échoue, un message bref est visible, mais les six cartes
  de la collection restent utilisables.
- Aucun sélecteur de ville, hash Montréal ou logique multi-région.

### Collection

- Six cartes éditoriales rendues côté serveur, une par lieu réel.
- Chaque carte contient un aperçu local optimisé, le nom, le type et la
  description localisée.
- Les cartes sont de vrais boutons accessibles qui ouvrent le même viewer que les
  annotations MapKit.
- Le rythme visuel alterne subtilement les formats sur desktop tout en restant une
  liste simple sur mobile.
- Sans JavaScript, le contenu, les lieux et les descriptions demeurent visibles;
  seule l’ouverture immersive est indisponible.

### Viewer

- Modale plein écran pour panorama, photo ou futur clip réel.
- Nom, type, description et crédit sont toujours liés sémantiquement au dialogue.
- Boutons précédent/suivant, compteur « 01 / 06 » et fermeture.
- Les flèches gauche/droite naviguent; Échap ferme; Tab reste piégé dans le
  dialogue; le focus revient au déclencheur.
- Le panorama complet et Pannellum sont chargés uniquement à l’ouverture d’un
  média 360.
- Les photos utilisent `loading="eager"` dans la modale, car elles résultent d’une
  action explicite.
- Une erreur de média affiche un état de repli localisé et permet encore de
  naviguer vers le média suivant.
- `prefers-reduced-motion` désactive auto-rotation, zooms et transitions de
  déplacement.

## Contenu publié

Les seuls lieux visibles sont :

1. Domaine de Maizerets — panorama 360 réel;
2. Patro Roc-Amadour — panorama 360 réel;
3. Giffard — panorama 360 réel;
4. Centre Monseigneur-Marcoux — panorama 360 réel;
5. Limoilou — photographie réelle;
6. Colline Parlementaire — photographie réelle.

Les anciens IDs `vieux-quebec`, `chute-montmorency`, `ile-orleans`,
`vieux-port`, `mont-royal` et `centre-ville` sont explicitement interdits.

Le pipeline d’ingestion refuse une destination Montréal avant de modifier les
données, de publier un média ou d’attendre le déploiement de cette page.

## Données et architecture

### `src/data/labs360.ts`

`Labs360Place` reste la source unique. On ajoute :

- `capturedAt: string` au format `YYYY-MM` pour une date éditoriale stable;
- `preview: string` pour l’aperçu local optimisé;
- `featured?: boolean` pour choisir l’image du hero, avec un seul lieu vedette.

Le type `city` devient uniquement `'quebec'`. Le pipeline refuse explicitement
une publication Montréal au lieu de conserver une branche invisible.

### `src/components/pages/Labs360.astro`

Le composant :

- rend tout le contenu éditorial, la collection et les métadonnées;
- injecte seulement les données runtime nécessaires aux interactions;
- fournit un `<noscript>` localisé;
- ajoute les métadonnées sociales et les données structurées;
- ne charge plus directement le script MapKit dans le `<head>`.

### Modules client

- `src/scripts/labs360.js` orchestre page, modale et événements;
- `src/scripts/labs360-map.js` calcule la région et initialise MapKit à la
  demande;
- `src/scripts/labs360-view.js` fournit navigation circulaire, libellés et états
  testables;
- `src/scripts/labs360-motion.js` centralise la politique de mouvement;
- `src/scripts/labs360-map-loader.js` charge MapKit une seule fois lorsque la
  carte approche du viewport et expose une promesse rejetée clairement en cas
  d’échec.

Les modules ne dupliquent pas les lieux et utilisent l’identifiant stable comme
interface.

## Aperçus médias

Six fichiers WebP locaux sont dérivés des vrais médias existants :

`public/assets/labs360/previews/<id>.webp`

Contraintes :

- largeur maximale de 1600 px;
- qualité cible 76–80;
- poids maximal de 350 Ko par aperçu;
- dimensions explicites dans le markup pour éviter les sauts de mise en page;
- aucune modification des originaux distants, dont les noms restent immuables.

Le hero réutilise l’aperçu du lieu `featured`; aucun septième média ou faux lieu
n’est créé.

## Textes bilingues

### Français

- Positionnement : « Québec, vu autrement. »
- Promesse : captations aériennes réelles, explorables et produites par ISO NORD.
- Ton : précis, cinématographique, sans superlatifs vagues.

### Anglais

- Positionnement : « Québec, from another perspective. »
- Traduction naturelle canadienne, pas mot à mot.
- « Québec City » est utilisé lorsque la ville doit être distinguée de la
  province.

Les six descriptions restent factuelles. Aucun texte ne promet de vidéo ou de
nouvelle destination non publiée.

## SEO et partage

Les deux routes doivent inclure :

- `title`, description, canonical et hreflang existants;
- `og:image`, `og:image:width`, `og:image:height`, `twitter:card` et
  `twitter:image` basés sur l’aperçu vedette;
- JSON-LD `CollectionPage` avec `ItemList` de six `CreativeWork`;
- URL, langue, nom, description et position géographique de chaque lieu;
- HTML rendu côté serveur avec les six noms et descriptions.

Le JSON-LD ne doit pas présenter les panoramas comme une adresse commerciale ni
inventer de date, auteur ou client.

## Accessibilité

- Cibles tactiles d’au moins 44 × 44 px.
- Focus visible sur nav, CTA, cartes, contrôles du viewer et fermeture.
- Un seul `h1`; hiérarchie de titres continue.
- Carte identifiée comme région complémentaire, collection comme contenu
  principal.
- Dialogue annoncé avec nom et description du lieu.
- Contrôles précédent/suivant avec noms localisés.
- État courant du média annoncé avec `aria-live="polite"`.
- Fond de page rendu inerte pendant l’ouverture du dialogue lorsque supporté.
- Contraste texte/fond conforme WCAG AA.
- Aucun contenu indispensable dépend d’un hover, d’une animation ou de la carte.

## Performance

Critères mesurables sur le HTML de production :

- HTML initial inférieur à 35 Ko non compressé;
- JavaScript propre à Labs 360 inférieur à 20 Ko non compressé, hors dépendances
  chargées à la demande;
- aucun panorama complet dans les requêtes avant ouverture du viewer;
- Pannellum JS et CSS absents des ressources initiales;
- MapKit absent des requêtes initiales tant que la carte n’approche pas du
  viewport;
- somme des six aperçus inférieure à 1,8 Mo;
- images sous le fold en `loading="lazy"` et `decoding="async"`;
- aucune dépendance npm supplémentaire.

## Animations

- Reveal léger du hero et des cartes avec GSAP déjà présent.
- Une seule transition de modale; aucune animation en boucle.
- L’auto-rotation Pannellum est conservée uniquement sans mouvement réduit.
- Sur mobile tactile, aucun curseur custom n’est affiché.
- Toutes les animations sont fonctionnelles à 60 fps sans filtre ou blur animé.

## Gestion des erreurs

- MapKit : délai maximal de 8 secondes, message de repli et collection active.
- Média : état de repli localisé, navigation et fermeture toujours disponibles.
- Données runtime invalides : page statique visible, interactions non initialisées
  sans exception globale.
- Aperçu manquant : build ou test échoue avant déploiement.
- Zéro lieu visible : hero et état vide localisé, sans carte ni collection vide.

## Vérification

### Automatique

- Étendre `tests/labs360-page.sh` pour les données, previews, galerie, SEO,
  accessibilité statique, lazy loading et absence de Montréal.
- Ajouter des tests Node sans navigateur pour la navigation circulaire et le
  chargeur MapKit.
- Garder `tests/labs360-pipeline.sh` vert.
- `npm run build` doit produire exactement 10 pages.
- Scanner le HTML construit FR et EN pour les six lieux et les métadonnées.

### Visuelle et interactive

Vérifier en local puis en production :

- mobile 390 × 844;
- tablette 820 × 1180;
- desktop 1440 × 1000;
- FR et EN;
- carte chargée et carte en erreur;
- ouverture depuis collection et annotation;
- panorama, photo, précédent/suivant, clavier, focus et mouvement réduit;
- absence de débordement horizontal et erreurs console applicatives.

## Déploiement

Le travail est développé dans un worktree isolé basé sur `origin/main`. Les
commits Intercom locaux de la branche principale ne sont ni fusionnés ni poussés.

Avant publication :

1. tests page et pipeline verts;
2. build de 10 pages;
3. vérification du diff pour exclure les changements non liés;
4. push explicite de la branche validée vers `origin/main`;
5. attente du déploiement Vercel;
6. vérification des routes live FR et EN.

## Hors périmètre

- nouvelles destinations ou nouveaux originaux;
- Montréal;
- remplacement des fichiers distants sous un nom déjà caché;
- refonte des autres pages du site;
- modification de l’infrastructure Caddy, Cloudflare ou du NAS;
- ajout d’un CMS, d’analytics ou d’une dépendance cartographique.
