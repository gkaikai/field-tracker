import { Request, Response, NextFunction } from 'express';
import { AppError } from '../errors/AppError';
import { ErrorCodes } from '../errors/errorCodes';
import { logger } from '../config/logger';

/**
 * 全局异常捕获中间件
 * - AppError → 按错误码返回统一格式
 * - 其他未捕获异常 → 500 INTERNAL_ERROR + 记录日志
 */
export function errorHandler(err: Error, req: Request, res: Response, _next: NextFunction) {
  if (err instanceof AppError) {
    res.status(err.statusCode).json(err.toJSON());
    return;
  }

  // 未预期的异常 — 记录日志 + 返回详细错误（开发环境）
  const internal = ErrorCodes.INTERNAL_ERROR;
  const isDev = process.env.NODE_ENV !== 'production';

  logger.error('未捕获异常', {
    error: err.message,
    stack: err.stack,
    method: req.method,
    url: req.originalUrl,
    body: sanitizeBody(req.body),
  });

  res.status(500).json({
    code: internal.code,
    message: isDev ? `服务器内部错误: ${err.message}` : '服务器内部错误',
  });
}

/** 脱敏请求体（避免日志泄漏密码/Token） */
function sanitizeBody(body: any): any {
  if (!body) return body;
  const cloned = { ...body };
  if (cloned.password) cloned.password = '***';
  if (cloned.token) cloned.token = '***';
  return cloned;
}
