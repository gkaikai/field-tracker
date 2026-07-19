-- =============================================================================
-- Field Tracker — 测试种子数据
-- 为全部 12 张表插入可用的测试记录
-- 用法: psql -U postgres -d field_tracker -f seed.sql
-- =============================================================================
-- 环境要求: 先运行 migrate.sql (或 schema.sql) 确保表已创建
-- =============================================================================

BEGIN;

-- ============================================================
-- 密码统一为 "123456" 的 bcrypt hash
-- ============================================================
-- bcrypt hash for "123456": $2b$12$LJ3m4ys3Lk0TSwHnbfFHu.xYFHS5Ff6HBLmP0cbKgIZjLhMx5uqSO
-- 为方便不同环境，提供备选 hash
\set PWD_HASH '$2b$12$LJ3m4ys3Lk0TSwHnbfFHu.xYFHS5Ff6HBLmP0cbKgIZjLhMx5uqSO'

-- ============================================================
-- 1. users — 用户数据
-- ============================================================
INSERT INTO users (id, name, phone, password_hash, role, email, is_active) VALUES
    ('a0000000-0000-0000-0000-000000000001', '张三',     '13800138001', :'PWD_HASH', 'employee',    'zhangsan@example.com',    true),
    ('a0000000-0000-0000-0000-000000000002', '李四',     '13800138002', :'PWD_HASH', 'employee',    'lisi@example.com',        true),
    ('a0000000-0000-0000-0000-000000000003', '王五',     '13800138003', :'PWD_HASH', 'employee',    'wangwu@example.com',      true),
    ('a0000000-0000-0000-0000-000000000004', '赵六',     '13800138004', :'PWD_HASH', 'employee',    'zhaoliu@example.com',     true),
    ('a0000000-0000-0000-0000-000000000005', '陈七',     '13800138005', :'PWD_HASH', 'employee',    'chenqi@example.com',      true),
    ('a0000000-0000-0000-0000-000000000006', '刘经理',   '13900139001', :'PWD_HASH', 'manager',     'liu@example.com',         true),
    ('a0000000-0000-0000-0000-000000000007', '吴经理',   '13900139002', :'PWD_HASH', 'manager',     'wu@example.com',          true),
    ('a0000000-0000-0000-0000-000000000099', '管理员',   '13900000001', :'PWD_HASH', 'admin',       'admin@example.com',       true)
ON CONFLICT (phone) DO UPDATE SET
    name           = EXCLUDED.name,
    password_hash  = EXCLUDED.password_hash,
    role           = EXCLUDED.role;

-- ============================================================
-- 2. departments — 部门数据
-- ============================================================
INSERT INTO departments (id, name, parent_id, manager_id, description, sort_order) VALUES
    ('b0000000-0000-0000-0000-000000000001', '总公司',        NULL,        NULL,                          '总公司',         1),
    ('b0000000-0000-0000-0000-000000000002', '销售一部',      'b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000006', '销售一部',       2),
    ('b0000000-0000-0000-0000-0000-000000000003', '销售二部',    'b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000007', '销售二部',       3),
    ('b0000000-0000-0000-0000-000000000004', '技术部',        'b0000000-0000-0000-0000-000000000001', NULL,                          '技术支持',       4),
    ('b0000000-0000-0000-0000-000000000005', '行政部',        'b0000000-0000-0000-0000-000000000001', NULL,                          '行政管理',       5)
ON CONFLICT (id) DO NOTHING;

-- 更新用户部门归属
UPDATE users SET department_id = 'b0000000-0000-0000-0000-000000000002' WHERE id IN (
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002',
    'a0000000-0000-0000-0000-000000000003'
);
UPDATE users SET department_id = 'b0000000-0000-0000-0000-000000000003' WHERE id = 'a0000000-0000-0000-0000-000000000004';
UPDATE users SET department_id = 'b0000000-0000-0000-0000-000000000004' WHERE id = 'a0000000-0000-0000-0000-000000000005';
UPDATE users SET department_id = 'b0000000-0000-0000-0000-000000000002' WHERE id = 'a0000000-0000-0000-0000-000000000006';
UPDATE users SET department_id = 'b0000000-0000-0000-0000-000000000003' WHERE id = 'a0000000-0000-0000-0000-000000000007';
UPDATE users SET department_id = 'b0000000-0000-0000-0000-000000000001' WHERE id = 'a0000000-0000-0000-0000-000000000099';

