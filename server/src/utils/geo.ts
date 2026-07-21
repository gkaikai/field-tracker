/**
 * 地理计算工具函数
 * 统一管理 Haversine 公式、射线法围栏检测等
 */

/**
 * Haversine 公式计算两点距离（米）
 */
export function haversineDistance(
  lat1: number, lng1: number,
  lat2: number, lng2: number,
): number {
  const R = 6371e3;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/**
 * Haversine 公式计算两点距离（千米）
 */
export function haversineKm(
  lat1: number, lng1: number,
  lat2: number, lng2: number,
): number {
  return haversineDistance(lat1, lng1, lat2, lng2) / 1000;
}

/**
 * 射线法判断点是否在多边形内
 * @param lat 待检测纬度
 * @param lng 待检测经度
 * @param coords 多边形顶点数组 [{lat, lng}, ...]
 */
export function pointInPolygon(
  lat: number, lng: number,
  coords: Array<{lat: number; lng: number}>,
): boolean {
  if (coords.length < 3) return false;
  let inside = false;
  let j = coords.length - 1;
  for (let i = 0; i < coords.length; i++) {
    const ci = coords[i], cj = coords[j];
    if ((ci.lng > lng) !== (cj.lng > lng) &&
        lat < (cj.lat - ci.lat) * (lng - ci.lng) / (cj.lng - ci.lng) + ci.lat) {
      inside = !inside;
    }
    j = i;
  }
  return inside;
}
