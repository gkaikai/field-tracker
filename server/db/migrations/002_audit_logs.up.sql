-- 002_audit_logs.up.sql
-- 创建审计日志表，用于持久化存储操作审计记录

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

CREATE INDEX IF NOT EXISTS idx_audit_logs_operator_id  ON audit_logs(operator_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action_type   ON audit_logs(action_type);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at    ON audit_logs(created_at);

COMMENT ON TABLE  audit_logs               IS '审计日志表 — 记录关键操作';
COMMENT ON COLUMN audit_logs.operator_id   IS '操作人用户ID';
COMMENT ON COLUMN audit_logs.operator_phone IS '操作人手机号（冗余，防止用户删除后丢失）';
COMMENT ON COLUMN audit_logs.action_type   IS '操作类型：register / login / update / delete 等';
COMMENT ON COLUMN audit_logs.target_type   IS '操作目标类型：user / customer / fence 等';
COMMENT ON COLUMN audit_logs.target_id     IS '操作目标ID';
COMMENT ON COLUMN audit_logs.detail        IS '操作详情（JSON）';
COMMENT ON COLUMN audit_logs.ip_address    IS '操作来源IP';
COMMENT ON COLUMN audit_logs.created_at    IS '操作时间';
