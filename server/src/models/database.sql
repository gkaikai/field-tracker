-- Field Tracker 数据库初始化（无 PostGIS 版本）
-- 后续可升级到 PostGIS 以使用地理空间查询

-- 1. 用户表
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    user_code VARCHAR(50),
    phone VARCHAR(20) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    department_id UUID,
    role VARCHAR(20) DEFAULT 'employee' 
        CHECK (role IN ('employee', 'manager', 'admin')),
    avatar_url VARCHAR(500),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- 2. 部门表
CREATE TABLE IF NOT EXISTS departments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    parent_id UUID REFERENCES departments(id),
    manager_id UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT NOW()
);

-- 3. 定位记录表（按月分区）
CREATE TABLE IF NOT EXISTS location_records (
    id BIGSERIAL,
    user_id UUID NOT NULL REFERENCES users(id),
    lng DOUBLE PRECISION NOT NULL,
    lat DOUBLE PRECISION NOT NULL,
    accuracy FLOAT,
    speed FLOAT,
    altitude FLOAT,
    bearing FLOAT,
    battery FLOAT,
    recorded_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (id, recorded_at)
) PARTITION BY RANGE (recorded_at);

-- 注意：如果已有数据库（表已创建但无 PRIMARY KEY），需要手动为每个分区添加主键：
--   ALTER TABLE location_records_YYYYMM ADD PRIMARY KEY (id, recorded_at);

-- 创建当前月份分区
DO $$
DECLARE
    start_date TEXT;
    end_date TEXT;
    partition_name TEXT;
    i INT;
BEGIN
    FOR i IN 0..11 LOOP
        start_date := to_char(date_trunc('month', NOW()) + (i || ' months')::INTERVAL, 'YYYY-MM-DD');
        end_date := to_char(date_trunc('month', NOW()) + ((i+1) || ' months')::INTERVAL, 'YYYY-MM-DD');
        partition_name := 'location_records_' || to_char(date_trunc('month', NOW()) + (i || ' months')::INTERVAL, 'YYYYMM');
        
        IF NOT EXISTS (
            SELECT 1 FROM pg_class WHERE relname = partition_name
        ) THEN
            EXECUTE format(
                'CREATE TABLE %I PARTITION OF location_records FOR VALUES FROM (%L) TO (%L)',
                partition_name, start_date, end_date
            );
        END IF;
    END LOOP;
END $$;

-- 分区自动创建函数（供后端定时调用）
CREATE OR REPLACE FUNCTION ensure_next_partitions()
RETURNS void AS $$
DECLARE
    start_date TEXT;
    end_date TEXT;
    partition_name TEXT;
    i INT;
BEGIN
    FOR i IN 0..2 LOOP
        start_date := to_char(date_trunc('month', NOW()) + (i || ' months')::INTERVAL, 'YYYY-MM-DD');
        end_date := to_char(date_trunc('month', NOW()) + ((i+1) || ' months')::INTERVAL, 'YYYY-MM-DD');
        partition_name := 'location_records_' || to_char(date_trunc('month', NOW()) + (i || ' months')::INTERVAL, 'YYYYMM');
        
        IF NOT EXISTS (
            SELECT 1 FROM pg_class WHERE relname = partition_name
        ) THEN
            EXECUTE format(
                'CREATE TABLE %I PARTITION OF location_records FOR VALUES FROM (%L) TO (%L)',
                partition_name, start_date, end_date
            );
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- 索引
CREATE INDEX IF NOT EXISTS idx_location_user_time 
    ON location_records(user_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_location_lng_lat 
    ON location_records(lng, lat);

-- 4. 打卡记录表
CREATE TABLE IF NOT EXISTS attendance_records (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    type VARCHAR(10) NOT NULL CHECK (type IN ('checkin', 'checkout')),
    lng DOUBLE PRECISION NOT NULL,
    lat DOUBLE PRECISION NOT NULL,
    address VARCHAR(500),
    accuracy FLOAT,
    photo_url VARCHAR(500),
    wifi_bssid VARCHAR(50),
    device_info JSONB,
    check_time TIMESTAMP NOT NULL DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_attendance_user_time 
    ON attendance_records(user_id, check_time DESC);

-- 5. 打卡规则表
CREATE TABLE IF NOT EXISTS attendance_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    department_id UUID REFERENCES departments(id),
    rule_type VARCHAR(20) NOT NULL DEFAULT 'location'
        CHECK (rule_type IN ('location', 'wifi', 'bluetooth', 'face')),
    center_lat FLOAT,
    center_lng FLOAT,
    radius_meters FLOAT DEFAULT 300,
    wifi_ssid VARCHAR(100),
    wifi_bssid VARCHAR(50),
    checkin_start TIME,
    checkin_end TIME,
    checkout_start TIME,
    checkout_end TIME,
    allow_remote BOOLEAN DEFAULT false,
    need_face BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW()
);

-- 6. 电子围栏表
CREATE TABLE IF NOT EXISTS geo_fences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    department_id UUID REFERENCES departments(id),
    center_lat FLOAT NOT NULL,
    center_lng FLOAT NOT NULL,
    radius_meters FLOAT DEFAULT 100,
    shape_type VARCHAR(20) DEFAULT 'circle' CHECK (shape_type IN ('circle', 'polygon')),
    polygon_points JSONB,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW()
);

-- 7. 围栏事件表
CREATE TABLE IF NOT EXISTS fence_events (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    fence_id UUID NOT NULL REFERENCES geo_fences(id),
    event_type VARCHAR(10) NOT NULL CHECK (event_type IN ('enter', 'exit')),
    lng DOUBLE PRECISION NOT NULL,
    lat DOUBLE PRECISION NOT NULL,
    event_time TIMESTAMP DEFAULT NOW()
);

-- ========== 种子数据 ==========
INSERT INTO users (id, name, phone, password_hash, role) VALUES
    ('a0000000-0000-0000-0000-000000000001', '张三', '13800138000', '$2a$10$6uKE9YkWguirIUVHyOdKeu/uD7k.RBx71QFeTXNaBVDGF52e97kWq', 'employee'),
    ('a0000000-0000-0000-0000-000000000002', '李四', '13800138001', '$2a$10$6uKE9YkWguirIUVHyOdKeu/uD7k.RBx71QFeTXNaBVDGF52e97kWq', 'employee'),
    ('a0000000-0000-0000-0000-000000000099', '管理员', '13900000001', '$2a$10$6uKE9YkWguirIUVHyOdKeu/uD7k.RBx71QFeTXNaBVDGF52e97kWq', 'admin')
ON CONFLICT (phone) DO NOTHING;
