// 组织架构管理 — 全DB存储
import { Router, Request, Response } from 'express';
import { body } from 'express-validator';
import { authMiddleware, JwtPayload } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { pgPool } from '../config/database';

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
    res.status(500).json({ code: 'DB_ERROR', message: '查询部门失败' });
  }
});

// POST /api/v1/org/departments — 创建部门
router.post('/departments',
  validate([body('name').notEmpty().withMessage('部门名称不能为空')]),
  async (req: Request, res: Response) => {
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
  },
);

// PUT /api/v1/org/departments/:id
router.put('/departments/:id', async (req: Request, res: Response) => {
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
});

// DELETE /api/v1/org/departments/:id
router.delete('/departments/:id', async (req: Request, res: Response) => {
  const result = await pgPool.query(
    'UPDATE departments SET is_active=false WHERE id=$1 RETURNING id', [req.params.id]
  );
  if (result.rows.length === 0) return res.status(404).json({ code: '10014', message: '部门不存在' });
  res.json({ success: true });
});

// ---- 用户组织信息 ----

// GET /api/v1/org/users — 组织内用户列表
router.get('/users', async (_req: Request, res: Response) => {
  try {
    const result = await pgPool.query(
      `SELECT u.id, u.name, u.phone, u.role, u.department_id, d.name as department_name
       FROM users u LEFT JOIN departments d ON u.department_id = d.id
       WHERE u.is_active = true ORDER BY u.created_at DESC`
    );
    res.json(result.rows.map(r => ({
      id: r.id, name: r.name, phone: r.phone,
      role: r.role || 'employee',
      departmentId: r.department_id,
      department: r.department_name || '',
    })));
  } catch(e) {
    console.error('[org] 查询用户列表失败:', e);
    res.status(500).json({ code: 'DB_ERROR', message: '查询用户列表失败' });
  }
});

// PUT /api/v1/org/users/:id — 更新用户部门/角色
router.put('/users/:id', async (req: Request, res: Response) => {
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
    console.error('[org] 更新用户失败:', e);
    res.status(500).json({ code: 'DB_ERROR', message: '更新用户失败' });
  }
});

// DELETE /api/v1/org/users/:id — 删除用户（使用UUID，非手机号）
router.delete('/users/:id', async (req: Request, res: Response) => {
  try {
    const result = await pgPool.query('UPDATE users SET is_active=false WHERE id = $1 RETURNING id', [req.params.id]);
    if (result.rows.length === 0) return res.status(404).json({ code: '10014', message: '用户不存在' });
    res.json({ success: true, softDelete: true });
  } catch(e) {
    console.error('[org] 删除用户失败:', e);
    res.status(500).json({ code: 'DB_ERROR', message: '删除用户失败' });
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

export default router;
