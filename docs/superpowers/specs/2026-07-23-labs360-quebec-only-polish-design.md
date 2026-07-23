# Labs 360 — Québec seulement + polish ciblé

**Date :** 2026-07-23
**Statut :** approuvé verbalement par Théo, à relire avant implémentation

## Objectif

Transformer `/labs/360` et `/en/labs/360` en une expérience temporairement
centrée sur Québec, composée uniquement de médias réels. La page doit paraître
assumée et éditoriale, sans laisser deviner que Montréal ou des captations sont
« en attente ».

## Contenu publié

La page conserve uniquement les lieux qui pointent vers de vrais médias :

- Domaine de Maizerets — panorama 360°;
- Patro Roc-Amadour — panorama 360°;
- Giffard — panorama 360°;
- Centre Monseigneur-Marcoux — panorama 360°;
- Limoilou — photo;
- Colline Parlementaire — photo.

Les lieux suivants sont retirés des données :

- Vieux-Québec;
- Chute Montmorency;
- Île d’Orléans;
- Vieux-Port de Montréal;
- Mont-Royal;
- Centre-ville de Montréal.

Les médias synthétiques devenus orphelins dans `public/assets/labs360/` sont
supprimés s’ils ne sont plus référencés ailleurs. Aucun vrai média servi depuis
`media.theo-picture.com` n’est supprimé.

## Expérience Québec seulement

- Le sélecteur Québec/Montréal disparaît entièrement du markup et du JavaScript.
- La carte Apple Maps démarre directement sur Québec et cadre tous les pins
  publiés.
- Le hash historique `#montreal` n’a plus d’effet et n’est plus généré.
- La légende ne contient qu’une liste continue de lieux réels.
- Le modèle de données conserve `city` pour rester compatible avec
  `iso-ingest` et permettre un retour futur de Montréal sans migration.
- L’ingestion automatique continue de publier les nouvelles captures fiables.
  Tant que Montréal n’est pas relancé publiquement, un média géolocalisé à
  Montréal peut être ajouté aux données par le pipeline, mais la page ne doit
  pas le rendre visible. Le filtrage d’affichage est donc explicitement
  `city === 'quebec'`.

## Polish visuel ciblé

Le polish respecte la direction existante « still, tectonic, precise » :

- resserrer la hiérarchie entre le titre, le texte d’introduction et la carte;
- donner davantage d’espace utile à la carte sur mobile sans dépasser la zone
  sûre du viewport;
- alléger les contrôles et annotations devenus inutiles;
- uniformiser les badges `360°` et `Photo` dans les pins, la légende et la
  modale;
- améliorer les états hover, focus et press sans ajouter de couleur décorative;
- conserver le lime uniquement comme signal d’interaction;
- adoucir les transitions d’ouverture/fermeture et respecter
  `prefers-reduced-motion`;
- préserver le clavier, le focus piégé, Échap, les cibles tactiles de 44 px et
  les contrastes existants.

Ce travail ne remplace pas la direction artistique et n’ajoute ni cartes SaaS,
ni panneaux décoratifs, ni nouvelles dépendances.

## Architecture

### `src/data/labs360.ts`

- retirer les six entrées de démonstration;
- conserver le marqueur `// iso360:insert`;
- conserver le type `City` et le champ `city`.

### `src/components/pages/Labs360.astro`

- filtrer les lieux rendus à `city === 'quebec'`;
- retirer le groupe de boutons de ville et les conteneurs dupliqués par ville;
- rendre une carte et une légende uniques;
- ajuster le texte d’interface FR/EN seulement si une formulation mentionne
  encore Montréal ou le choix d’une ville;
- appliquer le polish ciblé dans les styles scoped existants.

### `src/scripts/labs360.js`

- supprimer le changement de ville, le cross-fade entre groupes et la gestion
  du hash;
- initialiser MapKit avec les seuls lieux rendus;
- conserver la modale, Pannellum, la lightbox photo, Lenis, le focus et les
  animations d’entrée;
- ne jamais afficher un lieu absent du JSON runtime filtré.

### `src/i18n/ui.ts`

- remplacer les formulations Québec + Montréal par Québec seulement;
- retirer les chaînes devenues réellement inutilisées si TypeScript et le build
  confirment qu’elles n’ont plus de consommateur.

## Gestion des cas limites

- Zéro lieu Québec : la carte reste stable et affiche le message média à venir,
  sans erreur JavaScript.
- Un seul lieu : MapKit utilise un cadrage raisonnable plutôt qu’un zoom maximal.
- Échec MapKit : le fallback actuel demeure lisible.
- Ancien lien `#montreal` : la page charge Québec normalement.
- Nouveau média Montréal auto-ingéré : il reste versionné dans les données, mais
  invisible jusqu’à la relance explicite de Montréal.

## Vérification

- test de données : les six IDs retirés sont absents et les six vrais lieux
  Québec sont présents;
- test DOM/runtime : aucun sélecteur de ville ni gestion `#montreal`;
- test d’ingestion : les contrats du pipeline restent verts;
- `npm run build` produit exactement 10 pages;
- inspection navigateur desktop et mobile :
  - carte Québec bien cadrée;
  - six pins/légende;
  - ouverture d’un panorama et d’une photo;
  - fermeture Échap/clic;
  - clavier et focus;
  - FR et EN;
  - `prefers-reduced-motion`;
  - aucune erreur console.

## Hors périmètre

- retour de Montréal;
- recrutement ou crédit de collaborateurs;
- nouvelles captations;
- suppression des vrais médias du NAS;
- refonte complète de la marque ou de la page Labs principale.
