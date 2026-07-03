import { Router, Request, Response, NextFunction } from 'express';
import bcrypt from 'bcryptjs';
import { body } from 'express-validator';
import { pgPool } from '../config/database';
import { generateToken, authMiddleware, JwtPayload } from '../middleware/auth';
import { AppError } from '../errors/AppError';
import { validate } from '../middleware/validate';

const router = Router();

// 登录 — POST /api/v1/auth/login
router.post('/login',
  validate([
    body('phone')
      .notEmpty().withMessage('手机号不能为空')
      .matches(/^1\d{10}$/).withMessage('手机号格式错误'),
    body('password')
      .notEmpty().withMessage('密码不能为空')
      .isLength({ min: 6 }).withMessage('密码长度不能少于6位'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { phone, password } = req.body;

      const result = await pgPool.query(
        'SELECT id, name, phone, password_hash, role, department_id FROM users WHERE phone = $1',
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

      const token = generateToken({
        userId: user.id,
        phone: user.phone,
        role: user.role,
        departmentId: user.department_id,
      });

      res.json({
        token,
        userId: user.id,
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

// 获取当前用户信息 — GET /api/v1/auth/me
router.get('/me', authMiddleware, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const user = (req as any).user as JwtPayload;
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

export default router;