-- 更新部门负责人（users 外键已创建后可做）
UPDATE departments SET manager_id = 'a0000000-0000-0000-0000-000000000006'
    WHERE id = 'b0000000-0000-0000-0000-000000000002';
UPDATE departments SET manager_id = 'a0000000-0000-0000-0000-000000000007'
    WHERE id = 'b0000000-0000-0000-0000-000000000003';

-- ============================================================
-- 3. attendance_rules — 打卡规则
-- ============================================================
INSERT INTO attendance_rules (id, name, department_id, rule_type,
    center_lat, center_lng, radius_meters,
    checkin_start, checkin_end, checkout_start, checkout_end,
    allow_remote, grace_minutes, created_by)
VALUES
    ('c0000000-0000-0000-0000-000000000001',
     '销售一部-默认规则',
     'b0000000-0000-0000-0000-000000000002',
     'location', 39.9042, 116.4074, 300,
     '08:00', '09:30', '17:30', '19:00',
     false, 15, 'a0000000-0000-0000-0000-000000000099'),
    ('c0000000-0000-0000-0000-000000000002',
     '销售二部-弹性规则',
     'b0000000-0000-0000-0000-000000000003',
     'location', 39.9142, 116.4174, 500,
     '08:30', '10:00', '17:00', '18:30',
     true, 30, 'a0000000-0000-0000-0000-000000000099'),
    ('c0000000-0000-0000-0000-000000000003',
     '技术部-WiFi规则',
     'b0000000-0000-0000-0000-000000000004',
     'wifi', NULL, NULL, NULL,
     '09:00', '09:30', '18:00', '18:30',
     false, 10, 'a0000000-0000-0000-0000-000000000099')
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 4. attendance_records — 打卡记录
-- ============================================================
INSERT INTO attendance_records (user_id, rule_id, type, check_time,
    lng, lat, address, accuracy, source, status)
SELECT
    u.id,
    'c0000000-0000-0000-0000-000000000001',
    'checkin',
    d::TIMESTAMPTZ + TIME '08:55:00',
    116.4074 + random() * 0.002 - 0.001,
    39.9042 + random() * 0.002 - 0.001,
    '北京市朝阳区建国路88号',
    10 + random() * 20,
    'app',
    CASE WHEN random() < 0.8 THEN 'normal' ELSE 'late' END
FROM users u
CROSS JOIN (
    SELECT generate_series(
        CURRENT_DATE - INTERVAL '30 days',
        CURRENT_DATE - INTERVAL '1 day',
        '1 day'::INTERVAL
    )::DATE AS d
) days
WHERE u.department_id = 'b0000000-0000-0000-0000-000000000002'
  AND u.is_active = true
  EXTRACT(DOW FROM days.d) NOT IN (0, 6)        -- 仅工作日
LIMIT 200;

INSERT INTO attendance_records (user_id, rule_id, type, check_time,
    lng, lat, address, accuracy, source, status)
SELECT
    user_id,
    rule_id,
    'checkout',
    check_time + INTERVAL '9 hours' + (random() * INTERVAL '30 minutes'),
    lng + random() * 0.001,
    lat + random() * 0.001,
    '北京市朝阳区建国路88号',
    10 + random() * 20,
    'app',
    CASE WHEN random() < 0.85 THEN 'normal' ELSE 'early' END
FROM attendance_records
WHERE type = 'checkin' AND id % 2 = 1
LIMIT 100;

