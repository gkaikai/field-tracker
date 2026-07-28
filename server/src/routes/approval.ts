// 审批流程 - 请假/出差/报销
import { Router, Request, Response, NextFunction } from 'express';
import { body, param, query } from 'express-validator';
import { authMiddleware, roleMiddleware, JwtPayload } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { pgPool } from '../config/database';

const router = Router();
router.use(authMiddleware);

// POST /api/v1/approvals — 创建审批
router.post('/',
  validate([
    body('type').isIn(['leave', 'business_trip', 'expense']).withMessage('类型无效'),
    body('title').notEmpty().withMessage('标题不能为空'),
    body('reason').notEmpty().withMessage('原因不能为空'),
    body('startDate').notEmpty().withMessage('开始日期不能为空'),
    body('endDate').notEmpty().withMessage('结束日期不能为空'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const { type, title, reason, startDate, endDate, duration, amount, remark } = req.body;
      const flowData: any = {};
      if (amount) flowData.amount = parseFloat(amount);
      if (remark) flowData.remark = remark;

      const result = await pgPool.query(
        `INSERT INTO approvals (applicant_id, approval_type, title, reason, status, start_date, end_date, duration_days, reject_reason, approval_flow)
         VALUES ($1, $2, $3, $4, 'pending', $5, $6, $7, $8, $9)
         RETURNING id, created_at`,
        [user.userId, type, title, reason, startDate, endDate,
         duration ? parseFloat(duration) : null, null,
         Object.keys(flowData).length > 0 ? JSON.stringify(flowData) : null]
      );

      const r = result.rows[0];
      res.status(201).json({
        id: r.id, userId: user.userId, userName: user.phone, type,
        status: 'pending', title, reason, startDate, endDate,
        duration: duration || '', amount: amount != null ? parseFloat(amount) : null,
        remark: remark || '', approverId: null, approverName: null, rejectReason: null,
        createdAt: r.created_at, updatedAt: r.created_at,
      });
    } catch (err) { next(err); }
  },
);

// GET /api/v1/approvals — 获取审批列表
// 管理员看到全系统审批，普通用户只能看自己的
router.get('/', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const user = (req as any).user as JwtPayload;
    const page = Math.max(1, parseInt(req.query.page as string) || 1);
    const pageSize = Math.max(1, Math.min(100, parseInt(req.query.pageSize as string) || 20));
    const type = req.query.type as string;
    const status = req.query.status as string;
    const offset = (page - 1) * pageSize;

    let whereClause: string;
    const params: any[] = [];

    if (user.role === 'admin') {
      // 管理员看到全系统审批，无 applicant_id 过滤
      whereClause = 'WHERE 1=1';
    } else {
      // 普通用户只能看自己提交的审批
      whereClause = 'WHERE a.applicant_id = $1';
      params.push(user.userId);
    }

    if (type) { params.push(type); whereClause += ` AND a.approval_type = $${params.length}`; }
    if (status) { params.push(status); whereClause += ` AND a.status = $${params.length}`; }

    const countResult = await pgPool.query(
      `SELECT COUNT(*)::int as total FROM approvals a ${whereClause}`, params
    );
    const total = countResult.rows[0].total;

    const dataResult = await pgPool.query(
      `SELECT a.id, a.applicant_id, a.approval_type, a.status, a.title, a.reason,
              a.start_date, a.end_date, a.duration_days, a.reject_reason, a.approval_flow,
              a.approver_id, a.approved_at, a.created_at, a.updated_at,
              u.name as applicant_name, u.phone as applicant_phone
       FROM approvals a
       LEFT JOIN users u ON a.applicant_id = u.id
       ${whereClause}
       ORDER BY a.created_at DESC
       LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
      [...params, pageSize, offset]
    );

    const approvals = dataResult.rows.map(r => ({
      id: r.id,
      userId: r.applicant_id,
      userName: r.applicant_name || r.applicant_phone || '未知用户',
      type: r.approval_type,
      status: r.status,
      title: r.title,
      reason: r.reason,
      startDate: r.start_date,
      endDate: r.end_date,
      duration: r.duration_days ? r.duration_days.toString() : '',
      amount: r.approval_flow ? (r.approval_flow as any).amount ?? null : null,
      remark: (r.approval_flow as any)?.remark ?? '',
      approverId: r.approver_id,
      rejectReason: r.reject_reason,
      createdAt: r.created_at,
      updatedAt: r.updated_at,
    }));

    res.json({ approvals, pagination: { page, pageSize, total } });
  } catch (err) { next(err); }
});

// PUT /api/v1/approvals/:id/approve — 审批操作（管理员）
router.put('/:id/approve',
  authMiddleware,
  roleMiddleware('admin'),
  validate([param('id').isUUID().withMessage('无效的审批ID'), body('status').isIn(['approved', 'rejected']), body('rejectReason').optional()]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const admin = (req as any).user as JwtPayload;
      const { status, rejectReason } = req.body;

      const result = await pgPool.query(
        `UPDATE approvals SET status=$1, reject_reason=$2, approver_id=$3, approved_at=NOW(), updated_at=NOW()
         WHERE id=$4 AND status='pending' RETURNING id, status, reject_reason, updated_at`,
        [status, rejectReason || null, admin.userId, req.params.id]
      );

      if (result.rows.length === 0) return res.status(404).json({ code: '10014', message: '审批不存在' });
      const r = result.rows[0];
      res.json({
        id: r.id, status: r.status, rejectReason: r.reject_reason,
        approverId: admin.userId, updatedAt: r.updated_at,
      });
    } catch (err) { next(err); }
  },
);

// 里程统计 — 用 Haversine 公式从 GPS 轨迹计算真实里程
// GET /api/v1/approvals/mileage
router.get('/mileage', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const user = (req as any).user as JwtPayload;
    const days = Math.max(1, parseInt(req.query.days as string) || 7);
    // Haversine 公式：对相邻 GPS 点位逐段计算球面距离并求和
    const result = await pgPool.query(
      `WITH points AS (
         SELECT lat, lng, recorded_at,
                LAG(lat) OVER (ORDER BY recorded_at, id) AS prev_lat,
                LAG(lng) OVER (ORDER BY recorded_at, id) AS prev_lng
         FROM location_records
         WHERE user_id = $1 AND recorded_at >= NOW() - $2::interval
       )
       SELECT COALESCE(
         (SELECT SUM(
            6371000 * 2 * ASIN(SQRT(
              POWER(SIN((lat - prev_lat) * PI() / 360), 2) +
              COS(lat * PI() / 180) * COS(prev_lat * PI() / 180) *
              POWER(SIN((lng - prev_lng) * PI() / 360), 2)
            ))
          ) / 1000 FROM points WHERE prev_lat IS NOT NULL AND prev_lng IS NOT NULL)
       , 0)::float8 AS total_km`,
      [user.userId, `${days} days`]
    );
    res.json({ totalKm: result.rows[0].total_km, days, unit: 'km' });
  } catch (err) {
    next(err);
  }
});

export default router;
