import { Router, Request, Response } from 'express';
import { authMiddleware } from '../middleware/auth';

const router = Router();

// 内存中保存当前隧道URL（重启丢失，首次启动时从TUNNEL_URL环境变量读取）
let currentTunnelUrl = process.env.TUNNEL_URL || '';
let backupTunnelUrl = '';  // 备用隧道URL

// ── GET /api/v1/tunnel — APK轮询获取最新隧道URL（含备用） ──
// 需要认证，防止泄露内网入口
router.get('/', authMiddleware, (_req: Request, res: Response) => {
  res.json({
    url: currentTunnelUrl,
    backup_url: backupTunnelUrl,
    updated_at: new Date().toISOString(),
    ttl_seconds: 1800,  // 预估有效期30分钟
  });
});

// ── POST /api/v1/tunnel — 保活脚本上报新隧道URL（仅限localhost） ──
router.post('/', (req: Request, res: Response) => {
  const ip = req.ip || req.socket.remoteAddress || '';
  if (ip !== '127.0.0.1' && ip !== '::1' && ip !== '::ffff:127.0.0.1' && req.hostname !== 'localhost') {
    res.status(403).json({ error: 'forbidden' });
    return;
  }
  const { url } = req.body;
  if (url && typeof url === 'string') {
    currentTunnelUrl = url;
    console.log(`[tunnel] URL已更新: ${url}`);
    res.json({ ok: true, url });
  } else {
    res.status(400).json({ error: 'missing or invalid url' });
  }
});

// ── POST /api/v1/tunnel/backup — 保活脚本上报备用隧道URL（仅限localhost）
router.post('/backup', (req: Request, res: Response) => {
  const ip = req.ip || req.socket.remoteAddress || '';
  if (ip !== '127.0.0.1' && ip !== '::1' && ip !== '::ffff:127.0.0.1' && req.hostname !== 'localhost') {
    res.status(403).json({ error: 'forbidden' });
    return;
  }
  const { url } = req.body;
  if (url && typeof url === 'string') {
    backupTunnelUrl = url;
    console.log(`[tunnel] 备用URL已更新: ${url}`);
    res.json({ ok: true, url });
  } else {
    res.status(400).json({ error: 'missing or invalid url' });
  }
});

// ── GET /api/v1/tunnel/health — 健康检查 ──
router.get('/health', (_req: Request, res: Response) => {
  res.json({ ok: true, timestamp: Date.now() });
});

export default router;
