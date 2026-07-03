# Field Tracker — 模块清单

> 最后更新: 2026-07-03
>
> 状态说明:
> - ✅ Complete — 代码已完备，测试覆盖
> - ⚠️ Partial — 功能有但缺部分逻辑
> - ❌ Missing — 完全未开发

---

## 客户端 (Flutter App)

### App Config — ✅ Complete

**文件**: `app/lib/config/app_config.dart`, `app/lib/config/amap_key.dart`
**功能**: 集中管理 API 基础 URL、高德地图 Key、定位间隔参数、通知渠道配置、上传批处理参数
**测试**: `app/test/config_test.dart` (5 tests), `app/test/service_test.dart` (AMapConfig section, 4 tests)
**缺口**: 无 — 所有配置常量已定义并有合理性校验测试

---

### API Service — ✅ Complete

**文件**: `app/lib/services/api_service.dart`
**功能**: 基于 Dio 的单例 HTTP 客户端，自动注入 Bearer Token，提供 `get()`/`post()` 方法
**测试**: `app/test/api_service_test.dart` (4 tests), `app/test/error_handling_test.dart` (API section)
**缺口**: 无 — 单例模式、Token 注入、请求/响应拦截器均已实现

---

### Auth Service — ⚠️ Partial

**文件**: `app/lib/services/auth_service.dart`
**功能**: 登录/登出/会话恢复，Token 及用户信息持久化到 SharedPreferences
**测试**: `app/test/auth_service_test.dart` (4 tests)
**缺口**:
- `login()` 将 `username` 字段发送给服务器，但**服务端 auth.ts 期望 `phone` 字段** — 字段名不匹配导致登录失败
- 缺少 Token 自动刷新机制
- 未实现生物认证（指纹/面容）
- 未实现记住密码功能

---

### Location Service — ✅ Complete

**文件**: `app/lib/services/location_service.dart`
**功能**: 基于 Geolocator 的持续 GPS 追踪，含权限检查、位置流监听、定时上报
**测试**: 间接通过 `app/test/background_task_test.dart` 测试相关逻辑
**缺口**: 无 — `startTracking()`/`stopTracking()`/位置流/定时上报完整实现。注意: `_uploadPosition()` 直接使用 ApiService 上报单点，而 `MapPage` 也有 `LocationUploader().enqueue()` 的独立上传路径 — 存在两条并行的上报逻辑。

---

### Location Uploader — ✅ Complete

**文件**: `app/lib/services/location_uploader.dart`
**功能**: 离线位置缓存与批量上传。攒够 N 条后批量 POST，无网络时缓存到本地文件，恢复后自动补传，最多每 60 秒强制上传一次
**测试**: `app/test/background_task_test.dart` (485 lines, ~30 tests) — 覆盖入队/缓存/文件持久化/Flush/生命周期等
**缺口**: 无 — 测试覆盖度高，包含边界值和异常场景

---

### Background Service — ✅ Complete

**文件**: `app/lib/services/background_service.dart`
**功能**: Android Foreground Service（前台服务+持久通知）+ WorkManager（15分钟周期性唤醒）+ iOS Background Fetch 配置
**测试**: `app/test/service_test.dart` (BackgroundService section, 2 tests), `app/test/background_task_test.dart`
**缺口**: 无 — 前台服务/WorkManager/通知渠道均已实现。注意: `main.dart` 中同时调用了旧版 `startBackgroundService()` 和 `registerPeriodicLocationTask()`，与新 `BackgroundService` 存在功能重叠。

---

### Login Page — ✅ Complete

**文件**: `app/lib/pages/login_page.dart`
**功能**: 登录表单页，含用户名/密码输入框、表单验证、登录按钮带 loading 态、登录成功后跳转 `/home`
**测试**: `app/test/login_page_test.dart` (2 tests), `app/test/widget_test.dart` (2 tests), `app/test/integration_test.dart` (login flow)
**缺口**: 无 — UI 元素完整，但如前所述 `username` 字段名与服务端 `phone` 不匹配

---

### Home Page — ⚠️ Partial

**文件**: `app/lib/pages/home_page.dart`
**功能**: 首页 — 高德地图 + 实时定位 + 标记点 + 开始/停止定位按钮 + 退出登录
**测试**: `app/test/widget_test.dart` (smoke test)
**缺口**:
- 仅依赖旧版 `LocationService` 的 `onLocationChanged` 回调更新标记，未使用 `LocationUploader`
- 未显示缓存待上传数量
- 未集成 `BackgroundService` 新方案
- 页面不显示用户信息（姓名/部门）

---

### Map Page — ⚠️ Partial

**文件**: `app/lib/pages/map_page.dart`
**功能**: 详细地图页 — AMapWidget、定位状态栏、缓存计数、打卡按钮（入口）、回到当前位置按钮、右上角设置入口跳转权限引导
**测试**: 无专用测试
**缺口**:
- 打卡按钮仅显示 SnackBar **"打卡功能将在下一期实现"**
- 打卡功能 (check-in / check-out) 完全未实现
- 缺少历史轨迹回放功能
- 未实现人员实时位置列表

---

### Permission Guide Page — ✅ Complete

**文件**: `app/lib/pages/permission_guide_page.dart`
**功能**: 国产 ROM 后台权限引导页 — 自动检测手机品牌，展示对应厂商的后台保活设置路径，标记设置完成
**测试**: `app/test/service_test.dart` (DeviceInfo section, ~15 tests) — 覆盖华为/荣耀/小米/OPPO/vivo/三星/Apple 的品牌引导
**缺口**: 无 — 7 大品牌引导文案完整，测试全覆盖

