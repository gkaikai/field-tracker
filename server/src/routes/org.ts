// 组织架构管理 — 全DB存储
import { Router, Request, Response, NextFunction } from 'express';
import { body } from 'express-validator';
import * as bcrypt from 'bcryptjs';
import { authMiddleware, adminMiddleware, JwtPayload } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { pgPool } from '../config/database';
import { ErrorCodes } from '../errors/errorCodes';

const router = Router();
router.use(authMiddleware);

// ---- departments CRUD ----

// GET /api/v1/org/departments — 部门树
router.get('/departments', async (_req: Request, res: Response) => {
  try {
    const result = await pgPool.query(
      'SELECT id, name, parent_id, manager_id, description, sort_order, is_active, created_at FROM departments WHERE is_active = true ORDER BY sort_order'
    );
    const depts = result.rows.map(r => ({
      id: r.id, name: r.name, parentId: r.parent_id,
      managerId: r.manager_id, description: r.description || '',
      sort: r.sort_order, isActive: r.is_active, createdAt: r.created_at,
    }));
    res.json(depts);
  } catch(e) {
    console.error('[org] 查询部门失败:', e);
    res.status(500).json({ code: ErrorCodes.DB_ERROR.code, message: ErrorCodes.DB_ERROR.message });
  }
});

// POST /api/v1/org/departments — 创建部门（仅管理员）
router.post('/departments',
  adminMiddleware,
  validate([body('name').notEmpty().withMessage('部门名称不能为空')]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { name, parentId, description, sort } = req.body;
      const result = await pgPool.query(
        `INSERT INTO departments (name, parent_id, description, sort_order)
         VALUES ($1, $2, $3, $4) RETURNING id, created_at`,
        [name, parentId || null, description || '', sort || 0]
      );
      const r = result.rows[0];
      res.status(201).json({
        id: r.id, name, parentId: parentId || null, description: description || '',
        sort: sort || 0, isActive: true, createdAt: r.created_at,
      });
    } catch (err) {
      next(err);
    }
  },
);

// PUT /api/v1/org/departments/:id — 更新部门（仅管理员）
router.put('/departments/:id', adminMiddleware, async (req: Request, res: Response, next: NextFunction) => {
  try {
    // 先查现有值，为 in_body 兜底做准备
    const existingResult = await pgPool.query(
      'SELECT name, parent_id, manager_id, description, sort_order FROM departments WHERE id=$1',
      [req.params.id]
    );
    if (existingResult.rows.length === 0) return res.status(404).json({ code: '10014', message: '部门不存在' });
    const cur = existingResult.rows[0];
    const result = await pgPool.query(
      `UPDATE departments SET name=$1, parent_id=$2, description=$3, sort_order=$4,
       manager_id=$5, updated_at=NOW()
       WHERE id=$6 RETURNING id, name, parent_id, manager_id, description, sort_order, is_active, created_at`,
      [
        'name' in req.body ? req.body.name : cur.name,
        'parentId' in req.body ? req.body.parentId : cur.parent_id,
        'description' in req.body ? req.body.description : cur.description,
        'sort' in req.body ? req.body.sort : cur.sort_order,
        'managerId' in req.body ? req.body.managerId : cur.manager_id,
        req.params.id,
      ]
    );
    const r = result.rows[0];
    res.json({
      id: r.id, name: r.name, parentId: r.parent_id,
      managerId: r.manager_id, description: r.description || '',
      sort: r.sort_order, isActive: r.is_active, createdAt: r.created_at,
    });
  } catch (err) {
    next(err);
  }
});

// DELETE /api/v1/org/departments/:id — 删除部门（仅管理员）
router.delete('/departments/:id', adminMiddleware, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const result = await pgPool.query(
      'UPDATE departments SET is_active=false WHERE id=$1 RETURNING id', [req.params.id]
    );
    if (result.rows.length === 0) return res.status(404).json({ code: '10014', message: '部门不存在' });
    res.json({ success: true });
  } catch (err) {
    next(err);
  }
});

// ---- 用户组织信息 ----

// GET /api/v1/org/users — 员工列表（管理员/经理可看全部，员工只看同部门）
router.get('/users', async (req: Request, res: Response) => {
  try {
    const user = (req as any).user as JwtPayload;
    const isAdmin = user.role === 'admin' || user.role === 'manager';

    let queryStr = `SELECT u.id, u.name, u.phone, u.role, u.department_id, d.name as department_name
       FROM users u LEFT JOIN departments d ON u.department_id = d.id
       WHERE u.is_active = true`;
    const params: any[] = [];

    // 非管理员只看到同部门人员
    if (!isAdmin) {
      const deptResult = await pgPool.query('SELECT department_id FROM users WHERE id=$1', [user.userId]);
      const myDept = deptResult.rows[0]?.department_id;
      if (myDept) {
        queryStr += ' AND u.department_id = $1';
        params.push(myDept);
      }
    }
    queryStr += ' ORDER BY u.created_at DESC';

    const result = await pgPool.query(queryStr, params);
    res.json(result.rows.map(r => ({
      id: r.id, name: r.name, phone: r.phone,
      role: r.role || 'employee',
      departmentId: r.department_id,
      department: r.department_name || '',
    })));
  } catch(e) {
    console.error('[org] 查询用户列表失败:', e);
    res.status(500).json({ code: ErrorCodes.DB_ERROR.code, message: ErrorCodes.DB_ERROR.message });
  }
});

