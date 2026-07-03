import { ErrorCodes, ErrorCode, getHttpStatus } from './errorCodes';

/**
 * 业务异常 — 携带统一错误码
 * 全局异常中间件会捕获并转换为 { code, message } 格式返回
 */
export class AppError extends Error {
  /** 错误码 (如 '10001') */
  public readonly code: string;
  /** HTTP 状态码 */
  public readonly statusCode: number;

  constructor(errorCode: ErrorCode, customMessage?: string) {
    const errDef = ErrorCodes[errorCode];
    super(customMessage || errDef.message);
    this.code = errDef.code;
    this.statusCode = getHttpStatus(errorCode);
    this.name = 'AppError';
  }

  /** 转 JSON 响应体 */
  toJSON() {
    return {
      code: this.code,
      message: this.message,
    };
  }
}
