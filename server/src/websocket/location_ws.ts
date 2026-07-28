/// 定位 WebSocket 服务
/// 
/// 功能：
///   1. 客户端连接后，实时接收位置上报
///   2. 广播给该用户所属组织的管理者
///   3. 管理者打开 Web 管理端时，接收所有下属的实时位置

import { WebSocketServer, WebSocket } from 'ws';
import { IncomingMessage } from 'http';
import { pgPool, redis } from '../config/database';
import jwt from 'jsonwebtoken';

function getJwtSecret(): string {
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    throw new Error('JWT_SECRET 环境变量未设置');
  }
  return secret;
}

interface LocationPayload {
  userId: string;
  lng: number;
  lat: number;
  accuracy?: number;
  speed?: number;
  battery?: number;
  timestamp: string;
}

// 连接管理：userId -> WebSocket[]
const connections = new Map<string, WebSocket[]>();
// 反向查找：WebSocket -> userId
const wsToUser = new WeakMap<WebSocket, string>();

// admin ID 缓存（避免每次广播都查数据库）
let adminIdsCache: string[] = [];
let adminCacheTimer: ReturnType<typeof setInterval> | null = null;
const ADMIN_CACHE_REFRESH_MS = 60_000; // 每60秒刷新一次

/** 刷新 admin ID 缓存 */
async function refreshAdminCache() {
  try {
    const result = await pgPool.query(
      `SELECT id FROM users WHERE role = 'admin' AND is_active = true`
    );
    adminIdsCache = result.rows.map(r => r.id as string);
  } catch (err) {
    // 刷新失败时保留旧缓存
    console.error('刷新 admin 缓存失败:', (err as Error).message);
  }
}

export function setupLocationWS(wss: WebSocketServer) {
  // 设置定时刷新 admin 缓存（首次刷新延迟到数据库连接确认后进行）
  if (adminCacheTimer === null) {
    adminCacheTimer = setInterval(refreshAdminCache, ADMIN_CACHE_REFRESH_MS);
  }

  wss.on('connection', (ws: WebSocket, req: IncomingMessage) => {
    // 从 URL 参数获取 Token
    const url = new URL(req.url || '', 'http://localhost');
    const token = url.searchParams.get('token');

    if (!token) {
      ws.close(4001, '缺少认证Token');
      return;
    }

    // 验证 Token
    let userId: string;
    let role: string;
    try {
      const decoded = jwt.verify(token, getJwtSecret()) as any;
      userId = decoded.userId;
      role = decoded.role;
    } catch {
      ws.close(4001, 'Token无效');
      return;
    }

    // 记录连接
    if (!connections.has(userId)) {
      connections.set(userId, []);
    }
    connections.get(userId)!.push(ws);
    wsToUser.set(ws, userId);

    console.log(`WS 用户 ${userId} 已连接 (${connections.get(userId)!.length})`);

    // 接收消息
    ws.on('message', async (data: Buffer) => {
      try {
        const payload: LocationPayload = JSON.parse(data.toString());

        // 验证是本人上报
        if (payload.userId !== userId) {
          ws.send(JSON.stringify({ error: 'userId 不匹配' }));
          return;
        }

        // 1. 写入 Redis 实时位置
        try {
          await redis.geoadd('realtime:locations', payload.lng, payload.lat, userId);
          // 不设置全局 realtime:locations 的 TTL（避免所有用户位置同时过期）
          // 改为单独设置用户位置 TTL，每个用户独立过期
          await redis.hset(`user:${userId}:last`, {
            lng: payload.lng,
            lat: payload.lat,
            accuracy: payload.accuracy || 0,
            speed: payload.speed || 0,
            battery: payload.battery || 0,
            timestamp: payload.timestamp,
          });
          await redis.expire(`user:${userId}:last`, 300);
        } catch (redisErr) {
          console.error('Redis写入失败（降级运行）:', (redisErr as Error).message);
        }

        // 2. 写入 PostgreSQL（异步）
        pgPool.query(
          `INSERT INTO location_records (user_id, lng, lat, accuracy, speed, battery, recorded_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7)`,
          [userId, payload.lng, payload.lat, payload.accuracy, payload.speed, payload.battery, payload.timestamp]
        ).catch(err => console.error('DB写入失败:', err.message));

        // 3. 广播该用户位置给管理员
        broadcastToManagers(userId, payload);

        // 4. 回复 ack
        ws.send(JSON.stringify({ type: 'ack', timestamp: payload.timestamp }));
      } catch (err) {
        console.error('WS消息解析错误:', err);
      }
    });

    // 断连
    ws.on('close', () => {
      const conns = connections.get(userId) || [];
      const idx = conns.indexOf(ws);
      if (idx >= 0) conns.splice(idx, 1);
      if (conns.length === 0) connections.delete(userId);
      console.log(`WS 用户 ${userId} 已断开`);
    });

    ws.on('error', (err) => {
      console.error(`WS 错误 [${userId}]:`, err.message);
      // 清理连接，防止内存泄漏
      const conns = connections.get(userId);
      if (conns) {
        const idx = conns.indexOf(ws);
        if (idx >= 0) conns.splice(idx, 1);
        if (conns.length === 0) connections.delete(userId);
      }
    });

    // 发送欢迎消息
    ws.send(JSON.stringify({ type: 'connected', userId }));
  });
}

/// 广播位置给管理员
async function broadcastToManagers(userId: string, payload: LocationPayload) {
  try {
    // 使用缓存的 admin ID 列表（每60秒刷新一次），避免每次广播都查数据库
    for (const adminId of adminIdsCache) {
      const adminConns = connections.get(adminId);
      if (adminConns) {
        const msg = JSON.stringify({
          type: 'location_update',
          userId,
          lng: payload.lng,
          lat: payload.lat,
          accuracy: payload.accuracy,
          speed: payload.speed,
          timestamp: payload.timestamp,
        });
        for (const conn of adminConns) {
          if (conn.readyState === WebSocket.OPEN) {
            conn.send(msg);
          }
        }
      }
    }
  } catch (err) {
    console.error('广播位置失败:', err);
  }
}

/// 获取在线人数统计
export function getOnlineCount(): number {
  return connections.size;
}

/** 停止 admin 缓存刷新（优雅关闭时调用） */
export function stopAdminCacheRefresh(): void {
  if (adminCacheTimer !== null) {
    clearInterval(adminCacheTimer);
    adminCacheTimer = null;
  }
}

/** 强制立即刷新 admin 缓存（数据库连接确认后调用） */
export const forceRefreshAdminCache = refreshAdminCache;
