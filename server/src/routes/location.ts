import { Router, Request, Response, NextFunction } from 'express';
import { body, query } from 'express-validator';
import { authMiddleware, JwtPayload } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { pgPool } from '../config/database';

const router = Router();

/** 所有 location 端点都需要登录 */
router.use(authMiddleware);

// ============================================================
//  内存存储（数据库不可用时的降级方案）
// ============================================================

interface TrackPoint {
  lng: number;
  lat: number;
  accuracy: number;
  speed: number;
  timestamp: number; // epoch ms
}

interface UserTrack {
  userId: string;
  points: TrackPoint[];
}

/** 用户实时位置（key=userId） */
const liveLocations = new Map<string, { lng: number; lat: number; accuracy: number; speed: number; timestamp: number; name: string }>();

/** 历史轨迹（key=userId, 按时间排序）— 内存降级 */
const trackStore = new Map<string, TrackPoint[]>();

function addTrackPoint(userId: string, pt: TrackPoint) {
  let points = trackStore.get(userId);
  if (!points) {
    points = [];
    trackStore.set(userId, points);
  }
  points.push(pt);
  if (points.length > 10000) {
    points.splice(0, points.length - 10000);
  }
}

function getTrackPoints(userId: string, startMs: number, endMs: number): TrackPoint[] {
  const points = trackStore.get(userId) || [];
  return points.filter(p => p.timestamp >= startMs && p.timestamp <= endMs);
}

// ============================================================
//  单点上报 — POST /api/v1/location/report
// ============================================================
router.post('/report',
  validate([
    body('lng').exists().isFloat({ min: -180, max: 180 }),
    body('lat').exists().isFloat({ min: -85.05, max: 85.05 }),
  ]),
  async (req: Request, res: Response) => {
    const user = (req as any).user as JwtPayload;
    const { lng, lat, accuracy, speed, timestamp } = req.body;
    const ts = timestamp || Date.now();

    // 更新实时位置（始终写入内存）
    liveLocations.set(user.userId, {
      lng, lat,
      accuracy: accuracy || 0,
      speed: speed || 0,
      timestamp: ts,
      name: user.phone,
    });

    // 写入内存（降级备份）
    addTrackPoint(user.userId, { lng, lat, accuracy: accuracy || 0, speed: speed || 0, timestamp: ts });

    // 写入 PostgreSQL（主存储）
    try {
      await pgPool.query(
        `INSERT INTO location_records (user_id, lng, lat, accuracy, speed, recorded_at, provider)
         VALUES ($1, $2, $3, $4, $5, to_timestamp($6::double precision / 1000), 'gps')`,
        [user.userId, lng, lat, accuracy || 0, speed || 0, ts]
      );
    } catch (_dbErr) {
      // 数据库不可用时降级到内存
    }

    res.status(201).json({
      success: true,
      points: (trackStore.get(user.userId) || []).length,
    });
  },
);

// ============================================================
//  批量上报 — POST /api/v1/location/batch
// ============================================================
router.post('/batch',
  validate([
    body('points').isArray({ min: 1 }),
    body('points.*.lng').isFloat({ min: -180, max: 180 }),
    body('points.*.lat').isFloat({ min: -85.05, max: 85.05 }),
  ]),
  async (req: Request, res: Response) => {
    const user = (req as any).user as JwtPayload;
    const points = req.body.points as Array<{ lng: number; lat: number; accuracy?: number; speed?: number; timestamp?: number }>;

    const dbValues: any[][] = [];
    for (const pt of points) {
      const ts = pt.timestamp || Date.now();
      // 内存
      addTrackPoint(user.userId, {
        lng: pt.lng, lat: pt.lat,
        accuracy: pt.accuracy || 0, speed: pt.speed || 0,
        timestamp: ts,
      });
      // 数据库批量
      dbValues.push([user.userId, pt.lng, pt.lat, pt.accuracy || 0, pt.speed || 0, ts]);
    }

    // 批量写入数据库
    try {
      const placeholders = dbValues.map((_, i) =>
        `($${i * 6 + 1}, $${i * 6 + 2}, $${i * 6 + 3}, $${i * 6 + 4}, $${i * 6 + 5}, to_timestamp($${i * 6 + 6}::double precision / 1000))`
      ).join(', ');
      const flatValues = dbValues.flat();
      await pgPool.query(
        `INSERT INTO location_records (user_id, lng, lat, accuracy, speed, recorded_at) VALUES ${placeholders}`,
        flatValues
      );
    } catch (_dbErr) {
      // 数据库不可用时降级
    }

    // 更新实时位置（最后一点）
    const last = points[points.length - 1];
    liveLocations.set(user.userId, {
      lng: last.lng, lat: last.lat,
      accuracy: last.accuracy || 0, speed: last.speed || 0,
      timestamp: last.timestamp || Date.now(),
      name: user.phone,
    });

    res.json({ success: true, count: points.length });
  },
);

