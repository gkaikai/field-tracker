import { Router, Request, Response, NextFunction } from 'express';
import * as bcrypt from 'bcryptjs';
import { body, param } from 'express-validator';
import rateLimit from 'express-rate-limit';
import * as svgCaptcha from 'svg-captcha';
import * as crypto from 'crypto';
import { pgPool } from '../config/database';
import { generateToken, authMiddleware, adminMiddleware, JwtPayload } from '../middleware/auth';
import { AppError } from '../errors/AppError';
import { validate } from '../middleware/validate';

const router = Router();

// ============================================================
//  内存存储：验证码 & 短信码
// ============================================================

interface CaptchaRecord {
  text: string;         // 验证码文字
  createdAt: number;    // ms
}

interface SmsRecord {
  code: string;
  phone: string;
  createdAt: number;
  verified: boolean;    // 已校验通过（用于密码重置等后续操作）
  resetToken?: string;  // 校验通过时生成的 resetToken，forgot-password 需验证
}

const captchaStore = new Map<string, CaptchaRecord>();
const smsStore = new Map<string, SmsRecord>();  // key = phone

// 每5分钟清理过期记录
setInterval(() => {
  const now = Date.now();
  Array.from(captchaStore.keys()).forEach(key => {
    const val = captchaStore.get(key)!;
    if (now - val.createdAt > 5 * 60 * 1000) captchaStore.delete(key);
  });
  Array.from(smsStore.keys()).forEach(key => {
    const val = smsStore.get(key)!;
    if (now - val.createdAt > 10 * 60 * 1000) smsStore.delete(key);
  });
}, 5 * 60 * 1000);

// ============================================================
//  统一手机号校验：严格11位
// ============================================================
function validatePhone(phone: string): boolean {
  return /^1\d{10}$/.test(phone);
}

// ============================================================
//  1. 获取图形验证码 — GET /api/v1/auth/captcha
// ============================================================
router.get('/captcha', async (_req: Request, res: Response) => {
  const captcha = svgCaptcha.createMathExpr({
    mathMin: 1,
    mathMax: 20,
    mathOperator: '+',
  });
  // captcha.text 是表达式文本 "3+15="，需要算出结果存储
  const exprText = captcha.text.replace('=', '');
  const parts = exprText.split('+');
  const answer = String(parseInt(parts[0], 10) + parseInt(parts[1], 10));
  const token = crypto.randomBytes(16).toString('hex');
  captchaStore.set(token, { text: answer, createdAt: Date.now() });
  res.json({
    token,
    svg: captcha.data,       // SVG 字符串
    expiredIn: 300,          // 5分钟过期
  });
});

// ============================================================
//  2. 校验图形验证码 — POST /api/v1/auth/verify-captcha
// ============================================================
router.post('/verify-captcha',
  validate([
    body('token').notEmpty().withMessage('验证码token不能为空'),
    body('code').notEmpty().withMessage('验证码不能为空'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { token, code } = req.body;
      const record = captchaStore.get(token);
      if (!record) throw new AppError('CAPTCHA_EXPIRED');
      if (Date.now() - record.createdAt > 5 * 60 * 1000) {
        captchaStore.delete(token);
        throw new AppError('CAPTCHA_EXPIRED');
      }
      if (record.text !== code.trim()) {
        captchaStore.delete(token);
        throw new AppError('CAPTCHA_CODE_ERROR');
      }
      captchaStore.delete(token);
      res.json({ success: true, message: '验证码正确' });
    } catch (err) {
      next(err);
    }
  },
);

// ============================================================
//  3. 发送短信验证码 — POST /api/v1/auth/send-code
//  开发阶段：打印到控制台，不实际发短信
// ============================================================
const smsLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  message: { code: 'RATE_LIMIT', message: '操作过于频繁' },
});

