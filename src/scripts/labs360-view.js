/** Libellés et états simples du viewer, gardés testables hors du navigateur. */
export function badgeForType(type, labels) {
  if (type === '360') return labels.badge360;
  if (type === 'photo') return labels.badgePhoto;
  return labels.badgeVideo;
}

export const hasVisiblePlaces = (places) => places.length > 0;
