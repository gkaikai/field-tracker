/// WebSocket 心跳检测端点
///
/// 功能:
///   1. 客户端连接后，通过 URL 参数 ?clientId=xxx 标识
///   2. 客户端每隔 30-60 秒发送 {"type":"ping"}
///   3. 服务器记录每个 client 的 lastPingTime
///   4. 每 10 秒检查一次: lastPingTime > 180 秒 → 标记疑似断连
///   5. 冷却期（360 秒）内同 client 再次断连不触发重复通知
///   6. 冷却期过后才允许再次触发
///
/// 导出接口供管理后台和 REST API 使用

import { WebSocketServer, WebSocket } from 'ws';
import { IncomingMessage } from 'http';
import { logger } from '../config/logger';

// ---- 常量 ----
const PING_CHECK_INTERVAL_MS = 10_000;   // 检查周期 10s
const DISCONNECT_THRESHOLD_MS = 180_000; // 3 分钟（180 秒）
const COOLDOWN_MS = 360_000;             // 冷却期 6 分钟（360 秒）

// ---- 类型定义 ----

interface HeartbeatClientState {
  /** 客户端标识 */
  clientId: string;
  /** 最后一次收到 ping 的时间戳（ms） */
  lastPingTime: number;
  /** 连接建立时间 */
  connectedAt: number;
  /** 是否已发出断连警告 */
  warned: boolean;
  /** 最近一次触发断连的时间（用于冷却期计算） */
  disconnectedAt: number | null;
}

type ConnectionStatus = 'normal' | 'suspected_disconnected' | 'disconnected';

// ---- 状态管理 ----

/** clientId → 心跳状态 */
const clients = new Map<string, HeartbeatClientState>();

/** WebSocket → clientId 反向查找 */
const wsToClient = new WeakMap<WebSocket, string>();

/** 定时器句柄 */
let checkInterval: ReturnType<typeof setInterval> | null = null;

// ---- 内部辅助函数 ----

function getNow(): number {
  return Date.now();
}

/**
 * 检查并更新所有 client 的连接状态
 */
function checkClients(): void {
  const now = getNow();

  for (const [clientId, state] of clients.entries()) {
    const elapsed = now - state.lastPingTime;

    if (elapsed <= DISCONNECT_THRESHOLD_MS) {
      // 正常在线 — 清除断连标记
      if (state.warned) {
        state.warned = false;
        logger.info(`心跳: ${clientId} 恢复正常`, { clientId });
      }
      continue;
    }

    // ---- 超过阈值 ---- 
    const cooldownElapsed = state.disconnectedAt !== null
      ? now - state.disconnectedAt
      : Infinity;

    if (cooldownElapsed < COOLDOWN_MS) {
      // 仍在冷却期内 — 不触发新警告
      continue;
    }

    // 冷却期已过（或从未触发过断连）→ 触发警告
    if (!state.warned) {
      state.warned = true;
      state.disconnectedAt = now;

      sendDisconnectWarning(state);
      logger.warn(`心跳: ${clientId} 疑似断连 (已 ${Math.round(elapsed / 1000)}s 无心跳)`, {
        clientId,
        elapsedMs: elapsed,
      });
    } else {
      // 已经 warned 过，但仍在超时中 — 可以发送冷却期剩余信息
      const cooldownRemaining = Math.max(0, COOLDOWN_MS - (now - (state.disconnectedAt || now)));
      // 找该 client 的 WebSocket 连接发送通知
      // 注意：connected 不一定有 ws，可能客户端已经断开但状态还在
    }
  }
}

/**
 * 发送断连警告给特定 client
 */
function sendDisconnectWarning(state: HeartbeatClientState): void {
  const now = getNow();
  const cooldownRemaining = Math.max(0, COOLDOWN_MS - (now - (state.disconnectedAt || now)));

  const payload = JSON.stringify({
    type: 'disconnect_warning',
    clientId: state.clientId,
    lastPing: state.lastPingTime,
    cooldown_remaining: Math.round(cooldownRemaining / 1000),
  });

  // 遍历所有连接找到该 client 的 ws
  // 由于 ws 可能已关闭，此通知通过管理端日志体现，不强制推送
  logger.info(`断连通知: ${state.clientId} 冷却剩余 ${Math.round(cooldownRemaining / 1000)}s`);
}

// ---- 导出接口 ----

/** 获取所有在线 client 列表和状态 */
export function getOnlineClients(): HeartbeatClientState[] {
  return Array.from(clients.values()).map(c => ({ ...c }));
}

