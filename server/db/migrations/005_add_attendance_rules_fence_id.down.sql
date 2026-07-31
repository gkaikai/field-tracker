-- 005 — 移除打卡规则与电子围栏的关联
BEGIN;

DROP INDEX IF EXISTS idx_attendance_rules_fence;
ALTER TABLE attendance_rules DROP COLUMN IF EXISTS fence_id;

COMMIT;
