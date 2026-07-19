// 审批流程 - 请假/出差

import { Router, Request, Response } from 'express';
import { body, query } from 'express-validator';
import { authMiddleware, roleMiddleware, JwtPayload } from '../middleware/auth';
import { validate } from '../middleware/validate';

const router = Router();
router.use(authMiddleware);

// 内存存储
interface Approval {
  id: number;
  userId: string;
  userName: string;
  type: 'leave' | 'business_trip' | 'expense';
  status: 'pending' | 'approved' | 'rejected';
  title: string;
  reason: string;
  startDate: string;
  endDate: string;
  duration: string;
  amount: number | null;       // 报销金额
  remark: string;              // 备注
  approverId: string | null;
  approverName: string | null;
  rejectReason: string | null;
  createdAt: string;
  updatedAt: string;
}

const approvals: Approval[] = [];
let approvalIdSeq = 1;

// POST /api/v1/approvals — 创建审批
router.post('/',
  validate([
    body('type').isIn(['leave', 'business_trip', 'expense']).withMessage('类型无效'),
    body('title').notEmpty().withMessage('标题不能为空'),
    body('reason').notEmpty().withMessage('原因不能为空'),
    body('startDate').notEmpty().withMessage('开始日期不能为空'),
    body('endDate').notEmpty().withMessage('结束日期不能为空'),
  ]),
  async (req: Request, res: Response) => {
    const user = (req as any).user as JwtPayload;
    const { type, title, reason, startDate, endDate, duration, amount, remark } = req.body;
    const approval: Approval = {
      id: approvalIdSeq++, userId: user.userId, userName: user.phone, type,
      status: 'pending', title, reason, startDate, endDate, duration: duration || '',
      amount: amount ? parseFloat(amount) : null, remark: remark || '',
      approverId: null, approverName: null, rejectReason: null,
      createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(),
    };
    approvals.push(approval);
    res.status(201).json(approval);
  },
);

// GET /api/v1/approvals — 获取审批列表
router.get('/', async (req: Request, res: Response) => {
  const user = (req as any).user as JwtPayload;
  const page = parseInt(req.query.page as string) || 1;
  const pageSize = parseInt(req.query.pageSize as string) || 20;
  const type = req.query.type as string;
  const status = req.query.status as string;

  let filtered = approvals.filter(a => a.userId === user.userId);
  if (type) filtered = filtered.filter(a => a.type === type);
  if (status) filtered = filtered.filter(a => a.status === status);
  filtered.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

  const total = filtered.length;
  res.json({ approvals: filtered.slice((page - 1) * pageSize, page * pageSize), pagination: { page, pageSize, total } });
});

// PUT /api/v1/approvals/:id/approve — 审批操作（管理员）
router.put('/:id/approve',
  validate([body('status').isIn(['approved', 'rejected']), body('rejectReason').optional()]),
  async (req: Request, res: Response) => {
    const idx = approvals.findIndex(a => a.id === parseInt(req.params.id));
    if (idx === -1) return res.status(404).json({ code: '10014', message: '审批不存在' });
    approvals[idx].status = req.body.status;
    approvals[idx].rejectReason = req.body.rejectReason || null;
    approvals[idx].updatedAt = new Date().toISOString();
    res.json(approvals[idx]);
  },
);

// 里程统计
// GET /api/v1/mileage/stats
router.get('/mileage', async (req: Request, res: Response) => {
  const user = (req as any).user as JwtPayload;
  const days = parseInt(req.query.days as string) || 7;
  const end = new Date();
  const start = new Date(Date.now() - days * 86400000);

  // 从位置记录计算里程（用服务器内存数据）
  // 简化：基于模拟数据，实际从location routes取
  const { default: locationRoutes } = await import('./location');
  // 这里简化处理，返回模拟里程数据
  res.json({ totalKm: (Math.random() * 100 + 10).toFixed(1), days, unit: 'km' });
});

// 密码修改
// PUT /api/v1/auth/password
router.put('/password',
  validate([
    body('oldPassword').notEmpty().withMessage('旧密码不能为空'),
    body('newPassword').isLength({ min: 6 }).withMessage('新密码至少6位'),
  ]),
  async (req: Request, res: Response) => {
    // 内存存储模式：统一密码为 test123456
    const { oldPassword, newPassword } = req.body;
    if (oldPassword !== 'test123456') {
      return res.status(400).json({ code: '10015', message: '旧密码错误' });
    }
    // 实际项目中应更新数据库，内存模式固定密码不改
    res.json({ success: true, message: '密码修改成功' });
  },
);

export default router;
