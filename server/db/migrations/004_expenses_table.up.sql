-- 004 — 费用报销表
-- 新增 expenses 表存储报销记录
BEGIN;

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

COMMIT;
