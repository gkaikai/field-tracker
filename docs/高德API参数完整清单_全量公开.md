# 高德地图 API 参数完整清单（全量公开版）

> 项目：Field Tracker（人员定位管理APP）
> 日期：2026-07-29
> 本文件包含所有实际值、完整参数、完整请求示例，无任何隐藏或引用

---

## 一、所有密钥实际值（共5个，全部公开）

| # | 密钥名称 | 实际值 | 使用端 | 在哪里写的 |
|---|---------|--------|-------|-----------|
| 1 | Android Key | `0e00439a3a2b04282e78083ea7a9b19d` | Android原生定位+地图SDK | `AndroidManifest.xml` 第36行 `<meta-data android:name="com.amap.api.v2.apikey" android:value="0e00439a3a2b04282e78083ea7a9b19d" />` |
| 2 | iOS Key | `9debae73ed4f59ce9f934c9b1fda1a23` | iOS原生定位+地图SDK | `Info.plist` 第62行 `<key>AMapApiKey</key><string>9debae73ed4f59ce9f934c9b1fda1a23</string>` |
| 3 | Web JS API Key | `7ac68442bb2d4a49a4aab6237ea29f48` | 管理后台高德JS地图v2.0 | `admin.html` 第60行 `script src="https://webapi.amap.com/maps?v=2.0&key=7ac68442bb2d4a49a4aab6237ea29f48"` |
| 4 | Web JS SecurityCode | `f54f44a83e49995348e72713f2ca1b9a` | JS API安全密钥 | `admin.html` 第58行 `window._AMapSecurityConfig = { securityJsCode: 'f54f44a83e49995348e72713f2ca1b9a' }` |
| 5 | Web Service Key | `665f6c9959c69f9c08ae1d869d2b7abd` | POI搜索/地理编码 Web API | 编译注入 `--dart-define=AMAP_WS_KEY=665f6c9959c69f9c08ae1d869d2b7abd` + `server/.env` 文件 |

---

## 二、Flutter SDK 初始化（main.dart）

### 2.1 代码原文

```dart
// 文件：app/lib/main.dart（第18-22行）
import 'package:amap_flutter_location/amap_flutter_location.dart';
import 'config/amap_key.dart';

void main() {
  // 第一步：隐私合规声明（必须在 SDK 初始化前调用，否则报错）
  AMapFlutterLocation.updatePrivacyShow(true, true);       // 参数1=是否包含隐私协议, 参数2=是否展示给用户
  AMapFlutterLocation.updatePrivacyAgree(true);             // 参数=true表示用户已同意

  // 第二步：注入 Key
  AMapFlutterLocation.setApiKey(
    '0e00439a3a2b04282e78083ea7a9b19d',   // Android Key
    '9debae73ed4f59ce9f934c9b1fda1a23',   // iOS Key
  );

  runApp(const MyApp());
}
```

### 2.2 AMapConfig 类（完整代码）

```dart
// 文件：app/lib/config/amap_key.dart（全部28行）
class AMapConfig {
  // Android Key — 通过 --dart-define=AMAP_ANDROID_KEY=xxx 编译注入
  static const String androidKey = String.fromEnvironment('AMAP_ANDROID_KEY', defaultValue: '');
  // iOS Key — 通过 --dart-define=AMAP_IOS_KEY=xxx 编译注入
  static const String iosKey = String.fromEnvironment('AMAP_IOS_KEY', defaultValue: '');
  // Web Service Key（POI搜索/地理编码用）— 通过 --dart-define=AMAP_WS_KEY=xxx 编译注入
  static const String webServiceKey = String.fromEnvironment('AMAP_WS_KEY', defaultValue: '');
  static const String webServiceSecurityCode = '';

  // 定位上报参数
  static const int uploadBatchSize = 10;         // 每批最多缓存10个点再上报
  static const int uploadIntervalMs = 60000;      // 上报间隔60秒

  // 校验密钥是否已配置（开发模式下可跳过）
  static bool get isConfigured =>
      androidKey.isNotEmpty && webServiceKey.isNotEmpty;
}
```

