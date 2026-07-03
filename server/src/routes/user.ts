import { Router, Request, Response, NextFunction } from 'express';
import { pgPool } from '../config/database';
import { authMiddleware } from '../middleware/auth';
import { AppError } from '../errors/AppError';
import { ErrorCodes } from '../errors/errorCodes';

const router = Router();
router.use(authMiddleware);

// GET /api/v1/users — 用户列表
router.get('/', async (_req: Request, res: Response, next: NextFunction) => {
  try {
    const result = await pgPool.query(
      `SELECT u.id, u.name, u.phone, u.role, u.department_id, d.name as department_name, u.is_active
       FROM users u LEFT JOIN departments d ON u.department_id = d.id
       WHERE u.is_active = true
       ORDER BY u.name`,
    );
    res.json(result.rows);
  } catch (err) {
    next(err);
  }
});

// GET /api/v1/users/departments — 部门列表
router.get('/departments', async (_req: Request, res: Response, next: NextFunction) => {
  try {
    const result = await pgPool.query(
      'SELECT id, name, parent_id FROM departments ORDER BY name',
    );
    res.json(result.rows);
  } catch (err) {
    next(err);
  }
});

export default router;
