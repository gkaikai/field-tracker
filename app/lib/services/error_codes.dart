/// 后端业务错误码映射表
///
/// 后端约定：成功响应 code=200，业务异常 code 范围：
///   Auth 10001~10009, 验证码 10015~10020, 位置 20001~20006,
///   Attendance 40001, Common 50000~50001
/// ApiService 拦截器自动拦截非 200 的 code 并转为 ApiException，
/// 业务层无需重复处理。
class ErrorCode {
  // ──────────────────────────────────────────────
  // Auth 模块（10001-10009）
  // ──────────────────────────────────────────────

  /// 10001 - 手机号不能为空
  static const int phoneRequired = 10001;

  /// 10002 - 密码不能为空
  static const int passwordRequired = 10002;

  /// 10003 - 手机号格式错误
  static const int phoneInvalid = 10003;

  /// 10004 - 密码长度不能少于6位
  static const int passwordTooShort = 10004;

  /// 10005 - 账号或密码错误
  static const int loginFailed = 10005;

  /// 10006 - Token无效或已过期
  static const int tokenInvalid = 10006;

  /// 10007 - 未提供认证Token
  static const int tokenMissing = 10007;

  /// 10008 - 用户不存在
  static const int userNotFound = 10008;

  /// 10009 - 无权限访问
  static const int forbidden = 10009;

  // ──────────────────────────────────────────────
  // Captcha / SMS 模块（10015-10020）
  // ──────────────────────────────────────────────

  /// 10015 - 验证码错误
  static const int captchaCodeError = 10015;

  /// 10016 - 验证码已过期
  static const int captchaExpired = 10016;

  /// 10017 - 短信验证码错误
  static const int smsCodeError = 10017;

  /// 10018 - 短信验证码已过期
  static const int smsCodeExpired = 10018;

  /// 10019 - 发送过于频繁
  static const int smsTooFrequent = 10019;

  /// 10020 - 手机号格式不正确
  static const int phoneFormatInvalid = 10020;

  // ──────────────────────────────────────────────
  // Location 模块（20001-20006）
  // ──────────────────────────────────────────────

  /// 20001 - 经度超出有效范围
  static const int lngInvalid = 20001;

  /// 20002 - 纬度超出有效范围
  static const int latInvalid = 20002;

  /// 20003 - 位置数据不能为空
  static const int locDataRequired = 20003;

  /// 20004 - 批量位置数据不能为空
  static const int locBatchEmpty = 20004;

  /// 20005 - 批量数据超过上限
  static const int locBatchTooLarge = 20005;

  /// 20006 - 日期参数无效
  static const int locDateInvalid = 20006;

  // ──────────────────────────────────────────────
  // Attendance 模块
  // ──────────────────────────────────────────────

  /// 40001 - 不在打卡范围内
  static const int attendOutOfRange = 40001;

  /// 40004 - 当前时间不在打卡有效时段内
  static const int attendTimeInvalid = 40004;

  /// 40005 - 今日已打卡，请勿重复签到
  static const int attendDuplicate = 40005;

  // ──────────────────────────────────────────────
  // Common 模块（50000-50001）
  // ──────────────────────────────────────────────

  /// 50000 - 服务器内部错误
  static const int internalError = 50000;

  /// 50001 - 请求参数无效
  static const int paramInvalid = 50001;

  // ──────────────────────────────────────────────
  // 错误码 → 中文提示 映射表
  // ──────────────────────────────────────────────

  static const Map<int, String> _messages = {
    // ── Auth ──
    10001: '手机号不能为空',
    10002: '密码不能为空',
    10003: '手机号格式错误',
    10004: '密码长度不能少于6位',
    10005: '账号或密码错误',
    10006: 'Token无效或已过期',
    10007: '未提供认证Token',
    10008: '用户不存在',
    10009: '无权限访问',
    // ── 预留 10010~10014（前端通用兜底）──
    10010: '系统繁忙，请稍后重试',
    10011: '请勿重复操作',
    10012: '数据已存在，无法重复添加',
    10013: '签到位置超出打卡范围',
    10014: '当前时间不在打卡有效时段内',
    // ── Captcha / SMS ──
    10015: '验证码错误',
    10016: '验证码已过期，请重新获取',
    10017: '短信验证码错误',
    10018: '短信验证码已过期，请重新获取',
    10019: '发送过于频繁，请60秒后再试',
    10020: '手机号格式不正确，请输入11位手机号',
    // ── Location ──
    20001: '经度超出有效范围(-180~180)',
    20002: '纬度超出有效范围(-85~85)',
    20003: '位置数据不能为空',
    20004: '批量上传数据不能为空',
    20005: '单次批量上传不能超过100条',
    20006: '日期参数无效(格式: YYYY-MM-DD)',
    // ── Attendance ──
    40001: '不在打卡范围内，请靠近打卡点',
    40004: '当前时间不在打卡有效时段内',
    40005: '今日已打卡，请勿重复签到',
    // ── Common ──
    50000: '服务器内部错误',
    50001: '请求参数无效',
  };

  /// 根据错误码获取用户友好提示
  static String message(int code) {
    return _messages[code] ?? '未知错误($code)';
  }

  /// 判断是否为业务层的错误码
  /// Auth(10001-10009), 预留(10010-10014), Captcha/SMS(10015-10020),
  /// Location(20001-20006), Attendance(40001), Common(50000-50001)
  static bool isBusinessError(int code) {
    return (code >= 10001 && code <= 10020) ||
        (code >= 20001 && code <= 20006) ||
        code == 40001 || code == 40004 || code == 40005 ||
        (code >= 50000 && code <= 50001);
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
      10011 || 10012 || 10013 || 10014 || 40001 || 40004 || 40005 => true,
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