-- ============================================================
-- 5. location_records — 定位记录（需先有分区）
-- ============================================================
INSERT INTO location_records (user_id, lng, lat, accuracy, speed, altitude, battery, provider, recorded_at)
SELECT
    u.id,
    116.4 + random() * 0.05,
    39.9 + random() * 0.05,
    5 + random() * 30,
    random() * 10,
    30 + random() * 50,
    50 + random() * 50,
    'gps',
    NOW() - (random() * INTERVAL '7 days')
FROM users u
WHERE u.is_active = true
  AND u.role = 'employee'
LIMIT 500;

-- ============================================================
-- 6. geo_fences — 电子围栏
-- ============================================================
INSERT INTO geo_fences (id, name, department_id, center_lat, center_lng, radius_meters, shape_type, color, description, created_by) VALUES
    ('f0000000-0000-0000-0000-000000000001',
     '销售一部办公区', 'b0000000-0000-0000-0000-000000000002',
     39.9042, 116.4074, 300, 'circle', '#FF6B6B',
     '销售一部办公地点围栏', 'a0000000-0000-0000-0000-000000000099'),
    ('f0000000-0000-0000-0000-000000000002',
     '销售二部办公区', 'b0000000-0000-0000-0000-000000000003',
     39.9142, 116.4174, 500, 'circle', '#4ECDC4',
     '销售二部办公地点围栏', 'a0000000-0000-0000-0000-000000000099'),
    ('f0000000-0000-0000-0000-000000000003',
     '总部大楼',     'b0000000-0000-0000-0000-000000000001',
     39.9092, 116.4124, 200, 'circle', '#45B7D1',
     '总部大楼围栏', 'a0000000-0000-0000-0000-000000000099')
ON CONFLICT (id) DO NOTHING;

-- 多边形围栏示例（北京国贸商圈）
INSERT INTO geo_fences (id, name, department_id, shape_type,
    polygon_points, color, description, created_by)
VALUES (
    'f0000000-0000-0000-0000-000000000004',
    '国贸商圈',
    'b0000000-0000-0000-0000-000000000002',
    'polygon',
    '[{"lat":39.9080,"lng":116.4500},{"lat":39.9080,"lng":116.4700},{"lat":39.8980,"lng":116.4700},{"lat":39.8980,"lng":116.4500}]'::JSONB,
    '#FFA500', '国贸商圈多边形围栏', 'a0000000-0000-0000-0000-000000000099');

-- ============================================================
-- 7. fence_events — 围栏事件
-- ============================================================
INSERT INTO fence_events (user_id, fence_id, event_type, lng, lat, event_time, processed, notified)
SELECT
    u.id,
    f.id,
    CASE WHEN random() < 0.6 THEN 'enter' ELSE 'exit' END,
    f.center_lng + (random() - 0.5) * 0.01,
    f.center_lat + (random() - 0.5) * 0.01,
    NOW() - (random() * INTERVAL '14 days'),
    random() < 0.9,
    random() < 0.8
FROM users u
CROSS JOIN geo_fences f
WHERE u.is_active = true AND u.role = 'employee'
  AND f.is_active = true
LIMIT 100;

-- ============================================================
-- 8. customers — 客户数据
-- ============================================================
INSERT INTO customers (id, name, short_name, phone, contact_person, contact_phone,
    province, city, district, address, lng, lat, industry, level, status, manager_id, created_by)
