# Field Tracker — API 文档

> 最后更新: 2026-07-03
>
> 基础 URL: `http://localhost:3000`
>
> 认证方式: JWT Bearer Token (除登录接口外，所有接口需在请求头携带 `Authorization: Bearer <token>`)
>
> **统一响应格式:**
> - 成功: 按各接口定义返回 JSON
> - 失败: `{ "code": "50001", "message": "错误描述" }`
>
> **错误码一览:**
> | code | 说明 | HTTP 状态 |
> |------|------|-----------|
> | 10001 | 手机号不能为空 | 400 |
> | 10002 | 密码不能为空 | 400 |
> | 10003 | 手机号格式错误 | 400 |
> | 10004 | 密码长度不能少于6位 | 400 |
> | 10005 | 账号或密码错误 | 401 |
> | 10006 | Token无效或已过期 | 401 |
> | 10007 | 未提供认证Token | 401 |
> | 10008 | 用户不存在 | 404 |
> | 10009 | 无权限访问 | 403 |
> | 20001 | 经度超出范围 | 400 |
> | 20002 | 纬度超出范围 | 400 |
> | 20003 | 位置数据不能为空 | 400 |
> | 20004 | 批量数据不能为空 | 400 |
> | 20005 | 批量数据超过上限 | 400 |
> | 20006 | 日期参数无效 | 400 |
> | 50000 | 服务器内部错误 | 500 |
> | 50001 | 请求参数无效 | 400 |

---

## POST /api/v1/auth/login

**描述**: 用户登录获取 JWT Token（使用手机号+密码）

**请求体**:
```json
{
  "phone": "string (必填, 手机号)",
  "password": "string (必填, 密码)"
}
```

**成功响应** (200):
```json
{
  "token": "jwt_token_string",
  "userId": "uuid",
  "name": "string",
  "phone": "string",
  "role": "string (employee | manager | admin)",
  "departmentId": "uuid | null"
}
```

**错误响应**:
- 400: `{"message": "手机号和密码不能为空"}`
- 401: `{"message": "账号或密码错误"}`
- 500: `{"message": "服务器内部错误"}`

**备注**: 客户端 `AuthService.login()` 发送字段名为 **`username`**，与服务端期待的 **`phone`** 不匹配，需对齐。

---

## GET /api/v1/auth/me

**描述**: 获取当前登录用户详细信息（需 Token）

**请求头**: `Authorization: Bearer <token>`

**成功响应** (200):
```json
{
  "id": "uuid",
  "name": "string",
  "phone": "string",
  "role": "string",
  "department_id": "uuid | null",
  "avatar_url": "string | null",
  "created_at": "ISO datetime string"
}
```

**错误响应**:
- 401: `{"message": "未提供认证Token"}` 或 `{"message": "Token无效或已过期"}`
- 404: `{"message": "用户不存在"}`
- 500: `{"message": "服务器内部错误"}`

---

## POST /api/v1/location/report

**描述**: 单点位置上报（需 Token）。写入 Redis GEO（实时位置，TTL 5分钟）+ 异步写入 PostgreSQL

**请求头**: `Authorization: Bearer <token>`

**请求体**:
```json
{
  "lng": "number (必填, 经度, -180~180)",
  "lat": "number (必填, 纬度, -85.05~85.05)",
  "accuracy": "number (可选, 精度米)",
  "speed": "number (可选, 速度 m/s)",
  "altitude": "number (可选, 海拔米)",
  "bearing": "number (可选, 方向角度)",
  "battery": "number (可选, 电量 0~1)"
}
```

**成功响应** (200):
```json
{
  "status": "ok"
}
```

**错误响应**:
- 400: `{"message": "经纬度不能为空"}` 或 `{"message": "经纬度超出有效范围"}`
- 401: Token 无效
- 500: `{"message": "服务器内部错误"}`

---

## POST /api/v1/location/batch

