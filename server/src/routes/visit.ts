// 拜访/巡店执行 — 适配已有visit_records表
import { Router, Request, Response, NextFunction } from 'express';
import { body, param, query } from 'express-validator';
import { authMiddleware, adminMiddleware, JwtPayload } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { ErrorCodes } from '../errors/errorCodes';
import { pgPool } from '../config/database';

const router = Router();
router.use(authMiddleware);

// GET /api/v1/visits/today — 获取今日拜访计划（任务列表）
router.get('/today',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const today = new Date().toISOString().split('T')[0];

      const result = await pgPool.query(
        `SELECT vr.*, c.name as customer_name, c.address as customer_address,
                c.lat as customer_lat, c.lng as customer_lng
         FROM visit_records vr
         LEFT JOIN customers c ON vr.customer_id = c.id
         WHERE vr.user_id = $1
           AND (vr.planned_at::date = $2::date OR vr.start_time::date = $2::date)
         ORDER BY vr.planned_at ASC NULLS LAST, vr.created_at ASC
         LIMIT 50`,
        [user.userId, today],
      );

      res.json({ visits: result.rows, date: today });
    } catch (err) {
      next(err);
    }
  },
);

// POST /api/v1/visits — 创建拜访计划（管理员/经理）
router.post('/',
  adminMiddleware,
  validate([
    body('customerId').notEmpty().isUUID().withMessage('客户不能为空'),
    body('plannedAt').optional(),
    body('purpose').optional().isString(),
    body('visitType').optional().isIn(['field', 'phone', 'video', 'office']),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const { customerId, plannedAt, purpose, visitType } = req.body;

      const result = await pgPool.query(
        `INSERT INTO visit_records (user_id, customer_id, visit_type, status, planned_at, purpose)
         VALUES ($1, $2, $3, 'planned', $4, $5) RETURNING *`,
        [user.userId, customerId, visitType || 'field', plannedAt || new Date().toISOString(), purpose || ''],
      );

      res.status(201).json(result.rows[0]);
    } catch (err) {
      next(err);
    }
  },
);

// POST /api/v1/visits/:id/checkin — 拜访签到
router.post('/:id/checkin',
  validate([
    param('id').isUUID(),
    body('lat').isFloat(),
    body('lng').isFloat(),
    body('address').optional().isString(),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const { lat, lng, address } = req.body;

      // 校验归属
      const check = await pgPool.query(
        'SELECT id, status FROM visit_records WHERE id=$1 AND user_id=$2',
        [req.params.id, user.userId],
      );
      if (check.rows.length === 0) {
        return res.status(404).json(ErrorCodes.VISIT_NOT_FOUND);
      }
      if (check.rows[0].status !== 'planned') {
        return res.status(409).json(ErrorCodes.VISIT_ALREADY_CHECKIN);
      }

      const result = await pgPool.query(
        `UPDATE visit_records
         SET status = 'in_progress', start_time = NOW(),
             signin_lat = $1, signin_lng = $2, signin_address = $3,
             has_photo = CASE WHEN $4 IS NOT NULL AND $4 != '' THEN true ELSE false END,
             updated_at = NOW()
         WHERE id = $5 AND user_id = $6
         RETURNING *`,
        [lat, lng, address || '', req.body.photoUrl || null, req.params.id, user.userId],
      );

      res.json(result.rows[0]);
    } catch (err) {
      next(err);
    }
  },
);

