// 组织架构管理

import { Router, Request, Response } from 'express';
import { body } from 'express-validator';
import { authMiddleware, JwtPayload } from '../middleware/auth';
import { validate } from '../middleware/validate';

const router = Router();
router.use(authMiddleware);

// 内存存储
interface Department {
  id: number;
  name: string;
  parentId: number | null;
  manager: string;
  sort: number;
  createdAt: string;
}
const departments: Department[] = [
  { id: 1, name: '总公司', parentId: null, manager: '管理员', sort: 0, createdAt: new Date().toISOString() },
];
let deptIdSeq = 2;

// 用户扩展信息
interface UserProfile {
  userId: string;
  name: string;
  phone: string;
  departmentId: number | null;
  role: 'staff' | 'manager' | 'admin';
}
// 用户扩展信息（导出供auth模块同步使用）
export const userProfiles: UserProfile[] = [];
let profileInit = false;

// GET /api/v1/org/departments — 部门树
router.get('/departments', async (_req: Request, res: Response) => {
  res.json(departments.sort((a, b) => a.sort - b.sort));
});

// POST /api/v1/org/departments — 创建部门
router.post('/departments',
  validate([body('name').notEmpty().withMessage('部门名称不能为空')]),
  async (req: Request, res: Response) => {
    const { name, parentId, manager, sort } = req.body;
    const dept: Department = {
      id: deptIdSeq++, name, parentId: parentId || null,
      manager: manager || '', sort: sort || 0, createdAt: new Date().toISOString(),
    };
    departments.push(dept);
    res.status(201).json(dept);
  },
);

// PUT /api/v1/org/departments/:id
router.put('/departments/:id', async (req: Request, res: Response) => {
  const idx = departments.findIndex(d => d.id === parseInt(req.params.id));
  if (idx === -1) return res.status(404).json({ code: '10014', message: '部门不存在' });
  departments[idx] = { ...departments[idx], ...req.body, id: departments[idx].id };
  res.json(departments[idx]);
});

// DELETE /api/v1/org/departments/:id
router.delete('/departments/:id', async (req: Request, res: Response) => {
  const idx = departments.findIndex(d => d.id === parseInt(req.params.id));
  if (idx === -1) return res.status(404).json({ code: '10014', message: '部门不存在' });
  departments.splice(idx, 1);
  res.json({ success: true });
});

// ---- 用户组织信息 ----

// GET /api/v1/org/users — 组织内用户列表
router.get('/users', async (_req: Request, res: Response) => {
  const { default: authRoutes } = await import('./auth');
  // 从TEST_USERS构建完整用户列表
  const { default: authModule } = await import('./auth');
  res.json(userProfiles);
});

// DELETE /api/v1/org/users/:phone — 删除用户
router.delete('/users/:phone', async (req: Request, res: Response) => {
  const idx = userProfiles.findIndex(u => u.phone === req.params.phone);
  if (idx === -1) return res.status(404).json({ code: 'NOT_FOUND', message: '用户不存在' });
  userProfiles.splice(idx, 1);
  res.json({ success: true });
});

// PUT /api/v1/org/users/:id — 更新用户部门/角色
router.put('/users/:id', async (req: Request, res: Response) => {
  const idx = userProfiles.findIndex(u => u.userId === req.params.id);
  if (idx === -1) return res.status(404).json({ code: '10014', message: '用户不存在' });
  Object.assign(userProfiles[idx], req.body);
  res.json(userProfiles[idx]);
});

// 初始化默认用户信息（导出供auth模块使用）
export function initUserProfiles() {
  if (profileInit) return;
  // 在实际应用中从auth模块获取用户列表
  userProfiles.push({ userId: '1', name: '管理员', phone: '13800138000', departmentId: 1, role: 'admin' });
  profileInit = true;
}
initUserProfiles();

// ---- 多人实时位置（Web端用） ----
// 增强版：含部门信息
router.get('/locations/online', async (req: Request, res: Response) => {
  try {
    // 从location模块获取当前在线位置（通过内部机制）
    const resp = await fetch('http://localhost:3000/api/v1/location/batch', {
      headers: { 'Authorization': req.headers.authorization || '' }
    });
    const data: any = await resp.json();
    // 附加部门信息
    const locations = (data.locations || []).map((loc: any) => {
      const profile = userProfiles.find(u => u.userId === loc.userId);
      return { ...loc, department: profile?.name || '未分配', departmentId: profile?.departmentId };
    });
    res.json({ locations, total: locations.length });
  } catch (e: any) {
    res.json({ locations: [], total: 0 });
  }
});

export default router;
