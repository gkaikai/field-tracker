/**
 * 统一错误码定义
 * 格式: 模块(2位) + 序号(3位)
 * 10xxx — Auth 模块
 * 20xxx — Location 模块
 * 30xxx — User 模块
 * 40xxx — Attendance 模块
 * 50xxx — Common/通用
 */
export const ErrorCodes = {
  // ===== Auth 模块 =====
  /** 手机号不能为空 */
  AUTH_PHONE_REQUIRED: { code: '10001', message: '手机号不能为空' },
  /** 密码不能为空 */
  AUTH_PASSWORD_REQUIRED: { code: '10002', message: '密码不能为空' },
  /** 手机号格式错误 */
  AUTH_PHONE_INVALID: { code: '10003', message: '手机号格式错误' },
  /** 密码长度不足 */
  AUTH_PASSWORD_TOO_SHORT: { code: '10004', message: '密码长度不能少于6位' },
  /** 账号或密码错误 */
  AUTH_LOGIN_FAILED: { code: '10005', message: '账号或密码错误' },
  /** Token无效或已过期 */
  AUTH_TOKEN_INVALID: { code: '10006', message: 'Token无效或已过期' },
  /** 未提供认证Token */
  AUTH_TOKEN_MISSING: { code: '10007', message: '未提供认证Token' },
  /** 用户不存在 */
  AUTH_USER_NOT_FOUND: { code: '10008', message: '用户不存在' },
  /** 无权限访问 */
  AUTH_FORBIDDEN: { code: '10009', message: '无权限访问' },

  // ===== Location 模块 =====
  /** 经度超出范围 */
  LOC_LNG_INVALID: { code: '20001', message: '经度超出有效范围(-180~180)' },
  /** 纬度超出范围 */
  LOC_LAT_INVALID: { code: '20002', message: '纬度超出有效范围(-85~85)' },
  /** 位置数据不能为空 */
  LOC_DATA_REQUIRED: { code: '20003', message: '位置数据不能为空' },
  /** 批量位置数据不能为空 */
  LOC_BATCH_EMPTY: { code: '20004', message: '批量上传数据不能为空' },
  /** 批量数据超过上限 */
  LOC_BATCH_TOO_LARGE: { code: '20005', message: '单次批量上传不能超过100条' },
  /** 日期参数无效 */
  LOC_DATE_INVALID: { code: '20006', message: '日期参数无效(格式: YYYY-MM-DD)' },

  // ===== Common 模块 =====
  /** 服务器内部错误 */
  INTERNAL_ERROR: { code: '50000', message: '服务器内部错误' },
  /** 请求参数无效 */
  PARAM_INVALID: { code: '50001', message: '请求参数无效' },
} as const;

export type ErrorCode = keyof typeof ErrorCodes;

/** 根据错误码获取状态码 */
export function getHttpStatus(errorCode: ErrorCode): number {
  const module = errorCode.split('_')[0];
  switch (module) {
    case 'AUTH':
      if (errorCode === 'AUTH_FORBIDDEN') return 403;
      if (errorCode === 'AUTH_TOKEN_MISSING' || errorCode === 'AUTH_TOKEN_INVALID') return 401;
      return 400;
    case 'LOC':
      return 400;
    default:
      return 500;
  }
}
