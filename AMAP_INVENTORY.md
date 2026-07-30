# 高德地图（AMap）API 调用/配置完整清单

> 生成时间：2026-07-29
> 项目路径：`/Users/openclaw-gkf/development/field_tracker`

---

## 一、密钥配置

### 1. Flutter 端 (编译注入 + 原生配置文件)

| 密钥名 | 定义位置 | 注入方式 | 值 |
|--------|---------|---------|-----|
| **AMAP_ANDROID_KEY** (Android) | `app/lib/config/amap_key.dart:13` | `--dart-define=AMAP_ANDROID_KEY=xxx` | 不硬编码，编译注入 |
| **AMAP_IOS_KEY** (iOS) | `app/lib/config/amap_key.dart:15` | `--dart-define=AMAP_IOS_KEY=xxx` | 不硬编码，编译注入 |
| **AMAP_WS_KEY** (Web服务端) | `app/lib/config/amap_key.dart:18` | `--dart-define=AMAP_WS_KEY=xxx` | 不硬编码，编译注入 |
| **AMAP_WS_SECURITY_CODE** | `app/lib/config/amap_key.dart:19` | 硬编码（但值为空字符串） | `''`（空） |

### 2. Android 原生 (硬编码)

| 密钥名 | 定义位置 | 值 |
|--------|---------|-----|
| **com.amap.api.v2.apikey** (AndroidManifest) | `app/android/app/src/main/AndroidManifest.xml:35-36` | `0e00439a3a2b04282e78083ea7a9b19d`² |
| **iOS Info.plist AMapApiKey** | `app/ios/Runner/Info.plist:61-62` | `9debae73ed4f59ce9f934c9b1fda1a23` |

### 3. Web 管理端 (硬编码)

| 密钥名 | 定义位置 | 值 |
|--------|---------|-----|
| **JS API Key** | `server/public/admin.html:60` | `7ac68442bb2d4a49a4aab6237ea29f48` |
| **securityJsCode** | `server/public/admin.html:58` | `f54f44a83e49995348e72713f2ca1b9a` |

### 4. 服务端 (环境变量)

| 密钥名 | 定义位置 | 值 |
|--------|---------|-----|
| **AMAP_WS_KEY** (Express 服务端) | `server/.env` | `665f6c9959c69f9c08ae1d869d2b7abd` |
| 引用位置 | `server/src/routes/geocode.ts:21` | `process.env.AMAP_WS_KEY` |

> 注：AndroidManifest 中的 `0e00439a3a2b04282e78083ea7a9b19d` 和 iOS Info.plist 中的 `9debae73ed4f59ce9f934c9b1fda1a23` 可能是旧版 SDK 遗留，因为 Flutter 3.x 插件实际上要求通过 Dart 代码 `AMapFlutterLocation.setApiKey()` 注入，AndroidManifest 配置已无效。

---

## 二、pubspec.yaml 依赖（高德相关）

`app/pubspec.yaml`:

```yaml
dependencies:
  amap_flutter_map: ^3.0.0       # 高德地图 Flutter 插件（地图 UI）
  amap_flutter_base: ^3.0.0      # 高德地图 Flutter 基础库
  amap_flutter_location: ^3.0.0  # 高德定位 Flutter 插件
```

---

## 三、Android 原生依赖 (build.gradle.kts)

`app/android/app/build.gradle.kts:61-62`:

```kotlin
implementation("com.amap.api:3dmap:8.1.0")   // 高德 3D 地图 SDK
implementation("com.amap.api:location:5.6.0") // 高德定位 SDK
```

---

## 四、iOS Podfile 依赖

`app/ios/Podfile:36-38`:

```ruby
pod 'AMapLocation-NO-IDFA', '>= 2.9.0'      // 高德定位 SDK (无IDFA)
pod 'AMapSearch-NO-IDFA', '>= 9.0.0'         // 高德搜索 SDK (无IDFA)
pod 'AMapFoundation-NO-IDFA', '>= 1.8.0'     // 高德基础库 (无IDFA)
```

---

## 五、Flutter 端高德 SDK 初始化

### 5.1 隐私合规 + Key 注入（main.dart）

**文件**：`app/lib/main.dart:18-22`

```dart
AMapFlutterLocation.updatePrivacyShow(true, true);       // 隐私合规声明
AMapFlutterLocation.updatePrivacyAgree(true);             // 用户同意隐私
AMapFlutterLocation.setApiKey(AMapConfig.androidKey, AMapConfig.iosKey); // 注入Key
```

### 5.2 AMapConfig 配置类

**文件**：`app/lib/config/amap_key.dart`

