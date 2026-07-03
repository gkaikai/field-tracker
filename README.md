# Field Tracker

外勤定位追踪 APP — 地图显示 + 实时定位 + 后台保活，适配 iOS / Android / HarmonyOS。

## 项目结构

```
field_tracker/
├── app/                          # Flutter 移动端
│   ├── lib/
│   │   ├── main.dart             # 入口
│   │   ├── config/
│   │   │   └── amap_key.dart     # 高德地图 Key
│   │   ├── models/
│   │   │   ├── user.dart
│   │   │   └── location_point.dart
│   │   ├── services/
│   │   │   ├── location_service.dart     # 定位服务（三级采样策略）
│   │   │   ├── background_service.dart   # 后台保活
│   │   │   ├── location_uploader.dart    # 批量上传 + 离线缓存
│   │   │   └── api_service.dart          # HTTP 通信
│   │   ├── pages/
│   │   │   ├── login_page.dart
│   │   │   ├── map_page.dart             # 地图首页（核心）
│   │   │   └── permission_guide_page.dart # 国产ROM引导页
│   │   └── utils/
│   │       └── device_info.dart          # 设备识别（华为/小米等）
│   ├── android/                         # Android 原生配置
│   └── ios/                             # iOS 原生配置
│
├── server/                       # Node.js 后端
│   ├── src/
│   │   ├── index.ts              # 入口
│   │   ├── config/database.ts    # PostgreSQL + Redis
│   │   ├── routes/auth.ts        # 登录认证
│   │   ├── routes/location.ts    # 定位上报/查询
│   │   ├── routes/user.ts        # 用户管理
│   │   ├── websocket/location_ws.ts  # WebSocket 实时推送
│   │   ├── middleware/auth.ts    # JWT 中间件
│   │   └── models/database.sql   # 数据库建表脚本
│   └── public/index.html         # Web 管理端（实时地图）
│
├── setup.sh                      # 一键初始化脚本
└── README.md
```

## 功能

### 第一期（已实现）

| 功能 | 状态 |
|------|------|
| 高德地图显示 | ✅ |
| 实时 GPS 定位 + 地图蓝点 | ✅ |
| 三级采样策略（省电/标准/高精度） | ✅ |
| 运动状态自动切换频率 | ✅ |
| 后台保活（Foreground Service） | ✅ |
| 离线缓存 + 网络恢复补传 | ✅ |
| WorkManager 周期性唤醒 | ✅ |
| 国产ROM后台权限引导页 | ✅ |
| WebSocket 实时位置推送 | ✅ |
| Web 管理端地图 | ✅ |
| 批量上传减少网络请求 | ✅ |
| JWT 登录认证 | ✅ |

### 第二期（规划中）

- 轨迹记录 + 回放
- 考勤打卡（位置/WiFi/蓝牙）
- 拍照水印
- 电子围栏
- 数据报表

## 快速开始

### 前提条件

- Flutter SDK ≥ 3.0
- Node.js ≥ 18
- PostgreSQL ≥ 14 + PostGIS 扩展
- Redis ≥ 6
- 高德地图开发者 Key

### 1. 初始化

```bash
chmod +x setup.sh
./setup.sh
```

### 2. 启动后端

```bash
cd server
npm run dev
```

### 3. 启动 App

```bash
cd app
flutter run
```

### 4. 打开 Web 管理端

浏览器打开 `http://localhost:3000`

## 测试账号

| 角色 | 手机号 | 密码 |
|------|--------|------|
| 管理员 | 13900000001 | 123456 |
| 员工A | 13800138000 | 123456 |
| 员工B | 13800138001 | 123456 |

## 定位三级采样策略

| 模式 | 频率 | 定位方式 | 场景 |
|------|------|---------|------|
| 省电模式 | 30秒/次 | 网络定位 | 静止/后台 |
| 标准模式 | 15秒/次 | GPS+网络 | 步行/外勤 |
| 高精度 | 1秒/次, 持续10秒 | 纯GPS | 打卡瞬间 |

## 后台保活策略

- **Android**: Foreground Service + 常驻通知 + WorkManager
- **iOS**: 后台定位模式 + BGTaskScheduler
- **国产ROM**: 按品牌展示设置引导页（华为/小米/OPPO/vivo）

## 获取高德地图 Key

1. 访问 [高德开放平台](https://lbs.amap.com/dev/key/app)
2. 创建应用，选择「Android」和「iOS」平台
3. 获取 Key 后填入 `app/lib/config/amap_key.dart`
4. Web 管理端也需要独立的 JS API Key

## 技术栈

- **移动端**: Flutter (Dart) + 高德地图 SDK
- **后端**: Node.js (TypeScript) + Express
- **数据库**: PostgreSQL + PostGIS + Redis
- **实时通信**: WebSocket (ws)
- **后台保活**: flutter_background_service + WorkManager
