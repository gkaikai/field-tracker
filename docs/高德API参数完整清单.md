# 高德地图 API 参数完整清单

> 项目：Field Tracker（人员定位管理APP）
> 日期：2026-07-29
> 用途：提供给第三方或团队查阅所有高德API调用参数

---

## 目录

1. [密钥配置总表](#1-密钥配置总表)
2. [Flutter SDK 初始化参数](#2-flutter-sdk-初始化参数)
3. [移动端 REST API 调用参数](#3-移动端-rest-api-调用参数)
4. [服务端代理 API 参数](#4-服务端代理-api-参数)
5. [Android 原生 SDK 配置](#5-android-原生-sdk-配置)
6. [iOS 原生 SDK 配置](#6-ios-原生-sdk-配置)
7. [Web 管理后台 JS API 配置](#7-web-管理后台-js-api-配置)
8. [构建命令参数](#8-构建命令参数)

---

## 1. 密钥配置总表

### 1.1 所有密钥值

| 序号 | 密钥名称 | 用途 | 实际值 | 配置位置 |
|------|---------|------|--------|---------|
| ① | **Android 原生 Key** | Android 端定位+地图 SDK | `0e00439a3a2b04282e78083ea7a9b19d` | `AndroidManifest.xml` <meta-data> |
| ② | **iOS Key** | iOS 端定位+地图 SDK | `9debae73ed4f59ce9f934c9b1fda1a23` | `Info.plist` <key>AMapApiKey</key> |
| ③ | **Web JS API Key** | 管理后台高德JS地图 v2.0 | `7ac68442bb2d4a49a4aab6237ea29f48` | `admin.html` script src URL |
| ④ | **Web JS SecurityCode** | JS API 安全密钥 | `f54f44a83e49995348e72713f2ca1b9a` | `admin.html` AMapSecurityConfig |
| ⑤ | **Web Service Key** | POI搜索/地理编码 Web API | `665f6c9959c69f9c08ae1d869d2b7abd` | 编译注入 + `server/.env` |

### 1.2 密钥传递方式

| 端 | 注入方式 | 源码对应 |
|----|---------|---------|
| Flutter APP | `--dart-define=AMAP_ANDROID_KEY=xxx` 编译参数 | `amap_key.dart` `String.fromEnvironment()` 读取 |
| Android 原生 | `AndroidManifest.xml` 硬编码 | 直接在 `<meta-data>` 节点 |
| iOS 原生 | `Info.plist` 硬编码 | 直接在 `<key>AMapApiKey</key>` |
| Web 管理后台 | `admin.html` 硬编码 | script 标签 + securityConfig 对象 |
| 服务端 | `.env` 环境变量 | `process.env.AMAP_WS_KEY` 读取 |

---

## 2. Flutter SDK 初始化参数

### 2.1 main.dart 初始化（隐私合规 + Key注入）

```dart
// 文件：lib/main.dart (约第18-22行)

// 第一步：隐私合规声明（必须在 SDK 初始化前调用）
AMapFlutterLocation.updatePrivacyShow(true, true);     // 已展示隐私协议
AMapFlutterLocation.updatePrivacyAgree(true);           // 用户已同意

// 第二步：注入 Key（编译时通过 --dart-define 传入）
AMapFlutterLocation.setApiKey(AMapConfig.androidKey, AMapConfig.iosKey);
```

### 2.2 AMapConfig 类

```dart
// 文件：lib/config/amap_key.dart

class AMapConfig {
  // Android Key — 编译注入
  static const String androidKey = String.fromEnvironment('AMAP_ANDROID_KEY', defaultValue: '');
  // iOS Key — 编译注入
  static const String iosKey = String.fromEnvironment('AMAP_IOS_KEY', defaultValue: '');
  // Web Service Key（POI搜索/地理编码）— 编译注入
  static const String webServiceKey = String.fromEnvironment('AMAP_WS_KEY', defaultValue: '');
  // 安全码（当前未使用）
  static const String webServiceSecurityCode = '';

  // 定位上报参数
  static const int uploadBatchSize = 10;           // 每批上报点数
  static const int uploadIntervalMs = 60000;        // 上报间隔(ms)
}
```

### 2.3 AMapWidget 通用参数（4个页面一致）

```dart
AMapWidget(
  apiKey: AMapApiKey(
    androidKey: AMapConfig.androidKey,
    iosKey: AMapConfig.iosKey,
  ),
  // 隐私声明
  privacyStatement: const AMapPrivacyStatement(
    hasContains: true,    // 协议包含隐私政策
    hasShow: true,       // 已展示
    hasAgree: true,      // 已同意
  ),
  // 默认视角：天安门（首次加载默认）
  initialCameraPosition: CameraPosition(
    target: LatLng(39.909, 116.397),
    zoom: 15,
  ),
  // 定位蓝点
  myLocationStyleOptions: MyLocationStyleOptions(true),
  // 控件
  compassEnabled: true,     // 指南针
  scaleEnabled: true,       // 比例尺
  zoomGesturesEnabled: true, // 缩放手势
  scrollGesturesEnabled: true, // 拖拽手势
)
```

使用此参数的页面：

| 页面 | 文件 | 额外参数 |
|------|------|---------|
| 地图首页 | `map_page.dart` | `mapType`, `markers(_customerMarkers)`, `polygons(_fencePolygons)` |
| 电子围栏 | `fence_page.dart` | — |
| 围栏编辑 | `fence_edit_page.dart` | — |
| 轨迹回放 | `track_replay_page.dart` | `polylines`, `markers`(轨迹点) |

---

## 3. 移动端 REST API 调用参数

统一使用 `ApiService.amapDio` 发起 HTTP 请求，Dio实例配置：

```dart
// 文件：lib/services/api_service.dart (约209-215行)
static final Dio amapDio = Dio(BaseOptions(
  connectTimeout: Duration(seconds: 10),    // 连接超时10秒
  receiveTimeout: Duration(seconds: 10),    // 接收超时10秒
  headers: {'Content-Type': 'application/json'},
));
// 特点：无 Bearer Token、无业务拦截器、无熔断器
```

### 3.1 POI 文本搜索

```
请求方式: GET
基础URL: https://restapi.amap.com/v3/place/text
```

#### 参数表

| 参数名 | 类型 | 必填 | 默认值 | 说明 |
|--------|------|------|--------|------|
| `key` | string | ✅ | — | Web Service Key (`665f6c9959c69f9c08ae1d869d2b7abd`) |
| `keywords` | string | ✅ | — | 搜索关键词（如"成都高新区天府大道"） |
| `output` | string | ❌ | `JSON` | 返回格式，固定填 `JSON` |
| `offset` | int | ❌ | `20` | 每页记录数：**模糊建议=15，精确搜索=1** |
| `page` | int | ❌ | `1` | 页码，默认1 |
| `extensions` | string | ❌ | `base` | 返回结果控制：`base`（基本信息）/ `all`（详细信息） |

#### 调用场景

| 场景 | offset | 调用文件 | 行号 |
|------|--------|---------|------|
| 输入时模糊建议（防抖400ms） | 15 | `poi_search_field.dart` | 176 |
| 搜索按钮精确搜索 | 1 | `poi_search_field.dart` | 94 |
| 围栏页模糊建议 | 15 | `fence_page.dart` | — |
| 围栏页精确搜索 | 1 | `fence_page.dart` | — |
| 围栏编辑页搜索 | 1/15 | `fence_edit_page.dart` | — |

#### 返回格式

```json
{
  "status": "1",            // 1=成功, 0=失败
  "info": "OK",
  "count": "15",            // 结果总数
  "pois": [
    {
      "name": "成都高新区管委会",
      "address": "四川省成都市高新区天府大道北段18号",
      "location": "104.063576,30.570078",    // 注意：经度在前，纬度在后
      "pname": "四川省",
      "cityname": "成都市",
      "adname": "高新区",
      "type": "政府机构;政府机关;行政单位",
      "typecode": "160100"
    }
  ]
}
```

### 3.2 地理编码（POI回退）

```
请求方式: GET
基础URL: https://restapi.amap.com/v3/geocode/geo
```

#### 参数表

| 参数名 | 类型 | 必填 | 默认值 | 说明 |
|--------|------|------|--------|------|
| `key` | string | ✅ | — | Web Service Key |
| `address` | string | ✅ | — | 结构化地址（如"成都市高新区天府大道"） |
| `output` | string | ❌ | `JSON` | 返回格式 |
| `city` | string | ❌ | `""` | 指定城市，空字符串自动识别 |

#### 调用场景

| 场景 | 触发条件 | 文件 |
|------|---------|------|
| POI精确搜索无结果 | POI搜不到时自动降级 | `poi_search_field.dart:226` |
| 围栏页搜索无结果 | 同上 | `fence_page.dart` |
| 围栏编辑页搜索无结果 | 同上 | `fence_edit_page.dart` |

#### 返回格式

```json
{
  "status": "1",
  "info": "OK",
  "geocodes": [
    {
      "formatted_address": "四川省成都市高新区天府大道北段18号",
      "location": "104.063576,30.570078",
      "level": "区县"     // 匹配级别：省/市/区县/兴趣点
    }
  ]
}
```

### 3.3 输入提示

```
请求方式: GET
基础URL: https://restapi.amap.com/v3/assistant/inputtips
```

#### 参数表

| 参数名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `key` | string | ✅ | Web Service Key |
| `keywords` | string | ✅ | 用户输入的关键词 |
| `output` | string | ❌ | `JSON` |

#### 调用场景

| 场景 | 使用处 | 文件 |
|------|-------|------|
| 客户页面地址搜索 | 客户地址输入 | `customer_page.dart:96-97` |

---

## 4. 服务端代理 API 参数

### 4.1 地理编码代理

```
路由: GET /api/v1/geocode/search
认证: 需要 JWT Token（Bearer auth）
```

#### 请求参数

| 参数名 | 类型 | 位置 | 必填 | 说明 |
|--------|------|------|------|------|
| `address` | string | query | ✅ | 待编码的地址 |
| 无其他参数 | — | — | — | 密钥从环境变量读取 |

#### 内部实现

```typescript
// 文件：server/src/routes/geocode.ts
// 实际转发到高德 API：
const key = process.env.AMAP_WS_KEY || '';
const url = `https://restapi.amap.com/v3/geocode/geo?key=${key}&address=${encodeURIComponent(address)}&output=JSON`;
// 返回：直接透传高德返回的 JSON
```

#### 文件位置

```typescript
// server/src/routes/geocode.ts — 完整路由文件
// server/.env — AMAP_WS_KEY=665f6c9959c69f9c08ae1d869d2b7abd
```

---

## 5. Android 原生 SDK 配置

### 5.1 Gradle 依赖

```gradle
// app/android/app/build.gradle.kts (61-62行)
implementation("com.amap.api:3dmap:8.1.0")   // 高德 3D 地图 SDK
implementation("com.amap.api:location:5.6.0") // 高德定位 SDK
```

### 5.2 AndroidManifest 密钥

```xml
<!-- app/android/app/src/main/AndroidManifest.xml (33-36行) -->
<!-- 高德地图 SDK 配置 -->
<meta-data
    android:name="com.amap.api.v2.apikey"
    android:value="0e00439a3a2b04282e78083ea7a9b19d" />
```

### 5.3 定位服务参数（Java原生）

```java
// 文件：app/android/.../LocationForegroundService.java

AMapLocationClientOption option = new AMapLocationClientOption();
option.setLocationMode(AMapLocationClientOption.AMapLocationMode.Hight_Accuracy); // 高精度模式
option.setInterval(3000);           // 采集间隔：默认3000ms（可动态切换）
option.setOnceLocation(false);      // 连续定位
option.setNeedAddress(false);       // 不需要地址逆地理
option.setLocationCacheEnable(false); // 不缓存
option.setSensorEnable(true);       // 传感器辅助

// 定位客户端
AMapLocationClient client = new AMapLocationClient(context);
client.setLocationOption(option);
client.setLocationListener(location -> {
    // onLocationChanged → MethodChannel → Flutter端
});
```

**定位参数说明：**

| 参数 | 当前值 | 说明 |
|------|--------|------|
| 定位模式 | `Hight_Accuracy` | 高精度（GPS+网络/WiFi辅助） |
| 采集间隔 | 3000ms (3秒) | 每次GPS采集间隔，可动态切换 |
| 单次定位 | false | 连续模式 |
| 逆地理 | false | 不需要地址信息（省电量） |
| 缓存 | false | 不自带缓存 |
| 传感器 | true | 加速度计辅助 |

### 5.4 定位数据流

```
GPS卫星
  ↓
AMapLocationClient (Java原生, ForegroundService)
  ↓ onLocationChanged() 回调
MethodChannel `com.fieldtracker/location_service`
  ↓ onLocationUpdate
AmapLocationService (Flutter Dart)
  ├── 滑动中值滤波（3点均值）
  ├── 精度校验（>100m丢弃）
  ├── GPS看门狗（60秒无数据重建服务）
  └── → location_uploader.dart → POST到业务服务器
```

---

## 6. iOS 原生 SDK 配置

### 6.1 Podfile 依赖

```ruby
# app/ios/Podfile (36-38行)
pod 'AMapLocation-NO-IDFA', '>= 2.9.0'      # 定位SDK（无IDFA版本）
pod 'AMapSearch-NO-IDFA', '>= 9.0.0'         # 搜索SDK（无IDFA版本）
pod 'AMapFoundation-NO-IDFA', '>= 1.8.0'     # 基础库（无IDFA版本）
```

### 6.2 Info.plist 密钥

```xml
<!-- app/ios/Runner/Info.plist (60-62行) -->
<!-- ========== 高德地图 SDK API Key ========== -->
<key>AMapApiKey</key>
<string>9debae73ed4f59ce9f934c9b1fda1a23</string>
```

---

## 7. Web 管理后台 JS API 配置

### 7.1 SDK 加载

```html
<!-- server/public/admin.html (58-60行) -->
<script>
// 安全配置（必须放在加载SDK之前）
window._AMapSecurityConfig = {
    securityJsCode: 'f54f44a83e49995348e72713f2ca1b9a'
};
</script>
<!-- 加载高德 JS API v2.0 -->
<script src="https://webapi.amap.com/maps?v=2.0&key=7ac68442bb2d4a49a4aab6237ea29f48"></script>
```

### 7.2 公用地图工具函数

```javascript
// server/public/admin.js

// 创建地图实例
function makeMap(containerId, center, zoom) {
    return new AMap.Map(containerId, {
        center: center || [104.07, 30.57],  // 默认成都
        zoom: zoom || 14,
        layers: [new AMap.TileLayer()]       // 标准图层
    });
}

// 卫星/标准地图切换
function addLayerToggle(map) {
    const satellite = new AMap.TileLayer.Satellite();
    // UI按钮：切换 map.add([satellite]) / map.remove([satellite])
}
```

### 7.3 各模块使用的高德JS API

#### 围栏管理模块（fence tab）

| AMap 类 | 用途 | 参数 |
|---------|------|------|
| `AMap.Map` | 地图容器 `fenceMap` | center=成都, zoom=14 |
| `AMap.ToolBar` | 缩放工具条 | 默认参数 |
| `AMap.Scale` | 比例尺 | 默认参数 |
| `AMap.PlaceSearch` | POI搜索 | `type='poi'`, `pageSize=20` |
| `AMap.AutoComplete` | 输入自动补全 | `datatype='all'`, `pageSize=15` |
| `AMap.Marker` | 搜索位置标记 | position, label |
| `AMap.Marker` (draggable) | 围栏圆心可拖拽 | draggable=true |
| `AMap.Polygon` | 多边形围栏 | path(顶点路径) |
| `AMap.Polyline` | 多边形辅助线 | 绘图过程中 |

#### 实时监控模块（monitor tab）

| AMap 类 | 用途 | 参数 |
|---------|------|------|
| `AMap.Map` | 地图容器 `_monitorMap` | 动态center |
| `AMap.Marker` | 人员位置标记 | icon(content=HTML), position |
| `AMap.Polyline` | 轨迹线 | path, strokeColor, strokeWeight |
| `AMap.Marker` | 起点(绿)/终点(红) | — |
| `setPosition()` | 轨迹动画 | 定时器+坐标更新 |

#### 轨迹回放模块（tracks tab）

| AMap 类 | 用途 | 参数 |
|---------|------|------|
| `AMap.Map` | 地图容器 `trackMap` | 动态center |
| `AMap.Polyline` | 轨迹线 | path, strokeColor(速度着色) |
| `AMap.Marker` | 起点/终点标记 | 不同颜色 |
| `AMap.Marker` (content) | 动画播放标记 | HTML自定义(三角箭头) |
| `map.setFitView()` | 自适应视野 | — |
| `map.setCenter()` | 动态居中 | — |

---

## 8. 构建命令参数

### 8.1 Flutter 构建（APK）

```bash
flutter build apk --release \
  --dart-define=AMAP_ANDROID_KEY=0e00439a3a2b04282e78083ea7a9b19d \
  --dart-define=AMAP_IOS_KEY=9debae73ed4f59ce9f934c9b1fda1a23 \
  --dart-define=AMAP_WS_KEY=665f6c9959c69f9c08ae1d869d2b7abd
```

### 8.2 Flutter 构建（iOS）

```bash
flutter build ios --release \
  --dart-define=AMAP_ANDROID_KEY=0e00439a3a2b04282e78083ea7a9b19d \
  --dart-define=AMAP_IOS_KEY=9debae73ed4f59ce9f934c9b1fda1a23 \
  --dart-define=AMAP_WS_KEY=665f6c9959c69f9c08ae1d869d2b7abd
```

### 8.3 Flutter 依赖版本

```yaml
# app/pubspec.yaml
dependencies:
  amap_flutter_map: ^3.0.0       # 地图插件
  amap_flutter_base: ^3.0.0      # 基础库
  amap_flutter_location: ^3.0.0  # 定位插件
```

---

## 附录：完整文件索引

| 序号 | 文件路径 | 文件大小 | 涉及内容 |
|------|---------|---------|---------|
| 1 | `app/lib/config/amap_key.dart` | 1.1KB | Key注入配置类 |
| 2 | `app/lib/main.dart` | ~4KB | 隐私合规+Key注入初始化 |
| 3 | `app/lib/services/api_service.dart` | ~7KB | amapDio实例 |
| 4 | `app/lib/services/amap_location_service.dart` | ~18KB | 定位服务+错误码 |
| 5 | `app/lib/services/background_location_service.dart` | ~3KB | MethodChannel桥接 |
| 6 | `app/lib/widgets/poi_search_field.dart` | ~12KB | POI搜索组件(全文) |
| 7 | `app/lib/pages/map_page.dart` | ~16KB | 地图首页AMapWidget |
| 8 | `app/lib/pages/fence_page.dart` | ~20KB | 电子围栏AMapWidget+POI |
| 9 | `app/lib/pages/fence_edit_page.dart` | ~18KB | 围栏编辑AMapWidget+POI |
| 10 | `app/lib/pages/track_replay_page.dart` | ~46KB | 轨迹回放AMapWidget |
| 11 | `app/lib/pages/customer_page.dart` | ~8KB | 客户页面inputtips |
| 12 | `server/public/admin.html` | ~7.7KB | 管理后台HTML+JS API加载 |
| 13 | `server/public/admin.js` | ~18KB | JS API使用全集 |
| 14 | `server/src/routes/geocode.ts` | ~2KB | 服务端地理编码代理 |
| 15 | `android/.../AndroidManifest.xml` | ~3.4KB | Android密钥 |
| 16 | `android/.../LocationForegroundService.java` | ~8KB | 原生定位参数 |
| 17 | `ios/Runner/Info.plist` | ~2.7KB | iOS密钥 |
| 18 | `ios/Podfile` | ~1KB | iOS Pod依赖 |
| 19 | `app/pubspec.yaml` | ~3KB | Flutter依赖 |
| 20 | `server/.env` | — | 服务端密钥 |
