import { Router, Request, Response, NextFunction } from 'express';
import { body, param } from 'express-validator';
import * as bcrypt from 'bcryptjs';
import { pgPool } from '../config/database';
import { authMiddleware, adminMiddleware, JwtPayload } from '../middleware/auth';
import { AppError } from '../errors/AppError';
import { ErrorCodes } from '../errors/errorCodes';
import { validate } from '../middleware/validate';

const router = Router();
router.use(authMiddleware);

// GET /api/v1/users — 用户列表（管理员/经理看全部，员工只看同部门）
router.get('/', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const user = (req as any).user as JwtPayload;
    const isAdmin = user.role === 'admin' || user.role === 'manager';

    let queryStr = `
      SELECT u.id, u.name, u.phone, u.role, u.department_id,
             d.name as department, u.is_active, u.user_code as code,
             CASE WHEN l.last_time IS NOT NULL
                  AND l.last_time > NOW() - INTERVAL '5 minutes'
             THEN true ELSE false END as online
      FROM users u
      LEFT JOIN departments d ON u.department_id = d.id
      LEFT JOIN LATERAL (
        SELECT MAX(created_at) as last_time
        FROM location_records
        WHERE user_id = u.id
      ) l ON true
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
    res.json({ users: result.rows });
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

// POST /api/v1/users — 添加员工
router.post('/',
  adminMiddleware,
  validate([
    body('name').notEmpty().withMessage('姓名不能为空'),
    body('phone').isMobilePhone('zh-CN').withMessage('手机号格式不正确'),
    body('role').optional().isIn(['employee', 'manager', 'admin']),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { name, phone, role, departmentId, password } = req.body;
      // 检查手机号是否已存在
      const exists = await pgPool.query('SELECT id FROM users WHERE phone=$1', [phone]);
      if (exists.rows.length > 0) {
        return res.status(409).json(ErrorCodes.USER_EXISTS);
      }
      const pwdHash = await bcrypt.hash(password || '123456', 10);
      const result = await pgPool.query(
        `INSERT INTO users (name, phone, role, department_id, password_hash, user_code)
         VALUES ($1, $2, $3, $4, $5,
           (SELECT COALESCE(MAX(user_code::int), 1000) + 1 FROM users WHERE user_code ~ '^\\\d+$')::varchar)
         RETURNING id, name, phone, role, department_id`,
        [name, phone, role || 'employee', departmentId || null, pwdHash],
      );
      res.status(201).json(result.rows[0]);
    } catch (err) {
      next(err);
    }
  },
);

// PUT /api/v1/users/:id — 编辑员工
router.put('/:id',
  adminMiddleware,
  validate([
    param('id').isUUID(),
    body('name').optional().isString(),
    body('phone').optional().isMobilePhone('zh-CN'),
    body('role').optional().isIn(['employee', 'manager', 'admin']),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { name, phone, role, departmentId } = req.body;
      const result = await pgPool.query(
        `UPDATE users SET
          name = COALESCE($1, name),
          phone = COALESCE($2, phone),
          role = COALESCE($3, role),
          department_id = COALESCE($4, department_id),
          updated_at = NOW()
         WHERE id = $5 AND is_active = true
         RETURNING id, name, phone, role, department_id`,
        [name || null, phone || null, role || null, departmentId || null, req.params.id],
      );
      if (result.rows.length === 0) {
        return res.status(404).json(ErrorCodes.AUTH_USER_NOT_FOUND);
      }
      res.json(result.rows[0]);
    } catch (err) {
      next(err);
    }
  },
);

// DELETE /api/v1/users/:id — 停用员工（软删除，设置 is_active=false）
router.delete('/:id',
  adminMiddleware,
  validate([param('id').isUUID()]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const result = await pgPool.query(
        `UPDATE users SET is_active = false, updated_at = NOW()
         WHERE id = $1 AND is_active = true RETURNING id`,
        [req.params.id],
      );
      if (result.rows.length === 0) {
        return res.status(404).json(ErrorCodes.AUTH_USER_NOT_FOUND);
      }
      res.json({ message: '已停用' });
    } catch (err) {
      next(err);
    }
  },
);

export default router;