---

## 三、高德 REST API 完整参数（每个API都附完整请求示例）

### 3.1 POI 文本搜索（模糊建议 + 精确搜索）

```
接口：GET https://restapi.amap.com/v3/place/text
```

#### 完整请求示例

```http
GET https://restapi.amap.com/v3/place/text?key=665f6c9959c69f9c08ae1d869d2b7abd&keywords=成都高新区天府大道&output=JSON&offset=15&page=1&extensions=base
```

#### 参数详解

| 参数名 | 是否必填 | 类型 | 取值 | 说明 |
|--------|---------|------|------|------|
| `key` | 是 | string | `665f6c9959c69f9c08ae1d869d2b7abd` | 高德Web服务Key |
| `keywords` | 是 | string | 用户输入的文字（UTF-8编码） | 搜索关键词，如"成都高新区" |
| `output` | 否 | string | `JSON` | 返回格式，固定JSON |
| `offset` | 否 | int | 模糊建议=`15`，精确搜索=`1` | 每页返回记录数 |
| `page` | 否 | int | `1` | 页码 |
| `extensions` | 否 | string | `base` | base=基本信息, all=详细信息 |

#### 调用位置（7处）

| 文件 | 行号 | 用途 | offset值 | 触发时机 |
|------|------|------|---------|---------|
| `poi_search_field.dart` | 第94行 | 精确搜索 | 1 | 用户点击搜索按钮 |
| `poi_search_field.dart` | 第176行 | 模糊建议 | 15 | 输入框文字变化400ms防抖 |
| `fence_page.dart` | — | 精确搜索 | 1 | 围栏页搜索 |
| `fence_page.dart` | — | 模糊建议 | 15 | 围栏页输入建议 |
| `fence_edit_page.dart` | — | 精确搜索 | 1 | 围栏编辑页搜索 |
| `fence_edit_page.dart` | — | 模糊建议 | 15 | 围栏编辑页输入建议 |

#### 完整返回示例

```json
{
  "status": "1",
  "info": "OK",
  "infocode": "10000",
  "count": "237",
  "suggestion": {
    "keywords": ["成都高新区天府大道"],
    "cities": []
  },
  "pois": [
    {
      "id": "B0FFH5S6SJ",
      "name": "成都高新区管委会",
      "type": "政府机构;政府机关;行政单位",
      "typecode": "160100",
      "biz_type": "",
      "address": "四川省成都市高新区天府大道北段18号",
      "location": "104.063576,30.570078",
      "distance": "",
      "tel": "028-85339111",
      "pname": "四川省",
      "cityname": "成都市",
      "adname": "高新区",
      "importance": [],
      "shopid": [],
      "shopinfo": "0",
      "poiweight": [],
      "entr_location": [],
      "business_area": "",
      "parking_data": {
        "parking_type": 0,
        "total_qiwei": "",
        "total_parking": "",
        "fee": ""
      },
      "deep_info": {},
      "indoor_map": 0,
      "parent": "",
      "children": [],
      "childtype": "",
      "gridcode": "510109005001"
    }
  ]
}
```

---

### 3.2 地理编码（POI搜不到时的回退方案）

```
接口：GET https://restapi.amap.com/v3/geocode/geo
```

#### 完整请求示例

```http
GET https://restapi.amap.com/v3/geocode/geo?key=665f6c9959c69f9c08ae1d869d2b7abd&address=成都市高新区天府大道&output=JSON&city=
```

#### 参数详解

| 参数名 | 是否必填 | 类型 | 取值 | 说明 |
|--------|---------|------|------|------|
| `key` | 是 | string | `665f6c9959c69f9c08ae1d869d2b7abd` | 高德Web服务Key |
| `address` | 是 | string | 地址文字 | 结构化地址，如"成都市高新区" |
| `output` | 否 | string | `JSON` | 返回格式 |
| `city` | 否 | string | `""`(空字符串) | 指定城市，空=自动识别 |

#### 调用位置（3处）

