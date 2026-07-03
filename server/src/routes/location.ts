import { Router, Request, Response } from 'express';
import { pgPool, redis } from '../config/database';
import { authMiddleware } from '../middleware/auth';

const router = Router();
router.use(authMiddleware);

// ============================================================
// POST /api/v1/location/report  - 单点上报
// ============================================================
router.post('/report', async (req: Request, res: Response) => {
  try {
    const user = (req as any).user;
    const { lng, lat, accuracy, speed, altitude, bearing, battery } = req.body;

    if (lng === undefined || lng === null || lng === '' ||
        lat === undefined || lat === null || lat === '') {
      return res.status(400).json({ message: '经纬度不能为空' });
    }

    // 坐标有效性校验
    const lngNum = parseFloat(lng);
    const latNum = parseFloat(lat);
    if (isNaN(lngNum) || isNaN(latNum) ||
        lngNum < -180 || lngNum > 180 ||
        latNum < -85.05 || latNum > 85.05) {
      return res.status(400).json({ message: '经纬度超出有效范围' });
    }

    const recordedAt = new Date().toISOString();

    // 1. 写入 Redis GEO（实时位置，TTL 5分钟）
    await redis.geoadd('realtime:locations', lng, lat, user.userId);
    await redis.expire('realtime:locations', 300);
    // 同时存一份详细信息
    await redis.hset(`user:${user.userId}:last`, {
      lng, lat, accuracy: accuracy || 0, speed: speed || 0,
      battery: battery || 0, timestamp: recordedAt
    });
    await redis.expire(`user:${user.userId}:last`, 300);

      // 2. 异步写入 PostgreSQL
    pgPool.query(
      `INSERT INTO location_records (user_id, lng, lat, accuracy, speed, altitude, bearing, battery, recorded_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [user.userId, lng, lat, accuracy, speed, altitude, bearing, battery, recordedAt]
    ).catch(err => console.error('写入定位记录失败:', err.message));

    res.json({ status: 'ok' });
  } catch (err) {
    console.error('上报定位错误:', err);
    res.status(500).json({ message: '服务器内部错误' });
  }
});

// ============================================================
// POST /api/v1/location/batch  - 批量上报（App端合并后上传）
// ============================================================
router.post('/batch', async (req: Request, res: Response) => {
  try {
    const user = (req as any).user;
    const { points } = req.body;

    if (!points || !Array.isArray(points) || points.length === 0) {
      return res.status(400).json({ message: '定位数据不能为空' });
    }

    // 坐标有效性校验（每个点）
    for (const p of points) {
      const lng = parseFloat(p.lng);
      const lat = parseFloat(p.lat);
      if (isNaN(lng) || isNaN(lat) ||
          lng < -180 || lng > 180 ||
          lat < -85.05 || lat > 85.05) {
        return res.status(400).json({ message: '定位数据中包含无效坐标' });
      }
    }

    // 批量写入（参数化查询防SQL注入）
    const placeholders = points.map((_: any, i: number) =>
      `($${i * 7 + 1}, $${i * 7 + 2}, $${i * 7 + 3}, $${i * 7 + 4}, $${i * 7 + 5}, $${i * 7 + 6}, $${i * 7 + 7})`
    ).join(',');

    const values = points.flatMap((p: any) => {
      const recordedAt = p.timestamp || new Date().toISOString();
      return [user.userId, p.lng, p.lat, p.accuracy || 0, p.speed || 0, p.battery || 0, recordedAt];
    });

    await pgPool.query(`
      INSERT INTO location_records (user_id, lng, lat, accuracy, speed, battery, recorded_at)
      VALUES ${placeholders}
    `, values);

    // 更新 Redis 实时位置（用最后一条）
    const last = points[points.length - 1];
    await redis.geoadd('realtime:locations', last.lng, last.lat, user.userId);
    await redis.expire('realtime:locations', 300);

    res.json({ status: 'ok', count: points.length });
  } catch (err) {
    console.error('批量上报错误:', err);
    res.status(500).json({ message: '服务器内部错误' });
  }
});

// ============================================================
// GET /api/v1/location/current/:userId  - 获取某人实时位置
// ============================================================
router.get('/current/:userId', async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;

    // 从 Redis 获取
    const positions = await redis.geopos('realtime:locations', userId);
    if (positions && positions[0]) {
      const lastInfo = await redis.hgetall(`user:${userId}:last`);
      res.json({
        userId,
        lng: positions[0][0],
        lat: positions[0][1],
        accuracy: lastInfo.accuracy,
        speed: lastInfo.speed,
        battery: lastInfo.battery,
        timestamp: lastInfo.timestamp,
        online: true,
      });
    } else {
      // Redis 没有则查数据库最后一条
      const result = await pgPool.query(`
        SELECT lng, lat, accuracy, speed, battery, recorded_at
        FROM location_records
        WHERE user_id = $1
        ORDER BY recorded_at DESC LIMIT 1
      `, [userId]);

      if (result.rows.length > 0) {
        res.json({ ...result.rows[0], online: false });
      } else {
        res.status(404).json({ message: '暂无定位数据' });
      }
    }
  } catch (err) {
    res.status(500).json({ message: '服务器内部错误' });
  }
});

// ============================================================
// GET /api/v1/location/online  - 获取所有在线人员位置
// ============================================================
router.get('/online', async (req: Request, res: Response) => {
  try {
    const user = (req as any).user;

    // 获取所属部门所有成员（简化版：管理员看所有人，员工看自己）
    let userIds: string[];
    if (user.role === 'admin') {
      const result = await pgPool.query('SELECT id FROM users WHERE is_active = true');
      userIds = result.rows.map(r => r.id);
    } else {
      // 获取同部门人员
      const deptResult = await pgPool.query(
        'SELECT id FROM users WHERE department_id = (SELECT department_id FROM users WHERE id = $1)',
        [user.userId]
      );
      userIds = deptResult.rows.map(r => r.id);
    }

    // 从 Redis 批量查询实时位置
    const pipeline = redis.pipeline();
    userIds.forEach(uid => {
      pipeline.geopos('realtime:locations', uid);
      pipeline.hgetall(`user:${uid}:last`);
    });
    const results = await pipeline.exec();

    const onlineUsers = [];
    for (let i = 0; i < userIds.length; i++) {
      const posResult = results![i * 2];
      const infoResult = results![i * 2 + 1];
      const pos = posResult?.[1] as [number, number][] | null;
      const info = infoResult?.[1] as Record<string, string> | null;

      if (pos && pos[0]) {
        onlineUsers.push({
          userId: userIds[i],
          lng: pos[0][0],
          lat: pos[0][1],
          accuracy: info?.accuracy,
          speed: info?.speed,
          battery: info?.battery,
          timestamp: info?.timestamp,
        });
      }
    }

    res.json(onlineUsers);
  } catch (err) {
    console.error('获取在线人员错误:', err);
    res.status(500).json({ message: '服务器内部错误' });
  }
});

// ============================================================
// GET /api/v1/location/track/:userId  - 获取历史轨迹
// ============================================================
router.get('/track/:userId', async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const { date } = req.query;

    let dateFilter = '';
    const params: any[] = [userId];

    if (date) {
      dateFilter = 'AND recorded_at >= $2::date AND recorded_at < ($2::date + INTERVAL \'1 day\')';
      params.push(date as string);
    }

    const result = await pgPool.query(`
      SELECT lng, lat, 
             accuracy, speed, altitude, bearing, battery, recorded_at
      FROM location_records
      WHERE user_id = $1 ${dateFilter}
      ORDER BY recorded_at ASC
    `, params);

    res.json({
      userId,
      points: result.rows,
      total: result.rows.length,
    });
  } catch (err) {
    res.status(500).json({ message: '服务器内部错误' });
  }
});

export default router;
