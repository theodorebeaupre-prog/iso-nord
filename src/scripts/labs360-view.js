/** Libellés et états simples du viewer, gardés testables hors du navigateur. */
export function badgeForType(type, labels) {
  if (type === '360') return labels.badge360;
  if (type === 'photo') return labels.badgePhoto;
  return labels.badgeVideo;
}

export const hasVisiblePlaces = (places) => places.length > 0;

export function adjacentPlaceId(places, currentId, direction) {
  if (!places.length) return '';
  const currentIndex = places.findIndex((place) => place.id === currentId);
  if (currentIndex < 0) return places[0].id;
  const nextIndex = (currentIndex + direction + places.length) % places.length;
  return places[nextIndex].id;
}

export function counterLabel(index, total, pattern) {
  const current = String(index + 1).padStart(2, '0');
  const count = String(total).padStart(2, '0');
  return pattern.replace('{current}', current).replace('{total}', count);
}
