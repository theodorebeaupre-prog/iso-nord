/**
 * Calcule le cadrage MapKit à partir des médias actuellement publiés.
 * `mapkit` est fourni globalement par Apple Maps dans le navigateur.
 */
export function regionForPlaces(places, mapkitApi = globalThis.mapkit) {
  if (!places.length) {
    return new mapkitApi.CoordinateRegion(
      new mapkitApi.Coordinate(46.84, -71.22),
      new mapkitApi.CoordinateSpan(0.18, 0.24),
    );
  }
  const lats = places.map((p) => p.lat);
  const lons = places.map((p) => p.lon);
  const minLat = Math.min(...lats);
  const maxLat = Math.max(...lats);
  const minLon = Math.min(...lons);
  const maxLon = Math.max(...lons);
  const latSpan = Math.max((maxLat - minLat) * 1.8, 0.08);
  const lonSpan = Math.max((maxLon - minLon) * 1.8, 0.12);
  return new mapkitApi.CoordinateRegion(
    new mapkitApi.Coordinate((minLat + maxLat) / 2, (minLon + maxLon) / 2),
    new mapkitApi.CoordinateSpan(latSpan, lonSpan),
  );
}

/** Initialise la carte et ses annotations à partir du contrat de données SSR. */
export function createMap({
  mapkitApi,
  elementId,
  places,
  labels,
  language,
  authorizationCallback,
  onSelect,
}) {
  mapkitApi.init({ authorizationCallback, language });
  const map = new mapkitApi.Map(elementId, {
    region: regionForPlaces(places, mapkitApi),
    mapType: mapkitApi.Map.MapTypes.Hybrid,
    colorScheme: mapkitApi.Map.ColorSchemes.Dark,
    showsCompass: mapkitApi.FeatureVisibility.Hidden,
    showsScale: mapkitApi.FeatureVisibility.Hidden,
    showsMapTypeControl: false,
    showsZoomControl: true,
    showsUserLocationControl: false,
    isRotationEnabled: true,
  });

  const annotations = places.map((place) => {
    const glyph = place.type === '360' ? '◉' : place.type === 'photo' ? '◆' : '▶';
    const badge =
      place.type === '360'
        ? labels.badge360
        : place.type === 'photo'
          ? labels.badgePhoto
          : labels.badgeVideo;
    const annotation = new mapkitApi.MarkerAnnotation(
      new mapkitApi.Coordinate(place.lat, place.lon),
      {
        color: '#c8ff00',
        glyphText: glyph,
        title: place.name,
        subtitle: badge,
      },
    );
    annotation.data = { id: place.id };
    annotation.addEventListener('select', () => onSelect(place.id));
    return annotation;
  });
  map.addAnnotations(annotations);
  return map;
}
