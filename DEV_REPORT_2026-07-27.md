# Field Tracker 2026-07-27 完整开发报告

> 报告日期：2026-07-27
> 当前版本：v1.0.49+62
> 最终APK：https://gofile.io/d/DEY8YO

---

## 一、版本升级履历

| 版本 | 改动 | 
|------|------|
| v1.0.48+61 (初始) | 今日开发起点 |
| v1.0.49+62 (最终) | 全部修复合并后的最终版本 |

---

## 二、改动文件清单（今日）

### 2.1 新建文件

| 文件 | 行数 | 说明 |
|------|------|------|
| `app/lib/pages/fence_edit_page.dart` | ~793行 | **全新独立围栏编辑页面** — 全屏地图可视化编辑，与创建页完全分离 |

### 2.2 修改文件

| 文件 | 改动量 | 说明 |
|------|--------|------|
| `app/lib/pages/fence_page.dart` | +737/-737行 | 重构编辑/创建分离，修复搜索/滚轮/坐标问题 |
| `server/public/admin.js` | +377行 | 修复围栏搜索4个bug（Web管理后台） |
| `server/src/routes/geocode.ts` | +38行 | geocode回退从photon.komoot.io改为高德Web Service API |
| `app/lib/pages/customer_page.dart` | +1行 | 搜索建议列表 8→15条 |
| `server/public/app-version.json` | 更新 | 版本号+下载链接+更新日志 |

---

## 三、手机端（Flutter）全部修复

### 3.1 核心架构变更 — 编辑与创建完全分离

**背景：** 原实现中编辑围栏和创建围栏共用同一个Tab（创建tab）。编辑时修改`_editingFenceId`状态，切换tab后预填数据。这导致：
- 用户手动点「创建围栏」tab时错误显示「更新围栏」
- 搜索/建议列表在编辑模式下无声覆盖围栏坐标（🔴 致命）
- 状态容易混乱，二次编辑失效

**修复方案：**

```
┌─ 编辑流程（新） ─────────────────────┐
│ 围栏列表 → 点「编辑」→ Navigator.push │
│   → fence_edit_page.dart（独立页面）  │
│     → 全屏地图显示围栏当前几何数据     │
│     → 编辑名称/半径/顶点              │
│     → 点「更新围栏」→ PUT API         │
│     → pop回到列表                      │
└──────────────────────────────────────┘

┌─ 创建流程（不变） ─────────────────────┐
│ 点「创建围栏」tab                      │
│   → 地图点击设中心（圆）/点击设顶点（多边形）│
│   → 输入名称，滑块调半径                │
│   → 点「保存」→ POST API               │
└──────────────────────────────────────┘
```

**涉及的代码：**
- `_editFence()` — 从共享tab跳转改为 `Navigator.push(MaterialPageRoute(builder: (_) => FenceEditPage(fence: f)))`
- `_createCircleFence()` — 移除PUT分支，只保留POST
- `_createPolygonFence()` — 同上
- `_buildCircleControls()` / `_buildPolygonControls()` — 简化，不再显示「更新围栏」按钮和「取消编辑」按钮
- 移除 `_editingFenceId` 和 `_editNavigationRequested` 状态变量
- 简化 `_tabController.addListener`（移除编辑状态清理逻辑）

### 3.2 fence_edit_page.dart — 全新围栏编辑页面

**文件路径：** `app/lib/pages/fence_edit_page.dart`
**架构：** 独立的 `StatefulWidget`（`FenceEditPage`），不依赖fence_page的任何状态。

**功能：**
- 圆形围栏编辑：
  - 地图上可点击重设中心点
  - 底部滑块调整半径（50-5000米）
  - 独立的搜索/定位功能（高德place/text API）
- 多边形围栏编辑：
  - 显示数据库已有顶点
  - 点击地图添加新顶点
  - 撤回/清空操作
  - 独立搜索
- PUT API保存
- AppBar返回 + 底部保存按钮

**API调用：** `PUT /api/v1/fences/{id}` 

### 3.3 二次编辑失效修复

**问题：** 第一次编辑保存后，回到列表再点编辑，按钮无反应。
**根因：** `_createCircleFence`/`_createPolygonFence` 中 `_loadFences()` 未 `await`，在 `setState` 和 `_tabController.animateTo(0)` 完成后才执行，导致状态覆盖。
**修复：** `await _loadFences();`

### 3.4 搜索建议列表数量不足

**问题：** place/text API 的 `offset` 参数设为 `'8'`（仅返回8条），建议列表不够用。
**修复：** 改为 `'15'`。涉及文件：
- `fence_page.dart` L227
- `fence_edit_page.dart` L208
- `customer_page.dart` L126（`itemCount: suggestions.length > 15 ? 15 : suggestions.length`）

### 3.5 `double.parse` → `double.tryParse`