/** 获取整体连接状态 */
export function getConnectionStatus(): ConnectionStatus {
  if (clients.size === 0) return 'normal';

  const now = getNow();
  let hasSuspected = false;

  for (const state of clients.values()) {
    const elapsed = now - state.lastPingTime;
    if (elapsed > DISCONNECT_THRESHOLD_MS) {
      const cooldownElapsed = state.disconnectedAt !== null
        ? now - state.disconnectedAt
        : Infinity;
      if (state.warned && cooldownElapsed < COOLDOWN_MS) {
        return 'disconnected';
      }
      hasSuspected = true;
    }
  }

  return hasSuspected ? 'suspected_disconnected' : 'normal';
}

/** 手动重置指定 client 的冷却期 */
export function resetCooldown(clientId: string): boolean {
  const state = clients.get(clientId);
  if (!state) return false;

  state.disconnectedAt = null;
  state.warned = false;
  state.lastPingTime = getNow(); // 重置 ping 时间，相当于立刻在线
  logger.info(`心跳: ${clientId} 冷却期已手动重置`, { clientId });
  return true;
}

/** 获取某 client 冷却期剩余秒数（0 = 无冷却） */
export function getCooldownRemaining(clientId: string): number {
  const state = clients.get(clientId);
  if (!state || state.disconnectedAt === null) return 0;

  const now = getNow();
  const remaining = COOLDOWN_MS - (now - state.disconnectedAt);
  return Math.max(0, Math.round(remaining / 1000));
}

/** 获取总在线 client 数 */
export function getOnlineCount(): number {
  return clients.size;
}

// ---- 启动 / 停止 ----

/**
 * 设置心跳 WebSocket 服务
 */
export function setupHeartbeatWS(wss: WebSocketServer): void {
  // 启动定期检查
  if (checkInterval === null) {
    checkInterval = setInterval(checkClients, PING_CHECK_INTERVAL_MS);
    logger.info('心跳检测已启动', { checkIntervalMs: PING_CHECK_INTERVAL_MS, thresholdSec: DISCONNECT_THRESHOLD_MS / 1000 });
  }

  wss.on('connection', (ws: WebSocket, req: IncomingMessage) => {
    // 从 URL 参数获取 clientId
    const url = new URL(req.url || '', 'http://localhost');
    const clientId = url.searchParams.get('clientId');

    if (!clientId) {
      ws.close(4001, '缺少 clientId 参数');
      return;
    }

    // 记录或更新状态
    const now = getNow();
    let state = clients.get(clientId);

    if (state) {
      // 复用已有记录
      state.lastPingTime = now;
      state.warned = false;
      // 不重置 disconnectedAt — 冷却期逻辑独立
      logger.info(`心跳: ${clientId} 重连`, { clientId });
    } else {
      state = {
        clientId,
        lastPingTime: now,
        connectedAt: now,
        warned: false,
        disconnectedAt: null,
      };
      clients.set(clientId, state);
      logger.info(`心跳: ${clientId} 首次连接`, { clientId });
    }

    wsToClient.set(ws, clientId);

    // ---- 消息处理 ----
    ws.on('message', (data: Buffer) => {
      try {
        const msg = JSON.parse(data.toString());

        if (msg.type === 'ping') {
          // 更新心跳时间
          state!.lastPingTime = getNow();
          state!.warned = false; // 收到 ping 即视为在线

          // 回复 pong
          ws.send(JSON.stringify({
            type: 'pong',
            timestamp: Date.now(),
          }));
        }
      } catch {
        ws.send(JSON.stringify({ error: '无效消息格式' }));
      }
    });

    // ---- 断连处理 ----
    ws.on('close', () => {
      logger.info(`心跳: ${clientId} WebSocket 连接关闭`, { clientId });
      // 注意：不删除 clients 记录，因为可能只是网络波动
      // clients 中的记录会在超过阈值后被标记为疑似断连
      wsToClient.delete(ws);
      // 清理长时间未重连的 client 记录（超过1小时无活动）
      const now = getNow();
      for (const [cid, st] of clients.entries()) {
        if (now - st.lastPingTime > 3600_000) {
          clients.delete(cid);
          logger.info(`心跳: 清理过期 client ${cid}（超过1小时无活动）`);
        }
      }
    });

    ws.on('error', (err) => {
      logger.error(`心跳 WS 错误 [${clientId}]: ${err.message}`, { clientId, error: err.message });
      wsToClient.delete(ws);
    });
  });
}

/**
 * 停止心跳检测（用于优雅关闭）
 */
export function stopHeartbeatCheck(): void {
  if (checkInterval !== null) {
    clearInterval(checkInterval);
    checkInterval = null;
    logger.info('心跳检测已停止');
  }
}

/**
 * 清理所有心跳 client 状态（用于测试或完全重置）
 */
export function clearAllHeartbeatClients(): void {
  clients.clear();
  logger.info('心跳 client 状态已全部清除');
}