---

### User Model — ✅ Complete

**文件**: `app/lib/models/user.dart`
**功能**: User 数据模型，含 `id`/`name`/`phone`/`departmentName`/`role` 字段，支持 JSON 序列化/反序列化
**测试**: `app/test/model_test.dart` (User section, ~12 tests) — 覆盖全字段/空字段/Unicode/往返一致性
**缺口**: 无

---

### LocationPoint Model — ✅ Complete

**文件**: `app/lib/models/location_point.dart`
**功能**: 位置数据模型，含经纬度/精度/速度/海拔/方向/电量/时间戳，`toJson()`/`fromJson()`/`toDbMap()`
**测试**: `app/test/model_test.dart` (LocationPoint section, ~20 tests) — 覆盖全字段/边界值/字符串数值/空字段/无效时间戳/精度
**缺口**: 无

---

### Device Info Utility — ✅ Complete

**文件**: `app/lib/utils/device_info.dart`
**功能**: 设备品牌识别（华为/荣耀/小米/OPPO/vivo/三星/Apple/魅族）+ 品牌对应后台保活引导文案
**测试**: `app/test/service_test.dart` (DeviceInfo section) — 覆盖所有品牌的引导内容校验
**缺口**: 无

---

## 服务端 (Node.js / Express + TypeScript)

### Server Auth Route — ✅ Complete

**文件**: `server/src/routes/auth.ts`
**功能**: 用户登录 (`POST /login`，使用手机号+密码+bcrypt+JWT)、获取当前用户信息 (`GET /me`)
**测试**: 无
**缺口**: 无 — 登录和用户信息查询均已实现，含参数校验、JWT 签名、bcrypt 密码验证

---

### Server Location Route — ✅ Complete

**文件**: `server/src/routes/location.ts`
**功能**: 5 个端点 — 单点上报/批量上报/获取某人实时位置（Redis）/获取在线人员列表/获取历史轨迹（支持按日期筛选）
**测试**: 无
**缺口**: 无 — 所有定位相关端点已实现，含 Redis GEO + PostgreSQL 双写、时序分区表写入

---

### Server User Route — ⚠️ Partial

**文件**: `server/src/routes/user.ts`
**功能**: 获取用户列表 (`GET /`) 和部门列表 (`GET /departments`)
**测试**: 无
**缺口**:
- 缺少用户 CRUD 操作（创建/更新/删除用户）
- 缺少角色管理端点
- 缺少用户搜索/分页

---

### WebSocket Service — ✅ Complete

**文件**: `server/src/websocket/location_ws.ts`
**功能**: 实时位置推送 — JWT 鉴权连接、Redis GEO 实时更新、PostgreSQL 异步写入、管理员广播、心跳 Ack
**测试**: 无
**缺口**: 无 — Token 验证、位置上报处理、管理员广播、断连清理、在线统计完整实现

---

### Database Config & Seed — ✅ Complete

**文件**: `server/src/config/database.ts`, `server/src/models/database.sql`
**功能**: PostgreSQL 连接池 + Redis 客户端配置；完整数据库 Schema（用户/部门/定位记录/打卡记录/打卡规则/电子围栏/围栏事件）+ 按月分区 + 种子数据 3 用户
**测试**: 无
**缺口**: 无 — 7 张表的完整 DDL、分区函数、索引、种子数据均已提供

---

### Attendance (考勤打卡) — ❌ Missing

**文件**: 无
**功能**: 打卡签到/签退、考勤记录查询
**测试**: 无
**缺口**: 完全未开发
- `POST /api/v1/attendance/checkin` — 未实现
- `GET /api/v1/attendance/records` — 未实现
- 虽然 SQL schema 中已定义 `attendance_records` 和 `attendance_rules` 表，但后端无对应路由
- 客户端 `MapPage` 的打卡按钮仅显示占位 SnackBar

---

| 层级 | 模块 | 状态 | 测试文件数 | 测试用例数 (约) |
|---|---|---|---|---|
| Flutter Config | App Config | ✅ Complete | 2 | 9 |
| Flutter Service | API Service | ✅ Complete | 2 | 8 |
| Flutter Service | Auth Service | ⚠️ Partial | 2 | 8 |
| Flutter Service | Location Service | ✅ Complete | 1 | — |
| Flutter Service | Location Uploader | ✅ Complete | 1 | ~30 |
| Flutter Service | Background Service | ✅ Complete | 2 | 3 |
| Flutter UI | Login Page | ✅ Complete | 3 | 6 |
| Flutter UI | Home Page | ⚠️ Partial | 1 | 1 |
| Flutter UI | Map Page | ⚠️ Partial | 0 | 0 |
| Flutter UI | Permission Guide Page | ✅ Complete | 1 | 15 |
| Flutter Model | User Model | ✅ Complete | 1 | 12 |
| Flutter Model | LocationPoint Model | ✅ Complete | 1 | 20 |
| Flutter Util | Device Info | ✅ Complete | 1 | 15 |
| Server | Auth Route | ✅ Complete | 0 | 0 |
| Server | Location Route | ✅ Complete | 0 | 0 |
| Server | User Route | ⚠️ Partial | 0 | 0 |
| Server | WebSocket Service | ✅ Complete | 0 | 0 |
| Server | Database Config & Seed | ✅ Complete | 0 | 0 |
| Server | Attendance | ❌ Missing | 0 | 0 |
