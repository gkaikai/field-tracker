import * as winston from 'winston';
import * as path from 'path';
import 'winston-daily-rotate-file';
import { sendAlert } from '../monitoring/alert';

// ============================================================
//  日志配置
// ============================================================

const LOG_DIR = process.env.LOG_DIR || path.join(__dirname, '../../logs');
const LOG_LEVEL = process.env.LOG_LEVEL || 'info';
const LOG_RETENTION_DAYS = parseInt(process.env.LOG_RETENTION_DAYS || '30', 10);
const LOG_MAX_SIZE = process.env.LOG_MAX_SIZE || '100m';

// ============================================================
//  自定义格式
// ============================================================

/** 开发友好的控制台格式（带颜色） */
const consoleFormat = winston.format.combine(
  winston.format.colorize(),
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss.SSS' }),
  winston.format.printf(({ timestamp, level, message, ...rest }) => {
    const extra = Object.keys(rest).length > 0 ? ` | ${JSON.stringify(rest)}` : '';
    return `${timestamp} [${level}] ${message}${extra}`;
  }),
);

/** JSON 格式（用于文件输出） */
const jsonFormat = winston.format.combine(
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss.SSS' }),
  winston.format.errors({ stack: true }),
  winston.format.json(),
);

// ============================================================
//  Logger 实例
// ============================================================

export const logger = winston.createLogger({
  level: LOG_LEVEL,
  format: winston.format.combine(
    winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss.SSS' }),
    winston.format.errors({ stack: true }),
  ),
  transports: [
    // ==============================
    //  1. 控制台输出
    //     - error 级别 → stderr
    //     - info/warn/debug → stdout
    // ==============================
    new winston.transports.Console({
      format: consoleFormat,
      stderrLevels: ['error'],
    }),

    // ==============================
    //  2. 按日轮转文件（所有级别）
    //     保留 LOG_RETENTION_DAYS 天
    // ==============================
    new winston.transports.DailyRotateFile({
      level: 'debug',
      filename: path.join(LOG_DIR, 'application-%DATE%.log'),
      datePattern: 'YYYY-MM-DD',
      maxSize: LOG_MAX_SIZE,
      maxFiles: `${LOG_RETENTION_DAYS}d`,
      format: jsonFormat,
      zippedArchive: true,
    }),

    // ==============================
    //  3. 错误日志单独文件（warn+）
    // ==============================
    new winston.transports.DailyRotateFile({
      level: 'warn',
      filename: path.join(LOG_DIR, 'error-%DATE%.log'),
      datePattern: 'YYYY-MM-DD',
      maxSize: LOG_MAX_SIZE,
      maxFiles: `${LOG_RETENTION_DAYS}d`,
      format: jsonFormat,
      zippedArchive: true,
    }),
  ],
});

// ============================================================
//  Warn/Error 级别 → 告警通知集成
//  仅 production 环境生效，避免开发时刷屏
// ============================================================

const originalError = logger.error.bind(logger);
const originalWarn = logger.warn.bind(logger);

/** 脱敏对象中的敏感字段（递归处理），防止密码/token/key 泄露到 Webhook */
function sanitizeMeta(obj: any): any {
  if (!obj || typeof obj !== 'object') return obj;
  const sensitiveRegex = /^(.*)?(password|secret|token|key|authorization|credential|apikey|privatekey)(.*)?$/i;
  if (Array.isArray(obj)) return obj.map(sanitizeMeta);
  const cloned: Record<string, any> = {};
  for (const [k, v] of Object.entries(obj)) {
    if (sensitiveRegex.test(k) && typeof v === 'string') {
      cloned[k] = '***';
    } else if (typeof v === 'object' && v !== null) {
      cloned[k] = sanitizeMeta(v);
    } else {
      cloned[k] = v;
    }
  }
  return cloned;
}

// 递归保护标记，防止 sendAlert → logger.error → sendAlert 无限循环
let _alerting = false;

logger.error = function (msg: string, ...meta: any[]) {
  if (process.env.NODE_ENV === 'production' && !_alerting) {
    _alerting = true;
    try {
      const metaObj = sanitizeMeta(meta[0] || {});
      sendAlert('critical', `[服务错误] ${msg}`, JSON.stringify(metaObj));
    } finally {
      _alerting = false;
    }
  }
  return originalError(msg, ...meta);
} as winston.LeveledLogMethod;

logger.warn = function (msg: string, ...meta: any[]) {
  if (process.env.NODE_ENV === 'production' && !_alerting) {
    _alerting = true;
    try {
      const metaObj = sanitizeMeta(meta[0] || {});
      sendAlert('warning', `[服务警告] ${msg}`, JSON.stringify(metaObj));
    } finally {
      _alerting = false;
    }
  }
  return originalWarn(msg, ...meta);
} as winston.LeveledLogMethod;

// ============================================================
//  日志轮转事件
// ============================================================

logger.on('finish', () => {
  logger.info('日志系统关闭');
});

// ============================================================
//  请求日志中间件
// ============================================================

/**
 * 请求日志中间件 — 记录每个请求的方法/URL/耗时
 * 自动根据状态码选择日志级别:
 *   2xx/3xx → info
 *   4xx     → warn
 *   5xx     → error
 */
export function requestLogger(req: any, res: any, next: any) {
  const start = Date.now();

  res.on('finish', () => {
    const duration = Date.now() - start;
    const logLevel = res.statusCode >= 500 ? 'error'
      : res.statusCode >= 400 ? 'warn'
      : 'info';

    logger.log(logLevel, `${req.method} ${req.originalUrl}`, {
      status: res.statusCode,
      duration: `${duration}ms`,
      ip: req.ip || req.connection?.remoteAddress,
    });
  });

  next();
}

// ============================================================
//  便捷方法
// ============================================================

/** 获取当前日志目录路径 */
export function getLogDir(): string {
  return LOG_DIR;
}

/** 获取当前日志级别 */
export function getLogLevel(): string {
  return LOG_LEVEL;
}

export default logger;