```dart
class AMapConfig {
  static const String androidKey = String.fromEnvironment('AMAP_ANDROID_KEY', defaultValue: '');
  static const String iosKey = String.fromEnvironment('AMAP_IOS_KEY', defaultValue: '');
  static const String webServiceKey = String.fromEnvironment('AMAP_WS_KEY', defaultValue: '');
  static const String webServiceSecurityCode = '';
  static const int uploadBatchSize = 10;
  static const int uploadIntervalMs = 60000;
}
```

### 5.3 AppConfig 兼容引用

**文件**：`app/lib/config/app_config.dart:87`

```dart
static String get amapApiKey => AMapConfig.androidKey;  // 兼容旧代码
```

---

## 六、Flutter 端 AMapWidget 使用

所有使用 `AMapWidget` 的页面都传入 `AMapApiKey`：

### 6.1 地图首页 — map_page.dart

**文件**：`app/lib/pages/map_page.dart:367-371`

```dart
AMapWidget(
  apiKey: AMapApiKey(
    androidKey: AMapConfig.androidKey,
    iosKey: AMapConfig.iosKey,
  ),
  mapType: _mapType,
  privacyStatement: const AMapPrivacyStatement(hasContains: true, hasShow: true, hasAgree: true),
  initialCameraPosition: CameraPosition(target: LatLng(39.909, 116.397), zoom: 15),
  myLocationStyleOptions: MyLocationStyleOptions(true),
  compassEnabled: true, scaleEnabled: true,
  zoomGesturesEnabled: true, scrollGesturesEnabled: true,
  markers: _customerMarkers,
  polygons: _fencePolygons,
)
```

### 6.2 电子围栏页 — fence_page.dart

**文件**：`app/lib/pages/fence_page.dart:1117-1119`

```dart
apiKey: AMapApiKey(
  androidKey: AMapConfig.androidKey,
  iosKey: AMapConfig.iosKey,
),
```

### 6.3 围栏编辑页 — fence_edit_page.dart

**文件**：`app/lib/pages/fence_edit_page.dart:561-563`

```dart
apiKey:
  androidKey: AMapConfig.androidKey,
  iosKey: AMapConfig.iosKey,
```

### 6.4 轨迹回放页 — track_replay_page.dart

**文件**：`app/lib/pages/track_replay_page.dart:1024-1026`

```dart
apiKey: AMapApiKey(
  androidKey: AMapConfig.androidKey,
  iosKey: AMapConfig.iosKey,
),
```

---

## 七、Flutter 端定位服务 (AMapLocationClient)

### 7.1 核心定位服务 — AmapLocationService

**文件**：`app/lib/services/amap_location_service.dart`

核心定位逻辑类，通过原生 ForegroundService 的 AMapLocationClient 获取 GPS 数据，MethodChannel 回传 Flutter。

- 使用 `AMapLocationClient`（单一进程唯一实例）
- 3 点滑动中值滤波 + 漂移检测
- 精度校验：拒绝 >100m 的点（`AppConfig.maxAcceptableAccuracy`）
- GPS 看门狗：60 秒无数据则重建 ForegroundService（每小时最多 3 次）
- 状态机：MOVING（3秒间隔）/ UNCERTAIN / STATIONARY（60秒间隔）

### 7.2 后台定位服务桥接 — background_location_service.dart

**文件**：`app/lib/services/background_location_service.dart`

MethodChannel 与原生 Java 代码的桥梁：

```dart
const MethodChannel _channel = MethodChannel('com.fieldtracker/location_service');
```

- `startBackgroundLocationService()` — 启动原生 ForegroundService
- `stopBackgroundLocationService()` — 停止
- `setNativeGpsInterval(int intervalMs)` — 热切换 GPS 采集间隔
- `setupNativeLocationCallback()` — 注册 MethodChannel 回调（`onLocationUpdate`）

### 7.3 原生 Java 定位服务 — LocationForegroundService.java

**文件**：`app/android/app/src/main/java/com/fieldtracker/app/LocationForegroundService.java`

```java
import com.amap.api.location.AMapLocation;
import com.amap.api.location.AMapLocationClient;
import com.amap.api.location.AMapLocationClientOption;
import com.amap.api.location.AMapLocationListener;
```

定位参数配置（`AMapLocationClientOption`）：
- **定位模式**: `Hight_Accuracy`（高精度模式：GPS + 网络）
- **采集间隔**: 默认 3000ms（3秒），动态切换
- **onceLocation**: false（连续定位）
- **needAddress**: false（不需要地址信息）
- **locationCacheEnable**: false（关闭缓存）
- **sensorEnable**: true（启用传感器辅助）

数据流向：`AMapLocationClient` → `onLocationChanged()` → MethodChannel → Flutter

---

## 八、Flutter 端调用高德 Web Service API

