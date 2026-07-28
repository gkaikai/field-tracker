/// 心跳状态 REST API 路由
///
/// 提供管理后台和外部查询接口:
///   GET  /api/v1/heartbeat/status        → 返回所有 client 心跳状态
///   GET  /api/v1/heartbeat/cooldown       → 返回各 client 冷却期剩余时间
///   POST /api/v1/heartbeat/reset-cooldown → 手动重置冷却期

import { Router, Request, Response } from 'express';
import {
  getOnlineClients,
  getConnectionStatus,
  resetCooldown,
  getCooldownRemaining,
  getOnlineCount,
} from '../websocket/heartbeat_ws';
import { authMiddleware, roleMiddleware } from '../middleware/auth';

const router = Router();

// 所有心跳路由需要认证（仅 admin 可访问）
router.use(authMiddleware);
router.use(roleMiddleware('admin'));

// ============================================================
//  GET /api/v1/heartbeat/status
//  返回所有 client 的心跳状态
// ============================================================
router.get('/status', (_req: Request, res: Response) => {
  const clients = getOnlineClients();
  const overallStatus = getConnectionStatus();

  const formatted = clients.map(c => ({
    clientId: c.clientId,
    lastPing: c.lastPingTime,
    lastPingAgo: Date.now() - c.lastPingTime,
    connectedAt: c.connectedAt,
    warned: c.warned,
    inCooldown: c.disconnectedAt !== null && (Date.now() - c.disconnectedAt) < 360_000,
    disconnectedAt: c.disconnectedAt,
  }));

  res.json({
    success: true,
    data: {
      totalClients: getOnlineCount(),
      overallStatus,
      clients: formatted,
    },
  });
});

// ============================================================
//  GET /api/v1/heartbeat/cooldown
//  返回各 client 冷却期剩余时间（秒）
// ============================================================
router.get('/cooldown', (_req: Request, res: Response) => {
  const clients = getOnlineClients();
  const cooldowns: Record<string, { remainingSec: number; inCooldown: boolean }> = {};

  for (const c of clients) {
    const remainingSec = getCooldownRemaining(c.clientId);
    cooldowns[c.clientId] = {
      remainingSec,
      inCooldown: remainingSec > 0,
    };
  }

  res.json({
    success: true,
    data: {
      totalClients: getOnlineCount(),
      cooldowns,
    },
  });
});

// ============================================================
//  POST /api/v1/heartbeat/reset-cooldown
//  手动重置指定 client 的冷却期
//  Body: { clientId: string }
// ============================================================
router.post('/reset-cooldown', (req: Request, res: Response) => {
  const { clientId } = req.body;

  if (!clientId || typeof clientId !== 'string') {
    res.status(400).json({
      success: false,
      error: '缺少 clientId 参数',
    });
    return;
  }

  const ok = resetCooldown(clientId);

  if (!ok) {
    res.status(404).json({
      success: false,
      error: `client "${clientId}" 未找到`,
    });
    return;
  }

  res.json({
    success: true,
    message: `client "${clientId}" 冷却期已重置`,
    data: { clientId },
  });
});

export default router;