**描述**: 批量位置上报（需 Token）。接收一组位置点，批量写入 PostgreSQL，最后一条更新 Redis 实时位置

**请求头**: `Authorization: Bearer <token>`

**请求体**:
```json
{
  "points": [
    {
      "lng": "number (必填)",
      "lat": "number (必填)",
      "accuracy": "number (可选)",
      "speed": "number (可选)",
      "battery": "number (可选)",
      "timestamp": "string (可选, ISO datetime)"
    }
  ]
}
```

**成功响应** (200):
```json
{
  "status": "ok",
  "count": "number (写入条数)"
}
```

**错误响应**:
- 400: `{"message": "定位数据不能为空"}` 或 `{"message": "定位数据中包含无效坐标"}`
- 401: Token 无效
- 500: `{"message": "服务器内部错误"}`

---

## GET /api/v1/location/current/:userId

**描述**: 获取指定用户的实时位置（需 Token）。优先从 Redis 读取（在线），回退到 PostgreSQL 最后一条记录

**路径参数**: `userId` — 用户 UUID

**请求头**: `Authorization: Bearer <token>`

**成功响应** (200, 在线):
```json
{
  "userId": "uuid",
  "lng": "string (经度)",
  "lat": "string (纬度)",
  "accuracy": "string",
  "speed": "string",
  "battery": "string",
  "timestamp": "string (ISO datetime)",
  "online": true
}
```

**成功响应** (200, 离线/历史):
```json
{
  "lng": "number",
  "lat": "number",
  "accuracy": "number",
  "speed": "number",
  "battery": "number",
  "recorded_at": "ISO datetime string",
  "online": false
}
```

**错误响应**:
- 404: `{"message": "暂无定位数据"}`
- 500: `{"message": "服务器内部错误"}`

---

## GET /api/v1/location/online

**描述**: 获取所有在线人员位置（需 Token）。管理员查看所有用户，普通员工查看同部门人员

**请求头**: `Authorization: Bearer <token>`

**成功响应** (200):
```json
[
  {
    "userId": "uuid",
    "lng": "number",
    "lat": "number",
    "accuracy": "string | null",
    "speed": "string | null",
    "battery": "string | null",
    "timestamp": "string | null"
  }
]
```

**错误响应**:
- 500: `{"message": "服务器内部错误"}`

---

## GET /api/v1/location/track/:userId

**描述**: 获取某用户的历史轨迹（需 Token）。支持按日期筛选，按时间升序排列

**路径参数**: `userId` — 用户 UUID

**查询参数**:
- `date` (可选): 筛选日期，格式 `YYYY-MM-DD`

**请求头**: `Authorization: Bearer <token>`

**成功响应** (200):
```json
{
  "userId": "uuid",
  "points": [
    {
      "lng": "number",
      "lat": "number",
      "accuracy": "number | null",
      "speed": "number | null",
      "altitude": "number | null",
      "bearing": "number | null",
      "battery": "number | null",
      "recorded_at": "ISO datetime string"
    }
  ],
  "total": "number (总记录数)"
}
```

**错误响应**:
- 500: `{"message": "服务器内部错误"}`

---

## GET /api/v1/users

**描述**: 获取活跃用户列表（需 Token）。返回所有 `is_active = true` 的用户，含部门名称

**请求头**: `Authorization: Bearer <token>`

**成功响应** (200):
```json
[
  {
    "id": "uuid",
    "name": "string",
    "phone": "string",
    "role": "string",
    "department_id": "uuid | null",
    "department_name": "string | null",
    "is_active": true
  }
]
```

**错误响应**:
- 500: `{"message": "服务器内部错误"}`

---

## GET /api/v1/users/departments

**描述**: 获取部门列表（需 Token）

**请求头**: `Authorization: Bearer <token>`

**成功响应** (200):
```json
[
  {
    "id": "uuid",
    "name": "string",
    "parent_id": "uuid | null"
  }
]
```

**错误响应**:
- 500: `{"message": "服务器内部错误"}`

