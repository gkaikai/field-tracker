-- 007 — 回退：移除 late_time 列
BEGIN;
ALTER TABLE attendance_rules DROP COLUMN IF EXISTS late_time;
COMMIT;
