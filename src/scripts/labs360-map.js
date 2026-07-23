/**
 * Calcule le cadrage MapKit à partir des médias actuellement publiés.
 * `mapkit` est fourni globalement par Apple Maps dans le navigateur.
 */
export function regionForPlaces(places) {
  if (!places.length) {
    return new mapkit.CoordinateRegion(
      new mapkit.Coordinate(46.84, -71.22),
      new mapkit.CoordinateSpan(0.18, 0.24),
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
  return new mapkit.CoordinateRegion(
    new mapkit.Coordinate((minLat + maxLat) / 2, (minLon + maxLon) / 2),
    new mapkit.CoordinateSpan(latSpan, lonSpan),
  );
}