VALUES
    ('d0000000-0000-0000-0000-000000000001', '北京科技有限公司',      '北京科技', '010-88886666', '王经理', '13811112222',
     '北京市', '朝阳区', '望京', '望京SOHO T3-1801', 116.4806, 39.9960, '信息技术', 'A', 'active',
     'a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000099'),
    ('d0000000-0000-0000-0000-000000000002', '上海贸易有限公司',      '上海贸易', '021-88886666', '李总',   '13922223333',
     '上海市', '浦东新区', '陆家嘴', '陆家嘴金融中心15层', 121.5050, 31.2350, '贸易物流', 'A', 'active',
     'a0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000099'),
    ('d0000000-0000-0000-0000-000000000003', '深圳创新科技公司',      '深圳创新', '0755-88886666', '陈总',   '13633334444',
     '广东省', '深圳市', '南山区', '科技园南区A栋', 113.9420, 22.5400, '信息技术', 'B', 'active',
     'a0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000099'),
    ('d0000000-0000-0000-0000-000000000004', '广州建材批发市场',      '广州建材', '020-88886666', '刘总',   '13744445555',
     '广东省', '广州市', '天河区', '天河路560号', 113.3250, 23.1350, '建材', 'B', 'active',
     'a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000099'),
    ('d0000000-0000-0000-0000-000000000005', '成都高新区孵化器管理有限公司', '成都孵化器', '028-88886666', '杨总', '13555556666',
     '四川省', '成都市', '高新区', '天府大道999号', 104.0650, 30.5450, '企业服务', 'C', 'active',
     'a0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000099'),
    ('d0000000-0000-0000-0000-000000000006', '杭州电商科技有限公司',  '杭州电商', '0571-88886666', '周总',   '13455556666',
     '浙江省', '杭州市', '余杭区', '文一西路998号', 120.0200, 30.2800, '电子商务', 'A', 'active',
     'a0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000099'),
    ('d0000000-0000-0000-0000-000000000007', '武汉光谷信息技术公司',  '武汉光谷', '027-88886666', '张总',   '15666667777',
     '湖北省', '武汉市', '洪山区', '光谷大道77号', 114.4200, 30.5000, '信息技术', 'B', 'inactive',
     'a0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000099'),
    ('d0000000-0000-0000-0000-000000000008', '南京智能制造有限公司',  '南京智能', '025-88886666', '赵总',   '15988889999',
     '江苏省', '南京市', '江宁区', '将军大道128号', 118.8550, 31.9350, '制造业', 'D', 'lost',
     NULL, 'a0000000-0000-0000-0000-000000000099')
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 9. visit_records — 拜访记录
-- ============================================================
INSERT INTO visit_records (id, user_id, customer_id, visit_type, status,
    planned_at, start_time, end_time, duration_minutes,
    signin_lng, signin_lat, signin_address,
    purpose, content, result, satisfaction, has_photo)
VALUES
    ('e0000000-0000-0000-0000-000000000001',
     'a0000000-0000-0000-0000-000000000001',
     'd0000000-0000-0000-0000-000000000001',
     'field', 'completed',
     NOW() - INTERVAL '7 days' + TIME '09:00:00',
     NOW() - INTERVAL '7 days' + TIME '09:30:00',
     NOW() - INTERVAL '7 days' + TIME '11:00:00',
     90,
     116.4806, 39.9960, '北京市朝阳区望京SOHO T3-1801',
     '产品推介', '向客户介绍了公司最新产品，演示了核心功能。客户对产品表示兴趣。', '约定了下周进行第二次深入沟通',
     4, true),
    ('e0000000-0000-0000-0000-000000000002',
     'a0000000-0000-0000-0000-000000000001',
     'd0000000-0000-0000-0000-000000000004',
     'field', 'completed',
     NOW() - INTERVAL '5 days' + TIME '14:00:00',
     NOW() - INTERVAL '5 days' + TIME '14:20:00',
     NOW() - INTERVAL '5 days' + TIME '15:30:00',
     70,
     113.3250, 23.1350, '广州市天河区天河路560号',
     '售后回访', '了解客户使用产品后的反馈，解决了一些技术问题。', '客户满意度良好，提出了新的需求',
     5, true),
    ('e0000000-0000-0000-0000-000000000003',
     'a0000000-0000-0000-0000-000000000002',
     'd0000000-0000-0000-0000-000000000006',
     'field', 'completed',
     NOW() - INTERVAL '3 days' + TIME '10:00:00',
     NOW() - INTERVAL '3 days' + TIME '10:15:00',
     NOW() - INTERVAL '3 days' + TIME '11:45:00',
     90,
     120.0200, 30.2800, '杭州市余杭区文一西路998号',
     '合同续签', '与客户沟通年度合同续签事宜，讨论新的合作条款。', '达成初步续签意向',
     4, true),
    ('e0000000-0000-0000-0000-000000000004',
     'a0000000-0000-0000-0000-000000000003',
     'd0000000-0000-0000-0000-000000000003',
     'phone', 'completed',
     NOW() - INTERVAL '1 day' + TIME '15:00:00',
     NOW() - INTERVAL '1 day' + TIME '15:00:00',
     NOW() - INTERVAL '1 day' + TIME '15:25:00',
     25,
     NULL, NULL, NULL,
     '电话跟进', '电话了解客户近期需求变化，推送新产品资料。', '客户表示有兴趣，约定了下次面谈时间',
     3, false)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 10. photos — 照片记录
