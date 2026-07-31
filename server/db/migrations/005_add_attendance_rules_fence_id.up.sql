-- 005 — 打卡规则关联电子围栏
-- 围栏创建/编辑/删除时需同步 attendance_rules，因此增加 fence_id 关联列
BEGIN;

ALTER TABLE attendance_rules ADD COLUMN IF NOT EXISTS fence_id UUID REFERENCES geo_fences(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_attendance_rules_fence ON attendance_rules(fence_id);

COMMENT ON COLUMN attendance_rules.fence_id IS '关联的电子围栏 ID（围栏自动创建的规则通过此列双向同步）';

COMMIT;
