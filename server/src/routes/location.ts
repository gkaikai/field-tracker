import { Router, Request, Response, NextFunction } from 'express';
import { body, query } from 'express-validator';
import { authMiddleware, JwtPayload } from '../middleware/auth';
import { validate } from '../middleware/validate';

const router = Router();

/** 所有 location 端点都需要登录 */
router.use(authMiddleware);

// ============================================================
//  内存存储（代替 Redis + PostgreSQL）
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

/** 历史轨迹（key=userId, 按时间排序） */
const trackStore = new Map<string, TrackPoint[]>();

function addTrackPoint(userId: string, pt: TrackPoint) {
  let points = trackStore.get(userId);
  if (!points) {
    points = [];
    trackStore.set(userId, points);
  }
  points.push(pt);
  // 限制内存中最多保留 10000 个点
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
    body('lng')
      .exists().withMessage('经度不能为空')
      .isFloat({ min: -180, max: 180 }).withMessage('经度超出有效范围(-180~180)'),
    body('lat')
      .exists().withMessage('纬度不能为空')
      .isFloat({ min: -85.05, max: 85.05 }).withMessage('纬度超出有效范围(-85~85)'),
  ]),
  async (req: Request, res: Response) => {
    const user = (req as any).user as JwtPayload;
    const { lng, lat, accuracy, speed, timestamp } = req.body;
    const ts = timestamp || Date.now();

    // 更新实时位置
    liveLocations.set(user.userId, {
      lng, lat,
      accuracy: accuracy || 0,
      speed: speed || 0,
      timestamp: ts,
      name: user.phone,
    });

    // 写入历史轨迹
    addTrackPoint(user.userId, {
      lng, lat,
      accuracy: accuracy || 0,
      speed: speed || 0,
      timestamp: ts,
    });

    res.status(201).json({ success: true, points: (trackStore.get(user.userId) || []).length });
  },
);

// ============================================================
//  批量上报 — POST /api/v1/location/batch
// ============================================================
router.post('/batch',
  validate([
    body('points')
      .isArray({ min: 1 }).withMessage('批量位置数据不能为空'),
    body('points.*.lng')
      .isFloat({ min: -180, max: 180 }).withMessage('存在无效经度'),
    body('points.*.lat')
      .isFloat({ min: -85.05, max: 85.05 }).withMessage('存在无效纬度'),
  ]),
  async (req: Request, res: Response) => {
    const user = (req as any).user as JwtPayload;
    const points = req.body.points as Array<{ lng: number; lat: number; accuracy?: number; speed?: number; timestamp?: number }>;

    for (const pt of points) {
      addTrackPoint(user.userId, {
        lng: pt.lng,
        lat: pt.lat,
        accuracy: pt.accuracy || 0,
        speed: pt.speed || 0,
        timestamp: pt.timestamp || Date.now(),
      });
    }

    // 更新实时位置（最后一点）
    const last = points[points.length - 1];
    liveLocations.set(user.userId, {
      lng: last.lng,
      lat: last.lat,
      accuracy: last.accuracy || 0,
      speed: last.speed || 0,
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
      // 5分钟内算在线
      if (now - loc.timestamp < 5 * 60 * 1000) {
        users.push({
          userId,
          name: loc.name,
          lng: loc.lng,
          lat: loc.lat,
          accuracy: loc.accuracy,
          speed: loc.speed,
          timestamp: loc.timestamp,
        });
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
    query('date')
      .optional()
      .matches(/^\d{4}-\d{2}-\d{2}$/).withMessage('日期格式无效(YYYY-MM-DD)'),
  ]),
  async (req: Request, res: Response) => {
    const user = (req as any).user as JwtPayload;
    const targetUserId = req.params.userId;

    // 非管理员/经理只能查自己
    if (user.role === 'employee' && targetUserId !== user.userId) {
      return res.status(403).json({ code: '10009', message: '无权限访问' });
    }

    const date = (req.query.date as string) || new Date().toISOString().split('T')[0];
    const startMs = new Date(`${date}T00:00:00+08:00`).getTime();
    const endMs = new Date(`${date}T23:59:59.999+08:00`).getTime();

    // 从内存读取
    const points = getTrackPoints(targetUserId, startMs, endMs);

    // 同时从打卡内存中获取位置
    let checkInPoints: TrackPoint[] = [];
    try {
      const { getMemAttendanceRecords } = require('./attendance');
      const memRecords = getMemAttendanceRecords(targetUserId);
      checkInPoints = memRecords
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
    } catch (_e) {
      // ignore
    }

    // 合并去重 + 按时间排序
    const all = [...points, ...checkInPoints];
    all.sort((a, b) => a.timestamp - b.timestamp);

    res.json({
      userId: targetUserId,
      date,
      points: all,
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
    res.json({
      userId: req.params.userId,
      ...loc,
    });
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
    // 简单返回坐标地址，后续可接高德逆地理API
    res.json({
      address: `${lat}, ${lng}`,
      lat: parseFloat(lat || '0'),
      lng: parseFloat(lng || '0'),
    });
  },
);
