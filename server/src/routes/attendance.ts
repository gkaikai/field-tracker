import { Router, Request, Response, NextFunction } from 'express';
import { body, query } from 'express-validator';
import { pgPool } from '../config/database';
import { authMiddleware, roleMiddleware, adminMiddleware, JwtPayload } from '../middleware/auth';
import { AppError } from '../errors/AppError';
import { ErrorCodes } from '../errors/errorCodes';
import { validate } from '../middleware/validate';
import { attendanceCache, MemAttendanceRecord, getMemAttendanceRecords } from '../shared/attendance_cache';

const router = Router();
router.use(authMiddleware);

// 内存存储（数据库不可用时使用）
// Interface and cache moved to ../shared/attendance_cache

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
      // 去重校验：今日是否已打过同类型卡
      try {
        const today = new Date().toISOString().split('T')[0];
        const dupCheck = await pgPool.query(
          `SELECT id FROM attendance_records WHERE user_id=$1 AND type=$2 AND check_time::date=$3::date LIMIT 1`,
          [user.userId, type, today],
        );
        if (dupCheck.rows.length > 0) {
          throw new AppError('ATTEND_DUPLICATE');
        }
      } catch (dupErr) {
        if (dupErr instanceof AppError) throw dupErr;
        // 数据库错误忽略，继续尝试打卡
      }

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
            // 校验时间范围 — 转为分钟数比较（支持跨天规则）
            if (type === 'checkin' && rule.checkin_start && rule.checkin_end) {
            const now = new Date();
            const nowMin = now.getHours() * 60 + now.getMinutes();
            const startParts = rule.checkin_start.split(':').map(Number);
            const endParts = rule.checkin_end.split(':').map(Number);
            const startMin = startParts[0] * 60 + (startParts[1] || 0);
            const endMin = endParts[0] * 60 + (endParts[1] || 0);
            // 跨天规则（结束时间小于开始时间，如 22:00-06:00）
            if (endMin < startMin) {
              if (nowMin >= startMin || nowMin <= endMin) {
                matchedRule = true;
                break;
              }
            } else if (nowMin >= startMin && nowMin <= endMin) {
              matchedRule = true;
              break;
            }
            } else if (type === 'checkout' && rule.checkout_start && rule.checkout_end) {
              const now = new Date();
              const nowMin = now.getHours() * 60 + now.getMinutes();
              const startParts = rule.checkout_start.split(':').map(Number);
              const endParts = rule.checkout_end.split(':').map(Number);
              const startMin = startParts[0] * 60 + (startParts[1] || 0);
              const endMin = endParts[0] * 60 + (endParts[1] || 0);
              // 跨天规则
              if (endMin < startMin) {
                if (nowMin >= startMin || nowMin <= endMin) {
                  matchedRule = true;
                  break;
                }
              } else if (nowMin >= startMin && nowMin <= endMin) {
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
          id: attendanceCache.nextId++,
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
        attendanceCache.records.push(memRecord);
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
      const page = Math.max(1, parseInt(req.query.page as string) || 1);
      const pageSize = Math.max(1, Math.min(100, parseInt(req.query.pageSize as string) || 20));

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
        const records = attendanceCache.records
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
interface Rule { id: number; name: string; checkin_start: string; checkin_end: string; late_time: string | null; radius_meters: number; center_lat: number | null; center_lng: number | null; wifi_ssid: string; }
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
      res.json({ rules: result.rows.map(r => ({
        ...r,
        startTime: r.checkin_start,
        endTime: r.checkin_end,
        // late_time 无值返回 null（不拿下班时间顶替；前端编辑弹窗有 09:30 默认兜底）
        lateTime: r.late_time || null,
        radius: r.radius_meters,
      })) });
    } catch (err) {
      // 数据库不可用时返回内存规则（同样映射 camelCase，保持与 DB 路径一致）
      res.json({ rules: memRules.map(r => ({
        ...r,
        startTime: r.checkin_start,
        endTime: r.checkin_end,
        lateTime: r.late_time || null,
        radius: r.radius_meters,
      })) });
    }
  },
);

