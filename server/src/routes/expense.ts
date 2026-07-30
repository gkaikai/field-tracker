// 费用报销路由 — GET 列表 / POST 提交 / 管理员审核
import { Router, Request, Response, NextFunction } from 'express';
import { body, query, param } from 'express-validator';
import { authMiddleware, adminMiddleware, JwtPayload } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { pgPool } from '../config/database';

const router = Router();
router.use(authMiddleware);

// GET /api/v1/expenses — 当前用户的报销列表
router.get('/',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const result = await pgPool.query(
        `SELECT e.id, e.title, e.amount, e.note, e.status, e.created_at as date
         FROM expenses e
         WHERE e.user_id = $1
         ORDER BY e.created_at DESC
         LIMIT 50`,
        [user.userId],
      );
      res.json({ expenses: result.rows });
    } catch (err) {
      next(err);
    }
  },
);

// POST /api/v1/expenses — 提交报销
router.post('/',
  validate([
    body('title').notEmpty().withMessage('报销标题不能为空'),
    body('amount').isFloat({ min: 0.01 }).withMessage('金额必须大于0'),
    body('note').optional().isString(),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const { title, amount, note } = req.body;
      const result = await pgPool.query(
        `INSERT INTO expenses (user_id, title, amount, note, status)
         VALUES ($1, $2, $3, $4, 'pending') RETURNING *`,
        [user.userId, title, amount, note || ''],
      );
      res.status(201).json(result.rows[0]);
    } catch (err) {
      next(err);
    }
  },
);

// PUT /api/v1/expenses/:id/status — 管理员审核报销
router.put('/:id/status',
  adminMiddleware,
  validate([
    param('id').isUUID(),
    body('status').isIn(['approved', 'rejected']).withMessage('状态须为 approved/rejected'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const result = await pgPool.query(
        `UPDATE expenses SET status = $1, updated_at = NOW()
         WHERE id = $2 RETURNING *`,
        [req.body.status, req.params.id],
      );
      if (result.rows.length === 0) {
        return res.status(404).json({ code: 'EXPENSE_NOT_FOUND', message: '报销记录不存在' });
      }
      res.json(result.rows[0]);
    } catch (err) {
      next(err);
    }
  },
);

export default router;