| 文件 | 行号 | 触发条件 |
|------|------|---------|
| `poi_search_field.dart` | 第226行 | 精确搜索POI无结果时自动降级 |
| `fence_page.dart` | — | 同上 |
| `fence_edit_page.dart` | — | 同上 |

#### 完整返回示例

```json
{
  "status": "1",
  "info": "OK",
  "infocode": "10000",
  "count": "1",
  "geocodes": [
    {
      "formatted_address": "四川省成都市高新区天府大道北段18号",
      "country": "中国",
      "province": "四川",
      "citycode": "028",
      "city": "成都市",
      "district": "高新区",
      "township": [],
      "neighborhood": {
        "name": [],
        "type": []
      },
      "building": {
        "name": [],
        "type": []
      },
      "adcode": "510109",
      "street": [],
      "number": [],
      "location": "104.063576,30.570078",
      "level": "区县"
    }
  ]
}
```

---

### 3.3 输入提示（客户地址搜索用）

```
接口：GET https://restapi.amap.com/v3/assistant/inputtips
```

#### 完整请求示例

```http
GET https://restapi.amap.com/v3/assistant/inputtips?key=665f6c9959c69f9c08ae1d869d2b7abd&keywords=天府软件园&output=JSON
```

#### 参数详解

| 参数名 | 是否必填 | 类型 | 取值 | 说明 |
|--------|---------|------|------|------|
| `key` | 是 | string | `665f6c9959c69f9c08ae1d869d2b7abd` | 高德Web服务Key |
| `keywords` | 是 | string | 用户输入 | 输入提示关键词 |
| `output` | 否 | string | `JSON` | 返回格式 |

#### 调用位置（1处）

| 文件 | 行号 | 用途 |
|------|------|------|
| `customer_page.dart` | 第96-97行 | 客户地址输入搜索 |

---

## 四、Dio HTTP客户端配置（调用高德REST API用）

```dart
// 文件：app/lib/services/api_service.dart（第207-215行）
// 这是一个专用的Dio实例，不经过业务拦截器、不加Bearer token、不经过熔断器
static final Dio amapDio = Dio(BaseOptions(
  connectTimeout: Duration(seconds: 10),    // 连接超时10秒
  receiveTimeout: Duration(seconds: 10),    // 接收超时10秒
  headers: {
    'Content-Type': 'application/json',     // 请求头
  },
));
```

---

## 五、服务端代理API参数

### 5.1 地理编码代理路由（完整源码）

```typescript
// 文件：server/src/routes/geocode.ts

import { Router, Request, Response, NextFunction } from 'express';
import axios from 'axios';

const router = Router();

// GET /api/v1/geocode/search?address=xxx
router.get('/search', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const address = req.query.address as string;
    if (!address) {
      return res.status(400).json({ code: '10001', message: '缺少address参数' });
    }

    const key = process.env.AMAP_WS_KEY || '665f6c9959c69f9c08ae1d869d2b7abd';

    // 实际转发到高德地理编码API
    const url = `https://restapi.amap.com/v3/geocode/geo?key=${key}&address=${encodeURIComponent(address)}&output=JSON`;

    const response = await axios.get(url);
    res.json(response.data);
  } catch (err) {
    next(err);
  }
});

export default router;
```

### 路由注册

```typescript
// 文件：server/src/index.ts
import geocodeRouter from './routes/geocode';
app.use('/api/v1/geocode', geocodeRouter);
```

### 请求示例

```http
GET http://localhost:3000/api/v1/geocode/search?address=成都市高新区天府大道
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...
```

---

## 六、Android原生SDK完整配置

### 6.1 Gradle依赖

```kotlin
// 文件：app/android/app/build.gradle.kts（第61-62行）
dependencies {
    implementation("com.amap.api:3dmap:8.1.0")   // 高德3D地图SDK v8.1.0
    implementation("com.amap.api:location:5.6.0") // 高德定位SDK v5.6.0
}
```

### 6.2 AndroidManifest.xml（完整片段）

```xml
<!-- 文件：app/android/app/src/main/AndroidManifest.xml（第33-36行） -->
<!-- 高德地图 SDK 配置 -->
<meta-data
    android:name="com.amap.api.v2.apikey"
    android:value="0e00439a3a2b04282e78083ea7a9b19d" />
