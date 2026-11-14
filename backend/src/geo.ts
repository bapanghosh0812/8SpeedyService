const EARTH_RADIUS_M = 6_371_000;
const toRad = (d: number) => (d * Math.PI) / 180;

export function distanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(a)));
}

/** Bounding box that fully contains a circle of radiusM around the point (used to hit the btree index). */
export function boundingBox(lat: number, lng: number, radiusM: number) {
  const dLat = (radiusM / EARTH_RADIUS_M) * (180 / Math.PI);
  const dLng = dLat / Math.max(Math.cos(toRad(lat)), 0.01);
  return { minLat: lat - dLat, maxLat: lat + dLat, minLng: lng - dLng, maxLng: lng + dLng };
}

/** Service area: India (with margin). Rejects garbage/spoofed coordinates outright. */
export function isInServiceArea(lat: number, lng: number): boolean {
  return lat >= 6 && lat <= 37.6 && lng >= 68 && lng <= 97.6;
}

/** Fastest believable ground speed between two GPS fixes (m/s). ~250 km/h. */
export const MAX_PLAUSIBLE_SPEED_MS = 70;
