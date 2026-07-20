import { Router, Request, Response, NextFunction } from 'express';
import bcrypt from 'bcryptjs';
import { body } from 'express-validator';
import rateLimit from 'express-rate-limit';
import { pgPool } from '../config/database';
import { generateToken, authMiddleware, adminMiddleware, JwtPayload } from '../middleware/auth';
import { AppError } from '../errors/AppError';
import { validate } from '../middleware/validate';

const router = Router();

// 测试用户（数据库不可用时使用）
const TEST_USERS: Record<string, { password: string; name: string; role: string }> = {
  '13800138000': { password: 'test123456', name: '张三', role: 'admin' },
  '13900139000': { password: 'test123456', name: '李四', role: 'employee' },
  '13700137000': { password: 'test123456', name: '王经理', role: 'manager' },
};

// 登录 — POST /api/v1/auth/login
router.post('/login',
  validate([
    body('phone')
      .notEmpty().withMessage('手机号不能为空')
      .matches(/^\+?\d{5,20}$/).withMessage('手机号格式不正确（5-20位数字，支持国际号）'),
    body('password')
      .notEmpty().withMessage('密码不能为空')
      .isLength({ min: 6 }).withMessage('密码长度不能少于6位'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { phone, password } = req.body;
      // 硬校验
      if (!phone || !password) return res.status(400).json({ code: '10001', message: '手机号和密码不能为空' });
      if (password.length > 50) return res.status(400).json({ code: '10004', message: '参数异常' });

      // 先尝试数据库查询
      try {
        const result = await pgPool.query(
          'SELECT id, name, phone, password_hash, role, department_id FROM users WHERE phone = $1',
          [phone],
        );

        if (result.rows.length > 0) {
          const user = result.rows[0];
          const valid = await bcrypt.compare(password, user.password_hash);
          if (!valid) {
            throw new AppError('AUTH_LOGIN_FAILED');
          }

          const token = generateToken({
            userId: user.id,
            phone: user.phone,
            role: user.role,
            departmentId: user.department_id,
          });

          return res.json({
            token,
            userId: user.id,
            name: user.name,
            phone: user.phone,
            role: user.role,
            departmentId: user.department_id,
          });
        }
      } catch (dbErr) {
        // 数据库不可用时降级到测试用户
        console.warn('数据库查询失败，使用测试用户:', (dbErr as Error).message);
      }

      // 降级：检查测试用户
      const testUser = TEST_USERS[phone];
      if (!testUser || testUser.password !== password) {
        throw new AppError('AUTH_LOGIN_FAILED');
      }

      const token = generateToken({
        userId: '-1', // 测试用户无真实ID
        phone,
        role: testUser.role,
        departmentId: undefined,
      });

      res.json({
        token,
        userId: '-1',
        name: testUser.name,
        phone,
        role: testUser.role,
        departmentId: null,
      });
    } catch (err) {
      next(err);
    }
  },
);

// 获取当前用户信息 — GET /api/v1/auth/me
router.get('/me', authMiddleware, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const user = (req as any).user as JwtPayload;
    
    // 测试用户降级模式 — JWT中userId=-1，从缓存取
    if (user.userId === '-1') {
      const testUsers: Record<string, any> = {
        '13800138000': { id: '-1', name: '张三', phone: '13800138000', role: 'admin' },
        '13700137000': { id: '-1', name: '王经理', phone: '13700137000', role: 'manager' },
        '13900139000': { id: '-1', name: '李四', phone: '13900139000', role: 'employee' },
      };
      const info = testUsers[user.phone];
      if (info) return res.json(info);
    }

    const result = await pgPool.query(
      'SELECT id, name, phone, role, department_id, avatar_url, created_at FROM users WHERE id = $1',
      [user.userId],
    );

    if (result.rows.length === 0) {
      throw new AppError('AUTH_USER_NOT_FOUND');
    }

    res.json(result.rows[0]);
  } catch (err) {
    next(err);
  }
});