```

### 6.3 原生定位服务（Java）完整配置

```java
// 文件：app/android/.../LocationForegroundService.java

import com.amap.api.location.AMapLocation;
import com.amap.api.location.AMapLocationClient;
import com.amap.api.location.AMapLocationClientOption;
import com.amap.api.location.AMapLocationListener;

// AMapLocationClient 实例（单一进程唯一实例）
AMapLocationClient mLocationClient = new AMapLocationClient(context);

// 定位参数配置
AMapLocationClientOption option = new AMapLocationClientOption();
option.setLocationMode(AMapLocationClientOption.AMapLocationMode.Hight_Accuracy);
// Hight_Accuracy = 高精度模式（GPS优先+网络/WiFi辅助）
// Battery_Saving = 低功耗模式（仅网络/WiFi）
// Device_Sensors = 仅设备模式（仅GPS）

option.setInterval(3000);
// 定位采集间隔（毫秒）
// 标准模式: 3000ms（3秒）
// 省电模式: 30000ms（30秒）
// SOS模式: 1000ms（1秒）

option.setOnceLocation(false);
// true = 单次定位（获取一次就停止）
// false = 连续定位（按interval频率持续采集）

option.setNeedAddress(false);
// true = 返回地址信息（会消耗额外流量和电量）
// false = 只返回经纬度（省电）

option.setLocationCacheEnable(false);
// true = 开启SDK缓存（可能返回旧数据）
// false = 关闭缓存

option.setSensorEnable(true);
// true = 启用传感器（加速度计辅助定位，提高精度）
// false = 关闭传感器

mLocationClient.setLocationOption(option);

// 定位回调
mLocationClient.setLocationListener(new AMapLocationListener() {
    @Override
    public void onLocationChanged(AMapLocation location) {
        if (location != null && location.getErrorCode() == 0) {
            // 定位成功
            double lat = location.getLatitude();       // 纬度
            double lng = location.getLongitude();      // 经度
            float accuracy = location.getAccuracy();   // 精度(米)
            float speed = location.getSpeed();         // 速度(km/h)
            long time = location.getTime();            // 定位时间戳
            int locType = location.getLocationType();  // 定位来源: 1=GPS, 2=WiFi, 4=基站

            // 通过 MethodChannel 传递给 Flutter
            Map<String, Object> result = new HashMap<>();
            result.put("lat", lat);
            result.put("lng", lng);
            result.put("accuracy", accuracy);
            result.put("speed", speed);
            result.put("timestamp", time);
            result.put("locationType", locType);
            // 发送到Flutter端...
        } else {
            // 定位失败
            int errorCode = location.getErrorCode();   // 错误码
            String errorInfo = location.getErrorInfo(); // 错误信息
        }
    }
});

// 启动定位
mLocationClient.startLocation();
```

---

## 七、iOS原生SDK完整配置

### 7.1 Podfile依赖

```ruby
# 文件：app/ios/Podfile（第36-38行）
target 'Runner' do
  # 高德定位SDK（无IDFA版本，符合苹果隐私新规）
  pod 'AMapLocation-NO-IDFA', '>= 2.9.0'
  # 高德搜索SDK（无IDFA版本）
  pod 'AMapSearch-NO-IDFA', '>= 9.0.0'
  # 高德基础库（无IDFA版本）
  pod 'AMapFoundation-NO-IDFA', '>= 1.8.0'
end
```

### 7.2 Info.plist 密钥配置

```xml
<!-- 文件：app/ios/Runner/Info.plist（第60-62行） -->
<!-- ========== 高德地图 SDK API Key ========== -->
<key>AMapApiKey</key>
<string>9debae73ed4f59ce9f934c9b1fda1a23</string>
```

---

## 八、Web管理后台完整参数

### 8.1 SDK加载（HTML完整片段）

```html
<!-- 文件：server/public/admin.html（第57-61行） -->
<!-- 安全配置：必须在加载SDK之前设置，否则地图无法加载 -->
<script>
    window._AMapSecurityConfig = {
        securityJsCode: 'f54f44a83e49995348e72713f2ca1b9a'
    };
