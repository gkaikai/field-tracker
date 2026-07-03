import { Router, Request, Response } from 'express';
import { pgPool } from '../config/database';
import { authMiddleware } from '../middleware/auth';

const router = Router();
router.use(authMiddleware);

// GET /api/v1/users - 获取用户列表
router.get('/', async (req: Request, res: Response) => {
  try {
    const result = await pgPool.query(
      `SELECT u.id, u.name, u.phone, u.role, u.department_id, d.name as department_name, u.is_active
       FROM users u LEFT JOIN departments d ON u.department_id = d.id
       WHERE u.is_active = true
       ORDER BY u.name`
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: '服务器内部错误' });
  }
});

// GET /api/v1/users/departments - 获取部门列表
router.get('/departments', async (req: Request, res: Response) => {
  try {
    const result = await pgPool.query(
      'SELECT id, name, parent_id FROM departments ORDER BY name'
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: '服务器内部错误' });
  }
});

export default router;
