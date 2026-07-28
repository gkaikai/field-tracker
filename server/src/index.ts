/// Field Tracker 后端入口
///
/// 启动 HTTP + WebSocket 服务

import express from 'express';
import cors from 'cors';
import http from 'http';
import path from 'path';
import fs from 'fs';
import { WebSocketServer } from 'ws';
import dotenv from 'dotenv';
import { testConnection, pgPool, redis } from './config/database';
import { setupLocationWS, stopAdminCacheRefresh, forceRefreshAdminCache } from './websocket/location_ws';
import { setupHeartbeatWS, stopHeartbeatCheck } from './websocket/heartbeat_ws';
import { errorHandler } from './middleware/errorHandler';
import { logger, requestLogger } from './config/logger';
import { initAlert } from './monitoring/alert';
import { recordRequest, completeRequest, startMetricsSummary, checkDiskUsage, getMetricsSnapshot } from './monitoring/metrics';

// ============================================================
// 环境配置加载
// 根据 NODE_ENV 加载对应的 .env 文件:
//   development -> .env.development
//   production  -> .env.production
//   未设置      -> .env (兼容旧逻辑)
// ============================================================
const envFile = process.env.NODE_ENV === 'production'
  ? '.env.production'
  : process.env.NODE_ENV === 'development'
    ? '.env.development'
    : '.env';

const envPath = path.resolve(__dirname, '../', envFile);
dotenv.config({ path: envPath });
logger.info(`加载环境配置: ${envFile} (NODE_ENV=${process.env.NODE_ENV || '未设置'})`);

// ============================================================
//  启动时安全检查 — 校验必填环境变量
// ============================================================
const requiredEnvVars = ['JWT_SECRET', 'DB_PASSWORD'];
const missingEnvVars = requiredEnvVars.filter(v => !process.env[v]);
if (missingEnvVars.length > 0) {
  console.error(`\n❌ [安全] 以下环境变量未设置，拒绝启动：`);
  missingEnvVars.forEach(v => console.error(`   - ${v}`));
  console.error(`   请创建 ${envFile} 文件并设置上述变量后再启动。\n`);
  process.exit(1);
}

// 初始化告警通道（从环境变量读取 Webhook URL）
initAlert();

const app = express();
const PORT = parseInt(process.env.PORT || '3000');

// ---- 中间件 ----
const allowedOrigins = process.env.NODE_ENV === 'production'
  ? (process.env.ALLOWED_ORIGINS || '').split(',')
  : ['http://localhost:3000', 'http://localhost:*'];

app.use(cors({
  origin: process.env.NODE_ENV === 'production' ? allowedOrigins : 'http://localhost:3000',
  credentials: true,
}));
app.set('trust proxy', 1);  // 让 express-rate-limit 能正确识别代理后的 IP
app.use(express.json({ limit: '1mb' }));
app.use(requestLogger);

// 监控中间件 — 记录请求指标（在 requestLogger 之后）
app.use((req: any, res: any, next: any) => {
  const start = Date.now();
  res.on('finish', () => {
    recordRequest({
      path: req.originalUrl,
      method: req.method,
      statusCode: res.statusCode,
      durationMs: Date.now() - start,
      timestamp: Date.now(),
    });
    completeRequest();
  });
  next();
});

// ---- HTTP 路由 ----
import authRoutes from './routes/auth';
import locationRoutes from './routes/location';
import userRoutes from './routes/user';
import attendanceRoutes from './routes/attendance';
import fenceRoutes from './routes/fence';
import uploadRoutes from './routes/upload';
import reportRoutes from './routes/report';
import customerRoutes from './routes/customer';
import approvalRoutes from './routes/approval';
import orgRoutes from './routes/org';
import geocodeRoutes from './routes/geocode';
import tunnelRoutes from './routes/tunnel';
import heartbeatRoutes from './routes/heartbeat';

