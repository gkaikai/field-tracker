# 技术债登记（Tech Debt Register）

> 维护人：程序开发员 | 更新：2026-07-31
> 状态说明：P0=阻塞交付须优先解决；P1=计划内近期解决；P2=已知可接受长期存在

## 当前登记

| # | 级别 | 描述 | 影响 | 计划 |
|---|------|------|------|------|
| TD-001 | P2 | `attendance.ts` 内存规则回退（memRules）仅存活于进程内，不持久化；DB 不可用时创建的规则重启即丢 | 仅 DB 故障降级场景，正常生产库路径不受影响 | 保持现状（降级方案），如业务要求可后续引入本地文件持久化 |
| TD-002 | P2 | 围栏自动创建的打卡规则时间窗为默认值 `09:00-18:00`（fence.ts DEFAULT_CHECKIN_START/END），仅 POST/PUT 显式传 checkinStart/checkinEnd 可覆盖，不随围栏时间设置联动 | 首次创建默认时间窗固定，用户可在规则编辑页自行修改 | 保持现状；后续可给围栏增加时间段字段后联动 |
| TD-003 | P2 | 多边形围栏规则中心点为顶点均值、半径为最大顶点距离×1.2，非严格外接圆 | 多边形打卡边界略宽松于围栏多边形 | 保持现状；精确到面检测需额外几何计算，收益低 |
| TD-004 | P2 | `attendance.ts` GET 规则列表 DB 与内存两条路径各自映射 camelCase，逻辑重复 | 维护成本略高，行为一致 | 抽取公共映射函数（下一轮重构时合并） |
| TD-005 | P1 | `profile_page.dart` 版本号展示依赖 `PackageInfo.fromPlatform()`，release 构建时才准确，debug 构建可能显示 0.0.0 | 仅影响 debug 包显示 | 已动态化，无阻塞 |
| TD-006 | P1 | `api_service.dart` 的 `amapDio` 独立于主 `_dio`：不走统一 token 拦截器、不映射业务错误码，POI/地理编码调用（poi_search_field/fence_page/fence_edit_page/customer_page 共 4 个调用方）错误处理各自为政 | 高德 key 失效/限流时报错样式不统一，故障排查成本高 | 中期重构：amapDio 复用统一拦截器（仅替换 baseUrl+key），错误统一走 `_httpErrorMessage` |

## 已解决（历史）

- ~~expenses 迁移编号冲突（002→004）~~：已修复并提交
- ~~围栏↔打卡规则 PUT/DELETE 不同步~~：已修复（fence_id 关联 + 回填 + 级联）
- ~~规则编辑 PUT lateTime 空串报错~~：已修复（空串归一化为 NULL）
- ~~GET 内存回退不映射 camelCase~~：已修复

## 原则

1. 技术债须在交付前如实登记，不得隐瞒。
2. P0/P1 项须纳入最近迭代计划；P2 项可在迭代评审时重估。
3. 解决后移入"已解决"区并注明提交号/日期。
