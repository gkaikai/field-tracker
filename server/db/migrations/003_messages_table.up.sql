-- 003 — 消息中心表
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
CREATE INDEX IF NOT EXISTS idx_messages_user ON messages(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_unread ON messages(user_id) WHERE is_read = false;

COMMENT ON TABLE  messages            IS '消息中心表 — 系统/业务通知';
COMMENT ON COLUMN messages.user_id    IS '接收人';
COMMENT ON COLUMN messages.title      IS '消息标题';
COMMENT ON COLUMN messages.content    IS '消息内容';
COMMENT ON COLUMN messages.msg_type   IS '消息类型：system / attendance / approval 等';
COMMENT ON COLUMN messages.biz_type   IS '业务类型（关联业务模块）';
COMMENT ON COLUMN messages.biz_id     IS '业务ID';
COMMENT ON COLUMN messages.is_read    IS '是否已读';
COMMENT ON COLUMN messages.priority   IS '优先级：normal / high / urgent';
