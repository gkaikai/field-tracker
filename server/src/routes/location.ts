import { Router, Request, Response, NextFunction } from 'express';
import { body, param, query } from 'express-validator';
import { pgPool, redis } from '../config/database';
import { authMiddleware, roleMiddleware, JwtPayload } from '../middleware/auth';
import { AppError } from '../errors/AppError';
import { validate } from '../middleware/validate';

const router = Router();

/** 所有 location 端点都需要登录 */
router.use(authMiddleware);

// 单点上报 — POST /api/v1/location/report
router.post('/report',
  validate([
    body('lng')
      .exists().withMessage('经度不能为空')
      .isFloat({ min: -180, max: 180 }).withMessage('经度超出有效范围(-180~180)'),
    body('lat')
      .exists().withMessage('纬度不能为空')
      .isFloat({ min: -85.05, max: 85.05 }).withMessage('纬度超出有效范围(-85~85)'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const { lng, lat, accuracy, speed, timestamp } = req.body;

      // 写入 Redis GEO（实时位置，TTL 5分钟）
      const redisKey = `location:${user.userId}`;
      await redis.geoadd('locations:live', lng, lat, user.userId);
      await redis.expire('locations:live', 300);
      await redis.hset(redisKey, {
        lng: lng.toString(),
        lat: lat.toString(),
        accuracy: (accuracy || 0).toString(),
        speed: (speed || 0).toString(),
        timestamp: (timestamp || Date.now()).toString(),
        userId: user.userId,
        name: user.phone,
      });
      await redis.expire(redisKey, 300);

      // 异步写入 PostgreSQL（历史轨迹）
      const ts = timestamp ? new Date(timestamp) : new Date();
      await pgPool.query(
        `INSERT INTO location_records (user_id, lng, lat, accuracy, speed, recorded_at)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [user.userId, lng, lat, accuracy || 0, speed || 0, ts],
      );

      res.json({ success: true });
    } catch (err) {
      next(err);
    }
  },
);

// 批量上报 — POST /api/v1/location/batch
router.post('/batch',
  validate([
    body('points')
      .isArray({ min: 1 }).withMessage('批量位置数据不能为空'),
    body('points.*.lng')
      .isFloat({ min: -180, max: 180 }).withMessage('存在无效经度'),
    body('points.*.lat')
      .isFloat({ min: -85.05, max: 85.05 }).withMessage('存在无效纬度'),
    body('points')
      .isArray({ max: 100 }).withMessage('单次批量上传不能超过100条'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const { points } = req.body;

      const values: any[] = [];
      const placeholders: string[] = [];
      let idx = 1;

      for (const p of points) {
        placeholders.push(`($${idx}, $${idx + 1}, $${idx + 2}, $${idx + 3}, $${idx + 4}, $${idx + 5})`);
        values.push(
          user.userId,
          p.lng,
          p.lat,
          p.accuracy || 0,
          p.speed || 0,
          p.timestamp ? new Date(p.timestamp) : new Date(),
        );
        idx += 6;
      }

      await pgPool.query(
        `INSERT INTO location_records (user_id, lng, lat, accuracy, speed, recorded_at) VALUES ${placeholders.join(',')}`,
        values,
      );

      // 更新 Redis 实时位置（用最后一条）
      const last = points[points.length - 1];
      await redis.geoadd('locations:live', last.lng, last.lat, user.userId);
      await redis.expire('locations:live', 300);

      res.json({ success: true, count: points.length });
    } catch (err) {
      next(err);
    }
  },
);

// 获取某人实时位置 — 员工只能查自己，管理员/经理可查所有人
router.get('/current/:userId', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const user = (req as any).user as JwtPayload;
    const targetUserId = req.params.userId;

    // 非管理员/经理只能查自己
    if (user.role === 'employee' && targetUserId !== user.userId) {
      throw new AppError('AUTH_FORBIDDEN');
    }

    const redisKey = `location:${targetUserId}`;
    const exists = await redis.exists(redisKey);

    if (!exists) {
      return res.json({ online: false });
    }

    const data = await redis.hgetall(redisKey);
    res.json({
      online: true,
      userId: targetUserId,
      lng: parseFloat(data.lng),
      lat: parseFloat(data.lat),
      accuracy: parseFloat(data.accuracy || '0'),
      speed: parseFloat(data.speed || '0'),
      timestamp: parseInt(data.timestamp || '0', 10),
    });
  } catch (err) {
    next(err);
  }
});

// 获取在线人员列表 — 仅管理员/经理可见
router.get('/online',
  roleMiddleware('manager', 'admin'),
  async (_req: Request, res: Response, next: NextFunction) => {
  try {
    const results = await redis.geopos('locations:live', ...Array(100).fill(0).map((_, i) => `*`));
    // 改用 scan 方式获取
    const keys = await redis.keys('location:*');
    const users: any[] = [];

    for (const key of keys) {
      const data = await redis.hgetall(key);
      const userId = key.replace('location:', '');
      users.push({
        userId,
        lng: parseFloat(data.lng),
        lat: parseFloat(data.lat),
        accuracy: parseFloat(data.accuracy || '0'),
        speed: parseFloat(data.speed || '0'),
        timestamp: parseInt(data.timestamp || '0', 10),
      });
    }

    res.json({ users, total: users.length });
  } catch (err) {
    next(err);
  }
});

// 获取历史轨迹 — 员工只能查自己，管理员/经理可查所有人
router.get('/track/:userId',
  validate([
    query('date')
      .optional()
      .matches(/^\d{4}-\d{2}-\d{2}$/).withMessage('日期格式无效(YYYY-MM-DD)'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const targetUserId = req.params.userId;

      // 非管理员/经理只能查自己
      if (user.role === 'employee' && targetUserId !== user.userId) {
        throw new AppError('AUTH_FORBIDDEN');
      }
      const date = (req.query.date as string) || new Date().toISOString().split('T')[0];
      const startOfDay = new Date(`${date}T00:00:00+08:00`);
      const endOfDay = new Date(`${date}T23:59:59.999+08:00`);

      const result = await pgPool.query(
        `SELECT lng, lat, accuracy, speed, recorded_at
         FROM location_records
         WHERE user_id = $1 AND recorded_at >= $2 AND recorded_at <= $3
         ORDER BY recorded_at ASC`,
        [targetUserId, startOfDay, endOfDay],
      );

      res.json({
        userId: targetUserId,
        date,
        points: result.rows.map((r: any) => ({
          lng: parseFloat(r.lng),
          lat: parseFloat(r.lat),
          accuracy: r.accuracy,
          speed: r.speed,
          timestamp: new Date(r.recorded_at).getTime(),
        })),
      });
    } catch (err) {
      next(err);
    }
  },
);

export default router;
