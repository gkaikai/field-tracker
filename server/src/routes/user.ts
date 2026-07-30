import { Router, Request, Response, NextFunction } from 'express';
import { pgPool } from '../config/database';
import { authMiddleware, adminMiddleware, JwtPayload } from '../middleware/auth';
import { AppError } from '../errors/AppError';
import { ErrorCodes } from '../errors/errorCodes';

const router = Router();
router.use(authMiddleware);

// GET /api/v1/users — 用户列表（管理员/经理看全部，员工只看同部门）
router.get('/', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const user = (req as any).user as JwtPayload;
    const isAdmin = user.role === 'admin' || user.role === 'manager';

    let queryStr = `SELECT u.id, u.name, u.phone, u.role, u.department_id, d.name as department_name, u.is_active
       FROM users u LEFT JOIN departments d ON u.department_id = d.id
       WHERE u.is_active = true`;
    const params: any[] = [];

    if (!isAdmin) {
      const deptResult = await pgPool.query('SELECT department_id FROM users WHERE id=$1', [user.userId]);
      const myDept = deptResult.rows[0]?.department_id;
      if (myDept) {
        queryStr += ' AND u.department_id = $1';
        params.push(myDept);
      }
    }
    queryStr += ' ORDER BY u.name';

    const result = await pgPool.query(queryStr, params);
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