---

## WebSocket /ws/location

**描述**: 实时位置推送 WebSocket。连接需携带 JWT Token 作为 URL 参数。客户端上报位置后，服务端返回 ack 并将位置广播给管理员

**连接地址**: `ws://localhost:3000/ws/location?token=<jwt_token>`

**关闭码**:
- 4001: 缺少认证 Token 或 Token 无效

**客户端 → 服务端 (消息格式)**:
```json
{
  "userId": "string (必填, 必须与Token中的userId一致)",
  "lng": "number (必填)",
  "lat": "number (必填)",
  "accuracy": "number (可选)",
  "speed": "number (可选)",
  "battery": "number (可选)",
  "timestamp": "string (ISO datetime)"
}
```

**服务端 → 客户端**:

连接成功:
```json
{
  "type": "connected",
  "userId": "uuid"
}
```

上报确认:
```json
{
  "type": "ack",
  "timestamp": "string"
}
```

管理员接收广播:
```json
{
  "type": "location_update",
  "userId": "uuid",
  "lng": "number",
  "lat": "number",
  "accuracy": "number | null",
  "speed": "number | null",
  "timestamp": "string"
}
```

错误:
```json
{
  "error": "userId 不匹配"
}
```

---

## POST /api/v1/attendance/checkin

**描述**: 员工打卡签到/签退（需 Token）。支持位置验证与 WiFi BSSID 验证，按考勤规则校验打卡有效性

**请求头**: `Authorization: Bearer ***`

**请求体**:
```json
{
  "type": "string (必填, 'checkin' | 'checkout')",
  "lng": "number (必填, 经度)",
  "lat": "number (必填, 纬度)",
  "address": "string (可选, 地址描述)",
  "photo_url": "string (可选, 打卡照片 URL)",
  "wifi_bssid": "string (可选, 当前连接 WiFi 的 BSSID)"
}
```

**成功响应** (200):
```json
{
  "success": true,
  "recordId": "uuid",
  "checkTime": "ISO datetime string",
  "type": "checkin"
}
```

**错误响应**:
- 400: `{"message": "打卡类型不能为空"}` 或 `{"message": "经纬度不能为空"}`
- 401: `{"message": "Token 无效或已过期"}`
- 403: `{"message": "不在允许的打卡范围内"}` (位置/WiFi 校验未通过)
- 500: `{"message": "服务器内部错误"}`

**备注**: 系统根据当前用户所在部门自动匹配考勤规则。若规则要求位置验证但坐标匹配失败，或要求 WiFi 验证但 BSSID 不匹配，返回 403。

---

## GET /api/v1/attendance/records

**描述**: 分页查询考勤记录（需 Token）。管理员查看所有记录，普通员工仅查看自己记录

**请求头**: `Authorization: Bearer ***`

**查询参数**:
- `page` (可选, 默认 1): 页码
- `pageSize` (可选, 默认 20): 每页条数
- `startDate` (可选): 起始日期, 格式 `YYYY-MM-DD`
- `endDate` (可选): 结束日期, 格式 `YYYY-MM-DD`
- `type` (可选): 打卡类型筛选, `checkin` | `checkout`

**成功响应** (200):
```json
{
  "records": [
    {
      "id": "uuid",
      "user_id": "uuid",
      "user_name": "string",
      "type": "checkin",
      "lng": "number",
      "lat": "number",
      "address": "string | null",
      "photo_url": "string | null",
      "check_time": "ISO datetime string",
      "created_at": "ISO datetime string"
    }
  ],
  "pagination": {
    "page": 1,
    "pageSize": 20,
    "total": 100,
    "totalPages": 5
  }
}
```

**错误响应**:
- 400: `{"message": "日期参数无效"}`
- 401: Token 无效

---

## GET /api/v1/attendance/rules

**描述**: 获取考勤规则列表（需 Manager/Admin 角色）

**请求头**: `Authorization: Bearer ***`

