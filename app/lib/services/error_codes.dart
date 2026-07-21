/// 后端业务错误码映射表
///
/// 后端约定：成功响应 code=200，业务异常 code 为 10001~10014
/// ApiService 拦截器自动拦截非 200 的 code 并转为 ApiException，
/// 业务层无需重复处理。
class ErrorCode {
  // ──────────────────────────────────────────────
  // 通用错误（10001-10010）
  // ──────────────────────────────────────────────

  /// 10001 - 请求参数非法
  static const int invalidParam = 10001;

  /// 10002 - 未登录或 Token 已过期
  static const int tokenExpired = 10002;

  /// 10003 - 账号不存在
  static const int accountNotFound = 10003;

  /// 10004 - 密码错误
  static const int wrongPassword = 10004;

  /// 10005 - 账号已被锁定
  static const int accountLocked = 10005;

  /// 10006 - 手机号已被注册
  static const int phoneRegistered = 10006;

  /// 10007 - 验证码错误或已过期
  static const int codeInvalid = 10007;

  /// 10008 - 无权限访问
  static const int noPermission = 10008;

  /// 10009 - 资源不存在
  static const int resourceNotFound = 10009;

  /// 10010 - 系统繁忙，请稍后重试
  static const int systemBusy = 10010;

  // ──────────────────────────────────────────────
  // 业务专用错误（10011-10014）
  // ──────────────────────────────────────────────

  /// 10011 - 重复操作（如重复签到）
  static const int duplicateOperation = 10011;

  /// 10012 - 数据已存在
  static const int dataExists = 10012;

  /// 10013 - 签到距离超出允许范围
  static const int distanceOutOfRange = 10013;

  /// 10014 - 签到时间不在有效范围内
  static const int timeOutOfRange = 10014;

  /// 40001 - 不在打卡范围内
  static const int attendOutOfRange = 40001;

  // ──────────────────────────────────────────────
  // 错误码 → 中文提示 映射表
  // ──────────────────────────────────────────────

  static const Map<int, String> _messages = {
    10001: '请求参数有误，请检查输入',
    10002: '登录已过期，请重新登录',
    10003: '账号不存在，请检查手机号',
    10004: '密码错误，请重试',
    10005: '账号或密码错误，请重新输入',
    10006: '该手机号已被注册',
    10007: '验证码错误或已过期，请重新获取',
    10008: '无权限执行此操作',
    10009: '请求的资源不存在',
    10010: '系统繁忙，请稍后重试',
    10015: '验证码错误',
    10016: '验证码已过期，请重新获取',
    10017: '短信验证码错误',
    10018: '短信验证码已过期，请重新获取',
    10019: '发送过于频繁，请60秒后再试',
    10020: '手机号格式不正确，请输入11位手机号',
    10011: '请勿重复操作',
    10012: '数据已存在，无法重复添加',
    10013: '签到位置超出打卡范围',
    10014: '当前时间不在打卡有效时段内',
    40001: '不在打卡范围内，请靠近打卡点',
  };

  /// 根据错误码获取用户友好提示
  static String message(int code) {
    return _messages[code] ?? '未知错误($code)';
  }

  /// 判断是否为业务层的错误码（10001-10014, 40001）
  static bool isBusinessError(int code) {
    return (code >= 10001 && code <= 10020) || code == 40001;
  }

  /// 判断是否与登录/认证相关
  static bool isAuthError(int code) {
    return switch (code) {
      10002 || 10003 || 10004 || 10005 || 10007 => true,
      _ => false,
    };
  }

  /// 判断是否与签到业务相关
  static bool isAttendanceError(int code) {
    return switch (code) {
      10011 || 10012 || 10013 || 10014 => true,
      _ => false,
    };
  }
}

/// API 业务异常，携带后端返回的错误码
class ApiException implements Exception {
  final int code;
  final String message;
  final Map<String, dynamic>? rawData;

  const ApiException({
    required this.code,
    this.message = '',
    this.rawData,
  }) : assert(code != 0, 'error code must not be 0');

  String get friendlyMessage =>
      message.isNotEmpty ? message : ErrorCode.message(code);

  @override
  String toString() => 'ApiException($code): $friendlyMessage';
}
