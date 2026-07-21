import { Router, Request, Response, NextFunction } from 'express';
import { authMiddleware } from '../middleware/auth';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { pgPool } from '../config/database';

const router = Router();
router.use(authMiddleware);

// 确保上传目录存在
const UPLOAD_DIR = path.join(__dirname, '../../uploads/photos');
if (!fs.existsSync(UPLOAD_DIR)) {
  fs.mkdirSync(UPLOAD_DIR, { recursive: true });
}

// multer 配置
const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, UPLOAD_DIR),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname) || '.jpg';
    cb(null, `photo_${Date.now()}_${Math.random().toString(36).slice(2, 8)}${ext}`);
  },
});
const upload = multer({
  storage,
  limits: { fileSize: 20 * 1024 * 1024 }, // 20MB
});

// POST /api/v1/upload/photo — 上传水印照片
router.post('/photo', upload.single('photo'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const user = (req as any).user;
    const file = req.file;
    if (!file) {
      return res.status(400).json({ code: '400', message: '未提供照片文件' });
    }

    const bizType = req.body.bizType || 'attendance';
    const bizId = req.body.bizId || null;
    const url = `/uploads/photos/${file.filename}`;

    const result = await pgPool.query(
      `INSERT INTO photos (user_id, biz_type, biz_id, file_name, file_size, mime_type, storage_path, url, lng, lat, remark)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
       RETURNING id, url, created_at`,
      [
        user.userId,
        bizType,
        bizId,
        file.filename,
        file.size,
        file.mimetype || 'image/jpeg',
        url,
        url,
        parseFloat(req.body.lng || '0'),
        parseFloat(req.body.lat || '0'),
        req.body.address || null,
      ],
    );

    const record = result.rows[0];
    res.json({
      success: true,
      id: record.id,
      url: record.url,
      createdAt: record.created_at,
    });
  } catch (err) {
    next(err);
  }
});

// GET /api/v1/upload/photos — 获取我的水印照片列表
router.get('/photos', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const user = (req as any).user;
    const result = await pgPool.query(
      `SELECT id, url, lng, lat, remark, created_at
       FROM photos
       WHERE user_id = $1 AND is_deleted = false
       ORDER BY created_at DESC
       LIMIT 200`,
      [user.userId],
    );
    const photos = result.rows.map(r => ({
      id: r.id,
      url: r.url,
      lng: r.lng,
      lat: r.lat,
      address: r.remark || '',
      time: r.created_at,
    }));
    res.json({ photos, total: photos.length });
  } catch (err) {
    next(err);
  }
});

export default router;
