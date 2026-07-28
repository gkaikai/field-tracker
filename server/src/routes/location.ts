import { Router, Request, Response, NextFunction } from 'express';
import { body, query } from 'express-validator';
import { authMiddleware, JwtPayload } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { pgPool } from '../config/database';
import { haversineKm } from '../utils/geo';
import { getMemAttendanceRecords } from '../shared/attendance_cache';

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
  async (req: Request, res: Response, next: NextFunction) => {
    try {
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
        console.warn('[DB] 定位单点写入失败（降级到内存）:', (_dbErr as Error).message);
      }

      res.status(201).json({
        success: true,
        points: (trackStore.get(user.userId) || []).length,
      });
    } catch (err) {
      next(err);
    }
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
  async (req: Request, res: Response, next: NextFunction) => {
    try {
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
        console.warn('[DB] 定位批量写入失败（降级到内存）:', (_dbErr as Error).message);
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
    } catch (err) {
      next(err);
    }
  },
);

// ============================================================
//  获取所有在线人员实时位置 — GET /api/v1/location/batch
// ============================================================
router.get('/batch',
  async (_req: Request, res: Response, next: NextFunction) => {
    try {
      const now = Date.now();
      const users: any[] = [];
      for (const [userId, loc] of liveLocations.entries()) {
        if (now - loc.timestamp < 5 * 60 * 1000) {
          users.push({ userId, name: loc.name, lng: loc.lng, lat: loc.lat, accuracy: loc.accuracy, speed: loc.speed, timestamp: loc.timestamp });
        }
      }
      res.json({ users, total: users.length });
    } catch (err) {
      next(err);
    }
  },
);