router.post('/send-code',
  smsLimiter,
  validate([
    body('phone').notEmpty().withMessage('手机号不能为空'),
    body('captchaToken').notEmpty().withMessage('图形验证码token不能为空'),
    body('captchaCode').notEmpty().withMessage('图形验证码不能为空'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { phone, captchaToken, captchaCode } = req.body;
      if (!validatePhone(phone)) throw new AppError('PHONE_FORMAT_INVALID');

      // 服务端校验图形验证码
      const captchaRecord = captchaStore.get(captchaToken);
      if (!captchaRecord) throw new AppError('CAPTCHA_EXPIRED');
      if (Date.now() - captchaRecord.createdAt > 5 * 60 * 1000) {
        captchaStore.delete(captchaToken);
        throw new AppError('CAPTCHA_EXPIRED');
      }
      if (captchaRecord.text !== String(captchaCode).trim()) {
        captchaStore.delete(captchaToken);
        throw new AppError('CAPTCHA_CODE_ERROR');
      }
      captchaStore.delete(captchaToken);  // 一次性使用

      // 检查频率：同一手机号60秒内只能发一次
      const existing = smsStore.get(phone);
      if (existing && Date.now() - existing.createdAt < 60 * 1000) {
        throw new AppError('SMS_TOO_FREQUENT');
      }

      // 生成6位验证码
      const code = String(Math.floor(100000 + Math.random() * 900000));

      smsStore.set(phone, {
        code,
        phone,
        createdAt: Date.now(),
        verified: false,
      });

      // 开发阶段：打印到控制台
      console.log('');
      console.log('╔══════════════════════════════════════════╗');
      console.log(`║  短信验证码 [${phone}]`);
      console.log(`║  ────────────────────────`);
      console.log(`║  🔑 验证码: ${code}`);
      console.log(`║  有效期: 5 分钟`);
      console.log('╚══════════════════════════════════════════╝');
      console.log('');

      res.json({ success: true, message: '验证码已发送（开发模式，请查看服务端日志）' });
    } catch (err) {
      next(err);
    }
  },
);

// ============================================================
//  4. 校验短信验证码 — POST /api/v1/auth/verify-code
// ============================================================
router.post('/verify-code',
  validate([
    body('phone').notEmpty().withMessage('手机号不能为空'),
    body('code').notEmpty().withMessage('验证码不能为空'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { phone, code } = req.body;
      if (!validatePhone(phone)) throw new AppError('PHONE_FORMAT_INVALID');

      const record = smsStore.get(phone);
      if (!record) throw new AppError('SMS_CODE_EXPIRED');
      if (Date.now() - record.createdAt > 5 * 60 * 1000) {
        smsStore.delete(phone);
        throw new AppError('SMS_CODE_EXPIRED');
      }
      if (record.code !== code.trim()) {
        throw new AppError('SMS_CODE_ERROR');
      }

      const resetToken = crypto.randomBytes(20).toString('hex');
      record.verified = true;
      record.resetToken = resetToken;
      smsStore.set(phone, record);

      res.json({
        success: true,
        message: '验证码正确',
        resetToken,
      });
    } catch (err) {
      next(err);
    }
  },
);

// ============================================================
//  5. 忘记密码 — POST /api/v1/auth/forgot-password
//  需要短信验证码已校验通过 + resetToken 校验
// ============================================================
router.post('/forgot-password',
  validate([
    body('phone').notEmpty().withMessage('手机号不能为空'),
    body('resetToken').notEmpty().withMessage('resetToken不能为空'),
    body('newPassword').isLength({ min: 6, max: 50 }).withMessage('密码长度6~50位'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { phone, resetToken, newPassword } = req.body;
      if (!validatePhone(phone)) throw new AppError('PHONE_FORMAT_INVALID');

      // 检查短信验证码是否已校验通过
      const smsRecord = smsStore.get(phone);
      if (!smsRecord || !smsRecord.verified) {
        throw new AppError('SMS_CODE_EXPIRED');
      }
      // 校验通过后超过5分钟也失效
      if (Date.now() - smsRecord.createdAt > 5 * 60 * 1000) {
        smsStore.delete(phone);
        throw new AppError('SMS_CODE_EXPIRED');
      }
      // 校验 resetToken 与存储的匹配
      if (!smsRecord.resetToken || smsRecord.resetToken !== resetToken) {
        throw new AppError('SMS_CODE_EXPIRED');
      }

      // 检查用户是否存在
      const userResult = await pgPool.query(
        'SELECT id FROM users WHERE phone = $1 AND is_active = true',
        [phone],
      );
      if (userResult.rows.length === 0) {
        throw new AppError('AUTH_USER_NOT_FOUND');
      }

      // 更新密码
      const hash = await bcrypt.hash(newPassword, 10);
      await pgPool.query(
        'UPDATE users SET password_hash = $1 WHERE phone = $2',
        [hash, phone],
      );

      // 清除已使用的短信记录
      smsStore.delete(phone);

      res.json({ success: true, message: '密码重置成功，请使用新密码登录' });
    } catch (err) {
      next(err);
    }
  },
);

// ============================================================
//  6. 登录 — POST /api/v1/auth/login
//  ✅ 新增：手机号严格11位校验
// ============================================================
router.post('/login',
  validate([
    body('phone')
      .notEmpty().withMessage('手机号不能为空'),
    body('password')
      .notEmpty().withMessage('密码不能为空')
      .isLength({ min: 6 }).withMessage('密码长度不能少于6位'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { phone, password } = req.body;
      if (!phone || !password) return res.status(400).json({ code: '10001', message: '手机号和密码不能为空' });
      if (password.length > 50) return res.status(400).json({ code: '10004', message: '参数异常' });

      // 手机号格式校验
      if (!validatePhone(phone)) throw new AppError('PHONE_FORMAT_INVALID');

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
//  7. 当前用户信息 — GET /api/v1/auth/me
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
//  8. 修改密码 — POST /api/v1/auth/change-password
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
//  9. 注册新用户 — POST /api/v1/auth/register (管理员)
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
      .notEmpty().withMessage('手机号不能为空'),
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

      // 手机号格式校验
      if (!validatePhone(phone)) throw new AppError('PHONE_FORMAT_INVALID');

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

export default router;
export { regLog, smsStore };
