import { Router, Request, Response } from 'express';
import { body, query } from 'express-validator';
import { authMiddleware, roleMiddleware, JwtPayload } from '../middleware/auth';
import { validate } from '../middleware/validate';

const router = Router();
router.use(authMiddleware);

// 内存存储日报
interface Report {
  id: number;
  userId: string;
  userName: string;
  type: 'daily' | 'weekly' | 'monthly';
  content: string;
  summary: string;
  date: string; // YYYY-MM-DD
  createdAt: string;
}
const reports: Report[] = [];
let reportIdSeq = 1;

// POST /api/v1/reports — 创建汇报
router.post('/',
  validate([
    body('type').isIn(['daily', 'weekly', 'monthly']).withMessage('类型无效'),
    body('content').notEmpty().withMessage('汇报内容不能为空'),
    body('date').optional().matches(/^\d{4}-\d{2}-\d{2}$/),
  ]),
  async (req: Request, res: Response) => {
    const user = (req as any).user as JwtPayload;
    const { type, content, summary, date } = req.body;
    const report: Report = {
      id: reportIdSeq++,
      userId: user.userId,
      userName: user.phone,
      type, content, summary: summary || '',
      date: date || new Date().toISOString().split('T')[0],
      createdAt: new Date().toISOString(),
    };
    reports.push(report);
    res.status(201).json(report);
  },
);

// GET /api/v1/reports — 获取汇报列表
router.get('/',
  validate([
    query('type').optional().isIn(['daily', 'weekly', 'monthly']),
    query('date').optional().matches(/^\d{4}-\d{2}-\d{2}$/),
    query('page').optional().isInt({ min: 1 }).toInt(),
    query('pageSize').optional().isInt({ min: 1, max: 50 }).toInt(),
  ]),
  async (req: Request, res: Response) => {
    const user = (req as any).user as JwtPayload;
    const page = parseInt(req.query.page as string) || 1;
    const pageSize = parseInt(req.query.pageSize as string) || 20;

    let filtered = reports.filter(r => r.userId === user.userId);
    if (req.query.type) filtered = filtered.filter(r => r.type === req.query.type);
    if (req.query.date) filtered = filtered.filter(r => r.date === req.query.date);

    filtered.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
    const total = filtered.length;
    const paged = filtered.slice((page - 1) * pageSize, page * pageSize);

    res.json({ reports: paged, pagination: { page, pageSize, total, totalPages: Math.ceil(total / pageSize) } });
  },
);

// GET /api/v1/reports/stats — 统计
router.get('/stats',
  async (req: Request, res: Response) => {
    const user = (req as any).user as JwtPayload;
    const myReports = reports.filter(r => r.userId === user.userId);
    const dailyCount = myReports.filter(r => r.type === 'daily').length;
    const weeklyCount = myReports.filter(r => r.type === 'weekly').length;
    res.json({ total: myReports.length, daily: dailyCount, weekly: weeklyCount });
  },
);

// DELETE /api/v1/reports/:id
router.delete('/:id', async (req: Request, res: Response) => {
  const idx = reports.findIndex(r => r.id === parseInt(req.params.id));
  if (idx === -1) return res.status(404).json({ code: '10014', message: '汇报不存在' });
  reports.splice(idx, 1);
  res.json({ success: true });
});

export default router;
