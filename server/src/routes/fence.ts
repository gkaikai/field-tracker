import { Router, Request, Response, NextFunction } from 'express';
import { body, query } from 'express-validator';
import { authMiddleware, adminMiddleware, JwtPayload } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { pgPool } from '../config/database';
import { ErrorCodes } from '../errors/errorCodes';
import { AppError } from '../errors/AppError';
import { haversineDistance, pointInPolygon } from '../utils/geo';

const router = Router();
router.use(authMiddleware);

// 围栏 auto-check 频率限制（10次/分钟/用户）
const autoCheckRateMap = new Map<string, number[]>();
const RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1分钟
const RATE_LIMIT_MAX = 10; // 最多10次
// 每5分钟清理过期条目，防止内存泄漏
setInterval(() => {
  const cutoff = Date.now() - RATE_LIMIT_WINDOW_MS;
  autoCheckRateMap.forEach((timestamps, userId) => {
    const valid = timestamps.filter(t => t > cutoff);
    if (valid.length === 0) autoCheckRateMap.delete(userId);
    else autoCheckRateMap.set(userId, valid);
  });
}, 5 * 60 * 1000).unref();

// ============================================================
//  围栏接口（全部使用 PostgreSQL 持久化存储）
// ============================================================

/** 将数据库行转换为前端围栏对象 */
function formatFence(f: any) {
  return {
    id: f.id,
    name: f.name,
    departmentId: f.department_id,
    shapeType: f.shape_type,
    centerLat: f.center_lat,
    centerLng: f.center_lng,
    radiusMeters: f.radius_meters,
    coordinates: f.polygon_points,
    color: f.color,
    description: f.description,
    isActive: f.is_active,
    createdBy: f.created_by,
    createdAt: f.created_at,
  };
}

// GET /api/v1/fences — 围栏列表
router.get('/', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const user = (req as any).user as JwtPayload;

    let query = `SELECT id, name, department_id, shape_type,
                      center_lat, center_lng, radius_meters,
                      polygon_points, is_active, color, description,
                      created_by, created_at
               FROM geo_fences WHERE is_active = true`;

    const params: any[] = [];
    // 非管理员只能看到自己部门或未绑定部门的围栏
    if (user.role !== 'admin') {
      query += ` AND (department_id IS NULL OR department_id = $1)`;
      params.push(user.departmentId);
    }
    query += ' ORDER BY created_at DESC';

    const result = await pgPool.query(query, params);
    res.json(result.rows.map(formatFence));
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/fences — 创建围栏（仅管理员）
router.post('/',
  adminMiddleware,
  validate([
    body('name').notEmpty().withMessage('围栏名称不能为空'),
    body('shapeType').isIn(['circle', 'polygon']).withMessage('类型必须是 circle 或 polygon'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const { name, shapeType, centerLat, centerLng, radiusMeters, coordinates, departmentId, color } = req.body;

      const result = await pgPool.query(
        `INSERT INTO geo_fences (name, department_id, shape_type, center_lat, center_lng, radius_meters, polygon_points, color, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING id, name, department_id, shape_type, center_lat, center_lng, radius_meters, polygon_points, color, is_active, created_at`,
        [
          name,
          departmentId || null,
          shapeType,
          shapeType === 'circle' ? (centerLat ?? null) : null,
          shapeType === 'circle' ? (centerLng ?? null) : null,
          shapeType === 'circle' ? (radiusMeters ?? 100) : null,
          shapeType === 'polygon' ? (coordinates ? JSON.stringify(coordinates) : null) : null,
          color || '#FF0000',
          user.userId,
        ],
      );

      res.status(201).json(formatFence(result.rows[0]));
    } catch (err) {
      next(err);
    }
  },
);

// PUT /api/v1/fences/:id — 更新围栏（仅管理员）
// 使用先 SELECT 后 ?? 兜底，避免 NULL 覆盖已有坐标
router.put('/:id',
  adminMiddleware,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { id } = req.params;
      const { name, shapeType, centerLat, centerLng, radiusMeters, coordinates, isActive, color } = req.body;

      // 先 SELECT 现有值，为 ?? 兜底做准备
      const existing = await pgPool.query(
        `SELECT name, shape_type, center_lat, center_lng, radius_meters, polygon_points, color, is_active
       FROM geo_fences WHERE id = $1`, [id]
      );
      if (existing.rows.length === 0) {
        return res.status(404).json({ code: ErrorCodes.FENCE_NOT_FOUND.code, message: ErrorCodes.FENCE_NOT_FOUND.message });
      }
      const cur = existing.rows[0];

      const result = await pgPool.query(
        `UPDATE geo_fences SET
        name = $1,
        shape_type = $2,
        center_lat = $3,
        center_lng = $4,
        radius_meters = $5,
        polygon_points = $6,
        color = $7,
        is_active = $8,
        updated_at = NOW()
        WHERE id = $9
        RETURNING id, name, shape_type, center_lat, center_lng, radius_meters, polygon_points, color, is_active`,
        [
          name ?? cur.name,
          shapeType ?? cur.shape_type,
          centerLat ?? cur.center_lat,
          centerLng ?? cur.center_lng,
          radiusMeters ?? cur.radius_meters,
          Array.isArray(coordinates) && coordinates.length > 0 ? JSON.stringify(coordinates) : cur.polygon_points,
          color ?? cur.color,
          isActive ?? cur.is_active,
          id,
        ],
      );

      res.json(formatFence(result.rows[0]));
    } catch (err) {
      next(err);
    }
  },
);


