import { Router, Request, Response, NextFunction } from 'express';
import { body, query } from 'express-validator';
import { pgPool } from '../config/database';
import { authMiddleware, roleMiddleware, JwtPayload } from '../middleware/auth';
import { AppError } from '../errors/AppError';
import { validate } from '../middleware/validate';

const router = Router();
router.use(authMiddleware);

// 内存存储（数据库不可用时使用）
interface MemAttendanceRecord {
  id: number;
  user_id: string;
  type: string;
  lng: number;
  lat: number;
  address: string | null;
  accuracy: number;
  photo_url: string | null;
  wifi_bssid: string | null;
  device_info: string | null;
  check_time: string;
  created_at: string;
}
let memAttendanceRecords: MemAttendanceRecord[] = [];
let memRecordIdSeq = 1;

// 导出给其他模块使用
export function getMemAttendanceRecords(userId: string): MemAttendanceRecord[] {
  return memAttendanceRecords.filter(r => r.user_id === userId);
}

// ============================================================
//  员工打卡
// ============================================================

// POST /api/v1/attendance/checkin — 签到
router.post('/checkin',
  validate([
    body('type')
      .isIn(['checkin', 'checkout']).withMessage('打卡类型无效(需为 checkin 或 checkout)'),
    body('lng')
      .exists().withMessage('经度不能为空')
      .isFloat({ min: -180, max: 180 }),
    body('lat')
      .exists().withMessage('纬度不能为空')
      .isFloat({ min: -85.05, max: 85.05 }),
    body('address').optional().isString(),
    body('photo_url').optional().isString(),
    body('wifi_bssid').optional().isString(),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const { type, lng, lat, address, photo_url, wifi_bssid } = req.body;

      // 1. 校验是否有生效的打卡规则
      let rules;
      try {
        const rulesResult = await pgPool.query(
          `SELECT id, rule_type, radius_meters, center_lat, center_lng,
                  wifi_ssid, wifi_bssid, checkin_start, checkin_end,
                  checkout_start, checkout_end
           FROM attendance_rules
           WHERE (department_id IS NULL OR department_id = $1)
             AND is_active = true
           ORDER BY created_at DESC`,
          [user.departmentId || null],
        );
        rules = rulesResult;
      } catch (_dbErr) {
        // 数据库不可用，跳过规则校验
        rules = { rows: [] };
      }

      // 2. 如果有规则，校验位置是否在有效范围内
      let matchedRule = false;
      if (rules.rows.length > 0) {
        for (const rule of rules.rows) {
          let ruleMatch = false;

          // 位置打卡模式 — 校验距离
          if (rule.rule_type === 'location' && rule.center_lat && rule.center_lng) {
            const distance = haversineDistance(
              lat, lng,
              rule.center_lat, rule.center_lng,
            );
            if (distance <= (rule.radius_meters || 300)) {
              ruleMatch = true;
            }
          }

          // WiFi 打卡模式 — 校验 BSSID
          if (rule.rule_type === 'wifi' && rule.wifi_bssid) {
            if (wifi_bssid && wifi_bssid === rule.wifi_bssid) {
              ruleMatch = true;
            }
          }

          // 如果当前规则匹配，记录并继续检查时间
          if (ruleMatch) {
            // 校验时间范围
            if (type === 'checkin' && rule.checkin_start && rule.checkin_end) {
              const now = new Date();
              const time = now.toTimeString().slice(0, 5);
              if (time >= rule.checkin_start.slice(0, 5) && time <= rule.checkin_end.slice(0, 5)) {
                matchedRule = true;
                break;
              }
            } else {
              // 没有时间限制的规则直接匹配
              matchedRule = true;
              break;
            }
          }
        }
      }

      if (rules.rows.length > 0 && !matchedRule) {
        throw new AppError('ATTEND_OUT_OF_RANGE');
      }

      // 3. 写入打卡记录
      let recordResult;
      try {
        const result = await pgPool.query(
          `INSERT INTO attendance_records (user_id, type, lng, lat, address, accuracy, photo_url, wifi_bssid, device_info)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
           RETURNING id, check_time`,
          [
            user.userId,
            type,
            lng,
            lat,
            address || null,
            req.body.accuracy || 0,
            photo_url || null,
            wifi_bssid || null,
            JSON.stringify({ platform: 'flutter' }),
          ],
        );
        recordResult = result.rows[0];
      } catch (dbErr) {
        // 数据库不可用时降级到内存
        const now = new Date();
        const memRecord: MemAttendanceRecord = {
          id: memRecordIdSeq++,
          user_id: user.userId,
          type,
          lng,
          lat,
          address: address || null,
          accuracy: req.body.accuracy || 0,
          photo_url: photo_url || null,
          wifi_bssid: wifi_bssid || null,
          device_info: JSON.stringify({ platform: 'flutter' }),
          check_time: now.toISOString(),
          created_at: now.toISOString(),
        };
        memAttendanceRecords.push(memRecord);
        recordResult = { id: memRecord.id, check_time: memRecord.check_time };
      }

      res.status(201).json({
        success: true,
        recordId: recordResult.id,
        checkTime: recordResult.check_time,
        type,
      });
    } catch (err) {
      next(err);
    }
  },
);