### 8.1 ApiService.amapDio（专用 Dio 实例）

**文件**：`app/lib/services/api_service.dart:209-212`

```dart
static final Dio amapDio = Dio(BaseOptions(
  connectTimeout: Duration(seconds: 10),
  receiveTimeout: Duration(seconds: 10),
  headers: {'Content-Type': 'application/json'},
));
```
特点：不添加 Bearer token、不经过业务拦截器、不经过熔断器。

### 8.2 POI 搜索组件 — poi_search_field.dart

**文件**：`app/lib/widgets/poi_search_field.dart`

| 端点 | API 类型 | 用途 | 参数 |
|------|---------|------|------|
| `restapi.amap.com/v3/place/text` | POI 文本搜索 | 精确搜索 (offset=1, page=1) | `key`, `keywords`, `output=JSON`, `offset`, `page`, `extensions=base` |
| `restapi.amap.com/v3/place/text` | POI 文本搜索 | 模糊建议 (offset=15) | 同上，offset=15 |
| `restapi.amap.com/v3/geocode/geo` | 地理编码 | POI 搜不到时回退 | `key`, `address`, `output=JSON`, `city` |

### 8.3 电子围栏页搜索 — fence_page.dart

**文件**：`app/lib/pages/fence_page.dart`

| 端点 | API 类型 | 用途 | 参数 |
|------|---------|------|------|
| `restapi.amap.com/v3/place/text` | POI 文本搜索 | 模糊建议 (offset=15) | `key`, `keywords`, `output=JSON`, `offset=15` |
| `restapi.amap.com/v3/place/text` | POI 文本搜索 | 精确搜索 (offset=1) | `key`, `keywords`, `output=JSON`, `offset=1` |
| `restapi.amap.com/v3/geocode/geo` | 地理编码 | 地址回退 | `key`, `address`, `output=JSON`, `city` |

### 8.4 围栏编辑页搜索 — fence_edit_page.dart

**文件**：`app/lib/pages/fence_edit_page.dart`

与 fence_page.dart 完全相同的高德 API 调用（POI 搜索 + 地理编码回退）。

### 8.5 客户页面搜索 — customer_page.dart

**文件**：`app/lib/pages/customer_page.dart:96-97`

| 端点 | API 类型 | 用途 |
|------|---------|------|
| `restapi.amap.com/v3/assistant/inputtips` | 输入提示 | 客户地址模糊搜索 |

```dart
final resp = await dio.get(
  'https://restapi.amap.com/v3/assistant/inputtips',
  queryParameters: {'key': AMapConfig.webServiceKey, 'keywords': v.trim(), 'output': 'JSON'},
);
```

---

## 九、服务端高德 API 代理

### 9.1 地理编码代理路由 — geocode.ts

**文件**：`server/src/routes/geocode.ts`

```typescript
const key = process.env.AMAP_WS_KEY || '';
const url = `https://restapi.amap.com/v3/geocode/geo?key=${key}&address=${encodeURIComponent(address)}&output=JSON`;
```

| 项目 | 值 |
|------|-----|
| 路由 | `GET /api/v1/geocode/search` |
| 参数 | `address` (query string) |
| 高德 API | `restapi.amap.com/v3/geocode/geo` |
| 密钥来源 | 环境变量 `AMAP_WS_KEY` (server/.env) |
| 认证要求 | 需要 JWT auth middleware |
| 安全备注 | Key 通过 URL query 参数传递，会被服务器访问日志明文记录 |

---

## 十、Web 管理端高德 JS API 调用

### 10.1 HTML 加载

**文件**：`server/public/admin.html:58-60`

```html
<script>
window._AMapSecurityConfig = { securityJsCode: 'f54f44a83e49995348e72713f2ca1b9a' };
</script>
<script src="https://webapi.amap.com/maps?v=2.0&key=7ac68442bb2d4a49a4aab6237ea29f48"></script>
```

### 10.2 JS API 使用 (admin.js)

**文件**：`server/public/admin.js`

#### 公用工具函数

| 函数 | 说明 |
|------|------|
| `makeMap(containerId, center, zoom)` | 创建 AMap.Map 实例 + 加载 ToolBar/Scale 插件 |
| `addLayerToggle(map)` | 卫星/标准地图切换（AMap.TileLayer.Satellite） |

#### 围栏管理模块 (fence tab)

| 使用 | AMap API/类 |
|------|------------|
| `AMap.Map` | 地图容器 `fenceMap` |
| `AMap.ToolBar` | 缩放工具条 |
| `AMap.Scale` | 比例尺 |
| `AMap.PlaceSearch` | POI 搜索（type='poi', pageSize=20） |
| `AMap.AutoComplete` | 输入自动补全（datatype='all', pageSize=15） |
| `AMap.Marker` | 地图标记（搜索位置标记） |
| `AMap.Bounds` | 视野计算（多结果自适应缩放） |
| `AMap.Pixel` | 像素偏移（label 定位） |
| `AMap.Marker` (draggable) | 可拖拽标记（围栏圆心/多边形顶点） |
| `AMap.Polyline` | 辅助线（多边形绘制中） |
| `AMap.Polygon` | 多边形围栏覆盖物 |
| `AMap.Circle` (注释引用) | 圆形围栏（代码用边形逼近绕过） |

#### 实时监控模块 (monitor tab)

| 使用 | AMap API/类 |
|------|------------|
| `AMap.Map` | 地图容器 `_monitorMap` |
| `AMap.Marker` | 人员实时位置标记 |
| `AMap.Polyline` | 轨迹线显示 |
| `AMap.Marker` | 轨迹起点（绿点）/ 终点（红点）标记 |
| `AMap.Marker` (content) | 自定义 HTML 内容标记 |
| 轨迹动画 | 通过定时器 + Marker.setPosition 实现 |

#### 轨迹回放模块 (tracks tab)

| 使用 | AMap API/类 |
|------|------------|
| `AMap.Map` | 地图容器 `trackMap` |
| `AMap.Polyline` | 轨迹线 |
| `AMap.Marker` | 起点/终点标记 |
| `AMap.Marker` (content) | 动画播放中的位置标记（三角箭头） |
| `map.setFitView()` | 自适应视野 |
| `map.setCenter()` | 动态居中 |

---

## 十一、setup.sh 高德配置脚本

**文件**：`setup.sh:36-58`

- 提示用户输入 Android 高德 Key → 写入 `amap_key.dart`
- 提示用户输入 Web 管理端 JS API Key → 写入 `admin.html`
- 提供高德开发者平台地址：`https://lbs.amap.com/dev/key/app`