app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/location', locationRoutes);
app.use('/api/v1/users', userRoutes);
app.use('/api/v1/attendance', attendanceRoutes);
app.use('/api/v1/fences', fenceRoutes);
app.use('/api/v1/upload', uploadRoutes);
app.use('/api/v1/reports', reportRoutes);
app.use('/api/v1/customers', customerRoutes);
app.use('/api/v1/approvals', approvalRoutes);
app.use('/api/v1/org', orgRoutes);
app.use('/api/v1/geocode', geocodeRoutes);
app.use('/api/v1/tunnel', tunnelRoutes);
app.use('/api/v1/heartbeat', heartbeatRoutes);

// 根路径重定向到管理后台
app.get('/', (req, res) => res.redirect('/admin'));

// 提供静态文件服务（管理后台）
app.use(express.static('public'));
app.use('/uploads', express.static('uploads'));

// ---- 辅助函数: 查找最新的APK文件 ----
function findLatestApk(): string | null {
  const publicDir = path.join(__dirname, '../public');
  try {
    const files = fs.readdirSync(publicDir)
      .filter(f => f.endsWith('.apk'))
      .map(f => ({ name: f, mtime: fs.statSync(path.join(publicDir, f)).mtimeMs }))
      .sort((a, b) => b.mtime - a.mtime);
    return files.length > 0 ? path.join(publicDir, files[0].name) : null;
  } catch {
    return null;
  }
}

// APK下载路由（attachment方式下载，防止乱码）
app.get('/download-apk', (req, res) => {
  const filePath = findLatestApk();
  if (!filePath) {
    return res.status(404).json({ code: 'APK_NOT_FOUND', message: '暂无APK文件' });
  }
  const fileName = path.basename(filePath);
  res.download(filePath, fileName);
});

// 管理后台入口
app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, '../public/admin.html'));
});