// ============================================================
//  获取历史轨迹 — GET /api/v1/location/track/:userId
// ============================================================
router.get('/track/:userId',
  validate([
    query('date').optional().matches(/^\d{4}-\d{2}-\d{2}$/).withMessage('日期格式无效(YYYY-MM-DD)'),
    query('since').optional().isNumeric().withMessage('since必须是数值时间戳(ms)'),
    query('limit').optional().isInt({ min: 1, max: 10000 }).withMessage('limit须在1-10000之间'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const targetUserId = req.params.userId === 'me' ? user.userId : req.params.userId;

      if (user.role === 'employee' && targetUserId !== user.userId) {
        return res.status(403).json({ code: '10009', message: '无权限访问' });
      }

      const date = (req.query.date as string) || new Date().toISOString().split('T')[0];
      const startMs = new Date(`${date}T00:00:00+08:00`).getTime();
      const endMs = new Date(`${date}T23:59:59.999+08:00`).getTime();
      const sinceMs = req.query.since ? parseInt(req.query.since as string) : startMs;
      const limit = Math.min(Math.max(parseInt(req.query.limit as string) || 1000, 1), 10000);

      // 如果 since 在 startMs 之前，回退到 startMs
      const queryStartMs = Math.max(sinceMs, startMs);

      let all: TrackPoint[] = [];

      // 1. 优先从数据库读取（增量：只读 since 之后的数据，用 > 避免重复最后一个点）
      try {
        const result = await pgPool.query(
          `SELECT lng, lat, accuracy, speed,
                  (EXTRACT(EPOCH FROM recorded_at) * 1000)::bigint as timestamp
           FROM location_records
           WHERE user_id = $1 AND recorded_at >= to_timestamp($2::double precision / 1000)
             AND recorded_at <= to_timestamp($3::double precision / 1000)
           ORDER BY recorded_at ASC
           LIMIT $4`,
          [targetUserId, queryStartMs, endMs, limit]
        );
        all = result.rows.map(r => ({
          lng: parseFloat(r.lng) || 0,
          lat: parseFloat(r.lat) || 0,
          accuracy: parseFloat(r.accuracy) || 0,
          speed: parseFloat(r.speed) || 0,
          timestamp: parseInt(r.timestamp),
        }));
      } catch (_dbErr) {
        // 数据库不可用时，从内存读取
        all = getTrackPoints(targetUserId, queryStartMs, endMs);
      }

      // 2. 合并打卡数据（作为补充，也按 since 过滤）
      try {
        const memRecords = getMemAttendanceRecords(targetUserId);
        const checkInPoints = memRecords
          .filter((r: any) => {
            const t = new Date(r.check_time).getTime();
            return t >= queryStartMs && t <= endMs;
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

      // 限制总条数（取当天最早limit条，后续靠增量补充）
      if (all.length > limit) {
        all = all.slice(0, limit);
      }

      // 3. 中值滤波：移除孤立漂移点和连续漂移段
      // 策略：标记所有疑似漂移点，再识别连续漂移段整段移除
      if (sinceMs === startMs && all.length > 3) {
        const MAX_DRIFT_KM = 1.5;
        const MAX_SKIP_KM = 2.5;

        // 第一遍：标记每个点是否疑似漂移
        const driftFlags = new Array(all.length).fill(false);
        for (let i = 1; i < all.length - 1; i++) {
          const prev = all[i - 1];
          const curr = all[i];
          const next = all[i + 1];
          const d1 = haversineKm(prev.lat, prev.lng, curr.lat, curr.lng);
          const d2 = haversineKm(curr.lat, curr.lng, next.lat, next.lng);
          const dSkip = haversineKm(prev.lat, prev.lng, next.lat, next.lng);
          // 孤立漂移点：距前后都远，但前后很近
          if (d1 > MAX_DRIFT_KM && d2 > MAX_DRIFT_KM && dSkip < MAX_SKIP_KM) {
            driftFlags[i] = true;
          }
        }

        // 第二遍：识别连续漂移段（2+个连续漂移点）
        // 如果从最近的好点绕过整段连续漂移点到下一个好点的直线距离
        // 远小于正常轨迹距离，则整段移除
        const filtered: TrackPoint[] = [all[0]];
        let lastGoodIdx = 0;
        for (let i = 1; i < all.length - 1; i++) {
          if (!driftFlags[i]) {
            // 好点，加入
            filtered.push(all[i]);
            lastGoodIdx = i;
          } else if (!driftFlags[i + 1]) {
            // 当前是漂移点但下一个是好点 → 单点漂移，跳过
            // 检查是否是连续漂移段末尾
            // 从 lastGoodIdx 到 i+1 的直线距离
            const segDist = haversineKm(
              all[lastGoodIdx].lat, all[lastGoodIdx].lng,
              all[i + 1].lat, all[i + 1].lng
            );
            if (segDist < MAX_SKIP_KM) {
              // 整段跳过（孤立小区间）
              lastGoodIdx = i;
            } else {
              // 漂移段太长，可能是实际移动，保留最后一个点
              filtered.push(all[i]);
              lastGoodIdx = i;
            }
          }
          // 否则：连续漂移中段，继续跳过（不push）
        }
        filtered.push(all[all.length - 1]);
        all = filtered;
      }

      // 4. 计算最新时间戳
      const latestTimestamp = all.length > 0 ? all[all.length - 1].timestamp : queryStartMs;

      res.json({
        userId: targetUserId,
        date,
        points: all,
        source: all.length > 0 ? 'database' : 'memory',
        latestTimestamp,
      });
    } catch (err) {
      next(err);
    }
  },
);

// ============================================================
//  获取当前登录用户实时位置 — GET /api/v1/location/current
// ============================================================
router.get('/current',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const loc = liveLocations.get(user.userId);
      if (!loc) {
        return res.status(404).json({ code: '10014', message: '暂无位置信息' });
      }
      res.json({ userId: user.userId, ...loc });
    } catch (err) {
      next(err);
    }
  },
);

// ============================================================
//  获取指定用户实时位置 — GET /api/v1/location/current/:userId
//  权限：管理员可查任意用户，普通用户只能查自己
// ============================================================
router.get('/current/:userId',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      // 非管理员只能查自己的位置
      if (user.role !== 'admin' && user.userId !== req.params.userId) {
        return res.status(403).json({ code: 'AUTH_FORBIDDEN', message: '无权查看他人位置' });
      }
      const loc = liveLocations.get(req.params.userId);
      if (!loc) {
        return res.status(404).json({ code: '10014', message: '暂无位置信息' });
      }
      res.json({ userId: req.params.userId, ...loc });
    } catch (err) {
      next(err);
    }
  },
);

export default router;

// ============================================================
//  逆地理编码 — GET /api/v1/location/reverse-geocode
// ============================================================
router.get('/reverse-geocode',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const lat = req.query.lat as string;
      const lng = req.query.lng as string;
      res.json({
        address: `${lat}, ${lng}`,
        lat: parseFloat(lat || '0'),
        lng: parseFloat(lng || '0'),
      });
    } catch (err) {
      next(err);
    }
  },
);
