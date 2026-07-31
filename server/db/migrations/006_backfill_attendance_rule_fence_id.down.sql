-- 006 — 回退：移除唯一索引（fence_id 回填数据不可逆，保留不清理）
BEGIN;
DROP INDEX IF EXISTS idx_attendance_rules_fence_unique;
COMMIT;
