-- ============================================================
-- 001 — 初始建表（回退脚本）
-- 撤销 schema.sql 创建的所有表、索引、函数、触发器
-- ============================================================

BEGIN;

-- 按依赖顺序删除（子→父）以避免外键冲突
DROP TABLE IF EXISTS fence_events CASCADE;
DROP TABLE IF EXISTS visit_records CASCADE;
DROP TABLE IF EXISTS photos CASCADE;
DROP TABLE IF EXISTS attendance_records CASCADE;
DROP TABLE IF EXISTS location_records CASCADE;
DROP TABLE IF EXISTS geo_fences CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS app_updates CASCADE;
DROP TABLE IF EXISTS reports CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS departments CASCADE;

-- 删除分区函数（如存在）
DROP FUNCTION IF EXISTS create_location_partition(date) CASCADE;
DROP FUNCTION IF EXISTS ensure_future_partitions(int) CASCADE;
DROP FUNCTION IF EXISTS update_updated_at_column() CASCADE;

-- 不删除 _migrations 表（迁移框架自身管理）

COMMIT;
