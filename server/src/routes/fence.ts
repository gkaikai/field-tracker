import { Router, Request, Response } from 'express';
import { body, query } from 'express-validator';
import { authMiddleware, adminMiddleware, roleMiddleware, JwtPayload } from '../middleware/auth';
import { validate } from '../middleware/validate';

const router = Router();
router.use(authMiddleware);

// ============================================================
//  内存存储
// ============================================================

interface Fence {
  id: number;
  name: string;
  departmentId: string | null;
  shapeType: string;
  centerLat: number | null;
  centerLng: number | null;
  radiusMeters: number | null;
  coordinates: any[] | null;
  isActive: boolean;
  createdBy: string;
  createdAt: string;
}

let memFences: Fence[] = [];
let memFenceIdSeq = 1;

// 围栏事件
interface FenceEvent {
  id: number;
  userId: string;
  fenceId: number;
  fenceName: string;
  eventType: 'enter' | 'exit';
  lat: number;
  lng: number;
  createdAt: string;
}
let memFenceEvents: FenceEvent[] = [];
let memEventIdSeq = 1;

// ============================================================
//  GET 路由
// ============================================================

// GET /api/v1/fences — 围栏列表（管理员看全部，员工看本部门/未绑定的）
router.get('/', async (req: Request, res: Response) => {
  const user = (req as any).user as JwtPayload;
  let fences = memFences.filter(f => f.isActive);
  
  // 非管理员只看自己部门的 + 未绑定部门的公共围栏
  if (user.role !== 'admin') {
    fences = fences.filter(f => 
      !f.departmentId || f.departmentId === user.departmentId
    );
  }
  
  res.json(fences);
});

// GET /api/v1/fences/check — 检测位置是否在围栏内
router.get('/check',
  validate([
    query('lat').isFloat(),
    query('lng').isFloat(),
    query('fenceId').optional().isInt(),
  ]),
  async (req: Request, res: Response) => {
    const lat = parseFloat(req.query.lat as string);
    const lng = parseFloat(req.query.lng as string);
    const fenceId = req.query.fenceId ? parseInt(req.query.fenceId as string) : null;

    let fences = memFences.filter(f => f.isActive);
    if (fenceId) fences = fences.filter(f => f.id === fenceId);

    const results = fences.map(fence => {
      let inside = false;
      if (fence.shapeType === 'circle' && fence.centerLat && fence.centerLng) {
        inside = haversineDistance(lat, lng, fence.centerLat, fence.centerLng) <= (fence.radiusMeters || 300);
      } else if (fence.shapeType === 'polygon' && fence.coordinates && fence.coordinates.length >= 3) {
        inside = pointInPolygon(lat, lng, fence.coordinates);
      }
      return { fenceId: fence.id, name: fence.name, inside };
    });

    res.json({ lat, lng, results });
  },
);

// GET /api/v1/fences/events — 围栏事件
router.get('/events', async (req: Request, res: Response) => {
  const user = (req as any).user as JwtPayload;
  let events = memFenceEvents.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()).slice(0, 200);
  
  // 管理员看所有事件，员工只看自己的
  if (user.role !== 'admin') {
    events = events.filter(e => e.userId === user.userId);
  }
  
  res.json({ events, total: events.length });
});

// GET /api/v1/fences/:id — 单个围栏
router.get('/:id', async (req: Request, res: Response) => {
  const fence = memFences.find(f => f.id === parseInt(req.params.id));
  if (!fence) return res.status(404).json({ code: '10014', message: '围栏不存在' });
  res.json(fence);
});

// ============================================================
//  管理员路由（需要admin角色）
// ============================================================

// POST /api/v1/fences — 创建围栏（仅管理员）
router.post('/',
  adminMiddleware,
  validate([
    body('name').notEmpty().withMessage('围栏名称不能为空'),
    body('shapeType').isIn(['circle', 'polygon']),
    body('centerLat').optional().isFloat(),
    body('centerLng').optional().isFloat(),
    body('radiusMeters').optional().isFloat({ min: 10, max: 10000 }),
  ]),
  async (req: Request, res: Response) => {
    const user = (req as any).user as JwtPayload;
    const { name, departmentId, shapeType, centerLat, centerLng, radiusMeters, coordinates } = req.body;
    const fence: Fence = {
      id: memFenceIdSeq++, name, departmentId: departmentId || null, shapeType,
      centerLat: centerLat || null, centerLng: centerLng || null, radiusMeters: radiusMeters || 300,
      coordinates: coordinates || null, isActive: true, createdBy: user.userId,
      createdAt: new Date().toISOString(),
    };
    memFences.push(fence);
    res.status(201).json(fence);
  },
);

// PUT /api/v1/fences/:id — 更新围栏（仅管理员）
router.put('/:id', adminMiddleware, async (req: Request, res: Response) => {
  const idx = memFences.findIndex(f => f.id === parseInt(req.params.id));
  if (idx === -1) return res.status(404).json({ code: '10014', message: '围栏不存在' });
  memFences[idx] = { ...memFences[idx], ...req.body, id: memFences[idx].id };
  res.json(memFences[idx]);
});

