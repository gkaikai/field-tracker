# 迁移重排 — 线上部署核对手册

> 背景：第 4 轮整改将 `002_messages_table` 重命名为 `003_messages_table`、
> `002_expenses_table` 重命名为 `004_expenses_table`，并新增
> `005_add_attendance_rules_fence_id`、`006_backfill_attendance_rule_fence_id`。
> `migrate.js` 按**数字前缀 version** 去重（`_migrations.version` 唯一键），
> 因此**已有数据库必须核对历史 version=002 记录归属**，否则可能误判迁移已应用。

## 一、部署前核对（必须执行）

```bash
# 在服务器后端目录执行
cd /path/to/field_tracker/server
node db/migrate.js status
```

核对 `_migrations` 表中 **version=002 的记录 name 是 `audit_logs` 还是 `messages_table`**：

| 线上 002 记录归属 | 结论 | 处理 |
|------------------|------|------|
| `audit_logs` | ✅ 正常 | 直接 `node db/migrate.js up` 即可 |
| `messages_table`（旧名） | ⚠️ 冲突 | `002_audit_logs` 会被误判为"已应用"而**永不执行**，线上缺 audit_logs 表 |

### 冲突处理（002=messages_table 时）

方案 A（推荐）——手工修正 version 记录后正常迁移：

```sql
-- 1. 把 messages 的旧记录从 002 改为 003（与迁移文件新编号对齐）
UPDATE _migrations SET version = '003' WHERE version = '002' AND name = 'messages_table';

-- 2. 正常执行迁移（会应用 002_audit_logs + 004_expenses + 005 + 006）
node db/migrate.js up
```

方案 B——手工执行缺失迁移：

```bash
# 只应用 audit_logs（002 已被 messages 占用时）
psql "$DATABASE_URL" -f db/migrations/002_audit_logs.up.sql
node db/migrate.js up   # 应用 004/005/006
```

## 二、验证清单（迁移后）

### 迁移前预检（006 回填相关）

006 回填按「名称 = 围栏名 || '打卡规则'」匹配存量规则。若线上存在**重名围栏**，
回填可能把同一 fence_id 赋给多条规则，导致 `idx_attendance_rules_fence_unique`
创建失败、迁移整体回滚。迁移前先核对：

```sql
SELECT name, COUNT(*) FROM geo_fences GROUP BY name HAVING COUNT(*) > 1;
-- 期望 0 行；若 >0，需先人工去重重名围栏，或调整回填策略
```

```bash
node db/migrate.js status   # 期望 001~007 全部 ✅ 已应用，0 待处理
```

SQL 核对（psql 或 node）：

```sql
-- 三张新表应存在
SELECT tablename FROM pg_tables
WHERE schemaname='public' AND tablename IN ('audit_logs','messages','expenses');

-- attendance_rules 应有 fence_id 列、外键与唯一索引
SELECT column_name FROM information_schema.columns
WHERE table_name='attendance_rules' AND column_name='fence_id';

SELECT indexname FROM pg_indexes WHERE tablename='attendance_rules'
AND indexname IN ('idx_attendance_rules_fence','idx_attendance_rules_fence_unique');

-- 006 回填结果：围栏自动规则（名称含"打卡规则"）应全部有关联 fence_id
SELECT COUNT(*) AS orphan_rules FROM attendance_rules
WHERE name LIKE '%打卡规则' AND fence_id IS NULL;
-- 期望 0；若 >0 说明存量规则名称与围栏名不匹配，需人工核对
```

## 三、回滚注意

- 已应用的迁移若回滚，`migrate.js` 会做 **checksum 校验**：`002_messages_table.down.sql`
  已改名 `003_messages_table.down.sql`，**旧 002 记录的 checksum 与新文件不匹配**，
  回滚时该迁移会被跳过并提示手动处理（设计如此，不影响其他迁移回滚）。
- 006 回填不可逆（down 仅移除唯一索引，不回填数据）。

## 四、其他部署提醒

- `server/uploads/` 已加入 .gitignore，测试照片不再入库。
- 多边形围栏自动生成的打卡规则，打卡半径按围栏**外扩约 20%**（外接圆 × 1.2），属设计取舍。
