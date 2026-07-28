-- ============================================================
-- 数据清理脚本
-- 用途：修复生产数据完整性 — null/空值/脏数据
-- 运行：psql -h localhost -U postgres -d field_tracker -f cleanup.sql
-- 创建：2026-07-24
-- ============================================================

BEGIN;

-- 1. 清理 photos 表中的空记录（无关联业务ID、无缩略图）
DELETE FROM photos WHERE biz_id IS NULL AND thumbnail_url IS NULL;

-- 2. 创建默认部门（如不存在）
INSERT INTO departments (name, description)
SELECT '默认部门', '系统自动创建'
WHERE NOT EXISTS (SELECT 1 FROM departments WHERE name = '默认部门');

-- 3. 将所有无部门的用户分配到默认部门
UPDATE users
SET department_id = (SELECT id FROM departments WHERE name = '默认部门')
WHERE department_id IS NULL;

-- 4. 打卡记录 photo_url 空值标记
UPDATE attendance_records
SET photo_url = 'no_photo'
WHERE photo_url IS NULL OR photo_url = '';

-- 5. 定位记录空值置零
UPDATE location_records SET altitude = 0 WHERE altitude IS NULL;
UPDATE location_records SET bearing  = 0 WHERE bearing  IS NULL;
UPDATE location_records SET battery  = 0 WHERE battery  IS NULL;

-- 6. 围栏事件精度空值置零
UPDATE fence_events SET accuracy = 0 WHERE accuracy IS NULL;

COMMIT;

-- 验证
SELECT 'photos空记录' as check_name, count(*) FROM photos WHERE biz_id IS NULL AND thumbnail_url IS NULL;
SELECT '无部门用户'   as check_name, count(*) FROM users WHERE department_id IS NULL;
SELECT '打卡无照片'   as check_name, count(*) FROM attendance_records WHERE photo_url IS NULL OR photo_url = '';
SELECT '定位海拔空'   as check_name, count(*) FROM location_records WHERE altitude IS NULL;
SELECT '定位方向空'   as check_name, count(*) FROM location_records WHERE bearing IS NULL;
SELECT '定位电量空'   as check_name, count(*) FROM location_records WHERE battery IS NULL;
SELECT '围栏精度空'   as check_name, count(*) FROM fence_events WHERE accuracy IS NULL;