</script>
<!-- 加载高德JS API v2.0，key=Web JS API Key -->
<script src="https://webapi.amap.com/maps?v=2.0&key=7ac68442bb2d4a49a4aab6237ea29f48"></script>
```

### 8.2 JS API 使用明细（3个模块）

#### 模块1：围栏管理（fence tab）

```javascript
// server/public/admin.js — fence模块

// 1. 创建地图
const fenceMap = new AMap.Map('fenceMapContainer', {
    center: [104.07, 30.57],     // 默认成都中心
    zoom: 14,                     // 默认缩放级别
    layers: [new AMap.TileLayer()], // 标准地图图层
});

// 2. 添加控件
fenceMap.addControl(new AMap.ToolBar());   // 缩放工具条
fenceMap.addControl(new AMap.Scale());     // 比例尺

// 3. 卫星/标准地图切换
const satelliteLayer = new AMap.TileLayer.Satellite();
// 切换调用: map.add([satelliteLayer]) / map.remove([satelliteLayer])

// 4. POI搜索插件
const placeSearch = new AMap.PlaceSearch({
    type: 'poi',           // 搜索类型
    pageSize: 20,          // 每页返回数
});
placeSearch.search('关键词', function(status, result) {
    // result.poiList.pois — POI数组
});

// 5. 输入自动补全插件
const autoComplete = new AMap.AutoComplete({
    datatype: 'all',       // 数据类型: all/poi/bus
    pageSize: 15,          // 建议条数
});
autoComplete.search('关键词', function(status, result) {
    // result.tips — 建议列表
});

// 6. 绘制围栏（多边形）
const polygon = new AMap.Polygon({
    path: [                 // 顶点坐标数组
        [104.07, 30.57],
        [104.08, 30.57],
        [104.08, 30.58],
        [104.07, 30.58],
    ],
    strokeColor: '#FF0000',
    strokeWeight: 2,
    fillColor: '#FF0000',
    fillOpacity: 0.2,
});
fenceMap.add(polygon);

// 7. 可拖拽标记（围栏圆心）
const marker = new AMap.Marker({
    position: [104.07, 30.57],
    draggable: true,        // 可拖拽
    label: {
        content: '围栏中心',
        offset: new AMap.Pixel(-20, -30),
    }
});
fenceMap.add(marker);
```

#### 模块2：实时监控（monitor tab）

```javascript
// server/public/admin.js — monitor模块

// 1. 创建地图
const monitorMap = new AMap.Map('monitorMapContainer', {
    zoom: 13,
});

// 2. 人员位置标记（批量）
function addPersonMarker(person) {
    const marker = new AMap.Marker({
        position: [person.lng, person.lat],
        content: `<div style="...">${person.name}</div>`,  // 自定义HTML标记
        offset: new AMap.Pixel(-15, -30),
    });
    monitorMap.add(marker);
}

// 3. 轨迹线
const trackLine = new AMap.Polyline({
    path: [                 // 轨迹点数组（按时间排序）
        [104.07, 30.57],
        [104.08, 30.58],
        // ...
    ],
    strokeColor: '#1677FF',
    strokeWeight: 4,
    strokeOpacity: 0.8,
});
monitorMap.add(trackLine);

// 4. 轨迹动画（通过定时器逐帧移动标记）
const animMarker = new AMap.Marker({
    position: trackPath[0],
    content: '<div style="...">▶</div>',   // 三角箭头标记
});
let step = 0;
const timer = setInterval(() => {
    step++;
    if (step >= trackPath.length) { clearInterval(timer); return; }
    animMarker.setPosition(trackPath[step]);
    monitorMap.setCenter(trackPath[step]);
}, 1000);  // 每秒移动一步
```

#### 模块3：轨迹回放（tracks tab）

```javascript
// server/public/admin.js — tracks模块

// 1. 创建地图
const trackMap = new AMap.Map('trackMapContainer', {
    zoom: 14,
});

