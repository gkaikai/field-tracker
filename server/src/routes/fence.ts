import { Router, Request, Response, NextFunction } from 'express';
import { body, query } from 'express-validator';
import { pgPool } from '../config/database';
import { authMiddleware, roleMiddleware, JwtPayload } from '../middleware/auth';
import { AppError } from '../errors/AppError';
import { validate } from '../middleware/validate';

const router = Router();
router.use(authMiddleware);

// ============================================================
//  电子围栏 CRUD（管理员）
// ============================================================

// GET /api/v1/fences — 围栏列表
router.get('/',
  roleMiddleware('manager', 'admin'),
  async (_req: Request, res: Response, next: NextFunction) => {
    try {
      const result = await pgPool.query(
        `SELECT f.*, d.name as department_name
         FROM geo_fences f
         LEFT JOIN departments d ON f.department_id = d.id
         WHERE f.is_active = true
         ORDER BY f.created_at DESC`,
      );
      res.json(result.rows);
    } catch (err) {
      next(err);
    }
  },
);

// POST /api/v1/fences — 创建围栏
router.post('/',
  roleMiddleware('admin'),
  validate([
    body('name').notEmpty().withMessage('围栏名称不能为空'),
    body('center_lat').isFloat({ min: -85.05, max: 85.05 }).withMessage('纬度无效'),
    body('center_lng').isFloat({ min: -180, max: 180 }).withMessage('经度无效'),
    body('radius_meters').optional().isFloat({ min: 10, max: 50000 }),
    body('department_id').optional().isUUID(),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { name, department_id, center_lat, center_lng, radius_meters, shape_type, polygon_points } = req.body;
      const result = await pgPool.query(
        `INSERT INTO geo_fences (name, department_id, center_lat, center_lng, radius_meters, shape_type, polygon_points)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING *`,
        [name, department_id || null, center_lat, center_lng, radius_meters || 100, shape_type || 'circle', polygon_points || null],
      );
      res.status(201).json(result.rows[0]);
    } catch (err) {
      next(err);
    }
  },
);

// PUT /api/v1/fences/:id — 更新围栏
router.put('/:id',
  roleMiddleware('admin'),
  validate([
    body('name').optional().notEmpty(),
    body('center_lat').optional().isFloat({ min: -85.05, max: 85.05 }),
    body('center_lng').optional().isFloat({ min: -180, max: 180 }),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { name, center_lat, center_lng, radius_meters, is_active } = req.body;
      const sets: string[] = [];
      const params: any[] = [];
      let idx = 1;

      if (name !== undefined) { sets.push(`name = $${idx++}`); params.push(name); }
      if (center_lat !== undefined) { sets.push(`center_lat = $${idx++}`); params.push(center_lat); }
      if (center_lng !== undefined) { sets.push(`center_lng = $${idx++}`); params.push(center_lng); }
      if (radius_meters !== undefined) { sets.push(`radius_meters = $${idx++}`); params.push(radius_meters); }
      if (is_active !== undefined) { sets.push(`is_active = $${idx++}`); params.push(is_active); }

      if (sets.length === 0) {
        throw new AppError('PARAM_INVALID');
      }

      params.push(req.params.id);
      const result = await pgPool.query(
        `UPDATE geo_fences SET ${sets.join(', ')} WHERE id = $${idx} RETURNING *`,
        params,
      );

      if (result.rows.length === 0) {
        throw new AppError('PARAM_INVALID');
      }

      res.json(result.rows[0]);
    } catch (err) {
      next(err);
    }
  },
);

// DELETE /api/v1/fences/:id — 删除围栏
router.delete('/:id',
  roleMiddleware('admin'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      await pgPool.query('UPDATE geo_fences SET is_active = false WHERE id = $1', [req.params.id]);
      res.json({ success: true });
    } catch (err) {
      next(err);
    }
  },
);

// ============================================================
//  围栏判定（员工）
// ============================================================

// POST /api/v1/fences/check — 判定当前位置是否在某围栏内
router.post('/check',
  validate([
    body('lng').isFloat({ min: -180, max: 180 }),
    body('lat').isFloat({ min: -85.05, max: 85.05 }),
    body('fence_id').optional().isUUID(),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const { lng, lat, fence_id } = req.body;

      let fences;
      if (fence_id) {
        // 判定指定围栏
        fences = await pgPool.query(
          'SELECT * FROM geo_fences WHERE id = $1 AND is_active = true',
          [fence_id],
        );
        if (fences.rows.length === 0) {
          return res.json({ inside: false, message: '围栏不存在或已禁用' });
        }
      } else {
        // 判定该员工所属部门的所有围栏
        fences = await pgPool.query(
          `SELECT * FROM geo_fences
           WHERE is_active = true
           AND (department_id IS NULL OR department_id = $1)
           ORDER BY radius_meters ASC`,
          [user.departmentId || null],
        );
      }

      const results = fences.rows.map((fence: any) => {
        const distance = haversineDistance(lat, lng, fence.center_lat, fence.center_lng);
        const inside = distance <= (fence.radius_meters || 100);
        return {
          fenceId: fence.id,
          fenceName: fence.name,
          distance: Math.round(distance),
          inside,
        };
      });

      // 如果有围栏状态变化，记录事件
      for (const r of results) {
        if (r.inside) {
          // 查询上次事件，防止重复记录
          const lastEvent = await pgPool.query(
            `SELECT event_type FROM fence_events
             WHERE user_id = $1 AND fence_id = $2
             ORDER BY event_time DESC LIMIT 1`,
            [user.userId, r.fenceId],
          );
          if (lastEvent.rows.length === 0 || lastEvent.rows[0].event_type === 'exit') {
            await pgPool.query(
              `INSERT INTO fence_events (user_id, fence_id, event_type, lng, lat)
               VALUES ($1, $2, 'enter', $3, $4)`,
              [user.userId, r.fenceId, lng, lat],
            );
          }
        }
      }

      res.json({ fences: results });
    } catch (err) {
      next(err);
    }
  },
);

// GET /api/v1/fences/events — 围栏事件记录
router.get('/events',
  roleMiddleware('manager', 'admin'),
  validate([
    query('userId').optional().isUUID(),
    query('page').optional().isInt({ min: 1 }).toInt(),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const userId = req.query.userId as string;
      const page = parseInt(req.query.page as string) || 1;
      const pageSize = 50;
      const offset = (page - 1) * pageSize;

      let whereClause = '';
      const params: any[] = [];
      if (userId) {
        whereClause = 'WHERE fe.user_id = $1';
        params.push(userId);
      }

      const result = await pgPool.query(
        `SELECT fe.*, f.name as fence_name, u.name as user_name
         FROM fence_events fe
         LEFT JOIN geo_fences f ON fe.fence_id = f.id
         LEFT JOIN users u ON fe.user_id = u.id
         ${whereClause}
         ORDER BY fe.event_time DESC
         LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
        [...params, pageSize, offset],
      );

      res.json({ events: result.rows, page });
    } catch (err) {
      next(err);
    }
  },
);

// ============================================================
//  辅助函数
// ============================================================

function haversineDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function toRad(deg: number): number {
  return deg * Math.PI / 180;
}

export default router;
