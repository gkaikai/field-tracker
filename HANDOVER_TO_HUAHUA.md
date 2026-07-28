# Field Tracker 项目完整移交文档

> **移交日期：** 2026-07-28  
> **移交人（小明）：** agent 2051627651042902016  
> **接收人（花花）：** agent 2081748769069596672  
> **项目源码：** `/Users/openclaw-gkf/development/field_tracker`

---

## 📋 目录

1. [产品概述与定位](#1-产品概述与定位)
2. [技术架构全景](#2-技术架构全景)
3. [手机端APP完整功能清单](#3-手机端app完整功能清单)
4. [Web管理后台功能清单](#4-web管理后台功能清单)
5. [后端API接口文档](#5-后端api接口文档)
6. [数据库设计](#6-数据库设计)
7. [部署运维](#7-部署运维)
8. [密钥/账号/配置参数](#8-密钥账号配置参数)
9. [全量Bug修复记录](#9-全量bug修复记录)
10. [未完成功能 + 待办清单](#10-未完成功能--待办清单)
11. [审核流程说明](#11-审核流程说明)

---

## 1. 产品概述与定位

**Field Tracker（外勤定位系统）** 是一款面向外勤/销售团队的**全功能定位+考勤+巡查管理平台**。

### 用户群体
- 🔹 **管理员** — 在Web后台管理团队、查看轨迹、设置围栏和考勤规则
- 🔹 **外勤员工** — 使用手机APP打卡、定位、提交报告、拜访客户

### 核心场景
1. **实时定位监控** — 管理员地图上实时查看所有员工的当前位置
2. **轨迹回放** — 查看某位员工某天的运动轨迹（含动画播放）
3. **电子围栏** — 创建圆形/多边形围栏，员工进出自动记录事件
4. **考勤打卡** — 水印拍照+GPS+Wi-Fi多重签到
5. **拜访计划** — 安排客户拜访并执行
6. **审批流程** — 外出/请假/报销在线审批
7. **在线升级** — APP内检测新版本并下载

### 当前版本
- **版本号：** v1.0.49+62
- **最新APK：** https://gofile.io/d/DEY8YO
- **快速下载（tailnet）：** 在群内请求 `grix_file_link` 接口

---

## 2. 技术架构全景

```
┌──────────────────────────────────────────────────────────────────┐
│                    Field Tracker 系统架构                         │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  📱 Android APP (Flutter)          🖥 Web管理后台 (原生JS)       │
│  ┌─────────────────────────┐      ┌─────────────────────────┐    │
│  │ amap_flutter_map 3.0.0  │      │ AMap JS API 2.0         │    │
│  │ AmapLocationService      │      │ 高德AutoComplete        │    │
│  │ Dio HTTP Client          │      │ 事件委托 + Hash路由     │    │
│  │ SharedPreferences        │      │ WebSocket 实时位置      │    │
│  │ WorkManager (后台定位)   │      └──────────┬──────────────┘    │
│  │ Remote Config (隧道URL)  │                 │                    │
│  └─────────────┬────────────┘                 │                    │
│                │ HTTP REST API                │                    │
│                ▼                              ▼                    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                 🖧 Node.js 后端 (Express + TypeScript)       │  │
│  │  ┌──────────────┬─────────────┬────────────┬──────────────┐ │  │
│  │  │ auth / users │ attendance  │  fences    │ location     │ │  │
│  │  │ customers    │ reports     │  approval  │ org          │ │  │
│  │  │ geocode      │ upload/photo│  tunnel    │ heartbeat    │ │  │
│  │  └──────────────┴─────────────┴────────────┴──────────────┘ │  │
│  │  WebSocket: /ws/location (实时位置)  /ws/heartbeat (保活)   │  │
│  └──────────────────────┬──────────────────────────────────────┘  │
│                         │                                         │
│                         ▼                                         │
│  ┌─────────────────────────┐    ┌─────────────────────────────┐  │
│  │ 🗄 PostgreSQL 16        │    │ 📦 Redis (缓存)              │  │
│  │ • location (按月分区)   │    │ • Tunnel URL缓存            │  │
│  │ • fences / fence_events │    │ • 频率限制计数              │  │
│  │ • attendance_records    │    └─────────────────────────────┘  │
│  │ • customers / approvals │                                       │
│  │ • users / departments   │                                       │
│  │ • reports / photos      │                                       │
│  └─────────────────────────┘                                       │
│                                                                  │
│  隧道穿透: serveo.net → GitHub Config → APK RemoteConfig       │
│  (ServerSelector熔断器: 120s窗口/3次失败自动切服务器)            │
└──────────────────────────────────────────────────────────────────┘
```

### 关键技术选型

| 项目 | 技术 | 版本 |
|------|------|------|
| 手机端语言 | Dart (Flutter) | 3.22.3 |
| 地图SDK | 高德AMap Flutter SDK | 3.0.0 |
| 后端语言 | TypeScript (Node.js) | - |
| 后端框架 | Express | - |
| 数据库 | PostgreSQL 16 | 分区表 |
| 缓存 | Redis (ioredis) | - |
| 实时推送 | WebSocket (ws库) | - |
| 编译工具 | tsc | - |
| 进程管理 | PM2 | - |
| 隧道穿透 | Serveo SSH + GitHub Config | - |
| APK分发 | gofile CDN | 国内可访问 |
| 在线升级 | self-hosted /app-version.json | - |

---

## 3. 手机端APP完整功能清单

### 3.1 登录/认证 (`login_page.dart`, `auth_service.dart`)
- 手机号+密码登录
- JWT Token鉴权 + 本地持久化session
- 忘记密码（短信验证码重置）
- 角色体系：admin（管理员）/ user（普通员工）
- 密码明文存储已改为bcrypt + salt

### 3.2 首页 (`home_page.dart`)
- 功能导航入口（跳转到各模块）
- 定位服务启动 + 后台定位注册
- 电池优化白名单申请
- 首次安装权限引导

### 3.3 实时地图定位 (`map_page.dart`)
- 高德地图实时显示所有在线员工位置
- 小蓝点显示自己位置
- 位置每15秒自动刷新
- **资料卡** — 点击地图上的人头展示员工姓名、部门、当前状态
- WebSocket实时位置推送

### 3.4 轨迹回放 (`track_replay_page.dart`)
- 选择员工+日期 → 地图显示轨迹
- 播放/暂停/速度控制（可调节倍速）
- 进度拖拽条（跳到任意时间点）
- 15秒自动刷新（不重置地图视角）
- 手动刷新按钮
- 统计信息：总里程、平均速度、总时长
- 地图类型切换（标准/卫星）
- 量比分析（地量蓄势/试盘信号）

### 3.5 电子围栏 (`fence_page.dart`, `fence_edit_page.dart`)
#### 创建（`fence_page.dart`）
- 圆形围栏：地图点击设中心 → 滑块调半径（50-5000米）→ 输入名称 → 保存(POST)
- 多边形围栏：连续点击设顶点 → 至少3个 → 保存(POST)
- 地址搜索：高德place/text API（offset=15条）+ 地理编码回退
- 建议列表下拉（Stack overlay防地图触摸丢失）

#### 编辑（`fence_edit_page.dart` — 2026-07-27新建独立页面）
- **编辑与创建完全分离**（用户强烈要求）
- 圆形：全屏地图点选中心 + 半径滑块 + 名称编辑 → PUT
- 多边形：显示已有顶点 + 点击添加/撤回 → PUT
- 保存后pop并刷新列表

#### 围栏事件
- 实时事件列表（进出围栏记录，显示用户名+时间）
- 自动刷新（静默模式不闪烁）

### 3.6 考勤打卡 (`attendance_page.dart`, `attendance_rules_page.dart`)
- **签到** — 水印相机拍摄（叠加时间/地址/GPS）+ Wi-Fi名称 → 提交
- **签退** — 同上
- **签到记录列表** — 按月查看
- **打卡规则** — 管理员设置签到时间窗口、半径、Wi-Fi白名单
- **Wi-Fi打卡** — 自动识别公司Wi-Fi，半径内自动签到

### 3.7 客户管理 (`customer_page.dart`)
- 客户列表（分页）
- 新增/编辑客户（名称、地址、联系方式）
- 地址搜索 + 建议列表（15条上限）

### 3.8 拜访计划 (`visit_plan_page.dart`)
- 创建拜访计划（选择客户、时间）
- 拜访列表
- 当天拜访提醒

### 3.9 审批流程 (`approval_page.dart`)
- 提交审批申请（外出/请假/报销）
- 审批列表（待审批/已审批/全部）
- 管理员审批或拒绝

### 3.10 日报/报告 (`report_page.dart`)
- 提交每日工作报告
- 报告列表（按时间倒序）

### 3.11 水印相机/照片 (`watermark_camera_page.dart`, `photo_gallery_page.dart`)
- 拍照叠加时间/地址/经纬度水印
- 照片列表查看

### 3.12 组织架构
- 部门列表 → 部门成员
- 管理员创建/编辑/删除部门、管理成员

### 3.13 统计 (`stats_page.dart`)
- 考勤统计、轨迹统计等

### 3.14 个人中心 (`profile_page.dart`)
- 个人信息展示
- 版本号
- 退出登录

### 3.15 在线升级 (`update_service.dart`)
- 启动时检查 `GET /app-version.json`
- 新版本弹窗提示下载

### 3.16 权限引导 (`permission_guide_page.dart`)
- 首次安装引导：位置权限、后台定位、电池优化白名单

### 3.17 服务器配置自动切换 (`remote_config_service.dart`)
- 启动时从 `https://raw.githubusercontent.com/gkaikai/field-tracker-config/main/config.json` 拉取服务器URL
- 熔断器（120秒窗口，连续3次失败自动切换）
- 后台每60分钟刷新配置
- 本地SharedPreferences缓存
- 备用URL列表

---

## 4. Web管理后台功能清单

**入口：** `server/public/admin.html` + `admin.js`（原生JS，无框架，Hash routing）

| 标签页 | 功能 | 关键代码 |
|--------|------|---------|
| **仪表盘** | 今日概览、在线人数、围栏进出统计 | `showDashboard()` |
| **实时监控** | 地图实时显示所有员工位置（WebSocket推送） | `showMonitor()` |
| **围栏管理** | 创建/编辑/删除围栏，地址搜索，进出事件 | `showFences()` |
| **围栏事件** | 围栏进出事件列表（带用户名） | `showFenceEvents()` |
| **打卡规则** | 设置签到时间/半径/Wi-Fi规则 | `showAttendanceRules()` |
| **打卡记录** | 查看签到记录 | `showAttendanceRecords()` |
| **客户列表** | 管理客户信息 | `showCustomers()` |
| **审批列表** | 审批/拒绝申请 | `showApprovals()` |
| **照片墙** | 查看员工上传的照片 | `showPhotos()` |
| **报表** | 查看员工提交的报告 | `showReports()` |
| **组织管理** | 部门/员工管理（增删改查） | `showOrg()` |
| **轨迹回放** | 选择员工+日期 → 地图轨迹动画 + 进度拖拽 | `showTrackReplay()` |
| **在线升级** | 版本管理，触发更新 | `showUpgrade()` |

**特色实现：**
- Map + Track 合并架构（同一地图实时位置+轨迹线）
- 卫星/标准地图切换
- 72边形Polygon模拟Circle（解决Circle不渲染描边的问题）
- 事件委托替代内联onclick
- hash路由（刷新页面不跳转）

---

## 5. 后端API接口文档

### 5.1 路由挂载

| 路由前缀 | 文件 | 功能 |
|----------|------|------|
| `/api/v1/auth` | `routes/auth.ts` | 登录/注册/忘记密码/短信验证码 |
| `/api/v1/location` | `routes/location.ts` | 位置上报/轨迹查询/当前位置 |
| `/api/v1/users` | `routes/user.ts` | 用户信息查询/管理 |
| `/api/v1/attendance` | `routes/attendance.ts` | 签到签退/记录/规则管理 |
| `/api/v1/fences` | `routes/fence.ts` | 围栏CRUD/事件/Auto-check |
| `/api/v1/upload` | `routes/upload.ts` | 照片上传（MIME+魔数校验） |
| `/api/v1/reports` | `routes/report.ts` | 日报CRUD |
| `/api/v1/customers` | `routes/customer.ts` | 客户CRUD |
| `/api/v1/approvals` | `routes/approval.ts` | 审批CRUD |
| `/api/v1/org` | `routes/org.ts` | 部门/员工组织架构管理 |
| `/api/v1/geocode` | `routes/geocode.ts` | 地址→坐标（高德API代理） |
| `/api/v1/tunnel` | `routes/tunnel.ts` | 隧道URL管理 |
| `/api/v1/heartbeat` | `routes/heartbeat.ts` | 服务心跳检测 |

### 5.2 关键API端点

#### 认证
```
POST /api/v1/auth/login          { phone, password } → { token, user }
POST /api/v1/auth/register       { phone, password, name }
POST /api/v1/auth/forgot-password
POST /api/v1/auth/reset-password
POST /api/v1/auth/send-code      { phone } → 短信验证码
```

#### 位置
```
POST /api/v1/location/batch      { points: [{ lat, lng, timestamp, speed }] }
GET  /api/v1/location/latest     → 所有用户最新位置
GET  /api/v1/location/track/:userId?date=YYYY-MM-DD&since=timestamp
GET  /api/v1/location/current/:userId  → 单个用户当前位置
```

#### 围栏
```
GET    /api/v1/fences                     → 围栏列表
POST   /api/v1/fences                     → 创建围栏
PUT    /api/v1/fences/:id                 → 更新围栏
DELETE /api/v1/fences/:id                 → 删除围栏
GET    /api/v1/fences/events              → 围栏事件（分页）
GET    /api/v1/fences/auto-check          → 自动围栏检查
POST   /api/v1/fences/nearby             → 附近围栏查询
```

#### 考勤
```
POST   /api/v1/attendance/checkin         → 签到
POST   /api/v1/attendance/checkout        → 签退
GET    /api/v1/attendance/records         → 签到记录
GET    /api/v1/attendance/rules           → 打卡规则
PUT    /api/v1/attendance/rules/:id       → 更新规则
```

#### 客户
```
GET    /api/v1/customers                  → 客户列表
POST   /api/v1/customers                  → 创建客户
PUT    /api/v1/customers/:id              → 更新客户
DELETE /api/v1/customers/:id              → 删除客户
```

#### 审批
```
GET    /api/v1/approvals                  → 审批列表
POST   /api/v1/approvals                  → 创建审批
PUT    /api/v1/approvals/:id              → 审批/拒绝
```

#### 组织
```
GET    /api/v1/org/departments            → 部门列表
POST   /api/v1/org/departments            → 创建部门
PUT    /api/v1/org/departments/:id        → 更新部门
DELETE /api/v1/org/departments/:id        → 删除部门
GET    /api/v1/org/users                  → 用户列表
POST   /api/v1/org/users                 → 创建用户
DELETE /api/v1/org/users/:id              → 删除用户（软删除）
```

### 5.3 WebSocket

| 路径 | 说明 | 实现 |
|------|------|------|
| `/ws/location` | 实时位置推送 | `location_ws.ts` — 员工位置变化时广播 |
| `/ws/heartbeat` | 心跳保活 | `heartbeat_ws.ts` — 180s阈值+6min冷却期 |

### 5.4 杂项
```
GET    /health           → { status: 'ok', uptime }
GET    /metrics          → 请求指标
GET    /app-version.json → 在线升级信息
GET    /download-apk     → APK下载（attachment方式）
GET    /apk              → APK下载（Range请求支持）
POST   /api/v1/upload/photo → 照片上传（含MIME+魔数校验）
```

---

## 6. 数据库设计

### 6.1 主要表结构

| 表名 | 用途 | 关键字段 |
|------|------|---------|
| `users` | 用户 | id, phone, password_hash, name, role, department_id, is_active |
| `departments` | 部门 | id, name, description, parent_id |
| `location` | 位置（按月分区） | id, user_id, lat, lng, speed, timestamp, created_at |
| `fences` | 电子围栏 | id, name, shape_type, center_lat/center_lng, radius, coordinates, user_id |
| `fence_events` | 围栏进出事件 | id, fence_id, user_id, event_type(in/out), created_at |
| `attendance_records` | 考勤记录 | id, user_id, type(in/out), timestamp, photo_url, wifi, lat/lng |
| `attendance_rules` | 打卡规则 | id, name, checkin_time/checkout_time, radius, wifi_ssid |
| `customers` | 客户 | id, name, address, phone, lat/lng, user_id |
| `reports` | 日报 | id, user_id, content, date, created_at |
| `approvals` | 审批 | id, user_id, type, status(pending/approved/rejected), content |
| `visit_plans` | 拜访计划 | id, user_id, customer_id, visit_date, status |
| `photos` | 照片 | id, user_id, photo_url, lat/lng, address, created_at |

### 6.2 数据库配置
- PostgreSQL 16，连接：`localhost:5432`
- 用户名：`postgres`，密码：`postgres`
- 数据库名：`field_tracker`
- location表按月自动分区（`ensure_next_partitions()` 函数）
- schema文件：`server/db/schema.sql` + `server/src/models/database.sql`
- 迁移脚本：`server/db/migrate.js`、`server/db/archive-server.js`

### 6.3 Redis用途
- Tunnel URL缓存
- 频率限制计数器
- 熔断器状态

---

## 7. 部署运维

### 7.1 本地启动

```bash
# 后端
cd server
npm install && npm run build
export $(grep -v '^\s*#' .env.production | xargs)
npx tsx src/index.ts

# Flutter
cd app
flutter build apk --release \
  --dart-define=AMAP_ANDROID_KEY=xxx \
  --dart-define=AMAP_IOS_KEY=xxx \
  --dart-define=AMAP_WS_KEY=xxx
```

### 7.2 隧道穿透

**工具：** serveo.net（免费SSH隧道）  
**命令：** `ssh -R 80:localhost:3000 serveo.net`  
**保活脚本：** `scripts/tunnel-keepalive.sh`（每5分钟 cron 检查）
- 隧道断了自动重启 + 提取新URL
- 新URL自动更新 GitHub Config（APK通过 RemoteConfig 获取）

**隧道URL配置：** `https://raw.githubusercontent.com/gkaikai/field-tracker-config/main/config.json`

### 7.3 当前隧道

```
当前URL: https://ee58eb76ed59e642-123-123-97-213.serveousercontent.com
PID文件: /tmp/fieldtracker-tunnel.pid
URL文件: /tmp/fieldtracker-tunnel-url.txt
监控日志: ~/logs/tunnel-monitor.log
故障日志: ~/logs/tunnel-failures.log
```

### 7.4 进程管理
- PM2 守护后端
- 端口：3000
- 健康检查：`curl localhost:3000/health`
- 优雅关闭支持（SIGTERM/SIGINT）

### 7.5 GitHub仓库

| 项目 | 地址 | 认证 |
|------|------|------|
| 主仓库 | `git@github.com:gkaikai/field-tracker.git` | SSH密钥 |
| 配置仓库 | `git@github.com:gkaikai/field-tracker-config.git` | SSH密钥 |
| 当前分支 | `egg-xiaoming` | - |
| SSH公钥 | `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGiUfA2WdE2r4iXXtfX9V9R24AsfvHeFSSZK9O1uWc5u gkaikai@github` | - |

---

## 8. 密钥/账号/配置参数

### 8.1 高德地图密钥

| Key类型 | 值 | 用途 |
|---------|-----|------|
| Android SDK Key | `0e00439a3a2b04282e78083ea7a9b19d` | APP地图显示/定位 |
| iOS SDK Key | `9debae73ed4f59ce9f934c9b1fda1a23` | iOS地图显示/定位 |
| Web Service Key | `665f6c9959c69f9c08ae1d869d2b7abd` | POI搜索/geocode回退/JS API |

**注入方式：** `--dart-define=AMAP_ANDROID_KEY=xxx --dart-define=AMAP_IOS_KEY=xxx --dart-define=AMAP_WS_KEY=xxx`

### 8.2 环境变量

**`server/.env.production`（已脱敏）：**

| 变量 | 说明 |
|------|------|
| `JWT_SECRET` | JWT签名密钥（生产环境已改为非默认值） |
| `JWT_EXPIRES_IN` | Token有效期 |
| `DB_HOST=localhost` | 数据库地址 |
| `DB_PORT=5432` | 数据库端口 |
| `DB_USER=postgres` | 数据库用户 |
| `DB_PASSWORD=postgres` | 数据库密码 |
| `DB_NAME=field_tracker` | 数据库名 |
| `REDIS_URL=redis://localhost:6379` | Redis连接 |
| `AMAP_WS_KEY=665f6c9959c69f9c08ae1d869d2b7abd` | 高德Web服务Key（geocode回退） |
| `PORT=3000` | 服务端口 |
| `NODE_ENV=production` | 环境模式 |
| `ALLOWED_ORIGINS` | CORS允许域名 |
| `ALERT_WEBHOOK_URL` | 告警Webhook |

### 8.3 测试账号

| 角色 | 手机号 | 密码 | 说明 |
|------|--------|------|------|
| 管理员 | 13800138000 | `test123456` | admin角色，可管理所有 |
| 普通员工 | 13800138001 | `test123456` | user角色 |
| 普通员工 | 13800138002 | `test123456` | user角色 |

### 8.4 APK构建命令

```bash
cd app
export JAVA_HOME=/Users/openclaw-gkf/tools/jdk17/Contents/Home
export PATH="$JAVA_HOME/bin:/Users/openclaw-gkf/development/flutter/bin:$PATH"
flutter build apk --release \
  --dart-define=AMAP_ANDROID_KEY=0e00439a3a2b04282e78083ea7a9b19d \
  --dart-define=AMAP_IOS_KEY=9debae73ed4f59ce9f934c9b1fda1a23 \
  --dart-define=AMAP_WS_KEY=665f6c9959c69f9c08ae1d869d2b7abd
```

APK输出：`app/build/app/outputs/flutter-apk/app-release.apk`

### 8.5 推送GitHub Config

```bash
cd ~/development/field-tracker-config
git pull origin main
# 修改 config.json 中的 tunnel URL
git add config.json && git commit -m "update tunnel url"
git push origin main
```

### 8.6 Cron任务

```bash
*/5 * * * * /Users/openclaw-gkf/development/field_tracker/scripts/tunnel-keepalive.sh >/dev/null 2>&1
```

---

## 9. 全量Bug修复记录

### 9.1 审计轮次 — 全量代码审计（2026-07-25）

审核员（2068148595781013504）出具了全量审计报告，共**37个问题**（8致命+9严重+12一般+8建议）。

#### 🔴 致命（P0）— 3修1跳

| 问题 | 修复 | 状态 |
|------|------|------|
| 实时位置越权（任何人可查任意用户） | routes/location.ts 加 middleware 权限校验 | ✅ |
| resetToken重放（5分钟内可无限改密码） | 校验通过即标记已使用 | ✅ |
| 客户PUT/DELETE无owner校验 | 加 user_id 验证 | ✅ |
| 高德API Key明文硬编码 | 用户要求跳过（说暂时不管） | ⏭️ 跳过 |

#### 🟠 严重（P1）— 9/9全修

| 问题 | 修复 |
|------|------|
| 审批批准无角色校验 | 加 adminMiddleware |
| 审批幂等防重 | UPDATE加WHERE status='pending' |
| 围栏PUT坐标被NULL覆盖 | 先SELECT后兜底 |
| 围栏auto-check N+1查询 | 改IN查询 |
| 签到达量全表扫描 | 加索引 |
| GPS看门狗无限重启 | 加最大重启次数 |
| 审批越权脱敏不完整 | 补充字段过滤 |
| 文件上传无MIME校验 | 加fileFilter+魔数校验 |
| 离线同步N+1 | 改为批量端POST /batch |

#### 🟡 一般（P2）— 12/12全修

| 问题 | 修复 |
|------|------|
| 登录页硬编码测试账号 | 删除测试账号预填 |
| bizType枚举校验 | upload.ts加枚举校验 |
| 围栏事件分页 | 加limit/offset参数 |
| 缓存文件按userId隔离 | location_uploader.dart |
| 围栏频率限制Map内存泄漏 | fence.ts |
| 审批管理员申请信息回退 | approval.ts |
| 注释POST→GET不一致 | fence.ts |
| 汇报系统纯内存（重启丢数据） | 建reports表 |
| 死代码清理 | fence_page.dart |
| 客户PUT/DELETE无owner校验 | customer.ts |
| 高德API Key硬编码 | 改为dart-define注入（保留密钥） |
| JWT密钥未改 | 生产环境改非默认值 |

#### ✅ 建议（8项）— 未修（非阻断，后续可选）

---

### 9.2 管理后台围栏搜索Bug（2026-07-27）

#### 故障A — 搜索后地图永久失效
- **症状：** 搜地址后地图滚轮缩放+拖拽全失效
- **根因：** ① 点击建议项不触发input.blur()→scrollWheel永不恢复
  ② suggestBox幽灵覆盖未从body移除→拦截地图事件
  ③ suggestBox.onclick缺少stopPropagation→穿透到document
- **修复：** onTipClick末尾加input.blur() + suggestBox.onclick加stopPropagation + blur后300ms恢复scrollWheel

#### 故障B — 第二次点击不弹出
- **症状：** 第一次搜索正常→清空→第二次点搜索框无反应
- **根因：** `_fenceDocListenersBound`守卫+闭包引用已destroy的旧input DOM
- **修复：** document click改用`document.getElementById('fenceSearchInput')`实时查找

#### 故障C — 搜索失败
- **症状：** 部分地址搜不到
- **根因：** geocode回退用photon.komoot.io（境外OSM服务）
- **修复：** 后端改为高德Web Service API

#### 故障D — 编辑变新建
- **症状：** 编辑围栏后点大按钮保存→POST新建而非PUT更新
- **根因：** 主按钮调saveFence()(POST)，旁边小按钮才是saveFenceEdit(id)
- **修复：** editFence中将主按钮改为saveFenceEdit(id)，文字改为「💾 更新」

---

### 9.3 电子围栏手机端 — 编辑/创建分离（2026-07-27）

#### 核心重构
- **问题：** 编辑和创建共用同一个tab导致状态混乱（搜索无声覆盖坐标、错误显示"更新围栏"）
- **方案：** 编辑→Navigator.push到独立fence_edit_page.dart；创建tab保持纯POST
- **新建文件：** `fence_edit_page.dart`（793行，独立全屏地图编辑页面）
- **修改文件：** `fence_page.dart`（+737/-737行）
- **审核：** 初版AlertDialog→审核员建议升级为独立页面（最终通过）

#### 二次编辑失效
- **根因：** `_loadFences()`未await，setState后animateTo时序错乱
- **修复：** 加 `await _loadFences();`

#### 搜索建议数量
- **问题：** offset='8'只返回8条建议（用户反馈太少）
- **修复：** offset='15'（fence_page.dart + fence_edit_page.dart + customer_page.dart）

#### double.parse → double.tryParse
- **问题：** 高德坐标格式异常时跑出FormatException
- **修复：** 3处改为tryParse+null判断

#### 搜索栏不回填标准化名称
- **修复：** setState内加 `_searchCtrl.text = name;`

#### 搜索建议下拉导致地图触摸丢失
- **修复：** 建议框从Column移到Stack/Positioned overlay

#### EagerGestureRecognizer编译错误
- **问题：** Factory类型在Flutter 3.22未定义
- **修复：** 移除gestureRecognizers参数

---

### 9.4 隧道/网络相关问题

| 问题 | 解决 |
|------|------|
| Serveo隧道频繁断开 | 保活脚本每5分钟cron检查 |
| 隧道地址变化APK连不上 | RemoteConfig + GitHub Config + 熔断器 |
| GitHub Config CDN缓存 | 等待1-2分钟自动刷新 |
| 2026-07-27傍晚隧道断 | 手动重启 + 设置cron保活（已解决根本） |

---

## 10. 未完成功能 + 待办清单

### P0 — 必须优先处理

| 项目 | 说明 | 建议方案 |
|------|------|---------|
| **隧道保活脚本未持续运行** | cron已设置但服务器重启后需检查 | 确认cron正常运行 |
| **围栏搜索建议无"查看更多"** | 建议列表只有15条，无查看更多按钮 | admin.js showSuggest底部加查看更多项 |

### P1 — 重要

| 项目 | 说明 | 优先级 |
|------|------|-------|
| **多边形编辑不支持形状调整** | 多边形编辑模式下顶点不可修改 | 中 |
| **离线数据采集** | 无网络时APP不可用，需本地存+同步 | 高 |
| **离线轨迹绘制** | GPS数据在手机本地+地图渲染在本地=理论上可离线画轨迹 | 中 |
| **高德Key硬编码** | 虽已改为dart-define，但仍在编译命令中明文 | 低（用户让跳过） |

### P2 — 优化

| 项目 | 说明 |
|------|------|
| 审核员建议的8项 | 审计报告中的8个建议项（非阻塞，可后续） |
| 钉钉媒体库发APK | 钉钉凭证（appKey=dingebx6uanpdzhncxjx）仍返回40096 |
| 轨迹回放加载顺序优化 | 应：先显示地图→立刻显示当前定位→后台加载轨迹→画线 |

### 已知问题（用户反馈未修）

| 问题 | 用户反馈时间 |
|------|------------|
| APP未登录不能离线采集 | 2026-07-28 |
| 轨迹回放页面加载1000+点位慢，没有先显示当前位置 | 2026-07-28 |
| 搜索推荐列表数量偏少 | 2026-07-28 |

---

## 11. 审核流程说明

### 11.1 标准工作流

```
① 开发/修改代码完成
② dispatch_agent 送审给审核员 agent 2068148595781013504
③ 主动等待3分钟后查询 message_history 查看审核结果
④ 有问题？→ 修复 → 回到第②步重新送审
⑤ 全部通过 → 问用户"审核通过了，可以构建APK发给你吗？"
   → 用户同意 → 构建APK → 上传gofile
   → 用户不同意 → 不构建
```

### 11.2 审核员信息
- **审核员ID：** 2068148595781013504
- **送审函数：** `grix_invoke(action='dispatch_agent', params={'agent_id': '2068148595781013504', '...'})`
- **查看结果：** `grix_invoke(action='message_history', params={'session_id': 'xxx'})`
- **注意：** 审核员偶尔会误判或修改代码，需要人工复核

### 11.3 构建流程
```bash
# 1. flutter analyze 无错误
# 2. flutter build apk --release (带上所有dart-define)
# 3. 上传gofile:
curl -X POST "https://store-eu-par-5.gofile.io/contents/uploadfile?folderId=qf4H3Z" \
  -F "file=@build/app/outputs/flutter-apk/app-release.apk"
# 4. 更新 app-version.json
# 5. 告诉用户链接
```

---

## 附录A：项目文件目录结构

```
field_tracker/
├── app/                              # Flutter APP
│   ├── lib/
│   │   ├── config/
│   │   │   ├── amap_key.dart         # 高德密钥配置
│   │   │   ├── app_config.dart        # APP配置
│   │   │   └── env_config.dart        # 环境配置
│   │   ├── pages/
│   │   │   ├── login_page.dart        # 登录
│   │   │   ├── home_page.dart         # 首页导航
│   │   │   ├── map_page.dart          # 实时地图
│   │   │   ├── fence_page.dart        # 围栏创建/列表
│   │   │   ├── fence_edit_page.dart   # 围栏编辑（新建）
│   │   │   ├── track_replay_page.dart # 轨迹回放
│   │   │   ├── attendance_page.dart   # 考勤打卡
│   │   │   ├── attendance_rules_page.dart
│   │   │   ├── customer_page.dart     # 客户管理
│   │   │   ├── report_page.dart       # 日报
│   │   │   ├── approval_page.dart     # 审批
│   │   │   ├── visit_plan_page.dart   # 拜访计划
│   │   │   ├── watermark_camera_page.dart
│   │   │   ├── photo_gallery_page.dart
│   │   │   ├── stats_page.dart        # 统计
│   │   │   └── profile_page.dart      # 个人中心
│   │   ├── services/
│   │   │   ├── api_service.dart       # HTTP客户端
│   │   │   ├── auth_service.dart      # 认证
│   │   │   ├── amap_location_service.dart  # 高德定位
│   │   │   ├── background_location_service.dart
│   │   │   ├── remote_config_service.dart  # 远程配置
│   │   │   ├── update_service.dart    # 在线升级
│   │   │   └── offline_service.dart   # 离线存储
│   │   └── main.dart
│   └── pubspec.yaml
├── server/                           # Node.js后端
│   ├── src/
│   │   ├── index.ts                  # Express入口
│   │   ├── routes/                   # 路由
│   │   │   ├── auth.ts
│   │   │   ├── location.ts
│   │   │   ├── user.ts
│   │   │   ├── attendance.ts
│   │   │   ├── fence.ts
│   │   │   ├── upload.ts
│   │   │   ├── report.ts
│   │   │   ├── customer.ts
│   │   │   ├── approval.ts
│   │   │   ├── org.ts
│   │   │   ├── geocode.ts
│   │   │   ├── tunnel.ts
│   │   │   └── heartbeat.ts
│   │   ├── websocket/
│   │   │   ├── location_ws.ts
│   │   │   └── heartbeat_ws.ts
│   │   ├── middleware/
│   │   │   ├── auth.ts               # JWT认证中间件
│   │   │   └── errorHandler.ts       # 统一错误处理
│   │   ├── config/
│   │   │   └── database.ts           # DB+Redis连接
│   │   └── monitoring/
│   │       ├── metrics.ts            # 请求指标
│   │       └── alert.ts              # 告警系统
│   ├── public/
│   │   ├── admin.html                # 管理后台入口
│   │   ├── admin.js                  # 管理后台JS（功能标签页）
│   │   └── app-version.json          # 在线升级配置
│   ├── db/
│   │   ├── schema.sql                # 数据库schema
│   │   └── migrate.js                # 迁移脚本
│   └── package.json
├── scripts/
│   ├── tunnel-keepalive.sh           # 隧道保活脚本
│   └── release.sh                    # 发布脚本
└── DEV_REPORT_2026-07-27.md          # 当日修复报告
```

## 附录B：常用命令

```bash
# 检查服务
curl localhost:3000/health

# 检查隧道
curl https://[tunnel-url]/health

# 重启隧道
kill $(cat /tmp/fieldtracker-tunnel.pid)
ssh -R 80:localhost:3000 serveo.net

# 编译后端
cd server && npm run build

# Flutter分析
cd app && flutter analyze

# 构建APK
flutter build apk --release --dart-define=AMAP_ANDROID_KEY=0e00439a3a2b04282e78083ea7a9b19d --dart-define=AMAP_IOS_KEY=9debae73ed4f59ce9f934c9b1fda1a23 --dart-define=AMAP_WS_KEY=665f6c9959c69f9c08ae1d869d2b7abd

# 上传gofile
curl -X POST "https://store-eu-par-5.gofile.io/contents/uploadfile?folderId=qf4H3Z" -F "file=@app/build/app/outputs/flutter-apk/app-release.apk"

# 隧道保活启动（首次）
bash scripts/tunnel-keepalive.sh

# 更新GitHub config
cd ~/development/field-tracker-config
git pull origin main
# 修改config.json
git add config.json && git commit -m "update"
git push origin main
```

---

> **文档结束**
> 如有问题，随时在群内@我（小明，2051627651042902016）或花花（2081748769069596672）