// PUT /api/v1/visits/:id/report — 提交拜访报告
router.put('/:id/report',
  validate([
    param('id').isUUID(),
    body('content').optional().isString(),
    body('result').optional().isString(),
    body('nextPlan').optional().isString(),
    body('satisfaction').optional().isInt({ min: 1, max: 5 }),
    body('photoUrls').optional().isArray(),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const { content, result, nextPlan, satisfaction, photoUrls } = req.body;

      // 校验状态
      const check = await pgPool.query(
        'SELECT id, status FROM visit_records WHERE id=$1 AND user_id=$2',
        [req.params.id, user.userId],
      );
      if (check.rows.length === 0) {
        return res.status(404).json(ErrorCodes.VISIT_NOT_FOUND);
      }
      if (check.rows[0].status !== 'in_progress') {
        return res.status(409).json(ErrorCodes.VISIT_COMPLETED);
      }

      const updateRes = await pgPool.query(
        `UPDATE visit_records
         SET content = COALESCE($1, content),
             result = COALESCE($2, result),
             next_plan = COALESCE($3, next_plan),
             satisfaction = COALESCE($4, satisfaction),
             has_photo = CASE WHEN $5 IS NOT NULL AND jsonb_array_length($5) > 0 THEN true ELSE has_photo END,
             updated_at = NOW()
         WHERE id = $6 AND user_id = $7
         RETURNING *`,
        [content || null, result || null, nextPlan || null, satisfaction || null, photoUrls || null, req.params.id, user.userId],
      );

      res.json(updateRes.rows[0]);
    } catch (err) {
      next(err);
    }
  },
);

// POST /api/v1/visits/:id/checkout — 签退
router.post('/:id/checkout',
  validate([
    param('id').isUUID(),
    body('lat').optional().isFloat(),
    body('lng').optional().isFloat(),
    body('address').optional().isString(),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const { lat, lng, address } = req.body;

      const check = await pgPool.query(
        'SELECT id, status FROM visit_records WHERE id=$1 AND user_id=$2',
        [req.params.id, user.userId],
      );
      if (check.rows.length === 0) {
        return res.status(404).json(ErrorCodes.VISIT_NOT_FOUND);
      }
      if (check.rows[0].status !== 'in_progress') {
        return res.status(409).json(ErrorCodes.VISIT_NOT_IN_PROGRESS);
      }

      const result = await pgPool.query(
        `UPDATE visit_records
         SET status = 'completed', end_time = NOW(),
             signout_lat = COALESCE($1, signout_lat),
             signout_lng = COALESCE($2, signout_lng),
             signout_address = COALESCE($3, signout_address),
             duration_minutes = EXTRACT(EPOCH FROM (NOW() - start_time)) / 60,
             updated_at = NOW()
         WHERE id = $4 AND user_id = $5
         RETURNING *`,
        [lat || null, lng || null, address || null, req.params.id, user.userId],
      );

      res.json(result.rows[0]);
    } catch (err) {
      next(err);
    }
  },
);

// GET /api/v1/visits/history — 拜访历史
router.get('/history',
  validate([
    query('page').optional().isInt({ min: 1 }).toInt(),
    query('pageSize').optional().isInt({ min: 1, max: 50 }).toInt(),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const page = Math.max(1, parseInt(req.query.page as string) || 1);
      const pageSize = Math.max(1, Math.min(50, parseInt(req.query.pageSize as string) || 20));
      const offset = (page - 1) * pageSize;

      // admin/manager 看全量，employee只看自己
      const isAdmin = user.role === 'admin' || user.role === 'manager';
      const whereClause = isAdmin ? '1=1' : 'vr.user_id = $1';
      const params: any[] = isAdmin ? [] : [user.userId];

      const result = await pgPool.query(
        `SELECT vr.*, u.name as user_name, c.name as customer_name, c.address as customer_address
         FROM visit_records vr
         LEFT JOIN users u ON vr.user_id = u.id
         LEFT JOIN customers c ON vr.customer_id = c.id
         WHERE ${whereClause}
         ORDER BY vr.start_time DESC NULLS LAST, vr.created_at DESC
         LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
        [...params, pageSize, offset],
      );

      const countResult = await pgPool.query(
        `SELECT COUNT(*) FROM visit_records vr WHERE ${whereClause}`, params,
      );
      const total = parseInt(countResult.rows[0].count, 10);

      res.json({
        visits: result.rows,
        pagination: { page, pageSize, total, totalPages: Math.ceil(total / pageSize) },
      });
    } catch (err) {
      next(err);
    }
  },
);

export default router;