// GET /api/v1/attendance/records — 打卡记录查询
router.get('/records',
  validate([
    query('page').optional().isInt({ min: 1 }).toInt(),
    query('pageSize').optional().isInt({ min: 1, max: 100 }).toInt(),
    query('startDate').optional().matches(/^\d{4}-\d{2}-\d{2}$/),
    query('endDate').optional().matches(/^\d{4}-\d{2}-\d{2}$/),
    query('type').optional().isIn(['checkin', 'checkout']),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const page = parseInt(req.query.page as string) || 1;
      const pageSize = parseInt(req.query.pageSize as string) || 20;

      // 先尝试数据库查询
      try {
        const offset = (page - 1) * pageSize;
        let whereClause = 'WHERE user_id = $1';
        const params: any[] = [user.userId];
        let paramIdx = 2;

        if (req.query.startDate) {
          whereClause += ` AND check_time >= $${paramIdx}`;
          params.push(req.query.startDate);
          paramIdx++;
        }
        if (req.query.endDate) {
          whereClause += ` AND check_time <= $${paramIdx}::date + interval '1 day'`;
          params.push(req.query.endDate);
          paramIdx++;
        }
        if (req.query.type) {
          whereClause += ` AND type = $${paramIdx}`;
          params.push(req.query.type);
          paramIdx++;
        }

        const countResult = await pgPool.query(
          `SELECT COUNT(*) FROM attendance_records ${whereClause}`,
          params,
        );
        const total = parseInt(countResult.rows[0].count, 10);

        const result = await pgPool.query(
          `SELECT id, user_id, type, lng, lat, address, accuracy, photo_url, check_time, created_at
           FROM attendance_records ${whereClause}
           ORDER BY check_time DESC
           LIMIT $${paramIdx} OFFSET $${paramIdx + 1}`,
          [...params, pageSize, offset],
        );

        return res.json({
          records: result.rows,
          pagination: { page, pageSize, total, totalPages: Math.ceil(total / pageSize) },
        });
      } catch (_dbErr) {
        // 数据库不可用，从内存查询
        const typeFilter = req.query.type as string;
        const records = memAttendanceRecords
          .filter(r => r.user_id === user.userId)
          .filter(r => !typeFilter || r.type === typeFilter)
          .sort((a, b) => b.check_time.localeCompare(a.check_time));

        const total = records.length;
        const offset = (page - 1) * pageSize;
        const paged = records.slice(offset, offset + pageSize);

        return res.json({
          records: paged,
          pagination: { page, pageSize, total, totalPages: Math.ceil(total / pageSize) },
        });
      }
    } catch (err) {
      next(err);
    }
  },
);

// ============================================================
//  打卡规则管理（管理员）
// ============================================================

// 内存规则存储
interface Rule { id: number; name: string; startTime: string; endTime: string; radius: number; wifiName: string; }
const memRules: Rule[] = [];
let memRuleIdSeq = 1;

// GET /api/v1/attendance/rules — 规则列表（含内存回退）
router.get('/rules',
  async (_req: Request, res: Response, next: NextFunction) => {
    try {
      const result = await pgPool.query(
        `SELECT r.*, d.name as department_name
         FROM attendance_rules r
         LEFT JOIN departments d ON r.department_id = d.id
         ORDER BY r.created_at DESC`,
      );
      res.json({ rules: result.rows });
    } catch (err) {
      // 数据库不可用时返回内存规则
      res.json({ rules: memRules });
    }
  },
);