// ============================================================
//  获取所有在线人员实时位置 — GET /api/v1/location/batch
// ============================================================
router.get('/batch',
  async (_req: Request, res: Response) => {
    const now = Date.now();
    const users: any[] = [];
    for (const [userId, loc] of liveLocations.entries()) {
      if (now - loc.timestamp < 5 * 60 * 1000) {
        users.push({ userId, name: loc.name, lng: loc.lng, lat: loc.lat, accuracy: loc.accuracy, speed: loc.speed, timestamp: loc.timestamp });
      }
    }
    res.json({ users, total: users.length });
  },
);

// ============================================================
//  获取历史轨迹 — GET /api/v1/location/track/:userId
// ============================================================
router.get('/track/:userId',
  validate([
    query('date').optional().matches(/^\d{4}-\d{2}-\d{2}$/).withMessage('日期格式无效(YYYY-MM-DD)'),
  ]),
  async (req: Request, res: Response) => {
    const user = (req as any).user as JwtPayload;
    const targetUserId = req.params.userId;

    if (user.role === 'employee' && targetUserId !== user.userId) {
      return res.status(403).json({ code: '10009', message: '无权限访问' });
    }

    const date = (req.query.date as string) || new Date().toISOString().split('T')[0];
    const startMs = new Date(`${date}T00:00:00+08:00`).getTime();
    const endMs = new Date(`${date}T23:59:59.999+08:00`).getTime();

    let all: TrackPoint[] = [];

    // 1. 优先从数据库读取
    try {
      const result = await pgPool.query(
        `SELECT lng, lat, accuracy, speed,
                EXTRACT(EPOCH FROM recorded_at)::bigint * 1000 as timestamp
         FROM location_records
         WHERE user_id = $1 AND recorded_at >= to_timestamp($2::double precision / 1000)
           AND recorded_at <= to_timestamp($3::double precision / 1000)
         ORDER BY recorded_at ASC`,
        [targetUserId, startMs, endMs]
      );
      all = result.rows.map(r => ({
        lng: parseFloat(r.lng),
        lat: parseFloat(r.lat),
        accuracy: parseFloat(r.accuracy) || 0,
        speed: parseFloat(r.speed) || 0,
        timestamp: parseInt(r.timestamp),
      }));
    } catch (_dbErr) {
      // 数据库不可用时，从内存读取
      all = getTrackPoints(targetUserId, startMs, endMs);
    }

    // 2. 合并打卡数据（作为补充）
    try {
      const { getMemAttendanceRecords } = require('./attendance');
      const memRecords = getMemAttendanceRecords(targetUserId);
      const checkInPoints = memRecords
        .filter((r: any) => {
          const t = new Date(r.check_time).getTime();
          return t >= startMs && t <= endMs;
        })
        .map((r: any) => ({
          lng: r.lng,
          lat: r.lat,
          accuracy: 0,
          speed: 0,
          timestamp: new Date(r.check_time).getTime(),
        }));
      all = [...all, ...checkInPoints];
    } catch (_e) { /* ignore */ }

    // 按时间排序
    all.sort((a, b) => a.timestamp - b.timestamp);

    res.json({
      userId: targetUserId,
      date,
      points: all,
      source: all.length > 0 ? 'database' : 'memory',
    });
  },
);

// ============================================================
//  获取当前登录用户实时位置 — GET /api/v1/location/current
// ============================================================
router.get('/current',
  async (req: Request, res: Response) => {
    const user = (req as any).user as JwtPayload;
    const loc = liveLocations.get(user.userId);
    if (!loc) {
      return res.status(404).json({ code: '10014', message: '暂无位置信息' });
    }
    res.json({ userId: user.userId, ...loc });
  },
);

// ============================================================
//  获取指定用户实时位置 — GET /api/v1/location/current/:userId
// ============================================================
router.get('/current/:userId',
  async (req: Request, res: Response) => {
    const loc = liveLocations.get(req.params.userId);
    if (!loc) {
      return res.status(404).json({ code: '10014', message: '暂无位置信息' });
    }
    res.json({ userId: req.params.userId, ...loc });
  },
);

export default router;

// ============================================================
//  逆地理编码 — GET /api/v1/location/reverse-geocode
// ============================================================
router.get('/reverse-geocode',
  async (req: Request, res: Response) => {
    const lat = req.query.lat as string;
    const lng = req.query.lng as string;
    res.json({
      address: `${lat}, ${lng}`,
      lat: parseFloat(lat || '0'),
      lng: parseFloat(lng || '0'),
    });
  },
);
