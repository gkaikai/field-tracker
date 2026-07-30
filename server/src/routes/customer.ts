import { Router, Request, Response, NextFunction } from 'express';
import { body, query } from 'express-validator';
import { authMiddleware, adminMiddleware, JwtPayload } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { pgPool } from '../config/database';
import { ErrorCodes } from '../errors/errorCodes';

const router = Router();
router.use(authMiddleware);

// ============================================================
//  数据库存储 - 客户管理 + 拜访记录
// ============================================================

// ---- 客户 CRUD ----

// GET /api/v1/customers — 客户列表
router.get('/', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const user = (req as any).user as JwtPayload;
    const page = Math.max(1, parseInt(req.query.page as string) || 1);
    const pageSize = Math.max(1, Math.min(100, parseInt(req.query.pageSize as string) || 50));
    const keyword = (req.query.keyword as string || '').toLowerCase();
    const offset = (page - 1) * pageSize;

    let whereClause = 'WHERE (c.is_active = true OR c.is_active IS NULL)';
  const params: any[] = [];

  if (user.role !== 'admin' && user.role !== 'super_admin') {
    if (user.role === 'manager') {
      // 经理 — 查所管理部门的所有员工客户
      const deptResult = await pgPool.query(
        `SELECT id FROM departments WHERE manager_id = $1 AND is_active = true`,
        [user.userId]
      );
      const deptIds = deptResult.rows.map((r: any) => r.id);
      if (deptIds.length > 0) {
        const userInDept = await pgPool.query(
          `SELECT id FROM users WHERE department_id = ANY($1::uuid[]) AND is_active = true`,
          [deptIds]
        );
        const userIds = [...new Set([user.userId, ...userInDept.rows.map((r: any) => r.id)])];
        const mph = userIds.map((_, i) => `$${i + 1}`).join(',');
        params.splice(0, params.length, ...userIds); // replace existing params
        whereClause = `WHERE (c.is_active = true OR c.is_active IS NULL) AND (c.created_by IN (${mph}))`;
      } else {
        // 该经理没有管理部门，退化为只看自己
        params.push(user.userId);
        whereClause += ' AND c.created_by = $' + params.length;
      }
    } else {
      // 普通员工 — 只看自己创建或负责的客户
      params.push(user.userId);
      whereClause += ' AND (c.created_by = $' + params.length + ' OR c.manager_id = $' + params.length + ')';
    }
  }

  if (keyword) {
    params.push(`%${keyword}%`);
    const kwIdx = params.length;
    whereClause += ` AND (c.name ILIKE $${kwIdx} OR c.phone ILIKE $${kwIdx} OR c.address ILIKE $${kwIdx})`;
  }

  const countResult = await pgPool.query(`SELECT COUNT(*)::int as total FROM customers c ${whereClause}`, params);
  const total = countResult.rows[0].total;

  const dataResult = await pgPool.query(
    `SELECT c.id, c.name, c.phone, c.address, c.lng, c.lat, c.industry, c.level, c.status,
            c.remark, c.tags, c.created_by, c.created_at, c.updated_at,
            u.name as created_by_name
     FROM customers c
     LEFT JOIN users u ON c.created_by = u.id
     ${whereClause}
     ORDER BY c.created_at DESC
     LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
    [...params, pageSize, offset]
  );

  const customers = dataResult.rows.map(r => ({
    id: r.id,
    name: r.name,
    phone: r.phone || '',
    address: r.address || '',
    lng: r.lng || 0,
    lat: r.lat || 0,
    tags: r.tags || [],
    remark: r.remark || '',
    industry: r.industry || '',
    level: r.level || 'B',
    status: r.status || 'active',
    createdBy: r.created_by_name || '',
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  }));

  res.json({ customers, total });
  } catch (err) {
    next(err);
  }
});

// POST /api/v1/customers — 创建客户
router.post('/',
  validate([
    body('name').notEmpty().withMessage('客户名称不能为空'),
    body('phone').optional().matches(/^1\d{10}$/).withMessage('手机号格式不正确'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const { name, phone, address, lat, lng, tags, remark, industry, level } = req.body;

    const result = await pgPool.query(
      `INSERT INTO customers (name, phone, address, lng, lat, tags, remark, industry, level, status, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'active', $10)
       RETURNING id, created_at`,
      [name, phone || '', address || '', lat || 0, lng || 0, tags || [], remark || '',
       industry || '', level || 'B', user.userId]
    );

    const r = result.rows[0];
    res.status(201).json({
      id: r.id, name, phone: phone || '', address: address || '',
      lat: lat || 0, lng: lng || 0, tags: tags || [], remark: remark || '',
      industry: industry || '', level: level || 'B',
      createdAt: r.created_at, updatedAt: r.created_at,
    });
  } catch (err) {
    next(err);
  }
  },
);

// PUT /api/v1/customers/:id
router.put('/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const user = (req as any).user as JwtPayload;
    // 校验：只有创建者或管理员才能修改
  const existing = await pgPool.query('SELECT * FROM customers WHERE id=$1', [req.params.id]);
  if (existing.rows.length === 0) return res.status(404).json({ code: '10014', message: '客户不存在' });
  if (user.role !== 'admin' && existing.rows[0].created_by !== user.userId) {
    return res.status(403).json({ code: ErrorCodes.AUTH_FORBIDDEN.code, message: ErrorCodes.AUTH_FORBIDDEN.message });
  }
  const cur = existing.rows[0];
  const result = await pgPool.query(
    `UPDATE customers SET
      name=$1, phone=$2, address=$3, lng=$4, lat=$5,
      tags=$6, remark=$7, industry=$8, level=$9, status=$10,
      updated_at=NOW()
     WHERE id=$11 RETURNING id, name, phone, address, lng, lat, tags, remark, industry, level, status, created_at, updated_at`,
    [
      'name' in req.body ? req.body.name : cur.name,
      'phone' in req.body ? req.body.phone : cur.phone,
      'address' in req.body ? req.body.address : cur.address,
      'lng' in req.body ? req.body.lng : cur.lng,
      'lat' in req.body ? req.body.lat : cur.lat,
      'tags' in req.body ? req.body.tags : cur.tags,
      'remark' in req.body ? req.body.remark : cur.remark,
      'industry' in req.body ? req.body.industry : cur.industry,
      'level' in req.body ? req.body.level : cur.level,
      'status' in req.body ? req.body.status : cur.status,
      req.params.id,
    ],
  );
  if (result.rows.length === 0) return res.status(404).json({ code: '10014', message: '客户不存在' });
  const r = result.rows[0];
  res.json({
    id: r.id, name: r.name, phone: r.phone||'', address: r.address||'',
    lat: r.lat||0, lng: r.lng||0, tags: r.tags||[], remark: r.remark||'',
    industry: r.industry||'', level: r.level||'B', status: r.status||'active',
    createdAt: r.created_at, updatedAt: r.updated_at,
  });
  } catch (err) {
    next(err);
  }
});

// DELETE /api/v1/customers/:id
router.delete('/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const user = (req as any).user as JwtPayload;
    // 校验：只有创建者或管理员才能删除
  const existing = await pgPool.query('SELECT created_by FROM customers WHERE id=$1', [req.params.id]);
  if (existing.rows.length === 0) return res.status(404).json({ code: '10014', message: '客户不存在' });
  if (user.role !== 'admin' && existing.rows[0].created_by !== user.userId) {
    return res.status(403).json({ code: ErrorCodes.AUTH_FORBIDDEN.code, message: ErrorCodes.AUTH_FORBIDDEN.message });
  }
  const result = await pgPool.query('UPDATE customers SET is_active=false WHERE id=$1 RETURNING id', [req.params.id]);
  if (result.rows.length === 0) return res.status(404).json({ code: '10014', message: '客户不存在' });
  res.json({ success: true });
  } catch (err) {
    next(err);
  }
});

// ---- 拜访记录 ----

// POST /api/v1/customers/visit — 记录拜访
router.post('/visit',
  adminMiddleware,
  validate([
    body('customerId').notEmpty().withMessage('客户ID不能为空'),
    body('content').notEmpty().withMessage('拜访内容不能为空'),
  ]),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const { customerId, content, address, lat, lng, photos } = req.body;

    const result = await pgPool.query(
      `INSERT INTO visit_records (user_id, customer_id, visit_type, status, content, signin_lng, signin_lat, signin_address, has_photo)
       VALUES ($1, $2, 'field', 'completed', $3, $4, $5, $6, $7)
       RETURNING id, created_at`,
      [user.userId, customerId, content, lng || null, lat || null, address||'', photos?photos.length>0:false]
    );

    const r = result.rows[0];
    res.status(201).json({
      id: r.id, userId: user.userId, customerId, content,
      address: address || '', lat: lat || 0, lng: lng || 0,
      photos: photos || [],
      createdAt: r.created_at,
    });
  } catch (err) {
    next(err);
  }
  },
);

// GET /api/v1/customers/visits — 拜访记录列表
router.get('/visits',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = (req as any).user as JwtPayload;
      const customerId = req.query.customerId as string || null;

    let whereClause = 'WHERE v.user_id = $1';
    const params: any[] = [user.userId];

    if (customerId) {
      params.push(customerId);
      whereClause += ` AND v.customer_id = $${params.length}`;
    }

    const result = await pgPool.query(
      `SELECT v.id, v.user_id, v.customer_id, c.name as customer_name, v.visit_type, v.status,
              v.content, v.signin_address as address, v.signin_lat as lat, v.signin_lng as lng,
              v.has_photo, v.created_at
       FROM visit_records v
       LEFT JOIN customers c ON v.customer_id = c.id
       ${whereClause}
       ORDER BY v.created_at DESC LIMIT 100`,
      params
    );

    const visits = result.rows.map(r => ({
      id: r.id,
      userId: r.user_id,
      customerId: r.customer_id,
      customerName: r.customer_name || '未知客户',
      content: r.content || '',
      address: r.address || '',
      lat: r.lat || 0,
      lng: r.lng || 0,
      hasPhoto: r.has_photo,
      createdAt: r.created_at,
    }));

    res.json({ visits, total: visits.length });
  } catch (err) {
    next(err);
  }
  },
);

export default router;
