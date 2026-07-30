// 消息中心 — 系统通知/告警/任务提醒
import { Router, Request, Response, NextFunction } from 'express';
import { body, param, query } from 'express-validator';
import { authMiddleware, adminMiddleware, JwtPayload } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { pgPool } from '../config/database';
import { ErrorCodes } from '../errors/errorCodes';

const router = Router();
router.use(authMiddleware);

// GET /api/v1/messages — 获取消息列表
router.get('/',
  validate([
    query('page').optional().isInt({ min: 1 }).toInt(),
    query('pageSize').optional().isInt({ min: 1, max: 50 }).toInt(),
    query('type').optional().isString(),
    query('unreadOnly').optional().isIn(['true', 'false']),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const page = Math.max(1, parseInt(req.query.page as string) || 1);
      const pageSize = Math.max(1, Math.min(50, parseInt(req.query.pageSize as string) || 20));
      const offset = (page - 1) * pageSize;
      const unreadOnly = req.query.unreadOnly === 'true';

      let whereClause = 'WHERE user_id = $1';
      const params: any[] = [user.userId];
      let idx = 2;

      if (req.query.type) {
        whereClause += ` AND msg_type = $${idx}`;
        params.push(req.query.type);
        idx++;
      }
      if (unreadOnly) {
        whereClause += ' AND is_read = false';
      }

      const countResult = await pgPool.query(
        `SELECT COUNT(*) FROM messages ${whereClause}`, params,
      );
      const total = parseInt(countResult.rows[0].count, 10);

      const result = await pgPool.query(
        `SELECT id, user_id, title, msg_type, biz_type, biz_id, is_read, read_at, priority, created_at
         FROM messages ${whereClause} ORDER BY created_at DESC LIMIT 100 OFFSET $${idx}`,
        [...params, offset],
      );

      res.json({
        messages: result.rows,
        pagination: { page, pageSize, total, totalPages: Math.ceil(total / pageSize) },
      });
    } catch (err) {
      next(err);
    }
  },
);

// GET /api/v1/messages/unread-count — 未读消息数
router.get('/unread-count',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const result = await pgPool.query(
        `SELECT COUNT(*) as cnt FROM messages WHERE user_id = $1 AND is_read = false`,
        [user.userId],
      );
      res.json({ unreadCount: parseInt(result.rows[0].cnt, 10) });
    } catch (err) {
      next(err);
    }
  },
);

// PUT /api/v1/messages/:id/read — 标记已读
router.put('/:id/read',
  validate([
    param('id').isUUID().withMessage('无效的消息ID'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const result = await pgPool.query(
        `UPDATE messages SET is_read = true, read_at = NOW() WHERE id = $1 AND user_id = $2 RETURNING id`,
        [req.params.id, user.userId],
      );
      if (result.rowCount === 0) {
        return res.status(404).json(ErrorCodes.MESSAGE_NOT_FOUND);
      }
      res.json({ success: true });
    } catch (err) {
      next(err);
    }
  },
);

// PUT /api/v1/messages/read-all — 全部标记已读
router.put('/read-all',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      await pgPool.query(
        `UPDATE messages SET is_read = true, read_at = NOW() WHERE user_id = $1 AND is_read = false`,
        [user.userId],
      );
      res.json({ success: true });
    } catch (err) {
      next(err);
    }
  },
);

// POST /api/v1/messages — 创建消息（系统内部使用，也可用于测试）
router.post('/',
  adminMiddleware,
  validate([
    body('userId').notEmpty().isUUID(),
    body('title').notEmpty().isLength({ max: 200 }).withMessage('标题不能超过200字'),
    body('content').optional().isLength({ max: 2000 }),
    body('msgType').optional().isString(),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { userId, title, content, msgType, bizType, bizId, priority } = req.body;
      const result = await pgPool.query(
        `INSERT INTO messages (user_id, title, content, msg_type, biz_type, biz_id, priority)
         VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
        [userId, title, content || '', msgType || 'system', bizType || null, bizId || null, priority || 'normal'],
      );
      res.status(201).json(result.rows[0]);
    } catch (err) {
      next(err);
    }
  },
);

export default router;