// DELETE /api/v1/fences/:id — 删除围栏（仅管理员）
router.delete('/:id', adminMiddleware, async (req: Request, res: Response) => {
  const idx = memFences.findIndex(f => f.id === parseInt(req.params.id));
  if (idx === -1) return res.status(404).json({ code: '10014', message: '围栏不存在' });
  memFences[idx].isActive = false;
  res.json({ success: true });
});

// POST /api/v1/fences/event — 记录围栏事件（内部/系统调用）
router.post('/event',
  validate([
    body('fenceId').isInt(),
    body('eventType').isIn(['enter', 'exit']),
    body('lat').isFloat(), body('lng').isFloat(),
  ]),
  async (req: Request, res: Response) => {
    const user = (req as any).user as JwtPayload;
    const { fenceId, eventType, lat, lng } = req.body;
    const fence = memFences.find(f => f.id === fenceId);
    const event: FenceEvent = {
      id: memEventIdSeq++, userId: user.userId, fenceId,
      fenceName: fence?.name || '未知围栏', eventType, lat, lng,
      createdAt: new Date().toISOString(),
    };
    memFenceEvents.push(event);
    res.status(201).json(event);
  },
);

// POST /api/v1/fences/auto-check — 定位上报时自动检测围栏
router.post('/auto-check', async (req: Request, res: Response) => {
  const user = (req as any).user as JwtPayload;
  const { lat, lng } = req.body;
  if (lat === undefined || lng === undefined) {
    return res.json({ events: [] });
  }

  // 检查所有活跃围栏
  const events: { fenceId: number; fenceName: string; eventType: 'enter' | 'exit'; lat: number; lng: number }[] = [];
  
  for (const fence of memFences) {
    if (!fence.isActive) continue;
    // 部门权限过滤
    if (fence.departmentId && fence.departmentId !== user.departmentId) continue;
    
    let inside = false;
    if (fence.shapeType === 'circle' && fence.centerLat && fence.centerLng) {
      inside = haversineDistance(lat, lng, fence.centerLat, fence.centerLng) <= (fence.radiusMeters || 300);
    } else if (fence.shapeType === 'polygon' && fence.coordinates && fence.coordinates.length >= 3) {
      inside = pointInPolygon(lat, lng, fence.coordinates);
    }

    // 查找最近一次该用户对该围栏的事件
    const lastEvent = [...memFenceEvents].reverse().find(e => e.userId === user.userId && e.fenceId === fence.id);
    const lastWasInside = lastEvent?.eventType === 'enter';

    // 状态变化时才触发事件
    if (inside && !lastWasInside) {
      memFenceEvents.push({
        id: memEventIdSeq++, userId: user.userId, fenceId: fence.id,
        fenceName: fence.name, eventType: 'enter', lat, lng,
        createdAt: new Date().toISOString(),
      });
      events.push({ fenceId: fence.id, fenceName: fence.name, eventType: 'enter', lat, lng });
    } else if (!inside && lastWasInside) {
      memFenceEvents.push({
        id: memEventIdSeq++, userId: user.userId, fenceId: fence.id,
        fenceName: fence.name, eventType: 'exit', lat, lng,
        createdAt: new Date().toISOString(),
      });
      events.push({ fenceId: fence.id, fenceName: fence.name, eventType: 'exit', lat, lng });
    }
  }

  res.json({ events, count: events.length });
});

// ============================================================
//  辅助函数
// ============================================================

function haversineDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function toRad(deg: number) { return deg * Math.PI / 180; }

/** 射线法判断点是否在多边形内 (Point-in-Polygon)
 *  coordinates: [{lat, lng}, ...] 多边形折点数组，至少3个点
 *  返回 true = 点在多边形内部
 */
function pointInPolygon(lat: number, lng: number, coordinates: any[]): boolean {
  let inside = false;
  const n = coordinates.length;
  for (let i = 0, j = n - 1; i < n; j = i++) {
    const ci = coordinates[i];
    const cj = coordinates[j];
    const latI = typeof ci === 'object' ? (ci.lat ?? ci.latitude ?? parseFloat(ci[0] ?? ci[1])) : 0;
    const lngI = typeof ci === 'object' ? (ci.lng ?? ci.longitude ?? parseFloat(ci[1] ?? ci[0])) : 0;
    const latJ = typeof cj === 'object' ? (cj.lat ?? cj.latitude ?? parseFloat(cj[0] ?? cj[1])) : 0;
    const lngJ = typeof cj === 'object' ? (cj.lng ?? cj.longitude ?? parseFloat(cj[1] ?? cj[0])) : 0;
    
    if ((lngI > lng) !== (lngJ > lng) && lat < ((latJ - latI) * (lng - lngI) / (lngJ - lngI)) + latI) {
      inside = !inside;
    }
  }
  return inside;
}

export default router;
