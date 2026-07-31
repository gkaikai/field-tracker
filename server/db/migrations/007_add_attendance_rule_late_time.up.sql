-- 007 — 打卡规则增加 late_time（迟到时间）列
-- 前端编辑弹窗存在"迟到时间"输入框并提交 lateTime，但后端无列持久化（静默失效）。
BEGIN;

ALTER TABLE attendance_rules ADD COLUMN IF NOT EXISTS late_time TIME;

COMMENT ON COLUMN attendance_rules.late_time IS '迟到时间（如 09:30 后打卡记为迟到）';

COMMIT;