**成功响应** (200):
```json
[
  {
    "id": "uuid",
    "name": "string (规则名称)",
    "rule_type": "location | wifi | both",
    "center_lat": "number",
    "center_lng": "number",
    "radius_meters": "number",
    "wifi_ssid": "string | null",
    "wifi_bssid": "string | null",
    "is_active": true,
    "created_at": "ISO datetime string",
    "updated_at": "ISO datetime string"
  }
]
```

**错误响应**:
- 401: Token 无效
- 403: `{"message": "无权限访问"}`

---

## POST /api/v1/attendance/rules

**描述**: 创建考勤规则（需 Admin 角色）

**请求头**: `Authorization: Bearer ***`

**请求体**:
```json
{
  "name": "string (必填, 规则名称)",
  "rule_type": "string (必填, 'location' | 'wifi' | 'both')",
  "center_lat": "number (若 location/both 则必填)",
  "center_lng": "number (若 location/both 则必填)",
  "radius_meters": "number (若 location/both 则必填)",
  "wifi_ssid": "string (若 wifi/both 则必填, WiFi 名称)",
  "wifi_bssid": "string (若 wifi/both 则必填, WiFi MAC 地址)"
}
```

**成功响应** (201):
```json
{
  "id": "uuid",
  "name": "string",
  "rule_type": "both",
  "is_active": true,
  "created_at": "ISO datetime string"
}
```

**错误响应**:
- 400: `{"message": "规则名称不能为空"}` 或 `{"message": "必填参数缺失"}`
- 401: Token 无效
- 403: `{"message": "无权限访问"}`
- 500: 服务器内部错误

---

## DELETE /api/v1/attendance/rules/:id

**描述**: 删除考勤规则（需 Admin 角色）。物理删除记录

**路径参数**: `id` — 规则 UUID

**请求头**: `Authorization: Bearer ***`

**成功响应** (200):
```json
{
  "message": "规则已删除"
}
```

**错误响应**:
- 401: Token 无效
- 403: `{"message": "无权限访问"}`
- 404: `{"message": "规则不存在"}`

---

## GET /api/v1/attendance/stats

**描述**: 考勤统计（需 Manager/Admin 角色）。按用户汇总指定时间范围内的打卡次数

**请求头**: `Authorization: Bearer ***`

**查询参数**:
- `startDate` (可选): 起始日期, 格式 `YYYY-MM-DD`
- `endDate` (可选): 结束日期, 格式 `YYYY-MM-DD`

**成功响应** (200):
```json
{
  "startDate": "2026-07-01",
  "endDate": "2026-07-03",
  "stats": [
    {
      "user_id": "uuid",
      "name": "张三",
      "checkin_count": 3,
      "checkout_count": 2
    }
  ]
}
```

**错误响应**:
- 401: Token 无效
- 403: `{"message": "无权限访问"}`

---

## GET /api/v1/fences

**描述**: 获取电子围栏列表（需 Manager/Admin 角色）

**请求头**: `Authorization: Bearer ***`

**成功响应** (200):
```json
[
  {
    "id": "uuid",
    "name": "string (围栏名称)",
    "center_lat": "number",
    "center_lng": "number",
    "radius_meters": "number",
    "department_id": "uuid | null",
    "department_name": "string | null",
    "is_active": true,
    "created_at": "ISO datetime string",
    "updated_at": "ISO datetime string"
  }
]
```

**错误响应**:
- 401: Token 无效
- 403: `{"message": "无权限访问"}`

---

## POST /api/v1/fences

**描述**: 创建电子围栏（需 Admin 角色）

**请求头**: `Authorization: Bearer ***`

**请求体**:
```json
{
  "name": "string (必填, 围栏名称)",
  "center_lat": "number (必填, 围栏中心纬度)",
  "center_lng": "number (必填, 围栏中心经度)",
  "radius_meters": "number (必填, 围栏半径, 米)",
  "department_id": "uuid (可选, 关联部门 ID)"
}
```

