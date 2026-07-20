import { Router, Request, Response, NextFunction } from 'express';
import bcrypt from 'bcryptjs';
import { body } from 'express-validator';
import rateLimit from 'express-rate-limit';
import { pgPool } from '../config/database';
import { generateToken, authMiddleware, adminMiddleware, JwtPayload } from '../middleware/auth';
import { AppError } from '../errors/AppError';
import { validate } from '../middleware/validate';

const router = Router();

// ============================================================
//  登录 — POST /api/v1/auth/login
//  仅支持数据库用户，无硬编码测试用户
// ============================================================
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
      if (!phone || !password) return res.status(400).json({ code: '10001', message: '手机号和密码不能为空' });
      if (password.length > 50) return res.status(400).json({ code: '10004', message: '参数异常' });

      // 数据库查询用户
      const result = await pgPool.query(
        'SELECT id, user_code, name, phone, password_hash, role, department_id FROM users WHERE phone = $1 AND is_active = true',
        [phone],
      );

      if (result.rows.length === 0) {
        throw new AppError('AUTH_LOGIN_FAILED');
      }

      const user = result.rows[0];
      const valid = await bcrypt.compare(password, user.password_hash);
      if (!valid) {
        throw new AppError('AUTH_LOGIN_FAILED');
      }

      // 更新最后登录时间
      await pgPool.query('UPDATE users SET last_login_at = NOW() WHERE id = $1', [user.id]);

      const token = generateToken({
        userId: user.id,
        phone: user.phone,
        role: user.role,
        departmentId: user.department_id,
      });

      res.json({
        token,
        userId: user.id,
        userCode: user.user_code,
        name: user.name,
        phone: user.phone,
        role: user.role,
        departmentId: user.department_id,
      });
    } catch (err) {
      next(err);
    }
  },
);

// ============================================================
//  当前用户信息 — GET /api/v1/auth/me
// ============================================================
router.get('/me', authMiddleware, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const user = (req as any).user as JwtPayload;

    const result = await pgPool.query(
      'SELECT id, user_code, name, phone, role, department_id, avatar_url, created_at FROM users WHERE id = $1',
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

// ============================================================
//  修改密码 — POST /api/v1/auth/change-password
// ============================================================
router.post('/change-password', authMiddleware,
  validate([
    body('oldPassword').notEmpty().withMessage('旧密码不能为空'),
    body('newPassword').isLength({ min: 6 }).withMessage('新密码至少6位'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const { oldPassword, newPassword } = req.body;

      const result = await pgPool.query(
        'SELECT password_hash FROM users WHERE id = $1',
        [user.userId],
      );
      if (result.rows.length === 0) throw new AppError('AUTH_USER_NOT_FOUND');

      const valid = await bcrypt.compare(oldPassword, result.rows[0].password_hash);
      if (!valid) throw new AppError('AUTH_LOGIN_FAILED');

      const hash = await bcrypt.hash(newPassword, 10);
      await pgPool.query('UPDATE users SET password_hash = $1 WHERE id = $2', [hash, user.userId]);

      res.json({ success: true, message: '密码修改成功' });
    } catch (err) {
      next(err);
    }
  },
);

// ============================================================
//  注册新用户 — POST /api/v1/auth/register
//  仅管理员可用，直接写入数据库
// ============================================================
const regLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { code: 'RATE_LIMIT', message: '注册操作过于频繁，请稍后再试' },
});

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
      const admin = (req as any).user as JwtPayload;
      const { phone, password, name, role } = req.body;
      if (!phone || !password) return res.status(400).json({ code: '10001', message: '手机号和密码不能为空' });
      if (password.length < 6 || password.length > 50) return res.status(400).json({ code: '10004', message: '密码长度6~50位' });
      if (name && name.length > 50) return res.status(400).json({ code: '50001', message: '姓名不超过50字' });
      if (role === 'admin' && admin.role !== 'admin') {
        return res.status(403).json({ code: 'FORBIDDEN', message: '只有管理员可以创建管理员账号' });
      }

      // 检查手机号是否已存在
      const exist = await pgPool.query('SELECT id FROM users WHERE phone = $1', [phone]);
      if (exist.rows.length > 0) {
        return res.status(409).json({ code: 'USER_EXISTS', message: '该手机号已注册' });
      }

      // 写入数据库
      const hash = await bcrypt.hash(password, 10);
      const newUser = await pgPool.query(
        `INSERT INTO users (name, phone, password_hash, role)
         VALUES ($1, $2, $3, $4)
         RETURNING id, user_code, name, phone, role`,
        [name || phone, phone, hash, role || 'employee'],
      );

      const created = newUser.rows[0];

      // 审计日志
      regLog.push({
        time: new Date().toISOString(),
        admin: admin.phone,
        phone,
        ip: req.ip || req.socket.remoteAddress || 'unknown',
      });
      if (regLog.length > 1000) regLog.splice(0, regLog.length - 1000);

      res.status(201).json({
        id: created.id,
        userCode: created.user_code,
        name: created.name,
        phone: created.phone,
        role: created.role,
        message: '创建成功',
      });
    } catch (err) {
      next(err);
    }
  },
);

export default router;

// ============================================================
//  注册审计日志 — GET /api/v1/auth/register-log
// ============================================================
router.get('/register-log',
  authMiddleware,
  adminMiddleware,
  async (_req: Request, res: Response) => {
    res.json({ logs: regLog.slice(-200).reverse() });
  },
);

export { regLog };