**问题：** 高德API返回的坐标格式异常时（空字符串、`[]`、`"0,0,0"`），`double.parse` 抛出 `FormatException`。catch虽能兜住但错误消息变成「搜索失败: FormatException」。
**修复：** 改为 `double.tryParse` + null判断。涉及3处：
- POI搜索结果（`_searchAddress` L303-312）
- 地理编码回退（`_searchAddress` L334-342）
- 建议列表onTap（L1021-1026）

### 3.6 `_searchCtrl.text` 不更新标准化名称

**问题：** 搜索成功后标准化POI名称未回填到搜索栏。
**修复：** `_searchAddress` 的setState中追加 `_searchCtrl.text = name;`

### 3.7 搜索建议下拉导致地图触摸丢失

**问题：** 建议列表在 Column 内导致 AMap PlatformView resize 后触摸永久丢失。
**修复：** 建议下拉框从 Column 内移到 Stack/Positioned overlay。

### 3.8 EagerGestureRecognizer 吞桌面滚轮事件

**问题：** AMapWidget 的 `gestureRecognizers` 不兼容Flutter 3.22 API。
**修复：** 移除 `gestureRecognizers` 参数，避免因 `Factory` 类型未定义导致编译失败。

---

## 四、管理后台（Web端）全部修复

### 4.1 故障A — 搜索后地图永久失效

**症状：** 在围栏搜索框搜地址后，地图滚轮缩放+鼠标拖拽全部失效。
**根因（审核员分析）：**
1. 点击建议项不触发 `input.blur()` → `scrollWheel: false` 永不恢复
2. `suggestBox`（`z-index:99999`）幽灵覆盖未从body移除，拦截地图事件
3. `suggestBox.onclick` 缺少 `e.stopPropagation()` → 点击穿透到 document 监听器

**修复：**
- `onTipClick` 末尾加 `input.blur()`（选完建议自动失焦恢复滚轮）
- `suggestBox.onclick` 加 `e.stopPropagation()`
- `blur` 监听器300ms后恢复 `scrollWheel: true`

### 4.2 故障B — 第二次点击不弹出

**症状：** 第一次搜索正常→清空→第二次点击搜索框，建议/下拉不弹出。
**根因：** `_fenceDocListenersBound` 守卫+闭包引用已 `destroy` 的旧 `input` DOM。旧 `hideSuggest()` 闭包永远引用已被 `destroy` 的旧input，新input点击永远触发 `hideSuggest()`。
**修复：** document click 监听器改用 `document.getElementById('fenceSearchInput')` 实时查找当前DOM。

### 4.3 故障C — 搜索失败

**症状：** 某些地址搜索失败。
**根因：** geocode回退使用 `photon.komoot.io`（境外OSM服务），国内访问极不稳定。
**修复（后端）：** geocode.ts 从 photon.komoot.io 改为高德 Web Service API：
```
旧：https://photon.komoot.io/api/?q={address}&limit=1
新：https://restapi.amap.com/v3/geocode/geo?key=xxx&address={address}&output=JSON
```
**配置：** `.env` 增加 `AMAP_WS_KEY=665f6c9959c69f9c08ae1d869d2b7abd`

### 4.4 故障D — 编辑变新建

**症状：** 编辑围栏后，点主界面「💾 保存」按钮，结果是POST新建而非PUT更新。
**根因：** 主按钮调的是 `saveFence()`（POST），编辑按钮旁新增的小按钮才是 `saveFenceEdit(id)`。用户自然地点更大的主按钮。
**修复：** `editFence` 中将主按钮改为 `saveFenceEdit(id)`，文字改为「💾 更新」。

---

## 五、审核流程回顾

每个修改都经过了审核员（agent 2068148595781013504）审核：

| 批次 | 内容 | 审核结论 |
|------|------|---------|
| admin.js v15 | 围栏搜索4个bug修复 | ✅ 全部通过 |
| 二次编辑失效 + editNavigation标记 | await _loadFences + 清除编辑状态 | 🔴 整改→变为方案1 |
| 编辑创建分离 | AlertDialog方案（初版） | 🔴 审核员建议升级为独立页面 |
| fence_edit_page.dart | 全屏地图编辑页面（审核员补写） | ✅ 通过 |
| 8→15条 | 搜索建议数量 | ✅ 通过 |

---

## 六、构建交付

| 制品 | 链接 |
|------|------|
| APK v1.0.49+62 | https://gofile.io/d/DEY8YO |
| 在线升级配置 | server/public/app-version.json |
| gofile CDN | 全量APK分发，国内可访问 |

---

## 七、已知未完成项

1. **管理后台围栏搜索未测** — 用户明天到电脑前测试
2. **多边形编辑不支持形状调整** — 编辑多边形时暂时只改名称，顶点不可调（需要设计「完成修改」按钮）
3. **多边形编辑页面的搜索建议** — `fence_edit_page.dart` 中的搜索未完成集成（没有建议列表下拉）