**成功响应** (201):
```json
{
  "id": "uuid",
  "name": "string",
  "center_lat": "number",
  "center_lng": "number",
  "radius_meters": "number",
  "department_id": "uuid | null",
  "is_active": true,
  "created_at": "ISO datetime string"
}
```

**错误响应**:
- 400: `{"message": "围栏名称不能为空"}` 或 `{"message": "经纬度超出有效范围"}`
- 401: Token 无效
- 403: `{"message": "无权限访问"}`
- 500: 服务器内部错误

---

## PUT /api/v1/fences/:id

**描述**: 更新电子围栏（需 Admin 角色）。支持部分更新，仅发送需要修改的字段

**路径参数**: `id` — 围栏 UUID

**请求头**: `Authorization: Bearer ***`

**请求体** (全部可选，至少提供一个):
```json
{
  "name": "string (可选)",
  "center_lat": "number (可选)",
  "center_lng": "number (可选)",
  "radius_meters": "number (可选)",
  "is_active": "boolean (可选)"
}
```

**成功响应** (200):
```json
{
  "id": "uuid",
  "name": "string",
  "center_lat": "number",
  "center_lng": "number",
  "radius_meters": "number",
  "is_active": true,
  "updated_at": "ISO datetime string"
}
```

**错误响应**:
- 400: `{"message": "至少提供一个需要更新的字段"}`
- 401: Token 无效
- 403: `{"message": "无权限访问"}`
- 404: `{"message": "围栏不存在"}`

---

## DELETE /api/v1/fences/:id

**描述**: 删除电子围栏（需 Admin 角色）。软删除 — 将 `is_active` 设为 `false`

**路径参数**: `id` — 围栏 UUID

**请求头**: `Authorization: Bearer ***`

**成功响应** (200):
```json
{
  "message": "围栏已禁用"
}
```

**错误响应**:
- 401: Token 无效
- 403: `{"message": "无权限访问"}`
- 404: `{"message": "围栏不存在"}`

---

## POST /api/v1/fences/check

**描述**: 检查坐标是否在围栏内（需 Token）。使用 Haversine 公式计算球面距离，支持筛选特定围栏或检查全部围栏

**请求头**: `Authorization: Bearer ***`

**请求体**:
```json
{
  "lng": "number (必填, 待检测经度)",
  "lat": "number (必填, 待检测纬度)",
  "fence_id": "uuid (可选, 指定围栏 ID；不传则检查所有活跃围栏)"
}
```

**成功响应** (200):
```json
{
  "fences": [
    {
      "fenceId": "uuid",
      "fenceName": "string",
      "distance": "number (与围栏中心的距离, 米)",
      "inside": true
    }
  ]
}
```

**错误响应**:
- 400: `{"message": "经纬度不能为空"}`
- 401: Token 无效

---

## GET /api/v1/fences/events

**描述**: 获取围栏进出事件记录（需 Manager/Admin 角色）。支持按用户筛选和分页

**请求头**: `Authorization: Bearer ***`

**查询参数**:
- `userId` (可选): 按用户 ID 筛选
- `page` (可选, 默认 1): 页码
- `pageSize` (可选, 默认 20): 每页条数

**成功响应** (200):
```json
{
  "events": [
    {
      "id": "uuid",
      "fence_id": "uuid",
      "fence_name": "string",
      "user_id": "uuid",
      "user_name": "string",
      "event_type": "enter | exit",
      "lng": "number",
      "lat": "number",
      "occurred_at": "ISO datetime string"
    }
  ],
  "page": 1,
  "pageSize": 20,
  "total": 50,
  "totalPages": 3
}
```

**错误响应**:
- 401: Token 无效
- 403: `{"message": "无权限访问"}`

---

## 健康检查

### GET /health

**描述**: 服务健康检查（无需 Token）

**成功响应** (200):
```json
{
  "status": "ok",
  "uptime": "number (秒)"
}
```
