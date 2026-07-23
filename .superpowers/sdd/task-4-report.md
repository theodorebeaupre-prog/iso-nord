# Task 4 — Polish ciblé + vérification visuelle

## Résultat

- Rythme vertical du hero, de la carte et de la légende aligné sur la spec.
- Carte contrainte à `width: 100%` en plus de sa hauteur fluide : corrige un
  débordement horizontal découvert à 390 px.
- Carte mobile limitée à `min-height: 28rem; height: 62svh`.
- Lignes de légende à 64 px mesurés sur mobile, avec `touch-action:
  manipulation` et focus lime visible.
- Liens de navigation/footer et fermeture de modale à au moins 44 px.
- Bloc scoped `prefers-reduced-motion` : transitions supprimées, contenu forcé
  visible et sans transform.
- Aucun nouveau token, couleur, style ou dépendance.

## TDD

1. Ajout de `test_targeted_polish_contract` dans `tests/labs360-page.sh`.
2. RED observé : `not ok - le hero utilise le rythme vertical ciblé`.
3. GREEN observé après le polish : `6 réussite(s), 0 échec(s)`.
4. Le navigateur a ensuite révélé un overflow mobile (`mapRight: 419` pour un
   viewport de 390 px). Le contrat a été renforcé pour exiger `width: 100%`.
5. RED observé : `not ok - la carte desktop conserve une hauteur utile`.
6. GREEN et revalidation navigateur : carte `350 px`, de `x=20` à `x=370`,
   `overflowX: false`.

## Vérification navigateur

Surface utilisée : navigateur connecté + API Playwright du skill Browser.
Serveur local : `npm run dev -- --host 127.0.0.1`.

### FR — 390 × 844

- Capture pleine page inspectée dans la session.
- URL historique `/labs/360#montreal` conserve la page Québec normalement.
- 6 lignes de légende, aucun sélecteur, aucune mention Montréal.
- Les six lieux sont présents dans le fallback; MapKit n'est pas validé localement.
- Carte après correction : 350 × 523 px, aucun overflow horizontal.
- Chaque ligne de légende : 350 × 64 px; `touch-action: manipulation`.
- Maizerets ouvre Pannellum : titre, host panorama et indice de drag présents.
- Échap ferme la modale et restaure le focus sur `maizerets`.
- Limoilou ouvre un `<img>` avec le bon titre.
- Bouton de fermeture ferme la photo et restaure le focus sur `limoilou`.

### EN — 1440 × 1000

- Capture pleine page inspectée dans la session.
- URL historique `/en/labs/360#montreal` conserve la page Québec normalement.
- `lang=en`, titre `QUÉBEC IN 360.`, 6 lignes de légende.
- Aucun sélecteur, aucune mention Montreal, aucun overflow horizontal.
- Carte : 1008 × 680 px.
- Limoilou ouvre la modale photo.
- Un clic réel hors du panneau (backdrop) ferme la modale et restaure le focus.

### Accessibilité et mouvement réduit

- Focus : règle scoped `:focus-visible` avec outline accent et offset 4 px;
  restauration du focus vérifiée après Échap, bouton et backdrop.
- Les interactions essentielles sont disponibles au clic/tap/focus; aucun état
  essentiel ne dépend du hover.
- Mouvement réduit : branche JS existante désactive Lenis, reveals et
  autorotation; le nouveau media query scoped supprime les transitions et force
  les contenus critiques visibles.
- Console : aucune erreur applicative. Le warning MapKit `Authorization token is
  invalid` est attendu en local, car le token est restreint au domaine de
  production. Les autres warnings provenaient d'une extension Chrome.

## Vérification automatisée finale

```text
/bin/bash tests/labs360-page.sh
6 réussite(s), 0 échec(s)

/bin/bash tests/labs360-pipeline.sh
26 réussite(s), 0 échec(s)

npm run build
10 page(s) built

git diff --check
sortie vide, code 0
```

## Self-review

- Changements limités à `Labs360.astro`, au test de contrat et à ce rapport.
- CSS conservé dans le bloc scoped Astro et fusionné aux sélecteurs existants.
- FR/EN partagent le même composant; aucune copy n'avait besoin d'être modifiée.
- Le `width: 100%` ajouté à la carte est nécessaire pour éviter que
  `min-height` + `aspect-ratio` calcule une largeur supérieure au conteneur.
- Aucun asset ni média supprimé/modifié pendant cette tâche.

## Préoccupation résiduelle

La validation locale ne peut confirmer ni les tuiles ni les annotations MapKit :
l'origine `localhost` est volontairement refusée par le token. Le fallback et
les six entrées restent fonctionnels. Le cadrage géographique lui-même est
couvert par les tests de `regionForPlaces`.

## Correctifs après review

### Cibles de navigation

Le premier rapport affirmait trop largement que tous les liens de navigation
avaient une cible tactile complète. `LangSwitch` est un composant Astro enfant :
la classe reçue n'était pas couverte par le sélecteur scoped du parent. La
mesure initiale à 390 × 844 confirmait :

```text
ISO Nord   61.55 × 44 px
Labs       32.12 × 44 px
Portfolio  70.70 × 44 px
EN         16.84 × 44 px
```

Le sélecteur utilise maintenant `:global(.l360-nav__link)` de façon ciblée et
fixe `min-width`/`min-height` à 44 px. Mesures finales dans le navigateur :

```text
ISO Nord   61.55 × 44 px
Labs       44.00 × 44 px
Portfolio  70.70 × 44 px
EN         44.00 × 44 px
```

`touch-action: manipulation` est calculé sur les quatre liens. La navigation
fait 375 px, et la page ne produit aucun débordement horizontal à 390 px.

### Ouverture en mouvement réduit

La branche d'ouverture réduite appelait auparavant deux animations GSAP malgré
la préférence système. La politique est désormais isolée dans
`labs360-motion.js` et testée en Node :

- `reducedMotion=true` → aucune animation, avec ou sans déclencheur;
- `reducedMotion=false` → animation conservée;
- la branche réduite fixe immédiatement l'opacité et l'échelle finales avec
  `gsap.set`;
- la fermeture réduite demeure instantanée.

Le cycle RED/GREEN a été observé : le test échouait d'abord sur l'import absent,
puis passe avec la politique utilisée par `labs360.js`.

### Gate MapKit live obligatoire

**Post-push requis :** ouvrir `/labs/360` et `/en/labs/360` sur le domaine de
production, confirmer que les six annotations MapKit et les tuiles satellite
sont visibles, puis vérifier le cadrage des six lieux. La vérification locale ne
valide pas MapKit et ne doit jamais être rapportée comme telle, puisque le token
refuse volontairement `localhost`.
