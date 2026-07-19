import { Router, Request, Response, NextFunction } from 'express';
import { authMiddleware } from '../middleware/auth';
import multer from 'multer';
import path from 'path';
import fs from 'fs';

const router = Router();
router.use(authMiddleware);

// 确保上传目录存在
const UPLOAD_DIR = path.join(__dirname, '../../uploads/photos');
if (!fs.existsSync(UPLOAD_DIR)) {
  fs.mkdirSync(UPLOAD_DIR, { recursive: true });
}

// 内存存储照片记录
interface PhotoRecord {
  id: number;
  userId: string;
  url: string;
  fileName: string;
  lat: number;
  lng: number;
  address: string;
  createdAt: string;
}
const photoStore: PhotoRecord[] = [];
let photoIdSeq = 1;

// multer 配置
const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, UPLOAD_DIR),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname) || '.png';
    cb(null, `photo_${Date.now()}_${Math.random().toString(36).slice(2, 8)}${ext}`);
  },
});
const upload = multer({
  storage,
  limits: { fileSize: 20 * 1024 * 1024 }, // 20MB
});

// POST /api/v1/upload/photo — 上传水印照片
router.post('/photo', upload.single('photo'), (req: Request, res: Response) => {
  const user = (req as any).user;
  const file = req.file;

  if (!file) {
    return res.status(400).json({ code: '400', message: '未提供照片文件' });
  }

  const record: PhotoRecord = {
    id: photoIdSeq++,
    userId: user.userId,
    url: `/uploads/photos/${file.filename}`,
    fileName: file.filename,
    lat: parseFloat(req.body.lat || '0'),
    lng: parseFloat(req.body.lng || '0'),
    address: req.body.address || '',
    createdAt: new Date().toISOString(),
  };
  photoStore.push(record);

  res.json({
    success: true,
    id: record.id,
    url: record.url,
    createdAt: record.createdAt,
  });
});

// GET /api/v1/upload/photos — 获取我的水印照片列表
router.get('/photos', (req: Request, res: Response) => {
  const user = (req as any).user;
  const myPhotos = photoStore
    .filter(p => p.userId === user.userId)
    .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

  res.json({ photos: myPhotos, total: myPhotos.length });
});

export default router;
