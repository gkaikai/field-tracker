/// 地理坐标工具函数
/// 
/// 共享Haversine公式实现，避免多处重复定义

import 'dart:math' show sin, cos, sqrt, atan2, pi;

/// 地球半径（米）
const double _earthRadiusMeters = 6371000.0;

/// 角度转弧度
double toRad(double deg) => deg * pi / 180;

/// 计算两点间的大圆距离（米）
/// 使用Haversine公式
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  final dLat = toRad(lat2 - lat1);
  final dLng = toRad(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(toRad(lat1)) * cos(toRad(lat2)) *
      sin(dLng / 2) * sin(dLng / 2);
  return _earthRadiusMeters * 2 * atan2(sqrt(a), sqrt(1 - a));
}

/// 计算两点间的大圆距离（千米）
double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  return haversineMeters(lat1, lng1, lat2, lng2) / 1000.0;
}
