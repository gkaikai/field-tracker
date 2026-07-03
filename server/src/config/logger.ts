import * as winston from 'winston';
import * as path from 'path';

const LOG_DIR = process.env.LOG_DIR || path.join(__dirname, '../../logs');

/**
 * 日志配置
 * - 控制台输出: 开发友好格式，带颜色
 * - 文件输出: JSON 格式，按日轮转
 */
export const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss.SSS' }),
    winston.format.errors({ stack: true }),
  ),
  transports: [
    // 控制台输出
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.printf(({ timestamp, level, message, ...rest }) => {
          const extra = Object.keys(rest).length > 0 ? ` | ${JSON.stringify(rest)}` : '';
          return `${timestamp} [${level}] ${message}${extra}`;
        }),
      ),
    }),
  ],
});

/**
 * 请求日志中间件 — 记录每个请求的方法/URL/耗时
 */
export function requestLogger(req: any, res: any, next: any) {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    logger.info(`${req.method} ${req.originalUrl}`, {
      status: res.statusCode,
      duration: `${duration}ms`,
    });
  });
  next();
}
