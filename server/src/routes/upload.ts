import { Router, Request, Response, NextFunction } from 'express';
import { authMiddleware } from '../middleware/auth';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { pgPool } from '../config/database';
import { ErrorCodes } from '../errors/errorCodes';

const router = Router();
router.use(authMiddleware);

// 确保上传目录存在
const UPLOAD_DIR = path.join(__dirname, '../../uploads/photos');
if (!fs.existsSync(UPLOAD_DIR)) {
  fs.mkdirSync(UPLOAD_DIR, { recursive: true });
}

// 允许的图片 MIME 类型（fileFilter + 扩展名推导共享同一列表）
const ALLOWED_IMAGE_MIMES: Record<string, string> = {
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/webp': '.webp',
  'image/gif': '.gif',
  'image/heic': '.heic',
  'image/heif': '.heif',
};

/// 文件魔数签名表（用于校验文件内容真实性）
const MAGIC_SIGNATURES: Record<string, Uint8Array[]> = {
  'image/jpeg': [new Uint8Array([0xFF, 0xD8, 0xFF])],
  'image/png': [new Uint8Array([0x89, 0x50, 0x4E, 0x47])],
  'image/gif': [new Uint8Array([0x47, 0x49, 0x46, 0x38])],
  'image/webp': [new Uint8Array([0x52, 0x49, 0x46, 0x46])], // 运行时动态校验WEBP marker
};

/// 校验文件前4字节是否匹配预期魔数
function validateMagicNumber(filePath: string, mimeType: string): boolean {
  try {
    const sigs = MAGIC_SIGNATURES[mimeType];
    if (!sigs) return true; // HEIC/HEIF 跳过魔数校验
    const maxLen = Math.max(...sigs.map(s => s.length));
    const buf = Buffer.alloc(maxLen);
    const fd = fs.openSync(filePath, 'r');
    fs.readSync(fd, buf, 0, maxLen, 0);
    fs.closeSync(fd);
    // 对 WebP 特殊处理：校验 RIFF header + WEBP marker（跳过4字节文件大小）
  if (mimeType === 'image/webp' && buf.length >= 12) {
    const isRiff = buf[0] === 0x52 && buf[1] === 0x49 && buf[2] === 0x46 && buf[3] === 0x46;
    const isWebp = buf[8] === 0x57 && buf[9] === 0x45 && buf[10] === 0x42 && buf[11] === 0x50;
    return isRiff && isWebp;
  }
  return sigs.some(sig => sig.every((b, i) => b === buf[i]));
  } catch {
    return false;
  }
}

// multer 配置
const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, UPLOAD_DIR),
  filename: (_req, file, cb) => {
    // 从 MIME type 推导扩展名，不信任客户端原始文件名
    const ext = ALLOWED_IMAGE_MIMES[file.mimetype] || '.jpg';
    cb(null, `photo_${Date.now()}_${Math.random().toString(36).slice(2, 8)}${ext}`);
  },
});
const upload = multer({
  storage,
  limits: { fileSize: 20 * 1024 * 1024 }, // 20MB
  fileFilter: (_req: any, file: any, cb: any) => {
    if (ALLOWED_IMAGE_MIMES[file.mimetype]) {
      cb(null, true);
    } else {
      cb(new Error(`仅支持 ${Object.keys(ALLOWED_IMAGE_MIMES).map(m => m.split('/')[1].toUpperCase()).join('/')} 格式的图片`));
    }
  },
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
    // 校验 bizType 有效性
    const validBizTypes = ['attendance', 'visit', 'report', 'customer'];
    if (!validBizTypes.includes(bizType)) {
      return res.status(400).json({ code: ErrorCodes.BAD_REQUEST.code, message: ErrorCodes.BAD_REQUEST.message });
    }

    // 校验文件魔数（防止伪造MIME类型上传非图片文件）
    if (!validateMagicNumber(file.path, file.mimetype)) {
      // 删除非法文件
      fs.unlink(file.path, () => {});
      return res.status(400).json({ code: ErrorCodes.INVALID_FILE.code, message: ErrorCodes.INVALID_FILE.message });
    }
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
