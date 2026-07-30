-- 消息中心表
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