// PUT /api/v1/org/users/:id — 更新用户部门/角色（仅管理员）
router.put('/users/:id', adminMiddleware, async (req: Request, res: Response, next: NextFunction) => {
  try {
    // 先查现有值
    const existing = await pgPool.query('SELECT department_id, role, name FROM users WHERE id=$1', [req.params.id]);
    if (existing.rows.length === 0) return res.status(404).json({ code: '10014', message: '用户不存在' });
    const cur = existing.rows[0];
    await pgPool.query(
      `UPDATE users SET department_id=$1, role=$2, name=$3 WHERE id=$4`,
      [
        'departmentId' in req.body ? req.body.departmentId : cur.department_id,
        'role' in req.body ? req.body.role : cur.role,
        'name' in req.body ? req.body.name : cur.name,
        req.params.id,
      ]
    );
    res.json({ success: true });
  } catch(e) {
    next(e);
  }
});

// DELETE /api/v1/org/users/:id — 删除用户（使用UUID，非手机号，仅管理员）
router.delete('/users/:id', adminMiddleware, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const result = await pgPool.query('UPDATE users SET is_active=false WHERE id = $1 RETURNING id', [req.params.id]);
    if (result.rows.length === 0) return res.status(404).json({ code: '10014', message: '用户不存在' });
    res.json({ success: true, softDelete: true });
  } catch(e) {
    next(e);
  }
});

// ---- 多人实时位置（Web端用）----
router.get('/locations/online', async (req: Request, res: Response) => {
  try {
    const port = process.env.PORT || '3000';
    const resp = await fetch(`http://localhost:${port}/api/v1/location/batch`, {
      headers: { 'Authorization': req.headers.authorization || '' }
    });
    const data: any = await resp.json();
    // 从DB查用户部门信息
    const usersResult = await pgPool.query(
      'SELECT u.id, u.name, u.department_id, d.name as dept_name FROM users u LEFT JOIN departments d ON u.department_id = d.id'
    );
    const userMap = new Map(usersResult.rows.map(u => [u.id, { name: u.name, dept: u.dept_name || '' }]));

    const locations = (data.users || []).map((loc: any) => {
      const info = userMap.get(loc.userId);
      return {
        ...loc,
        name: info?.name || loc.name || loc.userId,
        department: info?.dept || '未分配',
      };
    });
    res.json({ locations, total: locations.length });
  } catch (e: any) {
    console.error('[org] 查询在线位置失败:', e.message);
    res.json({ locations: [], total: 0 });
  }
});

// POST /api/v1/org/users — 管理员创建员工账号
router.post('/users',
  adminMiddleware,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { name, phone, password, role, departmentId } = req.body;
      if (!phone) return res.status(400).json({ code: '10001', message: '手机号不能为空' });
      if (!name) return res.status(400).json({ code: '10001', message: '姓名不能为空' });

      // 角色提权校验：manager 不能创建 admin 账号
      const creator = (req as any).user as JwtPayload;
      const targetRole = role || 'employee';
      if (targetRole === 'admin' && creator.role !== 'admin') {
        return res.status(403).json({ code: '10009', message: '无权创建管理员账号' });
      }

      // 检查手机号是否已存在
      const exist = await pgPool.query('SELECT id FROM users WHERE phone = $1', [phone]);
      if (exist.rows.length > 0) {
        return res.status(409).json({ code: ErrorCodes.USER_EXISTS.code, message: ErrorCodes.USER_EXISTS.message });
      }

      const pwd = password || '123456';
      const hash = await bcrypt.hash(pwd, 10);

      const result = await pgPool.query(
        `INSERT INTO users (name, phone, password_hash, role, department_id)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id, name, phone, role, department_id, created_at`,
        [name, phone, hash, targetRole, departmentId || null]
      );

      const u = result.rows[0];
      res.status(201).json({
        id: u.id,
        name: u.name,
        phone: u.phone,
        role: u.role,
        departmentId: u.department_id,
        createdAt: u.created_at,
        message: '创建成功，请提醒员工修改默认密码',
      });
    } catch (err) {
      next(err);
    }
  },
);

// GET /api/v1/org/users/:id — 获取单个用户详情（管理员/经理可查任意，员工只能查自己）
router.get('/users/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const user = (req as any).user as JwtPayload;
    const isAdmin = user.role === 'admin' || user.role === 'manager';

    // 非管理员只能查自己
    if (!isAdmin && user.userId !== req.params.id) {
      return res.status(403).json({ code: '10009', message: '无权限访问' });
    }

    const result = await pgPool.query(
      `SELECT u.id, u.name, u.phone, u.role, u.department_id, d.name as department_name,
              u.is_active, u.created_at
       FROM users u LEFT JOIN departments d ON u.department_id = d.id
       WHERE u.id = $1`,
      [req.params.id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ code: '10014', message: '用户不存在' });
    }
    const u = result.rows[0];
    res.json({
      id: u.id,
      name: u.name,
      phone: u.phone,
      role: u.role || 'employee',
      departmentId: u.department_id,
      department: u.department_name || '',
      isActive: u.is_active,
      createdAt: u.created_at,
    });
  } catch (e) {
    next(e);
  }
});

export default router;