// POST /api/v1/attendance/rules — 创建规则（仅管理员/经理）
router.post('/rules',
  roleMiddleware('admin', 'manager'),
  validate([
    body('name').notEmpty().withMessage('规则名称不能为空'),
    body('rule_type').optional().isIn(['location', 'wifi', 'both']),
    body('center_lat').optional().isFloat({ min: -85.05, max: 85.05 }),
    body('center_lng').optional().isFloat({ min: -180, max: 180 }),
    body('radius_meters').optional().isFloat({ min: 10, max: 10000 }),
    // 时间字段格式校验（🟠-1 修复：防止非法格式穿透到 PG 报错→误报404）
    body('startTime').optional().custom((v: any) => v === '' || /^([01]\d|2[0-3]):[0-5]\d(:\d{2})?$/.test(v)).withMessage('上班时间格式应为 HH:mm'),
    body('lateTime').optional().custom((v: any) => v === '' || /^([01]\d|2[0-3]):[0-5]\d(:\d{2})?$/.test(v)).withMessage('迟到时间格式应为 HH:mm'),
    body('endTime').optional().custom((v: any) => v === '' || /^([01]\d|2[0-3]):[0-5]\d(:\d{2})?$/.test(v)).withMessage('下班时间格式应为 HH:mm'),
    body('checkin_start').optional().custom((v: any) => v === '' || /^([01]\d|2[0-3]):[0-5]\d(:\d{2})?$/.test(v)).withMessage('上班时间格式应为 HH:mm'),
    body('checkin_end').optional().custom((v: any) => v === '' || /^([01]\d|2[0-3]):[0-5]\d(:\d{2})?$/.test(v)).withMessage('下班时间格式应为 HH:mm'),
    body('late_time').optional().custom((v: any) => v === '' || /^([01]\d|2[0-3]):[0-5]\d(:\d{2})?$/.test(v)).withMessage('迟到时间格式应为 HH:mm'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    const { name, department_id, rule_type, center_lat, center_lng, radius_meters, wifi_ssid, wifi_bssid } = req.body;
    try {
      // 尝试数据库
      const result = await pgPool.query(
        `INSERT INTO attendance_rules (name, department_id, rule_type, center_lat, center_lng, radius_meters, wifi_ssid, wifi_bssid, checkin_start, checkin_end, late_time)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
         RETURNING *`,
        [name, department_id || null, rule_type || 'location', center_lat || null, center_lng || null, radius_meters || req.body.radius || 300, wifi_ssid || null, wifi_bssid || null, req.body.checkin_start || req.body.startTime || null, req.body.checkin_end || req.body.endTime || null, req.body.late_time || req.body.lateTime || null],
      );
      res.status(201).json(result.rows[0]);
    } catch (err) {
      // 数据库不可用——内存回退
      const rule: Rule = { id: memRuleIdSeq++, name: name || '默认', checkin_start: req.body.checkin_start || req.body.startTime || '09:00', checkin_end: req.body.checkin_end || req.body.endTime || '18:00', late_time: req.body.late_time || req.body.lateTime || null, radius_meters: radius_meters || req.body.radius || 300, center_lat: center_lat || req.body.center_lat || null, center_lng: center_lng || req.body.center_lng || null, wifi_ssid: wifi_ssid || req.body.wifi_ssid || '' };
      memRules.push(rule);
      res.status(201).json(rule);
    }
  },
);

// PUT /api/v1/attendance/rules/:id — 编辑规则（管理员/经理）
router.put('/rules/:id',
  adminMiddleware,
  validate([
    body('startTime').optional().custom((v: any) => v === '' || /^([01]\d|2[0-3]):[0-5]\d(:\d{2})?$/.test(v)).withMessage('上班时间格式应为 HH:mm'),
    body('lateTime').optional().custom((v: any) => v === '' || /^([01]\d|2[0-3]):[0-5]\d(:\d{2})?$/.test(v)).withMessage('迟到时间格式应为 HH:mm'),
    body('endTime').optional().custom((v: any) => v === '' || /^([01]\d|2[0-3]):[0-5]\d(:\d{2})?$/.test(v)).withMessage('下班时间格式应为 HH:mm'),
    body('checkin_start').optional().custom((v: any) => v === '' || /^([01]\d|2[0-3]):[0-5]\d(:\d{2})?$/.test(v)).withMessage('上班时间格式应为 HH:mm'),
    body('checkin_end').optional().custom((v: any) => v === '' || /^([01]\d|2[0-3]):[0-5]\d(:\d{2})?$/.test(v)).withMessage('下班时间格式应为 HH:mm'),
    body('late_time').optional().custom((v: any) => v === '' || /^([01]\d|2[0-3]):[0-5]\d(:\d{2})?$/.test(v)).withMessage('迟到时间格式应为 HH:mm'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      // 先查现有记录，避免编辑时未传字段被设为NULL
      const existing = await pgPool.query('SELECT * FROM attendance_rules WHERE id=$1', [req.params.id]);
      if (existing.rows.length === 0) return res.status(404).json(ErrorCodes.ATTEND_RULE_NOT_FOUND);
      const cur = existing.rows[0];
      await pgPool.query(
        `UPDATE attendance_rules SET
          name=$1, center_lat=$2, center_lng=$3, radius_meters=$4,
          checkin_start=$5, checkin_end=$6, late_time=$7, wifi_ssid=$8, wifi_bssid=$9
         WHERE id=$10`,
        [
          'name' in req.body ? req.body.name : cur.name,
          'center_lat' in req.body ? req.body.center_lat : cur.center_lat,
          'center_lng' in req.body ? req.body.center_lng : cur.center_lng,
          'radius_meters' in req.body ? req.body.radius_meters : ('radius' in req.body ? req.body.radius : cur.radius_meters),
          // 空串归一化为 NULL（🟠-1 修复：避免 PG time 类型解析报错→误报404）
          'checkin_start' in req.body ? (req.body.checkin_start === '' ? null : req.body.checkin_start) : ('startTime' in req.body ? (req.body.startTime === '' ? null : req.body.startTime) : cur.checkin_start),
          'checkin_end' in req.body ? (req.body.checkin_end === '' ? null : req.body.checkin_end) : ('endTime' in req.body ? (req.body.endTime === '' ? null : req.body.endTime) : cur.checkin_end),
          'late_time' in req.body ? (req.body.late_time === '' ? null : req.body.late_time) : ('lateTime' in req.body ? (req.body.lateTime === '' ? null : req.body.lateTime) : cur.late_time),
          'wifi_ssid' in req.body ? req.body.wifi_ssid : ('wifiName' in req.body ? req.body.wifiName : cur.wifi_ssid),
          'wifi_bssid' in req.body ? req.body.wifi_bssid : cur.wifi_bssid,
          req.params.id,
        ],
      );
      const result = await pgPool.query('SELECT * FROM attendance_rules WHERE id=$1', [req.params.id]);
      if (result.rows.length > 0) return res.json(result.rows[0]);
      res.json({ success: true });
    } catch (err) {
      // 内存回退
      const idx = memRules.findIndex(r => r.id === parseInt(req.params.id));
      if (idx === -1) return res.status(404).json(ErrorCodes.ATTEND_RULE_NOT_FOUND);
      memRules[idx] = { ...memRules[idx], ...req.body, id: memRules[idx].id };
      res.json(memRules[idx]);
    }
  },
);

// DELETE /api/v1/attendance/rules/:id — 删除规则（管理员/经理）
router.delete('/rules/:id',
  adminMiddleware,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      await pgPool.query('DELETE FROM attendance_rules WHERE id = $1', [req.params.id]);
      res.json({ success: true });
    } catch (err) {
      // 内存回退
      const idx = memRules.findIndex(r => r.id === parseInt(req.params.id));
      if (idx === -1) return res.status(404).json(ErrorCodes.ATTEND_RULE_NOT_FOUND);
      memRules.splice(idx, 1);
      res.json({ success: true });
    }
  },
);

// ============================================================
//  员工工作台数据（今日状态+统计）
// ============================================================

// GET /api/v1/attendance/my-status — 员工今日考勤状态 + 统计
router.get('/my-status',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const today = new Date().toISOString().split('T')[0];

      // 今日打卡状态
      let todayRecords: any[] = [];
      try {
        const result = await pgPool.query(
          `SELECT id, type, check_time, address, status
           FROM attendance_records
           WHERE user_id = $1 AND check_time::date = $2::date
           ORDER BY check_time`,
          [user.userId, today],
        );
        todayRecords = result.rows;
      } catch (_) {}

      const checkedIn = todayRecords.some(r => r.type === 'checkin');
      const checkedOut = todayRecords.some(r => r.type === 'checkout');

      // 当月统计
      const workDaysInMonth = 22; // 按22个工作日估算
      const monthStart = today.substring(0, 7) + '-01';
      let monthlyStats = { totalDays: 0, checkinDays: 0, totalMileage: 0 };
      try {
        const statsResult = await pgPool.query(
          `SELECT
             COUNT(DISTINCT check_time::date) as checkin_days,
             COUNT(*) as total_records
           FROM attendance_records
           WHERE user_id = $1 AND check_time::date >= $2::date`,
          [user.userId, monthStart],
        );
        if (statsResult.rows.length > 0) {
          monthlyStats = {
            totalDays: workDaysInMonth,
            checkinDays: parseInt(statsResult.rows[0].checkin_days) || 0,
            totalMileage: 0,
          };
        }
      } catch (_) {}

      // 待审批数量
      let pendingApprovalCount = 0;
      try {
        const approvalResult = await pgPool.query(
          `SELECT COUNT(*) as cnt FROM approvals
           WHERE status = 'pending'
             AND (applicant_id = $1 OR approver_id = $1)`,
          [user.userId],
        );
        if (approvalResult.rows.length > 0) {
          pendingApprovalCount = parseInt(approvalResult.rows[0].cnt);
        }
      } catch (_) {}

      res.json({
        today: {
          date: today,
          checkedIn,
          checkedOut,
          records: todayRecords,
        },
        monthly: monthlyStats,
        pendingApprovalCount,
        userName: user.phone || '',
        userRole: user.role || 'employee',
      });
    } catch (err) {
      next(err);
    }
  },
);

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
           u.id as user_id, u.name,
           COUNT(CASE WHEN a.type = 'checkin' THEN 1 END) as checkin_count,
           MAX(CASE WHEN a.type = 'checkin' THEN a.check_time END) as last_checkin
         FROM users u
         LEFT JOIN attendance_records a ON u.id = a.user_id
           AND a.check_time::date >= $1::date
           AND a.check_time::date <= $2::date
         GROUP BY u.id, u.name
         ORDER BY u.name`,
        [startDate, endDate],
      );

      const stats = result.rows;
      const totalUsers = stats.length;
      const checkedIn = stats.filter(r => parseInt(r.checkin_count as string, 10) > 0).length;

      res.json({
        startDate,
        endDate,
        stats,
        totalUsers,
        checkedIn,
        late: 0,
        absent: totalUsers - checkedIn,
        todayVisits: 0,
        pendingApprovals: 0,
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