// APK下载（支持 Range 请求，兼容代理隧道分块下载）
app.get('/apk', (req, res) => {
  const apkPath = findLatestApk();
  if (!apkPath) {
    return res.status(404).json({ code: 'APK_NOT_FOUND', message: '暂无APK文件' });
  }
  const stat = fs.statSync(apkPath);
  const fileSize = stat.size;
  const range = req.headers.range;

  if (range) {
    const parts = range.replace(/bytes=/, '').split('-');
    const start = parseInt(parts[0], 10);
    const end = parts[1] ? parseInt(parts[1], 10) : Math.min(start + 400 * 1024, fileSize - 1); // 400KB chunks
    const chunkSize = end - start + 1;

    res.writeHead(206, {
      'Content-Range': `bytes ${start}-${end}/${fileSize}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': chunkSize,
      'Content-Type': 'application/vnd.android.package-archive',
      'Content-Disposition': 'attachment; filename="field-tracker.apk"',
      'Cache-Control': 'no-cache',
    });

    const stream = fs.createReadStream(apkPath, { start, end });
    stream.pipe(res);
  } else {
    // 无Range请求时返回头200KB让浏览器可以发起Range请求
    const firstChunk = Math.min(200 * 1024, fileSize);
    res.writeHead(200, {
      'Content-Type': 'application/vnd.android.package-archive',
      'Content-Length': fileSize,
      'Content-Disposition': 'attachment; filename="field-tracker.apk"',
      'Accept-Ranges': 'bytes',
      'Cache-Control': 'no-cache',
    });

    const stream = fs.createReadStream(apkPath, { highWaterMark: 64 * 1024 });
    stream.pipe(res);
  }
});

// 健康检查
app.get('/health', (req, res) => {
  res.json({ status: 'ok', uptime: process.uptime() });
});

// 监控指标端点
app.get('/metrics', (req: any, res: any) => {
  res.json(getMetricsSnapshot());
});

// ---- 全局异常处理（必须在路由之后） ----
app.use(errorHandler);

// ---- 创建 HTTP Server ----
const server = http.createServer(app);

// ---- WebSocket 服务 ----
const wss = new WebSocketServer({
  server,
  path: '/ws/location',
});

setupLocationWS(wss);

// ---- WebSocket 心跳服务 ----
const heartbeatWss = new WebSocketServer({
  server,
  path: '/ws/heartbeat',
});

setupHeartbeatWS(heartbeatWss);

// ---- 启动 ----
async function start() {
  // 检查数据库连接
  await testConnection();

  // 数据库就绪后首次刷新 admin 缓存（避免启动时查询失败）
  forceRefreshAdminCache();

  // 确保未来3个月的分区存在
  try {
    await pgPool.query('SELECT ensure_next_partitions()');
    logger.info('分区检查完成');
  } catch (err) {
    logger.warn('分区创建失败（非致命）', { error: (err as Error).message });
  }

  server.listen(PORT, '0.0.0.0', () => {
    logger.info(`Field Tracker Server 启动成功 | HTTP: ${PORT} | WS: /ws/location, /ws/heartbeat`);
    console.log(`\n╔══════════════════════════════════════════════╗\n║          Field Tracker Server                ║\n║──────────────────────────────────────────────║\n║  HTTP  : http://localhost:${PORT}              ║\n║  WS    : ws://localhost:${PORT}/ws/location    ║\n║  Heart : ws://localhost:${PORT}/ws/heartbeat   ║\n║  Admin : http://localhost:${PORT}/admin        ║\n║  Health: http://localhost:${PORT}/health       ║\n║  Metrics: http://localhost:${PORT}/metrics     ║\n╚══════════════════════════════════════════════╝\n    `);

    // 启动定期监控摘要输出（每30分钟）
    startMetricsSummary();

    // 首次检查磁盘使用率
    checkDiskUsage();

    // 每15分钟检查一次磁盘使用率
    setInterval(() => checkDiskUsage(), 15 * 60 * 1000);

    logger.info('监控告警系统已启动');
  });

  // 端口被占用时自动重试
  server.on('error', (err: NodeJS.ErrnoException) => {
    if (err.code === 'EADDRINUSE') {
      logger.error(`端口 ${PORT} 已被占用，请先关闭旧进程或更换端口`);
      console.error(`\n❌ 端口 ${PORT} 已被占用!`);
      console.error(`   运行 lsof -ti:${PORT} | xargs kill 来释放端口\n`);
      process.exit(1);
    }
  });
}

start().catch(console.error);

// ============================================================
//  优雅关闭
// ============================================================
async function gracefulShutdown(signal: string) {
  logger.info(`收到 ${signal}，正在优雅关闭...`);

  // 1. 先关闭 WebSocket 连接（阻止新 WS 连接）
  wss.clients.forEach((ws) => {
    ws.close(1001, 'Server shutting down');
  });
  heartbeatWss.clients.forEach((ws) => {
    ws.close(1001, 'Server shutting down');
  });
  stopHeartbeatCheck();
  stopAdminCacheRefresh();

  // 2. 停止接受新 HTTP 连接（WS 关闭后 server.close 不再被 WS 阻塞）
  await new Promise<void>((resolve) => {
    server.close(() => {
      logger.info('HTTP 服务器已关闭');
      resolve();
    });
  });

  // 3. 等待待处理请求完成（最多5秒）
  await new Promise(resolve => setTimeout(resolve, 2000));

  // 4. 关闭数据库连接池
  try {
    await pgPool.end();
    logger.info('PostgreSQL 连接池已关闭');
  } catch (err) {
    logger.error('关闭 PostgreSQL 失败', { error: (err as Error).message });
  }

  // 5. 关闭 Redis
  try {
    redis.quit();
    logger.info('Redis 已断开');
  } catch (_) {}

  logger.info('服务器已完全关闭');
  process.exit(0);
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));
process.on('uncaughtException', (err) => {
  logger.error('未捕获异常，进程即将退出', { error: err.message, stack: err.stack });
  process.exit(1);
});
