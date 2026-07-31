-- =============================================================================
-- Field Tracker — 数据库 Schema 定义
-- PostgreSQL 16 | 完整表结构 + 索引 + 注释 + 自动更新时间触发器
-- =============================================================================
-- 位置追踪与考勤管理系统的完整数据库设计
-- 包含 12 张业务表 + 分区表 + 函数 + 触发器
-- =============================================================================

-- ============================================================
-- 扩展（可选）
-- ============================================================
-- 如需 PostGIS 地理空间支持，取消注释以下行：
-- CREATE EXTENSION IF NOT EXISTS postgis;
-- CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- 1. users — 用户表
--    存储所有系统用户，包括员工、管理员
-- ============================================================
CREATE TABLE IF NOT EXISTS users (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(100)    NOT NULL,
    user_code       VARCHAR(50)     UNIQUE,             -- 员工工号
    phone           VARCHAR(20)     NOT NULL,
    password_hash   VARCHAR(255)    NOT NULL,
    department_id   UUID,                          -- 外键在 departments 创建后补充
    role            VARCHAR(20)     NOT NULL DEFAULT 'employee'
                        CHECK (role IN ('employee', 'manager', 'admin', 'super_admin')),
    avatar_url      VARCHAR(500),
    email           VARCHAR(100),
    is_active       BOOLEAN         NOT NULL DEFAULT true,
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  users              IS '用户表 — 系统全部用户账号';
COMMENT ON COLUMN users.id           IS '主键 UUID';
COMMENT ON COLUMN users.name         IS '用户姓名';
COMMENT ON COLUMN users.phone        IS '手机号（登录凭证）';
COMMENT ON COLUMN users.password_hash IS '密码哈希（bcrypt）';
COMMENT ON COLUMN users.department_id IS '所属部门 ID';
COMMENT ON COLUMN users.role         IS '角色：employee(员工) / manager(经理) / admin(管理员) / super_admin(超级管理员)';
COMMENT ON COLUMN users.avatar_url   IS '头像 URL';
COMMENT ON COLUMN users.email        IS '邮箱';
COMMENT ON COLUMN users.is_active    IS '账号是否启用';
COMMENT ON COLUMN users.last_login_at IS '最后登录时间';
COMMENT ON COLUMN users.created_at   IS '创建时间';
COMMENT ON COLUMN users.updated_at   IS '最后更新时间';

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone        ON users(phone);
CREATE        INDEX IF NOT EXISTS idx_users_department_id ON users(department_id);
CREATE        INDEX IF NOT EXISTS idx_users_role          ON users(role);
CREATE        INDEX IF NOT EXISTS idx_users_is_active     ON users(is_active) WHERE is_active = true;


-- ============================================================
-- 2. departments — 部门表
--    树形组织结构，支持多级部门
-- ============================================================
CREATE TABLE IF NOT EXISTS departments (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(100)    NOT NULL,
    parent_id       UUID            REFERENCES departments(id) ON DELETE SET NULL,
    manager_id      UUID,                               -- 外键在 users 创建后补充
    description     VARCHAR(500),
    sort_order      INT             NOT NULL DEFAULT 0,
    is_active       BOOLEAN         NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  departments              IS '部门表 — 树形组织结构';
COMMENT ON COLUMN departments.id           IS '主键 UUID';
COMMENT ON COLUMN departments.name         IS '部门名称';
COMMENT ON COLUMN departments.parent_id    IS '上级部门 ID（自引用）';
COMMENT ON COLUMN departments.manager_id   IS '部门负责人用户 ID';
COMMENT ON COLUMN departments.description  IS '部门描述';
COMMENT ON COLUMN departments.sort_order   IS '排序序号';
COMMENT ON COLUMN departments.is_active    IS '是否启用';
COMMENT ON COLUMN departments.created_at   IS '创建时间';
COMMENT ON COLUMN departments.updated_at   IS '最后更新时间';

CREATE INDEX IF NOT EXISTS idx_departments_parent_id  ON departments(parent_id);
CREATE INDEX IF NOT EXISTS idx_departments_manager_id ON departments(manager_id);


-- ============================================================
-- 补充外键（users <-> departments 双向关联）
-- ============================================================
ALTER TABLE users       ADD CONSTRAINT fk_users_department
    FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE SET NULL;

ALTER TABLE departments ADD CONSTRAINT fk_departments_manager
    FOREIGN KEY (manager_id) REFERENCES users(id) ON DELETE SET NULL;


-- ============================================================
-- 3. attendance_rules — 打卡规则表
--    定义各考勤方式的规则参数
-- ============================================================
CREATE TABLE IF NOT EXISTS attendance_rules (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(100)    NOT NULL,
    department_id   UUID            REFERENCES departments(id) ON DELETE CASCADE,
    rule_type       VARCHAR(20)     NOT NULL DEFAULT 'location'
                        CHECK (rule_type IN ('location', 'wifi', 'bluetooth', 'face', 'qr_code')),
    -- 地理位置规则参数
    center_lat      DOUBLE PRECISION,
    center_lng      DOUBLE PRECISION,
    radius_meters   DOUBLE PRECISION DEFAULT 300,
    -- Wi-Fi 规则参数
    wifi_ssid       VARCHAR(100),
    wifi_bssid      VARCHAR(50),
    -- 蓝牙规则参数
    bluetooth_mac   VARCHAR(50),
    -- 时间规则
    checkin_start   TIME,
    checkin_end     TIME,
    checkout_start  TIME,
    checkout_end    TIME,
    -- 功能开关
    allow_remote    BOOLEAN         NOT NULL DEFAULT false,
    need_face       BOOLEAN         NOT NULL DEFAULT false,
    need_photo      BOOLEAN         NOT NULL DEFAULT false,
    grace_minutes   INT             NOT NULL DEFAULT 5,
    is_active       BOOLEAN         NOT NULL DEFAULT true,
    fence_id        UUID            REFERENCES geo_fences(id) ON DELETE CASCADE,
    created_by      UUID            REFERENCES users(id),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  attendance_rules               IS '打卡规则表 — 定义各考勤规则';
COMMENT ON COLUMN attendance_rules.id            IS '主键 UUID';
COMMENT ON COLUMN attendance_rules.name          IS '规则名称';
COMMENT ON COLUMN attendance_rules.department_id IS '适用部门';
COMMENT ON COLUMN attendance_rules.rule_type     IS '规则类型：location(位置) / wifi / bluetooth / face(人脸) / qr_code(二维码)';
COMMENT ON COLUMN attendance_rules.center_lat    IS '打卡中心纬度';
COMMENT ON COLUMN attendance_rules.center_lng    IS '打卡中心经度';
COMMENT ON COLUMN attendance_rules.radius_meters IS '打卡半径（米）';
COMMENT ON COLUMN attendance_rules.fence_id      IS '关联的电子围栏 ID（围栏自动创建的规则通过此列双向同步）';
COMMENT ON COLUMN attendance_rules.wifi_ssid     IS 'Wi-Fi SSID';
COMMENT ON COLUMN attendance_rules.wifi_bssid    IS 'Wi-Fi BSSID（MAC）';
COMMENT ON COLUMN attendance_rules.bluetooth_mac IS '蓝牙设备 MAC';
COMMENT ON COLUMN attendance_rules.checkin_start IS '上班打卡开始时间';
COMMENT ON COLUMN attendance_rules.checkin_end   IS '上班打卡截止时间';
COMMENT ON COLUMN attendance_rules.checkout_start IS '下班打卡开始时间';
COMMENT ON COLUMN attendance_rules.checkout_end   IS '下班打卡截止时间';
COMMENT ON COLUMN attendance_rules.allow_remote   IS '是否允许远程打卡';
COMMENT ON COLUMN attendance_rules.need_face      IS '是否需要人脸识别';
COMMENT ON COLUMN attendance_rules.need_photo     IS '是否需要拍照';
COMMENT ON COLUMN attendance_rules.grace_minutes  IS '宽限分钟数';
COMMENT ON COLUMN attendance_rules.is_active      IS '规则是否启用';
COMMENT ON COLUMN attendance_rules.created_by     IS '创建人';

CREATE INDEX IF NOT EXISTS idx_attendance_rules_dept ON attendance_rules(department_id);
CREATE INDEX IF NOT EXISTS idx_attendance_rules_type ON attendance_rules(rule_type);
CREATE INDEX IF NOT EXISTS idx_attendance_rules_active ON attendance_rules(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_attendance_rules_fence ON attendance_rules(fence_id);
-- 同一围栏最多一条关联规则（006 迁移；允许 NULL 不影响手动规则）
CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_rules_fence_unique
    ON attendance_rules(fence_id) WHERE fence_id IS NOT NULL;


-- ============================================================
-- 4. attendance_records — 打卡记录表
--    存储每次上下班打卡数据
-- ============================================================
CREATE TABLE IF NOT EXISTS attendance_records (
    id              BIGSERIAL       PRIMARY KEY,
    user_id         UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rule_id         UUID            REFERENCES attendance_rules(id) ON DELETE SET NULL,
    type            VARCHAR(10)     NOT NULL CHECK (type IN ('checkin', 'checkout')),
    check_time      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    -- 位置信息
    lng             DOUBLE PRECISION,
    lat             DOUBLE PRECISION,
    address         VARCHAR(500),
    accuracy        DOUBLE PRECISION,
    -- 设备与网络
    wifi_ssid       VARCHAR(100),
    wifi_bssid      VARCHAR(50),
    device_info     JSONB,
    -- 多媒体
    photo_url       VARCHAR(500),
    face_image_url  VARCHAR(500),
    -- 状态
    source          VARCHAR(20)     NOT NULL DEFAULT 'app'
                        CHECK (source IN ('app', 'web', 'auto', 'admin', 'qr_code')),
    remote          BOOLEAN         NOT NULL DEFAULT false,
    status          VARCHAR(20)     NOT NULL DEFAULT 'normal'
                        CHECK (status IN ('normal', 'late', 'early', 'overtime', 'absent', 'leave')),
    remark          VARCHAR(500),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  attendance_records                IS '打卡记录表 — 上下班打卡数据';
COMMENT ON COLUMN attendance_records.id             IS '主键 BIGSERIAL';
COMMENT ON COLUMN attendance_records.user_id        IS '用户 ID';
COMMENT ON COLUMN attendance_records.rule_id        IS '匹配的打卡规则 ID';
COMMENT ON COLUMN attendance_records.type           IS '打卡类型：checkin(上班) / checkout(下班)';
COMMENT ON COLUMN attendance_records.check_time     IS '打卡时间';
COMMENT ON COLUMN attendance_records.lng            IS '打卡经度';
COMMENT ON COLUMN attendance_records.lat            IS '打卡纬度';
COMMENT ON COLUMN attendance_records.address        IS '打卡地址文字描述';
COMMENT ON COLUMN attendance_records.accuracy       IS '定位精度（米）';
COMMENT ON COLUMN attendance_records.wifi_ssid      IS '连接的 Wi-Fi SSID';
COMMENT ON COLUMN attendance_records.wifi_bssid     IS '连接的 Wi-Fi BSSID';
COMMENT ON COLUMN attendance_records.device_info    IS '设备信息 JSON（型号、系统版本等）';
COMMENT ON COLUMN attendance_records.photo_url      IS '打卡照片 URL';
COMMENT ON COLUMN attendance_records.face_image_url  IS '人脸识别照片 URL';
COMMENT ON COLUMN attendance_records.source         IS '打卡来源：app / web / auto / admin / qr_code';
COMMENT ON COLUMN attendance_records.remote         IS '是否远程打卡';
COMMENT ON COLUMN attendance_records.status         IS '考勤状态：normal(正常) / late(迟到) / early(早退) / overtime(加班) / absent(缺勤) / leave(请假)';
COMMENT ON COLUMN attendance_records.remark         IS '备注';

CREATE INDEX IF NOT EXISTS idx_attendance_user_time   ON attendance_records(user_id, check_time DESC);
CREATE INDEX IF NOT EXISTS idx_attendance_type         ON attendance_records(type);
CREATE INDEX IF NOT EXISTS idx_attendance_date         ON attendance_records(DATE(check_time));
CREATE INDEX IF NOT EXISTS idx_attendance_status       ON attendance_records(status);
CREATE INDEX IF NOT EXISTS idx_attendance_source       ON attendance_records(source);


-- ============================================================
-- 5. location_records — 定位记录表
--    按 recorded_at 按月分区，存储高频 GPS 轨迹数据
-- ============================================================
CREATE TABLE IF NOT EXISTS location_records (
    id              BIGSERIAL,
    user_id         UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    lng             DOUBLE PRECISION NOT NULL,
    lat             DOUBLE PRECISION NOT NULL,
    accuracy        DOUBLE PRECISION,
    speed           DOUBLE PRECISION,
    altitude        DOUBLE PRECISION,
    bearing         DOUBLE PRECISION,
    battery         DOUBLE PRECISION,
    provider        VARCHAR(20)     DEFAULT 'gps'
                        CHECK (provider IN ('gps', 'network', 'wifi', 'bluetooth')),
    address         VARCHAR(500),
    recorded_at     TIMESTAMPTZ     NOT NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    PRIMARY KEY (id, recorded_at)
) PARTITION BY RANGE (recorded_at);

COMMENT ON TABLE  location_records              IS '定位记录表 — 按 recorded_at 按月分区存储 GPS 轨迹';
COMMENT ON COLUMN location_records.id           IS '主键 BIGSERIAL';
COMMENT ON COLUMN location_records.user_id      IS '用户 ID';
COMMENT ON COLUMN location_records.lng          IS '经度';
COMMENT ON COLUMN location_records.lat          IS '纬度';
COMMENT ON COLUMN location_records.accuracy     IS '定位精度（米）';
COMMENT ON COLUMN location_records.speed        IS '移动速度（m/s）';
COMMENT ON COLUMN location_records.altitude     IS '海拔高度（米）';
COMMENT ON COLUMN location_records.bearing      IS '方位角（度）';
COMMENT ON COLUMN location_records.battery      IS '设备电量（%）';
COMMENT ON COLUMN location_records.provider     IS '定位提供方：gps / network / wifi / bluetooth';
COMMENT ON COLUMN location_records.address      IS '地址文字描述';
COMMENT ON COLUMN location_records.recorded_at  IS '定位采集时间（分区键）';
COMMENT ON COLUMN location_records.created_at   IS '记录入库时间';

-- 分区创建函数
CREATE OR REPLACE FUNCTION create_location_partition(partition_date DATE)
RETURNS void AS $$
DECLARE
    partition_name  TEXT;
    start_date      TEXT;
    end_date        TEXT;
BEGIN
    partition_name := 'location_records_'
        || to_char(partition_date, 'YYYYMM');
    start_date     := to_char(date_trunc('month', partition_date), 'YYYY-MM-DD');
    end_date       := to_char(date_trunc('month', partition_date)
                        + INTERVAL '1 month', 'YYYY-MM-DD');

    IF NOT EXISTS (
        SELECT 1 FROM pg_class WHERE relname = partition_name
    ) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF location_records
             FOR VALUES FROM (%L) TO (%L)',
            partition_name, start_date, end_date
        );
        RAISE NOTICE 'Created partition: %', partition_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 自动创建最近 12 个月的分区
DO $$
DECLARE
    d DATE;
BEGIN
    FOR i IN 0..11 LOOP
        d := date_trunc('month', NOW())::DATE + (i || ' months')::INTERVAL;
        PERFORM create_location_partition(d);
    END LOOP;
END $$;

-- 索引（每个分区自动继承）
CREATE INDEX IF NOT EXISTS idx_location_user_time
    ON location_records(user_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_location_time
    ON location_records(recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_location_lng_lat
    ON location_records(lng, lat);
CREATE INDEX IF NOT EXISTS idx_location_provider
    ON location_records(provider) WHERE provider IS NOT NULL;


-- ============================================================
-- 6. geo_fences — 电子围栏表
--    定义地理围栏区域（圆形或多边形）
-- ============================================================
CREATE TABLE IF NOT EXISTS geo_fences (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(100)    NOT NULL,
    department_id   UUID            REFERENCES departments(id) ON DELETE CASCADE,
    -- 圆形围栏参数
    center_lat      DOUBLE PRECISION,
    center_lng      DOUBLE PRECISION,
    radius_meters   DOUBLE PRECISION DEFAULT 100,
    -- 多边形围栏参数
    polygon_points  JSONB,           -- [{"lat": x, "lng": y}, ...]
    -- 通用属性
    shape_type      VARCHAR(20)     NOT NULL DEFAULT 'circle'
                        CHECK (shape_type IN ('circle', 'polygon')),
    color           VARCHAR(20)     DEFAULT '#FF0000',
    is_active       BOOLEAN         NOT NULL DEFAULT true,
    description     VARCHAR(500),
    created_by      UUID            REFERENCES users(id),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  geo_fences                IS '电子围栏表 — 定义地理围栏区域';
COMMENT ON COLUMN geo_fences.id             IS '主键 UUID';
COMMENT ON COLUMN geo_fences.name           IS '围栏名称';
COMMENT ON COLUMN geo_fences.department_id  IS '所属部门';
COMMENT ON COLUMN geo_fences.center_lat     IS '围栏中心纬度（圆形围栏）';
COMMENT ON COLUMN geo_fences.center_lng     IS '围栏中心经度（圆形围栏）';
COMMENT ON COLUMN geo_fences.radius_meters  IS '围栏半径（米，圆形围栏）';
COMMENT ON COLUMN geo_fences.polygon_points IS '多边形顶点坐标 JSON 数组';
COMMENT ON COLUMN geo_fences.shape_type     IS '围栏形状：circle(圆形) / polygon(多边形)';
COMMENT ON COLUMN geo_fences.color          IS '围栏显示颜色';
COMMENT ON COLUMN geo_fences.is_active      IS '围栏是否启用';
COMMENT ON COLUMN geo_fences.description    IS '围栏描述';
COMMENT ON COLUMN geo_fences.created_by     IS '创建人';

CREATE INDEX IF NOT EXISTS idx_geo_fences_dept   ON geo_fences(department_id);
CREATE INDEX IF NOT EXISTS idx_geo_fences_active ON geo_fences(is_active) WHERE is_active = true;


-- ============================================================
-- 7. fence_events — 围栏事件表
--    记录用户进出围栏的触发事件
-- ============================================================
CREATE TABLE IF NOT EXISTS fence_events (
    id              BIGSERIAL       PRIMARY KEY,
    user_id         UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    fence_id        UUID            NOT NULL REFERENCES geo_fences(id) ON DELETE CASCADE,
    event_type      VARCHAR(10)     NOT NULL CHECK (event_type IN ('enter', 'exit', 'dwell')),
    lng             DOUBLE PRECISION NOT NULL,
    lat             DOUBLE PRECISION NOT NULL,
    accuracy        DOUBLE PRECISION,
    event_time      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    processed       BOOLEAN         NOT NULL DEFAULT false,
    notified        BOOLEAN         NOT NULL DEFAULT false,
    remark          VARCHAR(500),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  fence_events               IS '围栏事件表 — 进出围栏的触发事件';
COMMENT ON COLUMN fence_events.id            IS '主键 BIGSERIAL';
COMMENT ON COLUMN fence_events.user_id       IS '用户 ID';
COMMENT ON COLUMN fence_events.fence_id      IS '围栏 ID';
COMMENT ON COLUMN fence_events.event_type    IS '事件类型：enter(进入) / exit(离开) / dwell(停留)';
COMMENT ON COLUMN fence_events.lng           IS '触发时经度';
COMMENT ON COLUMN fence_events.lat           IS '触发时纬度';
COMMENT ON COLUMN fence_events.accuracy      IS '触发时定位精度';
COMMENT ON COLUMN fence_events.event_time    IS '事件发生时间';
COMMENT ON COLUMN fence_events.processed     IS '是否已处理';
COMMENT ON COLUMN fence_events.notified      IS '是否已发送通知';
COMMENT ON COLUMN fence_events.remark        IS '备注';

CREATE INDEX IF NOT EXISTS idx_fence_events_user_fence ON fence_events(user_id, fence_id);
CREATE INDEX IF NOT EXISTS idx_fence_events_time        ON fence_events(event_time DESC);
CREATE INDEX IF NOT EXISTS idx_fence_events_type        ON fence_events(event_type);
CREATE INDEX IF NOT EXISTS idx_fence_events_unprocessed ON fence_events(processed)
    WHERE processed = false;


-- ============================================================
-- 8a. audit_logs — 审计日志表
--    记录关键操作（登录/注册/增删改等）
-- ============================================================
CREATE TABLE IF NOT EXISTS audit_logs (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    operator_id     UUID            NOT NULL REFERENCES users(id) ON DELETE SET NULL,
    operator_phone  VARCHAR(20),
    action_type     VARCHAR(50)     NOT NULL,
    target_type     VARCHAR(50),
    target_id       VARCHAR(100),
    detail          JSONB,
    ip_address      VARCHAR(50),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  audit_logs               IS '审计日志表 — 记录关键操作';
COMMENT ON COLUMN audit_logs.operator_id   IS '操作人用户ID';
COMMENT ON COLUMN audit_logs.operator_phone IS '操作人手机号（冗余，防止用户删除后丢失）';
COMMENT ON COLUMN audit_logs.action_type   IS '操作类型：register / login / update / delete 等';
COMMENT ON COLUMN audit_logs.target_type   IS '操作目标类型：user / customer / fence 等';
COMMENT ON COLUMN audit_logs.target_id     IS '操作目标ID';
COMMENT ON COLUMN audit_logs.detail        IS '操作详情（JSON）';
COMMENT ON COLUMN audit_logs.ip_address    IS '操作来源IP';
COMMENT ON COLUMN audit_logs.created_at    IS '操作时间';

CREATE INDEX IF NOT EXISTS idx_audit_logs_operator_id  ON audit_logs(operator_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action_type   ON audit_logs(action_type);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at    ON audit_logs(created_at);


-- ============================================================
-- 8b. messages — 消息中心表
--    系统/业务通知消息
-- ============================================================
CREATE TABLE IF NOT EXISTS messages (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title           VARCHAR(200)    NOT NULL,
    content         TEXT            NOT NULL DEFAULT '',
    msg_type        VARCHAR(30)     NOT NULL DEFAULT 'system',
    biz_type        VARCHAR(30),
    biz_id          VARCHAR(100),
    is_read         BOOLEAN         NOT NULL DEFAULT false,
    read_at         TIMESTAMPTZ,
    priority        VARCHAR(10)     NOT NULL DEFAULT 'normal',
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  messages            IS '消息中心表 — 系统/业务通知';
COMMENT ON COLUMN messages.user_id    IS '接收人';
COMMENT ON COLUMN messages.title      IS '消息标题';
COMMENT ON COLUMN messages.content    IS '消息内容';
COMMENT ON COLUMN messages.msg_type   IS '消息类型：system / attendance / approval 等';
COMMENT ON COLUMN messages.biz_type   IS '业务类型（关联业务模块）';
COMMENT ON COLUMN messages.biz_id     IS '业务ID';
COMMENT ON COLUMN messages.is_read    IS '是否已读';
COMMENT ON COLUMN messages.priority   IS '优先级：normal / high / urgent';

CREATE INDEX IF NOT EXISTS idx_messages_user ON messages(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_unread ON messages(user_id) WHERE is_read = false;


-- ============================================================
-- 8c. expenses — 费用报销表
--    员工报销申请
-- ============================================================
CREATE TABLE IF NOT EXISTS expenses (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title           VARCHAR(200)    NOT NULL,
    amount          DOUBLE PRECISION NOT NULL CHECK (amount > 0),
    note            TEXT            DEFAULT '',
    status          VARCHAR(20)     NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'approved', 'rejected')),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  expenses            IS '费用报销表 — 员工报销申请';
COMMENT ON COLUMN expenses.id         IS '主键 UUID';
COMMENT ON COLUMN expenses.user_id    IS '报销人';
COMMENT ON COLUMN expenses.title      IS '报销标题';
COMMENT ON COLUMN expenses.amount     IS '报销金额';
COMMENT ON COLUMN expenses.note       IS '备注说明';
COMMENT ON COLUMN expenses.status     IS '状态：pending(待审) / approved(已通过) / rejected(已驳回)';

CREATE INDEX IF NOT EXISTS idx_expenses_user_id ON expenses(user_id);
CREATE INDEX IF NOT EXISTS idx_expenses_status  ON expenses(status);


-- ============================================================
-- 8. customers — 客户表
--    外勤拜访的客户信息
-- ============================================================
CREATE TABLE IF NOT EXISTS customers (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(200)    NOT NULL,
    short_name      VARCHAR(100),
    phone           VARCHAR(20),
    contact_person  VARCHAR(100),
    contact_phone   VARCHAR(20),
    -- 地址与位置
    province        VARCHAR(50),
    city            VARCHAR(50),
    district        VARCHAR(50),
    address         VARCHAR(500),
    lng             DOUBLE PRECISION,
    lat             DOUBLE PRECISION,
    -- 业务信息
    industry        VARCHAR(100),
    category        VARCHAR(100),
    level           VARCHAR(20)     DEFAULT 'B'
                        CHECK (level IN ('A', 'B', 'C', 'D')),
    status          VARCHAR(20)     NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'inactive', 'lost', 'potential')),
    -- 负责人
    manager_id      UUID            REFERENCES users(id) ON DELETE SET NULL,
    -- 元信息
    remark          TEXT,
    tags            TEXT[],
    is_active       BOOLEAN         NOT NULL DEFAULT true,
    created_by      UUID            REFERENCES users(id),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  customers               IS '客户表 — 外勤拜访的客户信息';
COMMENT ON COLUMN customers.id            IS '主键 UUID';
COMMENT ON COLUMN customers.name          IS '客户名称（公司名）';
COMMENT ON COLUMN customers.short_name    IS '客户简称';
COMMENT ON COLUMN customers.phone         IS '客户公司电话';
COMMENT ON COLUMN customers.contact_person IS '联系人姓名';
COMMENT ON COLUMN customers.contact_phone  IS '联系人电话';
COMMENT ON COLUMN customers.province      IS '省份';
COMMENT ON COLUMN customers.city          IS '城市';
COMMENT ON COLUMN customers.district      IS '区县';
COMMENT ON COLUMN customers.address       IS '详细地址';
COMMENT ON COLUMN customers.lng           IS '客户位置经度';
COMMENT ON COLUMN customers.lat           IS '客户位置纬度';
COMMENT ON COLUMN customers.industry      IS '所属行业';
COMMENT ON COLUMN customers.category      IS '客户分类';
COMMENT ON COLUMN customers.level         IS '客户等级：A(重要) / B(普通) / C(潜在) / D(流失)';
COMMENT ON COLUMN customers.status        IS '客户状态：active(活跃) / inactive(非活跃) / lost(流失) / potential(潜在)';
COMMENT ON COLUMN customers.manager_id    IS '负责员工 ID';
COMMENT ON COLUMN customers.remark        IS '备注';
COMMENT ON COLUMN customers.tags          IS '标签数组';
COMMENT ON COLUMN customers.is_active     IS '是否启用';
COMMENT ON COLUMN customers.created_by    IS '创建人';

CREATE INDEX IF NOT EXISTS idx_customers_phone     ON customers(phone) WHERE phone IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_customers_manager   ON customers(manager_id);
CREATE INDEX IF NOT EXISTS idx_customers_level     ON customers(level);
CREATE INDEX IF NOT EXISTS idx_customers_status    ON customers(status);
CREATE INDEX IF NOT EXISTS idx_customers_city      ON customers(city);
CREATE INDEX IF NOT EXISTS idx_customers_lng_lat   ON customers(lng, lat);
CREATE INDEX IF NOT EXISTS idx_customers_tags      ON customers USING gin(tags);


-- ============================================================
-- 9. visit_records — 拜访记录表
--    外勤人员的客户拜访记录
-- ============================================================
CREATE TABLE IF NOT EXISTS visit_records (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    customer_id     UUID            NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    -- 拜访基本信息
    visit_type      VARCHAR(20)     NOT NULL DEFAULT 'field'
                        CHECK (visit_type IN ('field', 'phone', 'video', 'office')),
    status          VARCHAR(20)     NOT NULL DEFAULT 'planned'
                        CHECK (status IN ('planned', 'arrived', 'in_progress', 'completed', 'cancelled')),
    -- 时间
    planned_at      TIMESTAMPTZ,
    start_time      TIMESTAMPTZ,
    end_time        TIMESTAMPTZ,
    duration_minutes INT,
    -- 位置（签到）
    signin_lng      DOUBLE PRECISION,
    signin_lat      DOUBLE PRECISION,
    signin_address  VARCHAR(500),
    signout_lng     DOUBLE PRECISION,
    signout_lat     DOUBLE PRECISION,
    signout_address VARCHAR(500),
    -- 内容
    purpose         VARCHAR(500),
    content         TEXT,
    result          TEXT,
    next_plan       TEXT,
    -- 评价与附件
    satisfaction    INT             CHECK (satisfaction BETWEEN 1 AND 5),
    has_photo       BOOLEAN         NOT NULL DEFAULT false,
    -- 元信息
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  visit_records                 IS '拜访记录表 — 外勤客户拜访详情';
COMMENT ON COLUMN visit_records.id              IS '主键 UUID';
COMMENT ON COLUMN visit_records.user_id         IS '执行拜访的员工 ID';
COMMENT ON COLUMN visit_records.customer_id     IS '被拜访的客户 ID';
COMMENT ON COLUMN visit_records.visit_type      IS '拜访方式：field(实地) / phone(电话) / video(视频) / office(办公室)';
COMMENT ON COLUMN visit_records.status          IS '拜访状态：planned(计划) / arrived(到达) / in_progress(进行中) / completed(完成) / cancelled(取消)';
COMMENT ON COLUMN visit_records.planned_at      IS '计划拜访时间';
COMMENT ON COLUMN visit_records.start_time        IS '实际开始时间';
COMMENT ON COLUMN visit_records.end_time         IS '实际结束时间';
COMMENT ON COLUMN visit_records.duration_minutes IS '拜访时长（分钟）';
COMMENT ON COLUMN visit_records.signin_lng       IS '签到经度';
COMMENT ON COLUMN visit_records.signin_lat       IS '签到纬度';
COMMENT ON COLUMN visit_records.signin_address   IS '签到地址';
COMMENT ON COLUMN visit_records.signout_lng      IS '签退经度';
COMMENT ON COLUMN visit_records.signout_lat      IS '签退纬度';
COMMENT ON COLUMN visit_records.signout_address  IS '签退地址';
COMMENT ON COLUMN visit_records.purpose          IS '拜访目的';
COMMENT ON COLUMN visit_records.content          IS '拜访内容详情';
COMMENT ON COLUMN visit_records.result           IS '拜访成果';
COMMENT ON COLUMN visit_records.next_plan        IS '下一步计划';
COMMENT ON COLUMN visit_records.satisfaction     IS '客户满意度评分 1-5';
COMMENT ON COLUMN visit_records.has_photo        IS '是否有照片附件';

CREATE INDEX IF NOT EXISTS idx_visit_user_customer  ON visit_records(user_id, customer_id);
CREATE INDEX IF NOT EXISTS idx_visit_user_time      ON visit_records(user_id, start_time DESC);
CREATE INDEX IF NOT EXISTS idx_visit_customer       ON visit_records(customer_id);
CREATE INDEX IF NOT EXISTS idx_visit_status         ON visit_records(status);
CREATE INDEX IF NOT EXISTS idx_visit_date           ON visit_records(DATE(start_time))
    WHERE start_time IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_visit_planned        ON visit_records(planned_at)
    WHERE status = 'planned';


-- ============================================================
-- 10. photos — 照片表
--     存储所有业务场景的图片记录
-- ============================================================
CREATE TABLE IF NOT EXISTS photos (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- 关联业务
    biz_type        VARCHAR(30)     NOT NULL
                        CHECK (biz_type IN (
                            'attendance', 'visit', 'customer',
                            'report', 'approval', 'fence', 'avatar'
                        )),
    biz_id          VARCHAR(50),    -- 关联业务记录 ID（UUID 或 BIGSERIAL 的字符串形式）
    -- 文件信息
    file_name       VARCHAR(200)    NOT NULL,
    file_size       INT             NOT NULL,       -- 字节
    mime_type       VARCHAR(50)     NOT NULL DEFAULT 'image/jpeg',
    storage_path    VARCHAR(500)    NOT NULL,
    thumbnail_path  VARCHAR(500),
    url             VARCHAR(500),
    thumbnail_url   VARCHAR(500),
    -- 元信息
    width           INT,
    height          INT,
    lng             DOUBLE PRECISION,
    lat             DOUBLE PRECISION,
    remark          VARCHAR(500),
    is_deleted      BOOLEAN         NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  photos                IS '照片表 — 所有业务场景的图片';
COMMENT ON COLUMN photos.id             IS '主键 UUID';
COMMENT ON COLUMN photos.user_id        IS '上传用户 ID';
COMMENT ON COLUMN photos.biz_type       IS '业务类型：attendance(打卡) / visit(拜访) / customer(客户) / report(报告) / approval(审批) / fence(围栏) / avatar(头像)';
COMMENT ON COLUMN photos.biz_id         IS '关联业务记录 ID';
COMMENT ON COLUMN photos.file_name      IS '原始文件名';
COMMENT ON COLUMN photos.file_size      IS '文件大小（字节）';
COMMENT ON COLUMN photos.mime_type      IS 'MIME 类型';
COMMENT ON COLUMN photos.storage_path   IS '存储路径';
COMMENT ON COLUMN photos.thumbnail_path IS '缩略图路径';
COMMENT ON COLUMN photos.url            IS '访问 URL';
COMMENT ON COLUMN photos.thumbnail_url  IS '缩略图 URL';
COMMENT ON COLUMN photos.width          IS '图片宽度（像素）';
COMMENT ON COLUMN photos.height         IS '图片高度（像素）';
COMMENT ON COLUMN photos.lng            IS '拍摄经度';
COMMENT ON COLUMN photos.lat            IS '拍摄纬度';
COMMENT ON COLUMN photos.remark         IS '备注';
COMMENT ON COLUMN photos.is_deleted     IS '是否软删除';

CREATE INDEX IF NOT EXISTS idx_photos_user       ON photos(user_id);
CREATE INDEX IF NOT EXISTS idx_photos_biz        ON photos(biz_type, biz_id);
CREATE INDEX IF NOT EXISTS idx_photos_created    ON photos(created_at DESC);


-- ============================================================
-- 11. approvals — 审批表
--     各类申请审批流程（请假、外出、报销等）
-- ============================================================
CREATE TABLE IF NOT EXISTS approvals (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    -- 申请人
    applicant_id    UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- 审批类型
    approval_type   VARCHAR(30)     NOT NULL
                        CHECK (approval_type IN (
                            'leave', 'business_trip', 'overtime',
                            'expense', 'purchase', 'adjustment', 'other'
                        )),
    -- 状态
    status          VARCHAR(20)     NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled', 'recalled')),
    -- 时间
    start_date      DATE,
    end_date        DATE,
    duration_days   NUMERIC(4,1),   -- 请假/出差天数
    start_time      TIMESTAMPTZ,    -- 精确起止时间
    end_time        TIMESTAMPTZ,
    -- 内容
    title           VARCHAR(200)    NOT NULL,
    reason          TEXT,
    -- 审批人链
    approver_id     UUID            REFERENCES users(id) ON DELETE SET NULL,
    approved_at     TIMESTAMPTZ,
    reject_reason   VARCHAR(500),
    -- 审批流（多级审批时使用 JSON 记录完整链路）
    approval_flow   JSONB,          -- [{"approver_id": "..", "level": 1, "status": "approved", "remark": ".."}, ...]
    -- 附件
    attachment_ids  UUID[],         -- photos.id 数组
    -- 元信息
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  approvals                 IS '审批表 — 各类申请审批流程';
COMMENT ON COLUMN approvals.id              IS '主键 UUID';
COMMENT ON COLUMN approvals.applicant_id    IS '申请人 ID';
COMMENT ON COLUMN approvals.approval_type   IS '审批类型：leave(请假) / business_trip(出差) / overtime(加班) / expense(报销) / purchase(采购) / adjustment(调岗) / other(其他)';
COMMENT ON COLUMN approvals.status          IS '审批状态：pending(待审批) / approved(通过) / rejected(驳回) / cancelled(取消) / recalled(撤回)';
COMMENT ON COLUMN approvals.start_date      IS '开始日期';
COMMENT ON COLUMN approvals.end_date        IS '结束日期';
COMMENT ON COLUMN approvals.duration_days   IS '天数';
COMMENT ON COLUMN approvals.start_time      IS '开始时间';
COMMENT ON COLUMN approvals.end_time        IS '结束时间';
COMMENT ON COLUMN approvals.title           IS '审批标题';
COMMENT ON COLUMN approvals.reason          IS '申请原因';
COMMENT ON COLUMN approvals.approver_id     IS '最终审批人';
COMMENT ON COLUMN approvals.approved_at     IS '审批时间';
COMMENT ON COLUMN approvals.reject_reason   IS '驳回原因';
COMMENT ON COLUMN approvals.approval_flow   IS '完整审批流 JSON';
COMMENT ON COLUMN approvals.attachment_ids  IS '附件照片 ID 数组';

CREATE INDEX IF NOT EXISTS idx_approvals_applicant    ON approvals(applicant_id);
CREATE INDEX IF NOT EXISTS idx_approvals_approver     ON approvals(approver_id) WHERE approver_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_approvals_type         ON approvals(approval_type);
CREATE INDEX IF NOT EXISTS idx_approvals_status       ON approvals(status);
CREATE INDEX IF NOT EXISTS idx_approvals_created      ON approvals(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_approvals_pending      ON approvals(approver_id, status)
    WHERE status = 'pending';


-- ============================================================
-- 12. reports — 报告表
--     日报、周报、月报等各类工作报告
-- ============================================================
CREATE TABLE IF NOT EXISTS reports (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    report_type     VARCHAR(20)     NOT NULL
                        CHECK (report_type IN ('daily', 'weekly', 'monthly', 'custom')),
    title           VARCHAR(200)    NOT NULL,
    -- 报告时间范围
    report_date     DATE            NOT NULL,       -- 日报对应日期；周报/月报取开始日
    start_date      DATE,
    end_date        DATE,
    -- 报告内容（使用 JSONB 支持灵活的结构化内容）
    content         JSONB,          -- {"today_work": "...", "plan": "...", "issues": [...], "summary": "..."}
    -- 工作量统计
    visit_count     INT             DEFAULT 0,
    customer_count  INT             DEFAULT 0,
    distance_km     NUMERIC(8,2)    DEFAULT 0,
    -- 状态
    status          VARCHAR(20)     NOT NULL DEFAULT 'draft'
                        CHECK (status IN ('draft', 'submitted', 'approved', 'rejected')),
    submit_time     TIMESTAMPTZ,
    approver_id     UUID            REFERENCES users(id) ON DELETE SET NULL,
    approved_at     TIMESTAMPTZ,
    reject_reason   VARCHAR(500),
    -- 元信息
    is_deleted      BOOLEAN         NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  reports                IS '报告表 — 工作报告（日报/周报/月报）';
COMMENT ON COLUMN reports.id             IS '主键 UUID';
COMMENT ON COLUMN reports.user_id        IS '报告人 ID';
COMMENT ON COLUMN reports.report_type    IS '报告类型：daily(日报) / weekly(周报) / monthly(月报) / custom(自定义)';
COMMENT ON COLUMN reports.title          IS '报告标题';
COMMENT ON COLUMN reports.report_date    IS '报告日期';
COMMENT ON COLUMN reports.start_date     IS '报告起始日期';
COMMENT ON COLUMN reports.end_date       IS '报告结束日期';
COMMENT ON COLUMN reports.content        IS '报告内容 JSON（结构化字段）';
COMMENT ON COLUMN reports.visit_count    IS '拜访客户数';
COMMENT ON COLUMN reports.customer_count IS '新增客户数';
COMMENT ON COLUMN reports.distance_km    IS '当日里程（公里）';
COMMENT ON COLUMN reports.status         IS '报告状态：draft(草稿) / submitted(已提交) / approved(已通过) / rejected(已驳回)';
COMMENT ON COLUMN reports.submit_time    IS '提交时间';
COMMENT ON COLUMN reports.approver_id    IS '审批人 ID';
COMMENT ON COLUMN reports.approved_at    IS '审批时间';
COMMENT ON COLUMN reports.reject_reason  IS '驳回原因';
COMMENT ON COLUMN reports.is_deleted     IS '是否软删除';

CREATE INDEX IF NOT EXISTS idx_reports_user_type_date ON reports(user_id, report_type, report_date DESC);
CREATE INDEX IF NOT EXISTS idx_reports_date            ON reports(report_date DESC);
CREATE INDEX IF NOT EXISTS idx_reports_type            ON reports(report_type);
CREATE INDEX IF NOT EXISTS idx_reports_status          ON reports(status);
CREATE INDEX IF NOT EXISTS idx_reports_submitted       ON reports(submit_time DESC)
    WHERE status = 'submitted';


-- ============================================================
-- 自动更新 updated_at 触发器（统一方案）
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 为所有含 updated_at 列的表创建触发器
DO $$
DECLARE
    tbl TEXT;
BEGIN
    FOR tbl IN
        SELECT unnest(ARRAY[
            'users', 'departments', 'attendance_rules',
            'geo_fences', 'customers', 'visit_records',
            'approvals', 'reports', 'expenses'
        ])
    LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%I_updated_at
             BEFORE UPDATE ON %I
             FOR EACH ROW
             WHEN (OLD.* IS DISTINCT FROM NEW.*)
             EXECUTE FUNCTION update_updated_at_column()',
            tbl, tbl
        );
    END LOOP;
END $$;


-- ============================================================
-- 自动创建下月分区（可被 cron 每月调用）
-- ============================================================
CREATE OR REPLACE FUNCTION ensure_future_partitions(months_ahead INT DEFAULT 3)
RETURNS void AS $$
DECLARE
    d DATE;
BEGIN
    FOR i IN 0..months_ahead LOOP
        d := date_trunc('month', NOW())::DATE + (i || ' months')::INTERVAL;
        PERFORM create_location_partition(d);
    END LOOP;
END;
$$ LANGUAGE plpgsql;