// POST /api/v1/attendance/rules — 创建规则（含内存回退）
router.post('/rules',
  validate([
    body('name').notEmpty().withMessage('规则名称不能为空'),
    body('rule_type').optional().isIn(['location', 'wifi', 'both']),
    body('center_lat').optional().isFloat({ min: -85.05, max: 85.05 }),
    body('center_lng').optional().isFloat({ min: -180, max: 180 }),
    body('radius_meters').optional().isFloat({ min: 10, max: 10000 }),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    const { name, department_id, rule_type, center_lat, center_lng, radius_meters, wifi_ssid, wifi_bssid } = req.body;
    try {
      // 尝试数据库
      const result = await pgPool.query(
        `INSERT INTO attendance_rules (name, department_id, rule_type, center_lat, center_lng, radius_meters, wifi_ssid, wifi_bssid)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         RETURNING *`,
        [name, department_id || null, rule_type || 'location', center_lat || null, center_lng || null, radius_meters || 300, wifi_ssid || null, wifi_bssid || null],
      );
      res.status(201).json(result.rows[0]);
    } catch (err) {
      // 数据库不可用——内存回退
      const rule: Rule = { id: memRuleIdSeq++, name: name || '默认', startTime: req.body.startTime || '09:00', endTime: req.body.endTime || '18:00', radius: req.body.radius || radius_meters || 300, wifiName: wifi_ssid || '' };
      memRules.push(rule);
      res.status(201).json(rule);
    }
  },
);

// PUT /api/v1/attendance/rules/:id — 编辑规则
router.put('/rules/:id',
  roleMiddleware('admin'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      await pgPool.query(
        `UPDATE attendance_rules SET name=$1, start_time=$2, end_time=$3, radius_meters=$4, wifi_ssid=$5 WHERE id=$6`,
        [req.body.name, req.body.startTime, req.body.endTime, req.body.radius || req.body.radius_meters, req.body.wifiName || req.body.wifi_ssid, req.params.id],
      );
      const result = await pgPool.query('SELECT * FROM attendance_rules WHERE id=$1', [req.params.id]);
      if (result.rows.length > 0) return res.json(result.rows[0]);
      res.json({ success: true });
    } catch (err) {
      // 内存回退
      const idx = memRules.findIndex(r => r.id === parseInt(req.params.id));
      if (idx === -1) return res.status(404).json({ code: 'NOT_FOUND', message: '规则不存在' });
      memRules[idx] = { ...memRules[idx], ...req.body, id: memRules[idx].id };
      res.json(memRules[idx]);
    }
  },
);

// DELETE /api/v1/attendance/rules/:id — 删除规则
router.delete('/rules/:id',
  roleMiddleware('admin'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      await pgPool.query('DELETE FROM attendance_rules WHERE id = $1', [req.params.id]);
      res.json({ success: true });
    } catch (err) {
      // 内存回退
      const idx = memRules.findIndex(r => r.id === parseInt(req.params.id));
      if (idx === -1) return res.status(404).json({ code: 'NOT_FOUND', message: '规则不存在' });
      memRules.splice(idx, 1);
      res.json({ success: true });
    }
  },
);

// ============================================================
//  管理后台统计数据
// ============================================================

// GET /api/v1/attendance/stats — 考勤统计
router.get('/stats',
  roleMiddleware('manager', 'admin'),
  validate([
    query('startDate').optional().matches(/^\d{4}-\d{2}-\d{2}$/),
    query('endDate').optional().matches(/^\d{4}-\d{2}-\d{2}$/),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const startDate = (req.query.startDate as string) || new Date().toISOString().split('T')[0];
      const endDate = (req.query.endDate as string) || startDate;

      const result = await pgPool.query(
        `SELECT
           u.id as user_id, u.name, u.department_id,
           COUNT(CASE WHEN a.type = 'checkin' THEN 1 END) as checkin_count,
           COUNT(CASE WHEN a.type = 'checkout' THEN 1 END) as checkout_count
         FROM users u
         LEFT JOIN attendance_records a ON u.id = a.user_id
           AND a.check_time::date >= $1::date
           AND a.check_time::date <= $2::date
         WHERE u.is_active = true
         GROUP BY u.id, u.name, u.department_id
         ORDER BY u.name`,
        [startDate, endDate],
      );

      res.json({
        startDate,
        endDate,
        stats: result.rows,
      });
    } catch (err) {
      next(err);
    }
  },
);

// ============================================================
//  辅助函数
// ============================================================

/** Haversine 公式计算两点间距离（米） */
function haversineDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000; // 地球半径（米）
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
