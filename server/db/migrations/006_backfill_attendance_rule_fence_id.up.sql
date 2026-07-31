-- 006 — 回填存量打卡规则的 fence_id + 唯一索引
-- 背景：修复前自动创建的打卡规则（名称 = 围栏名 + '打卡规则'）没有 fence_id，
--      导致编辑/删除围栏无法同步这些存量规则。此处按名称匹配回填关联。
BEGIN;

-- 回填：围栏自动创建的规则（名称 = 围栏名 || '打卡规则'）且当前无 fence_id
UPDATE attendance_rules r
SET fence_id = f.id
FROM geo_fences f
WHERE r.fence_id IS NULL
  AND r.name = f.name || '打卡规则';

-- 部分唯一索引：同一围栏最多一条关联规则（允许多个 NULL，不影响手动规则）
CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_rules_fence_unique
    ON attendance_rules(fence_id) WHERE fence_id IS NOT NULL;

COMMIT;
