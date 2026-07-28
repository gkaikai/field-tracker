import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { AppError } from '../errors/AppError';
import { ErrorCodes } from '../errors/errorCodes';

/// JWT_SECRET 每次请求时从环境变量读取（避免模块加载时序问题）
/// ⚠️ 生产环境必须设置 JWT_SECRET 环境变量，无默认值
function getJwtSecret(): string {
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    throw new Error('JWT_SECRET 环境变量未设置 — 启动时已在 index.ts 中校验，不应到达此处');
  }
  return secret;
}

// JWT payload 接口
export interface JwtPayload {
  userId: string;
  phone: string;
  role: string;
  departmentId?: string;
}

// 生成 Token
export function generateToken(payload: JwtPayload): string {
  return jwt.sign(payload, getJwtSecret(), {
    expiresIn: (process.env.JWT_EXPIRES_IN || '7d') as any,
  } as jwt.SignOptions);
}

// 验证 Token 中间件
export function authMiddleware(req: Request, res: Response, next: NextFunction) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return next(new AppError('AUTH_TOKEN_MISSING'));
  }

  const token = authHeader.slice(7);
  try {
    const decoded = jwt.verify(token, getJwtSecret()) as JwtPayload;
    (req as any).user = decoded;
    next();
  } catch (err) {
    return next(new AppError('AUTH_TOKEN_INVALID'));
  }
}

/** 角色权限中间件 — 允许指定的角色访问 */
export function roleMiddleware(...allowedRoles: string[]) {
  return (req: Request, _res: Response, next: NextFunction) => {
    const user = (req as any).user as JwtPayload;
    if (!allowedRoles.includes(user.role)) {
      return next(new AppError('AUTH_FORBIDDEN'));
    }
    next();
  };
}

// 管理员权限中间件（兼容旧代码）
export const adminMiddleware = roleMiddleware('admin');
