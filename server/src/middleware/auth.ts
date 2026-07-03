import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';

/// JWT_SECRET 每次请求时从环境变量读取（避免模块加载时序问题）
function getJwtSecret(): string {
  return process.env.JWT_SECRET || 'field-tracker-secret';
}

// JWT payload 接口
export interface JwtPayload {
  userId: string;
  phone: string;
  role: string;
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
    return res.status(401).json({ message: '未提供认证Token' });
  }

  const token = authHeader.slice(7);
  try {
    const decoded = jwt.verify(token, getJwtSecret()) as JwtPayload;
    (req as any).user = decoded;
    next();
  } catch (err) {
    return res.status(401).json({ message: 'Token无效或已过期' });
  }
}

// 管理员权限中间件
export function adminMiddleware(req: Request, res: Response, next: NextFunction) {
  const user = (req as any).user as JwtPayload;
  if (user.role !== 'admin') {
    return res.status(403).json({ message: '需要管理员权限' });
  }
  next();
}
