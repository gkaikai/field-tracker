import { Router, Request, Response } from 'express';
import { body, query } from 'express-validator';
import { authMiddleware, adminMiddleware, JwtPayload } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { pgPool } from '../config/database';
import { AppError } from '../errors/AppError';
import { haversineDistance, pointInPolygon } from '../utils/geo';

const router = Router();
router.use(authMiddleware);

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
router.get('/', async (req: Request, res: Response) => {
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
});

// POST /api/v1/fences — 创建围栏（仅管理员）
router.post('/',
  adminMiddleware,
  validate([
    body('name').notEmpty().withMessage('围栏名称不能为空'),
    body('shapeType').isIn(['circle', 'polygon']).withMessage('类型必须是 circle 或 polygon'),
  ]),
  async (req: Request, res: Response) => {
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
  },
);

// PUT /api/v1/fences/:id — 更新围栏（仅管理员）
router.put('/:id',
  adminMiddleware,
  async (req: Request, res: Response) => {
    const { id } = req.params;
    const { name, shapeType, centerLat, centerLng, radiusMeters, coordinates, isActive, color } = req.body;

    const exist = await pgPool.query('SELECT id FROM geo_fences WHERE id = $1', [id]);
    if (exist.rows.length === 0) {
      return res.status(404).json({ code: 'FENCE_NOT_FOUND', message: '围栏不存在' });
    }

    const result = await pgPool.query(
      `UPDATE geo_fences SET
        name = COALESCE($1, name),
        shape_type = COALESCE($2, shape_type),
        center_lat = COALESCE($3, center_lat),
        center_lng = COALESCE($4, center_lng),
        radius_meters = COALESCE($5, radius_meters),
        polygon_points = COALESCE($6, polygon_points),
        color = COALESCE($7, color),
        is_active = COALESCE($8, is_active),
        updated_at = NOW()
        WHERE id = $9
        RETURNING id, name, shape_type, center_lat, center_lng, radius_meters, polygon_points, color, is_active`,
        [
         name ?? null, shapeType ?? null,
         centerLat ?? null, centerLng ?? null,
         radiusMeters ?? null, coordinates ? JSON.stringify(coordinates) : null,
         color ?? null, isActive ?? null, id,
      ],
    );

    res.json(formatFence(result.rows[0]));
  },
);

// DELETE /api/v1/fences/:id — 删除围栏（仅管理员）
router.delete('/:id',
  adminMiddleware,
  async (req: Request, res: Response) => {
    const { id } = req.params;
    const result = await pgPool.query(
      'DELETE FROM geo_fences WHERE id = $1 RETURNING id',
      [id],
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ code: 'FENCE_NOT_FOUND', message: '围栏不存在' });
    }
    res.json({ success: true, message: '围栏已删除' });
  },
);

// GET /api/v1/fences/check?lat=&lng= — 检测某点是否在围栏内
router.get('/check',
  validate([
    query('lat').isFloat().withMessage('纬度必须是数字'),
    query('lng').isFloat().withMessage('经度必须是数字'),
  ]),
  async (req: Request, res: Response) => {
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
  },
);

// GET /api/v1/fences/events — 围栏事件列表
router.get('/events', async (req: Request, res: Response) => {
  const user = (req as any).user as JwtPayload;

  let query = `SELECT fe.id, fe.fence_id, fe.user_id, u.name as user_name, gf.name as fence_name, fe.event_type,
                      fe.lat, fe.lng, fe.created_at
               FROM fence_events fe
               JOIN geo_fences gf ON fe.fence_id = gf.id
               LEFT JOIN users u ON fe.user_id = u.user_id`;
  const params: any[] = [];
  if (user.role !== 'admin') {
    query += ` WHERE fe.user_id = $1`;
    params.push(user.userId);
  }
  query += ' ORDER BY fe.created_at DESC LIMIT 200';

  const result = await pgPool.query(query, params);
  res.json({
    total: result.rows.length,
    events: result.rows.map(r => ({
      id: r.id,
      fenceId: r.fence_id,
      userId: r.user_id,
      userName: r.user_name,
      fenceName: r.fence_name,
      eventType: r.event_type,
      lat: parseFloat(r.lat),
      lng: parseFloat(r.lng),
      createdAt: r.created_at,
    })),
  });
});

// GET /api/v1/fences/:id — 单个围栏详情（必须放在所有具名 GET 路由之后）
router.get('/:id', async (req: Request, res: Response) => {
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
    return res.status(404).json({ code: 'FENCE_NOT_FOUND', message: '围栏不存在' });
  }
  res.json(formatFence(result.rows[0]));
});

// POST /api/v1/fences/auto-check — 自动围栏检测（定位上报时调用）
// 追踪 enter/exit 状态切换，只在状态翻转时记录事件
router.post('/auto-check', async (req: Request, res: Response) => {
  const user = (req as any).user as JwtPayload;
  const { lat, lng } = req.body;
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
  const events: Array<{eventType: string; fenceId: string; fenceName: string; lat: number; lng: number}> = [];

  for (const f of fences) {
    let inside = false;
    if (f.shape_type === 'circle') {
      const distance = haversineDistance(lat, lng, f.center_lat, f.center_lng);
      inside = distance <= (f.radius_meters || 100);
    } else {
      const coords: Array<{lat: number; lng: number}> = f.polygon_points || [];
      inside = pointInPolygon(lat, lng, coords);
    }

    // 查询该用户对该围栏的最新事件，判断状态是否翻转
    const lastEventResult = await pgPool.query(
      `SELECT event_type FROM fence_events
       WHERE user_id = $1 AND fence_id = $2
       ORDER BY created_at DESC LIMIT 1`,
      [user.userId, f.id],
    );
    const lastWasInside = lastEventResult.rows.length > 0 && lastEventResult.rows[0].event_type === 'enter';

    if (inside && !lastWasInside) {
      await pgPool.query(
        `INSERT INTO fence_events (user_id, fence_id, event_type, lat, lng)
         VALUES ($1, $2, 'enter', $3, $4)`,
        [user.userId, f.id, lat, lng],
      );
      events.push({ eventType: 'enter', fenceId: f.id, fenceName: f.name, lat, lng });
    } else if (!inside && lastWasInside) {
      await pgPool.query(
        `INSERT INTO fence_events (user_id, fence_id, event_type, lat, lng)
         VALUES ($1, $2, 'exit', $3, $4)`,
        [user.userId, f.id, lat, lng],
      );
      events.push({ eventType: 'exit', fenceId: f.id, fenceName: f.name, lat, lng });
    }
    // 无变化，不记录
  }

  res.json({ events, count: events.length });
});

export default router;
