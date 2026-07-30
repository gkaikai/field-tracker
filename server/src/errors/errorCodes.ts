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

  // ===== Captcha / SMS 模块 =====
  /** 图形验证码错误 */
  CAPTCHA_CODE_ERROR: { code: '10015', message: '验证码错误' },
  /** 图形验证码已过期 */
  CAPTCHA_EXPIRED: { code: '10016', message: '验证码已过期，请重新获取' },
  /** 短信验证码错误 */
  SMS_CODE_ERROR: { code: '10017', message: '短信验证码错误' },
  /** 短信验证码已过期 */
  SMS_CODE_EXPIRED: { code: '10018', message: '短信验证码已过期，请重新获取' },
  /** 发送过于频繁 */
  SMS_TOO_FREQUENT: { code: '10019', message: '发送过于频繁，请60秒后再试' },
  /** 手机号格式不正确（需11位） */
  PHONE_FORMAT_INVALID: { code: '10020', message: '手机号格式不正确，请输入11位手机号' },

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

  // ===== Attendance 模块 =====
  /** 不在打卡范围内 */
  ATTEND_OUT_OF_RANGE: { code: '40001', message: '不在打卡范围内' },
  ATTEND_DUPLICATE: { code: '40005', message: '今日已打卡，请勿重复签到' },
  ATTEND_TIME_INVALID: { code: '40004', message: '不在打卡时间范围内' },

  // ===== Fence 模块 =====
  /** 围栏不存在 */
  FENCE_NOT_FOUND: { code: '30001', message: '围栏不存在' },
  /** 操作过于频繁 */
  FENCE_RATE_LIMITED: { code: '30002', message: '操作过于频繁，请稍后重试' },

  // ===== Org 模块 =====
  /** 用户已存在（手机号重复） */
  USER_EXISTS: { code: '30010', message: '该手机号已存在' },
  /** 数据库查询失败 */
  DB_ERROR: { code: '30011', message: '数据库查询失败' },
  /** 部门不存在 */
  DEPT_NOT_FOUND: { code: '30012', message: '部门不存在' },

  // ===== Upload 模块 =====
  /** 请求参数无效 */
  BAD_REQUEST: { code: '40010', message: '请求参数无效' },
  /** 文件类型不支持 */
  INVALID_FILE: { code: '40011', message: '不支持的文件类型' },

  // ===== Visit 模块 =====
  /** 拜访记录不存在 */
  VISIT_NOT_FOUND: { code: '30020', message: '拜访记录不存在' },
  /** 拜访已签到或已完成 */
  VISIT_ALREADY_CHECKIN: { code: '30021', message: '已签到或已完成' },
  /** 拜访已完成或已取消 */
  VISIT_COMPLETED: { code: '30022', message: '拜访已完成或已取消' },
  /** 未在拜访中 */
  VISIT_NOT_IN_PROGRESS: { code: '30023', message: '未在拜访中' },

  // ===== Message 模块 =====
  /** 消息不存在 */
  MESSAGE_NOT_FOUND: { code: '30030', message: '消息不存在' },

  // ===== Attendance Rules 模块 =====
  /** 考勤规则不存在 */
  ATTEND_RULE_NOT_FOUND: { code: '40006', message: '规则不存在' },

  // ===== Auth rate limit 模块 =====
  /** 操作过于频繁 */
  AUTH_RATE_LIMITED: { code: '10030', message: '操作过于频繁，请稍后重试' },
  /** 注册操作过于频繁 */
  REGISTER_RATE_LIMITED: { code: '10031', message: '注册操作过于频繁，请稍后再试' },

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
      if (errorCode === 'AUTH_TOKEN_MISSING' || errorCode === 'AUTH_TOKEN_INVALID' || errorCode === 'AUTH_LOGIN_FAILED') return 401;
      return 400;
    case 'CAPTCHA':
    case 'SMS':
    case 'PHONE':
    case 'LOC':
    case 'ATTEND':
    case 'FENCE':
    case 'VISIT':
      return 400;
    default:
      return 500;
  }
}