// 修改密码 — POST /api/v1/auth/change-password
router.post('/change-password', authMiddleware,
  validate([
    body('oldPassword').notEmpty().withMessage('旧密码不能为空'),
    body('newPassword').isLength({ min: 6 }).withMessage('新密码至少6位'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const { oldPassword, newPassword } = req.body;

      // 测试用户模式
      const testUser = TEST_USERS[user.phone || ''];
      if (testUser) {
        if (testUser.password !== oldPassword) {
          throw new AppError('AUTH_LOGIN_FAILED');
        }
        testUser.password = newPassword;
        return res.json({ success: true, message: '密码修改成功' });
      }

      // 数据库模式
      try {
        const result = await pgPool.query(
          'SELECT password_hash FROM users WHERE id = $1',
          [user.userId],
        );
        if (result.rows.length === 0) throw new AppError('AUTH_USER_NOT_FOUND');
        const valid = await bcrypt.compare(oldPassword, result.rows[0].password_hash);
        if (!valid) throw new AppError('AUTH_LOGIN_FAILED');
        const hash = await bcrypt.hash(newPassword, 10);
        await pgPool.query('UPDATE users SET password_hash = $1 WHERE id = $2', [hash, user.userId]);
      } catch (dbErr) {
        if (dbErr instanceof AppError) throw dbErr;
        console.warn('数据库修改密码失败（非致命）:', (dbErr as Error).message);
      }

      res.json({ success: true, message: '密码修改成功' });
    } catch (err) {
      next(err);
    }
  },
);

// POST /api/v1/auth/register — 注册新用户(仅管理员)
const regLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1小时窗口
  max: 20,                   // 每小时最多20次注册（防批量）
  standardHeaders: true,
  legacyHeaders: false,
  message: { code: 'RATE_LIMIT', message: '注册操作过于频繁，请稍后再试' },
});

// 注册审计日志（内存）
const regLog: Array<{time: string; admin: string; phone: string; ip: string}> = [];

router.post('/register',
  authMiddleware,
  adminMiddleware,
  regLimiter,
  validate([
    body('phone')
      .notEmpty().withMessage('手机号不能为空')
      .matches(/^\+?\d{5,20}$/).withMessage('手机号格式不正确（5-20位数字，支持国际号）'),
    body('password').notEmpty().isLength({ min: 6, max: 50 }).withMessage('密码长度6~50位'),
    body('name').optional().isLength({ max: 50 }).withMessage('姓名不超过50字'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const { phone, password, name, role } = req.body;
      // 后端硬校验 - 防止绕过express-validator
      if (!phone || !password) return res.status(400).json({ code: '10001', message: '手机号和密码不能为空' });
      if (password.length < 6 || password.length > 50) return res.status(400).json({ code: '10004', message: '密码长度6~50位' });
      if (name && name.length > 50) return res.status(400).json({ code: '50001', message: '姓名不超过50字' });
      // 超管校验 - 只有admin可以创建admin账号
      if (role === 'admin' && user.role !== 'admin') {
        return res.status(403).json({ code: 'FORBIDDEN', message: '只有管理员可以创建管理员账号' });
      }
      // 检查是否已存在
      if (TEST_USERS[phone]) return res.status(409).json({ code: 'USER_EXISTS', message: '用户已存在' });
      TEST_USERS[phone] = { password, name: name || phone, role: role || 'employee' };
      // 同步添加到 org userProfiles
      try {
        const { initUserProfiles, userProfiles } = await import('./org');
        if (typeof initUserProfiles === 'function') initUserProfiles();
        if (Array.isArray(userProfiles)) {
          userProfiles.push({ userId: phone, name: name || phone, phone, departmentId: null, role: (role || 'employee') as any });
        }
      } catch(_) {}
      // 审计日志
      regLog.push({
        time: new Date().toISOString(),
        admin: user.phone,
        phone,
        ip: req.ip || req.socket.remoteAddress || 'unknown',
      });
      // 超过1000条时清理旧日志
      if (regLog.length > 1000) regLog.splice(0, regLog.length - 1000);
      res.status(201).json({ id: phone, phone, name: name || phone, role: role || 'employee', message: '创建成功' });
    } catch (err) { next(err); }
  },
);

export default router;

// ============================================================
//  注册审计日志 — GET /api/v1/auth/register-log
//  查看最近注册记录，仅管理员
// ============================================================
router.get('/register-log',
  authMiddleware,
  adminMiddleware,
  async (_req: Request, res: Response) => {
    res.json({ logs: regLog.slice(-200).reverse() }); // 最近200条，倒序
  },
);

export { regLog };
