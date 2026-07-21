import 'dart:ui' show Color;

import 'package:dio/dio.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../config/app_config.dart';
import 'error_codes.dart';

/// Toast 红色背景（避免依赖 Material 包）
const Color _toastRed = Color.fromARGB(255, 212, 60, 60);

/// API通信服务
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;
  String? _token;

  ApiService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          final codeVal = data['code'];
          final int? bizCode = (codeVal is int) ? codeVal : int.tryParse('$codeVal');
          if (bizCode != null && bizCode != 200 && ErrorCode.isBusinessError(bizCode)) {
            final msg = ErrorCode.message(bizCode);

            Fluttertoast.showToast(
              msg: msg,
              backgroundColor: _toastRed,
              gravity: ToastGravity.TOP,
            );

            handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                response: response,
                type: DioExceptionType.badResponse,
                error: ApiException(code: bizCode, message: msg, rawData: data),
              ),
            );
            return;
          }
        }
        handler.next(response);
      },
      onError: (error, handler) {
        // 尝试从错误响应中提取业务错误码
        final resp = error.response;
        Map<String, dynamic>? bizData;
        if (resp != null && resp.data is Map) {
          bizData = resp.data as Map<String, dynamic>;
        }
        if (bizData != null) {
          final codeVal = bizData['code'];
          final int? bizCode = (codeVal is int) ? codeVal : int.tryParse('$codeVal');
          if (bizCode != null && ErrorCode.isBusinessError(bizCode)) {
            final msg = ErrorCode.message(bizCode);

            Fluttertoast.showToast(
              msg: msg,
              backgroundColor: _toastRed,
              gravity: ToastGravity.TOP,
            );

            handler.next(
              DioException(
                requestOptions: error.requestOptions,
                response: error.response,
                type: DioExceptionType.badResponse,
                error: ApiException(code: bizCode, message: msg, rawData: bizData),
              ),
            );
            return;
          }
        }

        // 非业务错误的网络/HTTP异常 —— 转译为友好提示
        final httpMsg = _httpErrorMessage(error);
        Fluttertoast.showToast(
          msg: httpMsg,
          backgroundColor: _toastRed,
          gravity: ToastGravity.TOP,
        );

        handler.next(error);
      },
    ));
  }

  void setToken(String? token) => _token = token;

  /// 更新服务器地址（用户手动设置后调用）
  void updateBaseUrl(String newUrl) {
    _dio.options.baseUrl = newUrl;
  }

  Future<Response> post(String path, {Map<String, dynamic>? data}) =>
      _dio.post(path, data: data);

  Future<Response> uploadFile(String path, FormData formData) =>
      _dio.post(path, data: formData);

  Future<Response> get(String path, {Map<String, dynamic>? query}) =>
      _dio.get(path, queryParameters: query);

  Future<Response> put(String path, {Map<String, dynamic>? data}) =>
      _dio.put(path, data: data);

  Future<Response> delete(String path) =>
      _dio.delete(path);

  static String _httpErrorMessage(DioException e) {
    final resp = e.response;
    if (resp != null && resp.data is Map) {
      final data = resp.data as Map<String, dynamic>;
      final msg = data['message'] as String?;
      if (msg != null && msg.isNotEmpty) return msg;
    }

    return switch (e.type) {
      DioExceptionType.connectionTimeout => '连接超时，请检查网络',
      DioExceptionType.sendTimeout => '请求发送超时，请稍后重试',
      DioExceptionType.receiveTimeout => '响应超时，请稍后重试',
      DioExceptionType.connectionError => '网络连接失败，请检查网络',
      DioExceptionType.badResponse => _statusCodeMessage(e.response?.statusCode),
      DioExceptionType.cancel => '请求已取消',
      DioExceptionType.badCertificate => '证书校验失败，请更新应用',
      _ => '网络异常，请稍后重试',
    };
  }

  static String _statusCodeMessage(int? code) {
    return switch (code) {
      400 => '请求参数有误',
      401 => '登录已过期，请重新登录',
      403 => '无权限访问',
      404 => '请求的资源不存在',
      405 => '不支持的请求方法',
      429 => '请求过于频繁，请稍后重试',
      500 => '服务器内部错误',
      502 => '网关错误',
      503 => '服务暂不可用',
      _ => '请求失败($code)',
    };
  }
}