-- ============================================================
INSERT INTO photos (id, user_id, biz_type, biz_id,
    file_name, file_size, mime_type, storage_path, url, width, height)
VALUES
    ('g0000000-0000-0000-0000-000000000001',
     'a0000000-0000-0000-0000-000000000001',
     'visit', 'e0000000-0000-0000-0000-000000000001',
     'visit_001.jpg', 2048576, 'image/jpeg',
     '/uploads/visits/2025/01/visit_001.jpg',
     'https://cdn.example.com/uploads/visits/2025/01/visit_001.jpg',
     4032, 3024),
    ('g0000000-0000-0000-0000-000000000002',
     'a0000000-0000-0000-0000-000000000001',
     'visit', 'e0000000-0000-0000-0000-000000000002',
     'visit_002.jpg', 1536000, 'image/jpeg',
     '/uploads/visits/2025/01/visit_002.jpg',
     'https://cdn.example.com/uploads/visits/2025/01/visit_002.jpg',
     4032, 3024),
    ('g0000000-0000-0000-0000-000000000003',
     'a0000000-0000-0000-0000-000000000002',
     'attendance', NULL,
     'attendance_001.jpg', 1024000, 'image/jpeg',
     '/uploads/attendance/2025/01/attendance_001.jpg',
     'https://cdn.example.com/uploads/attendance/2025/01/attendance_001.jpg',
     3024, 4032),
    ('g0000000-0000-0000-0000-000000000004',
     'a0000000-0000-0000-0000-000000000099',
     'avatar', 'a0000000-0000-0000-0000-000000000099',
     'avatar_admin.jpg', 512000, 'image/jpeg',
     '/uploads/avatars/avatar_admin.jpg',
     'https://cdn.example.com/uploads/avatars/avatar_admin.jpg',
     512, 512)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 11. approvals — 审批记录
-- ============================================================
INSERT INTO approvals (id, applicant_id, approval_type, status,
    start_date, end_date, duration_days, title, reason,
    approver_id, approved_at, reject_reason)
VALUES
    ('h0000000-0000-0000-0000-000000000001',
     'a0000000-0000-0000-0000-000000000001',
     'leave', 'approved',
     CURRENT_DATE + INTERVAL '5 days',
     CURRENT_DATE + INTERVAL '6 days',
     2, '事假申请', '家中临时有事，需请假两天',
     'a0000000-0000-0000-0000-000000000006',
     NOW() - INTERVAL '1 day', NULL),
    ('h0000000-0000-0000-0000-000000000002',
     'a0000000-0000-0000-0000-000000000002',
     'business_trip', 'pending',
     CURRENT_DATE + INTERVAL '10 days',
     CURRENT_DATE + INTERVAL '12 days',
     3, '上海出差申请', '前往上海拜访客户，洽谈年度合作',
     NULL, NULL, NULL),
    ('h0000000-0000-0000-0000-000000000003',
     'a0000000-0000-0000-0000-000000000003',
     'overtime', 'approved',
     CURRENT_DATE,
     CURRENT_DATE,
     1, '周末加班申请', '项目紧急上线，需周末加班',
     'a0000000-0000-0000-0000-000000000006',
     NOW() - INTERVAL '2 hours', NULL),
    ('h0000000-0000-0000-0000-000000000004',
     'a0000000-0000-0000-0000-000000000001',
     'expense', 'rejected',
     CURRENT_DATE - INTERVAL '3 days',
     CURRENT_DATE - INTERVAL '3 days',
     NULL, '差旅报销', '上周出差交通及住宿费用报销',
     'a0000000-0000-0000-0000-000000000006',
     NOW() - INTERVAL '1 day', '部分票据不符合报销规定，请重新整理后提交')
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 12. reports — 报告数据
-- ============================================================
INSERT INTO reports (user_id, report_type, title, report_date, start_date, end_date,
    content, visit_count, customer_count, distance_km, status,
    submit_time, approver_id, approved_at)
