import { Router, Request, Response, NextFunction } from 'express';
import { body, param, query } from 'express-validator';
import { authMiddleware, JwtPayload } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { pgPool } from '../config/database';

const router = Router();
router.use(authMiddleware);

// POST /api/v1/reports — 创建汇报（持久化到 PostgreSQL）
router.post('/',
  validate([
    body('type').isIn(['daily', 'weekly', 'monthly']).withMessage('类型无效'),
    body('content').notEmpty().withMessage('汇报内容不能为空'),
    body('date').optional().matches(/^\d{4}-\d{2}-\d{2}$/),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const { type, content, summary, date } = req.body;
      const reportDate = date || new Date().toISOString().split('T')[0];
      const title = type === 'daily' ? `日报 ${reportDate}` : type === 'weekly' ? `周报 ${reportDate}` : `月报 ${reportDate}`;
      const contentJson = JSON.stringify({ text: content, summary: summary || '' });
      const startDate = reportDate;
      const endDate = reportDate;

      const result = await pgPool.query(
        `INSERT INTO reports (user_id, report_type, title, report_date, start_date, end_date, content, status, submit_time)
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'submitted', NOW())
         RETURNING id, report_type, report_date, content, status, submit_time`,
        [user.userId, type, title, reportDate, startDate, endDate, contentJson]
      );

      const r = result.rows[0];
      let parsedContent: any = r.content;
      try {
        parsedContent = typeof r.content === 'string' ? JSON.parse(r.content) : r.content;
      } catch {
        parsedContent = { text: '', summary: '' };
      }
      res.status(201).json({
        id: r.id,
        userId: user.userId,
        userName: user.phone,
        type: r.report_type,
        content: parsedContent?.text || '',
        summary: parsedContent?.summary || '',
        date: r.report_date,
        createdAt: r.submit_time,
      });
    } catch (err) {
      next(err);
    }
  },
);

// GET /api/v1/reports — 获取汇报列表
router.get('/',
  validate([
    query('type').optional().isIn(['daily', 'weekly', 'monthly']),
    query('date').optional().matches(/^\d{4}-\d{2}-\d{2}$/),
    query('page').optional().isInt({ min: 1 }).toInt(),
    query('pageSize').optional().isInt({ min: 1, max: 50 }).toInt(),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const page = parseInt(req.query.page as string) || 1;
      const pageSize = parseInt(req.query.pageSize as string) || 20;

      let whereClause = 'WHERE user_id = $1 AND is_deleted = false';
      const params: any[] = [user.userId];
      let paramIdx = 2;

      if (req.query.type) {
        whereClause += ` AND report_type = $${paramIdx++}`;
        params.push(req.query.type);
      }
      if (req.query.date) {
        whereClause += ` AND report_date = $${paramIdx++}`;
        params.push(req.query.date);
      }

      // 总条数（与主查询使用相同的 WHERE 条件，确保过滤时计数正确）
      const countResult = await pgPool.query(
        `SELECT COUNT(*) FROM reports ${whereClause}`,
        params
      );
      const total = parseInt(countResult.rows[0].count);

      // 分页数据查询（复用 paramIdx 继续追加）
      let sql = `SELECT id, user_id, report_type, report_date, content, status, submit_time
                 FROM reports ${whereClause}`;
      sql += ' ORDER BY submit_time DESC';
      sql += ` LIMIT $${paramIdx++} OFFSET $${paramIdx++}`;
      params.push(pageSize, (page - 1) * pageSize);

      const result = await pgPool.query(sql, params);
      const reports = result.rows.map(r => {
        let parsedContent: any = r.content;
        try {
          parsedContent = typeof r.content === 'string' ? JSON.parse(r.content) : r.content;
        } catch {
          parsedContent = { text: '', summary: '' };
        }
        return {
          id: r.id,
          userId: r.user_id,
          userName: user.phone,
          type: r.report_type,
          content: parsedContent?.text || '',
          summary: parsedContent?.summary || '',
          date: r.report_date,
          createdAt: r.submit_time,
        };
      });

      res.json({ reports, pagination: { page, pageSize, total, totalPages: Math.ceil(total / pageSize) } });
    } catch (err) {
      next(err);
    }
  },
);

// GET /api/v1/reports/stats — 统计
router.get('/stats',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const result = await pgPool.query(
        `SELECT report_type, COUNT(*)::int AS cnt
         FROM reports WHERE user_id = $1 AND is_deleted = false
         GROUP BY report_type`,
        [user.userId]
      );
      const dailyCount = result.rows.find((r: any) => r.report_type === 'daily')?.cnt || 0;
      const weeklyCount = result.rows.find((r: any) => r.report_type === 'weekly')?.cnt || 0;
      const monthlyCount = result.rows.find((r: any) => r.report_type === 'monthly')?.cnt || 0;
      const total = dailyCount + weeklyCount + monthlyCount;
      res.json({ total, daily: dailyCount, weekly: weeklyCount, monthly: monthlyCount });
    } catch (err) {
      next(err);
    }
  },
);

// DELETE /api/v1/reports/:id — 删除汇报（软删除）
router.delete('/:id',
  validate([param('id').isUUID().withMessage('无效的汇报ID')]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const result = await pgPool.query(
        `UPDATE reports SET is_deleted = true WHERE id = $1 AND user_id = $2`,
        [req.params.id, user.userId]
      );
      if (result.rowCount === 0) {
        res.status(404).json({ error: '汇报不存在或无权删除' });
        return;
      }
      res.json({ success: true });
    } catch (err) {
      next(err);
    }
  },
);

export default router;