// 2. 绘制轨迹线
const polyline = new AMap.Polyline({
    path: trackPoints,           // [{lat, lng}]
    strokeColor: '#FF6A00',
    strokeWeight: 4,
    showDir: true,               // 显示方向箭头
});
trackMap.add(polyline);
trackMap.setFitView();           // 自适应视野

// 3. 起点/终点标记
const startMarker = new AMap.Marker({
    position: trackPoints[0],
    content: '<div style="background:green;...">起点</div>',
});
const endMarker = new AMap.Marker({
    position: trackPoints[trackPoints.length - 1],
    content: '<div style="background:red;...">终点</div>',
});
trackMap.add([startMarker, endMarker]);
```

---

## 九、构建命令（含所有实际参数）

### APK构建

```bash
flutter build apk --release \
  --dart-define=AMAP_ANDROID_KEY=0e00439a3a2b04282e78083ea7a9b19d \
  --dart-define=AMAP_IOS_KEY=9debae73ed4f59ce9f934c9b1fda1a23 \
  --dart-define=AMAP_WS_KEY=665f6c9959c69f9c08ae1d869d2b7abd
```

### iOS构建

```bash
flutter build ios --release \
  --dart-define=AMAP_ANDROID_KEY=0e00439a3a2b04282e78083ea7a9b19d \
  --dart-define=AMAP_IOS_KEY=9debae73ed4f59ce9f934c9b1fda1a23 \
  --dart-define=AMAP_WS_KEY=665f6c9959c69f9c08ae1d869d2b7abd
```

### 开发运行

```bash
flutter run \
  --dart-define=AMAP_ANDROID_KEY=0e00439a3a2b04282e78083ea7a9b19d \
  --dart-define=AMAP_IOS_KEY=9debae73ed4f59ce9f934c9b1fda1a23 \
  --dart-define=AMAP_WS_KEY=665f6c9959c69f9c08ae1d869d2b7abd
```

---

## 十、Flutter依赖版本

```yaml
# 文件：app/pubspec.yaml
dependencies:
  amap_flutter_map: ^3.0.0       # 高德地图Flutter插件（地图UI）
  amap_flutter_base: ^3.0.0      # 高德地图Flutter基础库
  amap_flutter_location: ^3.0.0  # 高德定位Flutter插件
```

---

## 附录：涉及的所有文件（共20个）

| 序号 | 文件路径 | 作用 |
|------|---------|------|
| 1 | `app/lib/config/amap_key.dart` | Key注入配置类 |
| 2 | `app/lib/main.dart` | 隐私合规 + Key初始化 |
| 3 | `app/lib/services/api_service.dart` | amapDio 实例 |
| 4 | `app/lib/services/amap_location_service.dart` | 定位服务 |
| 5 | `app/lib/services/background_location_service.dart` | 原生定位桥接 |
| 6 | `app/lib/services/location_uploader.dart` | 定位数据上传 |
| 7 | `app/lib/widgets/poi_search_field.dart` | POI搜索公共组件 |
| 8 | `app/lib/pages/map_page.dart` | 地图首页 |
| 9 | `app/lib/pages/fence_page.dart` | 电子围栏页 |
| 10 | `app/lib/pages/fence_edit_page.dart` | 围栏编辑页 |
| 11 | `app/lib/pages/track_replay_page.dart` | 轨迹回放页 |
| 12 | `app/lib/pages/customer_page.dart` | 客户管理页 |
| 13 | `app/android/.../AndroidManifest.xml` | Android Key配置 |
| 14 | `app/android/.../LocationForegroundService.java` | 原生定位参数 |
| 15 | `app/android/.../build.gradle.kts` | Gradle高德依赖 |
| 16 | `app/ios/Runner/Info.plist` | iOS Key配置 |
| 17 | `app/ios/Podfile` | iOS Pod依赖 |
| 18 | `server/public/admin.html` | Web管理后台HTML |
| 19 | `server/public/admin.js` | Web管理后台JS |
| 20 | `server/src/routes/geocode.ts` | 服务端地理编码代理 |