VALUES
    ('a0000000-0000-0000-0000-000000000001', 'daily',
     '2025-01-15 工作日报', CURRENT_DATE - INTERVAL '3 days',
     CURRENT_DATE - INTERVAL '3 days', CURRENT_DATE - INTERVAL '3 days',
     '{"today_work": "拜访了北京科技和广州建材两家客户，推进产品推介。", "plan": "整理客户反馈，准备下周方案。", "issues": [], "summary": "今日拜访两家客户，效果良好。"}'::JSONB,
     2, 0, 35.5, 'approved',
     NOW() - INTERVAL '3 days',
     'a0000000-0000-0000-0000-000000000006',
     NOW() - INTERVAL '2 days'),

    ('a0000000-0000-0000-0000-000000000002', 'daily',
     '2025-01-15 工作日报', CURRENT_DATE - INTERVAL '3 days',
     CURRENT_DATE - INTERVAL '3 days', CURRENT_DATE - INTERVAL '3 days',
     '{"today_work": "与杭州电商进行了合同续签沟通，初步达成意向。", "plan": "整理合同条款，准备正式报价。", "issues": [], "summary": "续签进展顺利。"}'::JSONB,
     1, 0, 0, 'approved',
     NOW() - INTERVAL '3 days',
     'a0000000-0000-0000-0000-000000000007',
     NOW() - INTERVAL '2 days'),

    ('a0000000-0000-0000-0000-000000000001', 'weekly',
     '第一周工作周报', CURRENT_DATE - INTERVAL '7 days',
     CURRENT_DATE - INTERVAL '7 days', CURRENT_DATE - INTERVAL '1 day',
     '{"today_work": "本周拜访客户5家，新增潜在客户2家。完成产品培训1次。", "plan": "下周二重点跟进北京科技意向客户。", "issues": ["个别客户反馈产品功能需要优化"], "summary": "本周整体工作按计划推进。"}'::JSONB,
     5, 2, 120.8, 'submitted',
     NOW() - INTERVAL '1 day', NULL, NULL),

    ('a0000000-0000-0000-0000-000000000003', 'daily',
     '2025-01-15 工作日报', CURRENT_DATE - INTERVAL '3 days',
     CURRENT_DATE - INTERVAL '3 days', CURRENT_DATE - INTERVAL '3 days',
     '{"today_work": "跟进深圳创新客户需求，远程支持技术问题。", "plan": "整理深圳客户需求文档。", "issues": [], "summary": "远程支持工作完成。"}'::JSONB,
     0, 0, 0, 'draft', NULL, NULL, NULL)

ON CONFLICT DO NOTHING;

-- ============================================================
-- 验证：打印各表数据量
-- ============================================================
DO $$
DECLARE
    r RECORD;
    total INT := 0;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '种子数据插入完成 — 数据统计';
    RAISE NOTICE '========================================';
    FOR r IN
        SELECT tablename AS tbl,
               (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM %I', tablename), false, true, '')))[1]::TEXT::INT AS cnt
        FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename NOT LIKE 'location_records_%'
        ORDER BY tablename
    LOOP
        RAISE NOTICE '  %: % 行', r.tbl, r.cnt;
        total := total + r.cnt;
    END LOOP;
    RAISE NOTICE '----------------------------------------';
    RAISE NOTICE '  总计: % 行（不含分区表）', total;
    RAISE NOTICE '========================================';
END $$;

COMMIT;
