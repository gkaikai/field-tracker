import { Router, Request, Response } from 'express';
import bcrypt from 'bcryptjs';
import { pgPool } from '../config/database';
import { generateToken, authMiddleware } from '../middleware/auth';

const router = Router();

// POST /api/v1/auth/login
router.post('/login', async (req: Request, res: Response) => {
  try {
    const { phone, password } = req.body;

    if (!phone || !password) {
      return res.status(400).json({ message: '手机号和密码不能为空' });
    }

    const result = await pgPool.query(
      'SELECT id, name, phone, password_hash, role, department_id FROM users WHERE phone = $1 AND is_active = true',
      [phone]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({ message: '账号或密码错误' });
    }

    const user = result.rows[0];

    // 验证密码
    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) {
      return res.status(401).json({ message: '账号或密码错误' });
    }

    // 生成 Token
    const token = generateToken({
      userId: user.id,
      phone: user.phone,
      role: user.role,
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
    console.error('登录错误:', err);
    res.status(500).json({ message: '服务器内部错误' });
  }
});

// GET /api/v1/auth/me - 获取当前用户信息
router.get('/me', authMiddleware, async (req: Request, res: Response) => {
  try {
    const user = (req as any).user;
    const result = await pgPool.query(
      'SELECT id, name, phone, role, department_id, avatar_url, created_at FROM users WHERE id = $1',
      [user.userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: '用户不存在' });
    }

    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: '服务器内部错误' });
  }
});

export default router;
