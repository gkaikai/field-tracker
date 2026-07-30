# Field Tracker — 高德地图API完整配置清单

> 最后更新: 2026-07-26
> 项目: 外勤定位APP (Field Tracker)

---

## 一、4个密钥清单

### 1. Android SDK Key
| 属性 | 值 |
|------|-----|
| **Key** | `0e00439a3a2b04282e78083ea7a9b19d` |
| **平台** | Android |
| **用途** | 地图显示、定位SDK、AMapWidget |
| **写入位置** | `android/app/src/main/AndroidManifest.xml` 第36行 |
| **配置方式** | 硬编码在 Manifest（直接写死） |

### 2. iOS SDK Key
| 属性 | 值 |
|------|-----|
| **Key** | `9debae73ed4f59ce9f934c9b1fda1a23` |
| **平台** | iOS |
| **用途** | 地图显示、AMapWidget |
| **写入位置** | `ios/Runner/Info.plist` 第62行 |
| **配置方式** | Info.plist 硬编码 |

### 3. Web端 JS API Key
| 属性 | 值 |
|------|-----|
| **Key** | `7ac68442bb2d4a49a4aab6237ea29f48` |
| **安全密钥** | `f54f44a83e49995348e72713f2ca1b9a` |
| **平台** | Web (JS API v2.0) |
| **用途** | 管理后台地图（实时监控、轨迹回放、围栏管理）|
| **写入位置** | `server/public/admin.html` 第58-60行 |
| **配置方式** | HTML script 标签 + `_AMapSecurityConfig` |

### 4. Web服务 API Key ★☆☆☆☆（所有API搜索用）
| 属性 | 值 |
|------|-----|
| **Key** | `665f6c9959c69f9c08ae1d869d2b7abd` |
| **平台** | Web服务（Restful API） |
| **用途** | POI搜索、地理编码、逆地理编码 |
| **写入位置** | 编译注入 `--dart-define=AMAP_WS_KEY=xxx` |
| **配置方式** | Flutter 编译时注入 `String.fromEnvironment('AMAP_WS_KEY')` |

---

## 二、Flutter端调用高德API（APP）

### 2.1 地图组件（3处）

| 页面 | 文件 | 行号 | 使用方式 |
|------|------|------|----------|
| 实时地图 | `pages/map_page.dart` | L368 | `AMapWidget(apiKey: AMapApiKey(androidKey, iosKey))` |
| 轨迹回放 | `pages/track_replay_page.dart` | L1024 | `AMapWidget(apiKey: AMapApiKey(androidKey, iosKey))` |
| 围栏管理 | `pages/fence_page.dart` | L1117 | `AMapWidget(apiKey: AMapApiKey(androidKey, iosKey))` |

**定位初始化**（`main.dart` 第22行）：
```dart
AMapFlutterLocation.setApiKey(AMapConfig.androidKey, AMapConfig.iosKey);
```

### 2.2 高德POI搜索（手机端模糊建议+精确搜索）

| 位置 | 文件名 | 行号 | 调用API |
|------|--------|------|---------|
| 围栏搜索 | `pages/fence_page.dart` | L237 | `restapi.amap.com/v3/place/text` |
| 通用搜索组件 | `widgets/poi_search_field.dart` | L95 | `restapi.amap.com/v3/place/text` |
| 通用搜索-地理编码回退 | `widgets/poi_search_field.dart` | L229 | `restapi.amap.com/v3/geocode/geo` |

**搜索API参数**：
- URL: `https://restapi.amap.com/v3/place/text`
- Query: `{ key: AMapConfig.webServiceKey, keywords, output: 'JSON', offset: '15', page: '1' }`
- 地理编码回退: `https://restapi.amap.com/v3/geocode/geo`
- 无安全密钥（Web服务Key不需要 `_AMapSecurityConfig`）

### 2.3 Flutter高德依赖（pubspec.yaml）

```yaml
amap_flutter_map: ^3.0.0      # 地图显示
amap_flutter_location: ^3.0.0  # 定位服务
amap_flutter_base: ^3.0.0     # 基础库
```

### 2.4 编译构建命令

```bash
# 发布APK（必须传 --dart-define）
flutter build apk \
  --dart-define=AMAP_ANDROID_KEY=0e00439a3a2b04282e78083ea7a9b19d \
  --dart-define=AMAP_IOS_KEY=9debae73ed4f59ce9f934c9b1fda1a23 \
  --dart-define=AMAP_WS_KEY=665f6c9959c69f9c08ae1d869d2b7abd

# 调试运行（--dart-define 同样需要）
flutter run \
  --dart-define=AMAP_ANDROID_KEY=0e00439a3a2b04282e78083ea7a9b19d \
  --dart-define=AMAP_IOS_KEY=9debae73ed4f59ce9f934c9b1fda1a23 \
  --dart-define=AMAP_WS_KEY=665f6c9959c69f9c08ae1d869d2b7abd
```

---

## 三、管理后台（Web端）高德API

### 3.1 JS API v2.0 加载

| 文件 | 行号 | 代码 |
|------|------|------|
| `admin.html` | L58 | `window._AMapSecurityConfig = { securityJsCode: 'f54f44a83e49995348e72713f2ca1b9a' };` |
| `admin.html` | L60 | `<script src="https://webapi.amap.com/maps?v=2.0&key=7ac68442bb2d4a49a4aab6237ea29f48"></script>` |

### 3.2 JS API插件

| 插件 | 用途 | 加载方式 |
|------|------|----------|
| `AMap.PlaceSearch` | POI精确搜索（搜索按钮） | `AMap.plugin()` |
| `AMap.AutoComplete` | 输入建议下拉 | `AMap.plugin()` |
| `AMap.ToolBar` | 缩放工具条 | `m.addControl()` |
| `AMap.Scale` | 比例尺 | `m.addControl()` |

### 3.3 围栏搜索流程

```
用户输入 "老君山"
  ↓ keyboard 输入事件
  → fenceAuto.search("老君山")       ← AMap.AutoComplete（建议列表）
  ↓ 用户点击建议项 或 点击搜索按钮
  → fencePlaceSearch.search(...)    ← AMap.PlaceSearch（精确搜索）
  ↓ 定位到地图 + 标记Marker
```

---

## 四、原生平台配置

### Android (`AndroidManifest.xml`)

```xml
<!-- 第34-36行: 高德Key -->
<meta-data
    android:name="com.amap.api.v2.apikey"
    android:value="0e00439a3a2b04282e78083ea7a9b19d" />

<!-- 前台定位服务（第69-73行） -->
<service
    android:name="com.fieldtracker.app.LocationForegroundService"
    android:foregroundServiceType="location"
    android:exported="false" />
```

### iOS (`Info.plist`)

```xml
<!-- 第61-62行 -->
<key>AMapApiKey</key>
<string>9debae73ed4f59ce9f934c9b1fda1a23</string>
```

---

## 五、密钥使用对照表

| 密钥值（完整） | 平台 | 存哪里 | 类型 |
|---------------|------|--------|------|
| `0e00439a3a2b04282e78083ea7a9b19d` | Android | `AndroidManifest.xml` | SDK Key |
| `9debae73ed4f59ce9f934c9b1fda1a23` | iOS | `Info.plist` | SDK Key |
| `7ac68442bb2d4a49a4aab6237ea29f48` | Web JS | `admin.html:60` | JS API Key |
| `f54f44a83e49995348e72713f2ca1b9a` | Web 安全 | `admin.html:58` | JS API安全密钥 |
| `665f6c9959c69f9c08ae1d869d2b7abd` | Web服务 | `--dart-define` 编译注入 | Web服务Key |