---

## 十二、测试文件中的引用

| 文件 | 内容 |
|------|------|
| `app/test/config_test.dart` | 测试 AMapConfig 相关配置 |
| `app/test/service_test.dart` | 测试定位服务 |
| `app/test/background_task_test.dart` | 测试后台定位任务 |
| `app/test/edge_case_test.dart` | 边缘情况测试（可能涉及定位） |
| `app/integration_test/app_test.dart` | 端到端测试（含地图） |

---

## 十三、密钥总表（实际值）

| 密钥角色 | 值 | 使用方 | 位置 |
|---------|-----|-------|------|
| Android (Manifest) | `0e00439a3a2b04282e78083ea7a9b19d` | Android 原生 SDK | `AndroidManifest.xml` |
| iOS (Info.plist) | `9debae73ed4f59ce9f934c9b1fda1a23` | iOS 原生 SDK | `Info.plist` |
| Web JS API | `7ac68442bb2d4a49a4aab6237ea29f48` | Web 管理端 | `admin.html` |
| securityJsCode | `f54f44a83e49995348e72713f2ca1b9a` | Web JS API 安全 | `admin.html` |
| 服务端 WS Key | `665f6c9959c69f9c08ae1d869d2b7abd` | Express 代理 | `server/.env` |

**注**：Flutter 端 AMAP_ANDROID_KEY / AMAP_IOS_KEY / AMAP_WS_KEY 通过 `--dart-define` 编译注入，不在源码中硬编码。

---

## 十四、架构总结

```
┌─────────────────────────────────────────────────────┐
│                    Flutter APP                        │
│                                                       │
│  AMapWidget (4 pages) ← amap_flutter_map/amap_flutter_base |
│  AmapLocationService (定位服务)                           │
│    └─ MethodChannel → 原生 ForegroundService            │
│         └─ AMapLocationClient (GPS采集)                 │
│  Web Service API 调用:                                   │
│    poi_search_field (POI文本搜索+地理编码回退)            │
│    fence_page (POI搜索+地理编码)                         │
│    fence_edit_page (POI搜索+地理编码)                    │
│    customer_page (inputtips输入提示)                     │
├─────────────────────────────────────────────────────┤
│                Express 服务端                            │
│  geocode.ts → GET /api/v1/geocode/search                 │
│    └─ 代理: restapi.amap.com/v3/geocode/geo              │
├─────────────────────────────────────────────────────┤
│            Web 管理后台 (admin.html/admin.js)            │
│  AMap JS API v2.0                                        │
│    └─ 围栏管理: Map + PlaceSearch + AutoComplete       │
│    └─ 实时监控: Map + Marker + Polyline + 轨迹动画     │
│    └─ 轨迹回放: Map + Polyline + Marker                │
└─────────────────────────────────────────────────────┘
```
