# 电子围栏 & 打卡规则 BUG 清单

## BUG 1: POI 搜索建议列表(ListTile)文字无显式颜色 — 白底白字风险

**文件**: `fence_page.dart` 第 887 / `fence_edit_page.dart` 第 505 行  
**严重度**: 高  
**描述**: `_buildSuggestionsOverlay()` 中 ListTile 的 `title` 和 `subtitle` 文字未设置显式颜色。  
- 背景: `Colors.white`（硬编码白色，第 871/489 行）  
- title: `const TextStyle(fontSize: 14)` — **无 color 属性**，继承 Theme 文字色  
- 暗黑模式下 Theme 文字色为白色 → **白底白字，完全不可见**

```dart
// fence_page.dart:887
title: Text(item['name'] ?? '', style: const TextStyle(fontSize: 14)),
// fence_edit_page.dart:505
title: Text(item['name'] ?? '', style: const TextStyle(fontSize: 14)),
```

**修复**: 添加 `color: Colors.black87` 或继承自主题的显式颜色。

---

## BUG 2: POI 搜索框 hintStyle 对比度过低

**文件**: `fence_page.dart` 第 951 行 / `fence_edit_page.dart` 第 334 行  
**严重度**: 中  
**描述**:  
- `fillColor: Colors.grey[50]` (#FAFAFA, 几乎白色)  
- `hintStyle: color: Colors.grey[400]` (#BDBDBD)  
- 对比度约 2.2:1，低于 WCAG AA 标准(4.5:1)，老年用户或户外强光下难以辨认

---

## BUG 3: 前端考勤规则参数字段名与后端不匹配（核心BUG）

**文件**: `attendance_rules_page.dart` 第 256-261 行 ↔ `server/src/routes/attendance.ts` 第 320-324 行  
**严重度**: **致命**  
**描述**: 前端发送的 API 字段名和后端期望的字段名完全不一致，导致打卡规则创建/编辑实际不生效。

| 含义 | 前端发送 | 后端expect | 匹配？|
|------|---------|-----------|:----:|
| 上班时间 | `startTime` | `checkin_start` | ❌ |
| 迟到时间 | `lateTime` | 后端无此字段 | ❌ |
| 下班时间 | `endTime` | `checkin_end` | ❌ |
| 范围(米) | `radius` | `radius_meters` | ❌ |

**后果**:
1. 新建规则时所有时间字段写为 `null` → 打卡校准时 start/end 为空
2. 编辑已有规则时时间字段不会被更新
3. `lateTime` 完全被后端忽略（数据库也无此列）

**修复**: 在 `attendance_rules_page.dart` 第 256-261 行将字段名改为后端格式，或在后端做字段名映射。

---

## BUG 4: 前端打卡规则列表读取字段名与后端返回不匹配

**文件**: `attendance_rules_page.dart` 第 127-130 行  
**严重度**: **致命**  
**描述**: 后端返回 snake_case 字段 `checkin_start`、`checkin_end`、`radius_meters`，但前端读取 camelCase 字段：

```dart
// 第127行 — 实际是 'checkin_start'，不是 'startTime'
'${rm['startTime'] ?? '09:00'} - ${rm['lateTime'] ?? '09:30'}'
// 第128行 — 实际是 'checkin_end'，不是 'endTime'
'${rm['endTime'] ?? '18:00'}'
// 第130行 — 实际是 'radius_meters'，不是 'radius'
'${rm['radius'] ?? 100}m'
```

**后果**: 围栏自动创建的打卡规则在列表中显示错误（永远显示默认 09:00-18:00, 100m），用户看到错误信息。

---

## BUG 5: 围栏编辑(PUT)不同步更新打卡规则

**文件**: `fence.ts` 第 126-175 行（PUT handler）  
**严重度**: 高  
**描述**: 创建围栏时自动创建了打卡规则(BUG 6的同步逻辑)，但 **编辑围栏（更新中心点/半径）时不会同步更新对应的打卡规则**。导致围栏和打卡规则数据不一致。

---

## BUG 6: 围栏删除(DELETE)未清理关联打卡规则（孤儿数据）

**文件**: `fence.ts` 第 178-196 行  
**严重度**: 高  
**描述**: 删除围栏(SET)时没有级联删除或置灰对应的打卡规则，产生孤立数据。删除围栏后，`attendance_rules` 表中仍保留着无归属的规则记录。

---

## BUG 7: 多边形围栏不自动创建打卡规则

**文件**: `fence.ts` 第 106 行  
**严重度**: 中  
**描述**: 自动同步逻辑以 `shapeType === 'circle'` 为条件（第106行），多边形围栏不会自动生成打卡规则。用户期望多边形围栏也能自动关联打卡。

```typescript
// fence.ts:106 — 只检查 circle
if (shapeType === 'circle' && centerLat && centerLng && radiusMeters) {
```

---

## BUG 8: 自动创建的打卡规则时间固定无个性化

**文件**: `fence.ts` 第 109-112 行  
**严重度**: 中  
**描述**: 围栏创建时自动插入的打卡规则硬编码时间为：
- `checkin_start: '06:00:00'` — 早上6点，对大多数企业过早  
- `checkin_end: '22:00:00'` — 晚上10点  
- 没有 `late_time` / `checkout_start` / `checkout_end`  
- 没有 `startTime` / `lateTime` / `endTime` 概念

---

## BUG 9: 编辑打卡规则时位置/经纬度数据不可见不可改

**文件**: `attendance_rules_page.dart` 第 156-294 行  
**严重度**: 中  
**描述**: 编辑对话框只有名称、时间、范围的输入框，没有显示/编辑 `center_lat` / `center_lng`（围栏中心点）。即使用户在打卡规则页面看到了自动生成的规则，也无法调整其地理位置——必须回到围栏编辑页才能改。

---

## BUG 10: 搜索按钮无文字反馈

**文件**: `fence_page.dart` 第 999 行 / `fence_edit_page.dart` 第 386 行  
**严重度**: 低  
**描述**: 搜索按钮只有图标(🔍)，无障碍和用户体验不佳。建议改为 FilledButton 带文字"搜索"。

---

## 总结

| # | 严重度 | 领域 | 描述 |
|---|--------|------|------|
| 1 | 🔴 高 | 前端UI | POI建议列表白底白字（ListTile无显式color） |
| 2 | 🟡 中 | 前端UI | 搜索框hintStyle对比度不足 |
| 3 | 🔴 **致命** | API | 考勤规则前端字段名与后端不匹配 → 创建/编辑不生效 |
| 4 | 🔴 **致命** | API | 考勤规则列表前端读取字段名与后端返回不匹配 → 显示错误 |
| 5 | 🟡 高 | 后端 | 编辑围栏不同步更新打卡规则 |
| 6 | 🟡 高 | 后端 | 删除围栏产生孤立打卡规则 |
| 7 | 🟡 中 | 后端 | 多边形围栏不自动创建打卡规则 |
| 8 | 🟡 中 | 后端 | 自动打卡规则时间硬编码不合理 |
| 9 | 🟡 中 | 前端 | 打卡规则编辑框无地理位置字段 |
| 10 | 🟢 低 | 前端UI | 搜索按钮无文字只图标 |
