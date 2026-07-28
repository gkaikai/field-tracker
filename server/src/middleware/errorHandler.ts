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

  // Multer 文件上传错误（含 fileFilter 拒绝）→ 400
  if (err.name === 'MulterError' || err.message.startsWith('不支持的文件类型')) {
    res.status(400).json({
      code: 'BAD_REQUEST',
      message: err.message,
    });
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

/** 脱敏请求体（避免日志泄漏密码/Token/密钥等敏感字段） */
function sanitizeBody(body: any): any {
  if (!body) return body;
  const cloned = { ...body };
  // 正则匹配任何含 password/secret/token/key 的字段名，不分大小写
  const sensitiveRegex = /^(.*)?(password|secret|token|key)(.*)?$/i;
  for (const key of Object.keys(cloned)) {
    if (sensitiveRegex.test(key) && typeof cloned[key] === 'string') {
      cloned[key] = '***';
    }
  }
  return cloned;
}
