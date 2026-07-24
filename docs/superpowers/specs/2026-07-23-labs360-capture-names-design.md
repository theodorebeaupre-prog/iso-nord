# Noms hybrides des panoramas Labs 360

## Objectif

Donner à chacun des six panoramas publiés un nom distinct, mémorable et fidèle
à son point de vue réel. Les deux photographies conservent leurs noms actuels.

## Convention éditoriale

Chaque panorama suit le format `Lieu — évocation` :

- le lieu précis vient en premier pour l’orientation et la recherche;
- l’évocation décrit un élément réellement visible ou l’ambiance de la scène;
- le titre reste court afin de bien fonctionner sur les cartes mobiles;
- les versions française et anglaise transmettent le même sens sans traduction
  excessivement littérale.

## Titres approuvés

| Identifiant | Français | Anglais |
| --- | --- | --- |
| `maizerets` | Domaine de Maizerets — Le fleuve au couchant | Domaine de Maizerets — River at sunset |
| `patro-roc-amadour` | Patro Roc-Amadour — Du terrain à la skyline | Patro Roc-Amadour — From the field to the skyline |
| `giffard` | Giffard — Entre deux rives | Giffard — Between two shores |
| `centre-monseigneur-marcoux` | Monseigneur-Marcoux — Limoilou sous la neige | Monseigneur-Marcoux — Limoilou under snow |
| `maizerets-2` | La Canardière — Vers le cœur de Québec | La Canardière — Toward the heart of Québec |
| `maizerets-3` | D’Estimauville — Entre ville et fleuve | D’Estimauville — Between city and river |

Les noms `La Canardière` et `D’Estimauville` correspondent aux coordonnées GPS
des deux panoramas importés le 23 juillet 2026.

## Données et affichage

Le champ `name` devient bilingue afin que le titre soit naturel dans chaque
langue, comme le champ `desc` existant. Les consommateurs de `name` dans la
page, le viewer, les données structurées et le script client doivent recevoir
la chaîne correspondant à la langue active.

Les descriptions seront ajustées pour reprendre le lieu exact et décrire
brièvement le panorama sans inventer d’élément absent de l’image.

## Pipeline d’import

Les nouveaux imports peuvent conserver un nom géographique automatique au
départ. La présente modification ne tente pas de générer automatiquement un
sous-titre créatif : celui-ci demeure une décision éditoriale.

## Vérification

- les six panoramas possèdent un titre français et anglais distinct;
- les deux photos restent inchangées;
- la page française et la page anglaise rendent le bon titre;
- le viewer, les cartes et les données structurées utilisent la langue active;
- les tests ne supposent plus exactement six entrées, puisque la collection en
  contient désormais huit après les deux imports récents;
- le build Astro produit toujours dix pages.
