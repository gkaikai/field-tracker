import { Router, Request, Response } from 'express';
import { body, query } from 'express-validator';
import { authMiddleware, JwtPayload } from '../middleware/auth';
import { validate } from '../middleware/validate';

const router = Router();
router.use(authMiddleware);

// ============================================================
//  内存存储 - 客户管理
// ============================================================

interface Customer {
  id: number;
  userId: string;
  name: string;
  phone: string;
  address: string;
  lat: number;
  lng: number;
  tags: string[];
  remark: string;
  createdAt: string;
  updatedAt: string;
}

interface VisitRecord {
  id: number;
  userId: string;
  customerId: number;
  customerName: string;
  content: string;
  lat: number;
  lng: number;
  photos: string[];
  createdAt: string;
}

let customers: Customer[] = [];
let visits: VisitRecord[] = [];
let customerIdSeq = 1;
let visitIdSeq = 1;

// ---- 客户 CRUD ----

// GET /api/v1/customers — 客户列表
router.get('/', async (req: Request, res: Response) => {
  const user = (req as any).user as JwtPayload;
  const page = parseInt(req.query.page as string) || 1;
  const pageSize = parseInt(req.query.pageSize as string) || 50;
  const keyword = (req.query.keyword as string || '').toLowerCase();

  let filtered = customers.filter(c => c.userId === user.userId);
  if (keyword) {
    filtered = filtered.filter(c =>
      c.name.toLowerCase().includes(keyword) ||
      c.phone.includes(keyword) ||
      c.address.toLowerCase().includes(keyword)
    );
  }
  filtered.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

  const total = filtered.length;
  const paged = filtered.slice((page - 1) * pageSize, page * pageSize);
  res.json({ customers: paged, total });
});

// POST /api/v1/customers — 创建客户
router.post('/',
  validate([body('name').notEmpty().withMessage('客户名称不能为空')]),
  async (req: Request, res: Response) => {
    const user = (req as any).user as JwtPayload;
    const { name, phone, address, lat, lng, tags, remark } = req.body;
    const customer: Customer = {
      id: customerIdSeq++, userId: user.userId, name, phone: phone || '',
      address: address || '', lat: lat || 0, lng: lng || 0,
      tags: tags || [], remark: remark || '',
      createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(),
    };
    customers.push(customer);
    res.status(201).json(customer);
  },
);

// PUT /api/v1/customers/:id
router.put('/:id', async (req: Request, res: Response) => {
  const idx = customers.findIndex(c => c.id === parseInt(req.params.id));
  if (idx === -1) return res.status(404).json({ code: '10014', message: '客户不存在' });
  customers[idx] = { ...customers[idx], ...req.body, id: customers[idx].id, updatedAt: new Date().toISOString() };
  res.json(customers[idx]);
});

// DELETE /api/v1/customers/:id
router.delete('/:id', async (req: Request, res: Response) => {
  const idx = customers.findIndex(c => c.id === parseInt(req.params.id));
  if (idx === -1) return res.status(404).json({ code: '10014', message: '客户不存在' });
  customers.splice(idx, 1);
  res.json({ success: true });
});

// ---- 拜访记录 ----

// POST /api/v1/customers/visit — 记录拜访
router.post('/visit',
  validate([
    body('customerId').isInt().withMessage('客户ID不能为空'),
    body('content').notEmpty().withMessage('拜访内容不能为空'),
  ]),
  async (req: Request, res: Response) => {
    const user = (req as any).user as JwtPayload;
    const { customerId, content, lat, lng, photos } = req.body;
    const customer = customers.find(c => c.id === customerId);
    const visit: VisitRecord = {
      id: visitIdSeq++, userId: user.userId, customerId, photos: photos || [],
      customerName: customer?.name || '未知客户', content, lat: lat || 0, lng: lng || 0,
      createdAt: new Date().toISOString(),
    };
    visits.push(visit);
    res.status(201).json(visit);
  },
);

// GET /api/v1/customers/visits — 拜访记录列表
router.get('/visits',
  async (req: Request, res: Response) => {
    const user = (req as any).user as JwtPayload;
    const customerId = req.query.customerId ? parseInt(req.query.customerId as string) : null;
    let filtered = visits.filter(v => v.userId === user.userId);
    if (customerId) filtered = filtered.filter(v => v.customerId === customerId);
    filtered.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
    res.json({ visits: filtered.slice(0, 100), total: filtered.length });
  },
);

export default router;