// DELETE /api/v1/fences/:id — 删除围栏（仅管理员）
router.delete('/:id',
  adminMiddleware,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { id } = req.params;
      const result = await pgPool.query(
        'DELETE FROM geo_fences WHERE id = $1 RETURNING id',
        [id],
      );
      if (result.rows.length === 0) {
        return res.status(404).json({ code: ErrorCodes.FENCE_NOT_FOUND.code, message: ErrorCodes.FENCE_NOT_FOUND.message });
      }
      res.json({ success: true, message: '围栏已删除' });
    } catch (err) {
      next(err);
    }
  },
);

// GET /api/v1/fences/check?lat=&lng= — 检测某点是否在围栏内
router.get('/check',
  validate([
    query('lat').isFloat().withMessage('纬度必须是数字'),
    query('lng').isFloat().withMessage('经度必须是数字'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const { lat, lng } = req.query;
      const userLat = parseFloat(lat as string);
      const userLng = parseFloat(lng as string);

      let fenceQuery = `SELECT id, name, shape_type, center_lat, center_lng, radius_meters, polygon_points
                       FROM geo_fences WHERE is_active = true`;
      const params: any[] = [];
      if (user.role !== 'admin') {
        fenceQuery += ` AND (department_id IS NULL OR department_id = $1)`;
        params.push(user.departmentId);
      }

      const result = await pgPool.query(fenceQuery, params);
      const fences = result.rows;

      const results = fences.map(f => {
        if (f.shape_type === 'circle') {
          const distance = haversineDistance(userLat, userLng, f.center_lat, f.center_lng);
          return { fenceId: f.id, name: f.name, inside: distance <= (f.radius_meters || 100) };
        } else {
          const coords: Array<{lat: number; lng: number}> = f.polygon_points || [];
          return { fenceId: f.id, name: f.name, inside: pointInPolygon(userLat, userLng, coords) };
        }
      });

      res.json({ lat: userLat, lng: userLng, results });
    } catch (err) {
      next(err);
    }
  },
);

// GET /api/v1/fences/events — 围栏事件列表（带分页）
router.get('/events', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const user = (req as any).user as JwtPayload;
    const page = Math.max(1, parseInt(req.query.page as string) || 1);
    const pageSize = Math.min(200, Math.max(1, parseInt(req.query.pageSize as string) || 50));
    const offset = (page - 1) * pageSize;

    // 先查总数
    let countQuery = 'SELECT COUNT(*)::int as total FROM fence_events fe';
    let dataQuery = `SELECT fe.id, fe.fence_id, fe.user_id, u.name as user_name, gf.name as fence_name, fe.event_type,
                          fe.lat, fe.lng, fe.accuracy, fe.created_at
                   FROM fence_events fe
                   JOIN geo_fences gf ON fe.fence_id = gf.id
                   LEFT JOIN users u ON fe.user_id = u.id`;
    const params: any[] = [];
    if (user.role !== 'admin') {
      const where = ' WHERE fe.user_id = $1';
      countQuery += where;
      dataQuery += where;
      params.push(user.userId);
    }
    dataQuery += ' ORDER BY fe.created_at DESC';

    const countResult = await pgPool.query(countQuery, params);
    const total = countResult.rows[0].total;

    dataQuery += ` LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
    const dataResult = await pgPool.query(dataQuery, [...params, pageSize, offset]);

    res.json({
      total,
      page,
      pageSize,
      totalPages: Math.ceil(total / pageSize),
      events: dataResult.rows.map(r => ({
        id: r.id,
        fenceId: r.fence_id,
        userId: r.user_id,
        userName: r.user_name,
        fenceName: r.fence_name,
        eventType: r.event_type,
        lat: parseFloat(r.lat),
        lng: parseFloat(r.lng),
        accuracy: r.accuracy ? parseFloat(r.accuracy) : null,
        createdAt: r.created_at,
      })),
    });
  } catch (err) {
    next(err);
  }
});

// GET /api/v1/fences/:id — 单个围栏详情（必须放在所有具名 GET 路由之后）
router.get('/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    const result = await pgPool.query(
      `SELECT id, name, department_id, shape_type,
            center_lat, center_lng, radius_meters,
            polygon_points, is_active, color, description,
            created_by, created_at
     FROM geo_fences WHERE id = $1`,
      [id],
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ code: ErrorCodes.FENCE_NOT_FOUND.code, message: ErrorCodes.FENCE_NOT_FOUND.message });
    }
    res.json(formatFence(result.rows[0]));
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/fences/auto-check — 自动围栏检测（定位上报时调用）
// 追踪 enter/exit 状态切换，只在状态翻转时记录事件
// 频率限制：10次/分钟/用户，防止恶意调用触发事件插入风暴
router.post('/auto-check', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const user = (req as any).user as JwtPayload;
    const now = Date.now();

    // 频率限制检查
    const timestamps = autoCheckRateMap.get(user.userId) || [];
    const recentTimestamps = timestamps.filter(t => now - t < RATE_LIMIT_WINDOW_MS);
    if (recentTimestamps.length >= RATE_LIMIT_MAX) {
      return res.status(429).json({ code: ErrorCodes.FENCE_RATE_LIMITED.code, message: ErrorCodes.FENCE_RATE_LIMITED.message });
    }
    recentTimestamps.push(now);
    autoCheckRateMap.set(user.userId, recentTimestamps);

    const { lat, lng, accuracy } = req.body;
    if (!lat || !lng) return res.json({ events: [], count: 0 });

    let fenceQuery = `SELECT id, name, shape_type, center_lat, center_lng, radius_meters, polygon_points
                     FROM geo_fences WHERE is_active = true`;
    const params: any[] = [];
    if (user.role !== 'admin') {
      fenceQuery += ` AND (department_id IS NULL OR department_id = $1)`;
      params.push(user.departmentId);
    }

    const result = await pgPool.query(fenceQuery, params);
    const fences = result.rows;
    const newEvents: Array<{eventType: string; fenceId: string; fenceName: string; lat: number; lng: number}> = [];
    const insertValues: any[][] = [];

    // 批量查询所有围栏的最新事件（替代 N+1 逐条查）
    const fenceIds = fences.map(f => f.id);
    const lastEventMap = new Map<string, string>();
    if (fenceIds.length > 0) {
      const lastEventsResult = await pgPool.query(
        `SELECT DISTINCT ON (fence_id) fence_id, event_type
       FROM fence_events
       WHERE user_id = $1 AND fence_id = ANY($2::uuid[])
       ORDER BY fence_id, created_at DESC`,
        [user.userId, fenceIds]
      );
      for (const row of lastEventsResult.rows) {
        lastEventMap.set(row.fence_id, row.event_type);
      }
    }

    for (const f of fences) {
      let inside = false;
      if (f.shape_type === 'circle') {
        const distance = haversineDistance(lat, lng, f.center_lat, f.center_lng);
        inside = distance <= (f.radius_meters || 100);
      } else {
        const coords: Array<{lat: number; lng: number}> = f.polygon_points || [];
        inside = pointInPolygon(lat, lng, coords);
      }

      const lastEventType = lastEventMap.get(f.id);
      const lastWasInside = lastEventType === 'enter';

      if (inside && !lastWasInside) {
        insertValues.push([user.userId, f.id, 'enter', lat, lng, accuracy ?? null]);
        newEvents.push({ eventType: 'enter', fenceId: f.id, fenceName: f.name, lat, lng });
      } else if (!inside && lastWasInside) {
        insertValues.push([user.userId, f.id, 'exit', lat, lng, accuracy ?? null]);
        newEvents.push({ eventType: 'exit', fenceId: f.id, fenceName: f.name, lat, lng });
      }
      // 无变化，不记录
    }

    // 事务包裹 — 所有事件INSERT一起成功或一起失败
    if (insertValues.length > 0) {
      const client = await pgPool.connect();
      try {
        await client.query('BEGIN');
        for (const vals of insertValues) {
          await client.query(
            `INSERT INTO fence_events (user_id, fence_id, event_type, lat, lng, accuracy)
           VALUES ($1, $2, $3, $4, $5, $6)`,
            vals,
          );
        }
        await client.query('COMMIT');
      } catch (txErr) {
        await client.query('ROLLBACK');
        throw txErr;
      } finally {
        client.release();
      }
    }

    res.json({ events: newEvents, count: newEvents.length });
  } catch (err) {
    next(err);
  }
});

export default router;
