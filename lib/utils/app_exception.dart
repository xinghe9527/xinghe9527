/// 应用自定义异常类
/// 
/// 用于统一管理应用中的异常，提供更友好的错误提示
class AppException implements Exception {
  /// 中文错误提示（给用户看的）
  final String message;
  
  /// HTTP 状态码（如果适用）
  final int? statusCode;
  
  /// 原始错误对象（用于调试）
  final dynamic originalError;
  
  /// 堆栈跟踪（用于调试）
  final StackTrace? stackTrace;

  AppException({
    required this.message,
    this.statusCode,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('AppException:');
    buffer.writeln('  消息: $message');
    
    if (statusCode != null) {
      buffer.writeln('  状态码: $statusCode');
    }
    
    if (originalError != null) {
      buffer.writeln('  原始错误: $originalError');
    }
    
    if (stackTrace != null) {
      buffer.writeln('  堆栈跟踪:');
      buffer.writeln(stackTrace.toString());
    }
    
    return buffer.toString();
  }

  /// 工厂构造函数：网络错误
  factory AppException.network({
    String? message,
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    return AppException(
      message: message ?? '网络连接失败，请检查您的网络设置',
      statusCode: null,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  /// 工厂构造函数：超时错误
  factory AppException.timeout({
    String? message,
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    return AppException(
      message: message ?? '请求超时，请稍后重试',
      statusCode: null,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  /// 工厂构造函数：服务器错误
  factory AppException.server({
    required int statusCode,
    String? message,
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    String defaultMessage;
    switch (statusCode) {
      case 400:
        defaultMessage = '请求参数错误';
        break;
      case 401:
        defaultMessage = '未授权，请检查 API Key';
        break;
      case 403:
        defaultMessage = '无权访问，请检查权限配置';
        break;
      case 404:
        defaultMessage = '请求的资源不存在';
        break;
      case 429:
        defaultMessage = '请求过于频繁，请稍后再试';
        break;
      case 500:
        defaultMessage = '服务器内部错误，请稍后重试';
        break;
      case 502:
        defaultMessage = '网关错误，请稍后重试';
        break;
      case 503:
        defaultMessage = '服务暂时不可用，请稍后重试';
        break;
      default:
        defaultMessage = '服务器错误 ($statusCode)';
    }
    
    return AppException(
      message: message ?? defaultMessage,
      statusCode: statusCode,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  /// 工厂构造函数：解析错误
  factory AppException.parse({
    String? message,
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    return AppException(
      message: message ?? '数据解析失败，请稍后重试',
      statusCode: null,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }

  /// 工厂构造函数：未知错误
  factory AppException.unknown({
    String? message,
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    return AppException(
      message: message ?? '未知错误，请稍后重试',
      statusCode: null,
      originalError: originalError,
      stackTrace: stackTrace,
    );
  }
}
