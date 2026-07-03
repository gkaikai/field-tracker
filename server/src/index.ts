/// Field Tracker 后端入口
///
/// 启动 HTTP + WebSocket 服务

import express from 'express';
import cors from 'cors';
import http from 'http';
import { WebSocketServer } from 'ws';
import dotenv from 'dotenv';
import { testConnection, pgPool, redis } from './config/database';
import { setupLocationWS } from './websocket/location_ws';

// 加载环境变量
dotenv.config();

const app = express();
const PORT = parseInt(process.env.PORT || '3000');

// ---- 中间件 ----
const allowedOrigins = process.env.NODE_ENV === 'production'
  ? (process.env.ALLOWED_ORIGINS || '').split(',')
  : ['http://localhost:3000', 'http://localhost:*'];

app.use(cors({
  origin: process.env.NODE_ENV === 'production' ? allowedOrigins : '*',
  credentials: true,
}));
app.use(express.json({ limit: '1mb' }));
app.use(express.static('public'));

// ---- HTTP 路由 ----
import authRoutes from './routes/auth';
import locationRoutes from './routes/location';
import userRoutes from './routes/user';

app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/location', locationRoutes);
app.use('/api/v1/users', userRoutes);

// 健康检查
app.get('/health', (req, res) => {
  res.json({ status: 'ok', uptime: process.uptime() });
});

// ---- 创建 HTTP Server ----
const server = http.createServer(app);

// ---- WebSocket 服务 ----
const wss = new WebSocketServer({
  server,
  path: '/ws/location',
});

setupLocationWS(wss);

// ---- 启动 ----
async function start() {
  // 检查数据库连接
  await testConnection();

  // 确保未来3个月的分区存在
  try {
    await pgPool.query('SELECT ensure_next_partitions()');
    console.log('分区检查完成');
  } catch (err) {
    console.warn('分区创建失败（非致命）:', (err as Error).message);
  }

  server.listen(PORT, '0.0.0.0', () => {
    console.log(`
╔══════════════════════════════════════════════╗
║          Field Tracker Server                ║
║──────────────────────────────────────────────║
║  HTTP  : http://localhost:${PORT}              ║
║  WS    : ws://localhost:${PORT}/ws/location    ║
║  Health: http://localhost:${PORT}/health       ║
╚══════════════════════════════════════════════╝
    `);
  });
}

start().catch(console.error);

// ============================================================
//  优雅关闭
// ============================================================
async function gracefulShutdown(signal: string) {
  console.log(`\n收到 ${signal}，正在优雅关闭...`);

  // 1. 停止接受新连接
  server.close(() => {
    console.log('HTTP 服务器已关闭');
  });

  // 2. 关闭 WebSocket 连接
  wss.clients.forEach((ws) => {
    ws.close(1001, 'Server shutting down');
  });

  // 3. 等待待处理请求完成（最多5秒）
  await new Promise(resolve => setTimeout(resolve, 2000));

  // 4. 关闭数据库连接池
  try {
    await pgPool.end();
    console.log('PostgreSQL 连接池已关闭');
  } catch (err) {
    console.error('关闭 PostgreSQL 失败:', (err as Error).message);
  }

  // 5. 关闭 Redis
  try {
    redis.quit();
    console.log('Redis 已断开');
  } catch (_) {}

  console.log('服务器已完全关闭');
  process.exit(0);
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));
process.on('uncaughtException', (err) => {
  console.error('未捕获异常:', err);
  gracefulShutdown('uncaughtException');
});
