/// WGS-84 (GPS) 转 GCJ-02 (高德/火星坐标系)
///
/// 中国法律规定，所有地图必须使用GCJ-02偏移坐标系。
/// 直接从GPS获取的WGS-84坐标投到高德地图上会有300-500米偏差。
library;
import 'dart:math' show pi, sin, cos, sqrt;

const double a = 6378245.0; // 长半轴
const double ee = 0.00669342162296594323; // 扁率

/// 判断是否在中国境内（不在境内的不偏移）
bool _outOfChina(double lat, double lng) {
  return lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271;
}

double _transformLat(double x, double y) {
  double ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(x.abs());
  ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
  ret += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0;
  ret += (160.0 * sin(y / 12.0 * pi) + 320.0 * sin(y * pi / 30.0)) * 2.0 / 3.0;
  return ret;
}

double _transformLng(double x, double y) {
  double ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(x.abs());
  ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
  ret += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0;
  ret += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0 * pi)) * 2.0 / 3.0;
  return ret;
}

/// 将WGS-84坐标转换为GCJ-02坐标
///
/// 输入: 标准GPS坐标 (WGS-84)
/// 输出: 高德地图坐标 (GCJ-02)
/// 返回: (gcjLat, gcjLng)
(double, double) wgs84ToGcj02(double wgsLat, double wgsLng) {
  if (_outOfChina(wgsLat, wgsLng)) {
    return (wgsLat, wgsLng);
  }
  double dlat = _transformLat(wgsLng - 105.0, wgsLat - 35.0);
  double dlng = _transformLng(wgsLng - 105.0, wgsLat - 35.0);
  double radlat = wgsLat / 180.0 * pi;
  double magic = sin(radlat);
  magic = 1 - ee * magic * magic;
  double sqrtmagic = sqrt(magic);
  dlat = (dlat * 180.0) / ((a * (1 - ee)) / (magic * sqrtmagic) * pi);
  dlng = (dlng * 180.0) / (a / sqrtmagic * cos(radlat) * pi);
  return (wgsLat + dlat, wgsLng + dlng);
}
