import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'app_exception.dart';

/// API 错误处理工具类
/// 
/// 将各种异常转换为用户友好的中文提示
class ApiErrorHandler {
  /// 处理 API 错误，返回用户友好的中文提示
  /// 
  /// [error] 原始错误对象
  /// [stackTrace] 堆栈跟踪（可选）
  /// 
  /// 返回适合显示给用户的中文错误消息
  static String handle(dynamic error, [StackTrace? stackTrace]) {
    // 如果已经是 AppException，直接返回消息
    if (error is AppException) {
      return error.message;
    }

    // HTTP 响应错误
    if (error is http.Response) {
      return _handleHttpResponse(error);
    }

    // 网络连接错误
    if (error is SocketException) {
      return '网络连接失败，请检查您的网络设置';
    }

    // 超时错误
    if (error is TimeoutException) {
      return '请求超时，服务器响应时间过长，请稍后重试';
    }

    // HTTP 客户端异常
    if (error is http.ClientException) {
      return '网络请求失败: ${error.message}';
    }

    // 格式化异常（JSON 解析失败）
    if (error is FormatException) {
      return '数据格式错误，无法解析服务器响应';
    }

    // 类型错误
    if (error is TypeError) {
      return '数据类型错误，请联系技术支持';
    }

    // 字符串错误
    if (error is String) {
      return _handleStringError(error);
    }

    // 异常对象
    if (error is Exception) {
      final errorMessage = error.toString();
      
      // 检查是否包含常见错误关键词
      if (errorMessage.contains('Connection refused')) {
        return '无法连接到服务器，请检查网络或服务器地址';
      }
      if (errorMessage.contains('Connection timed out')) {
        return '连接超时，请检查网络连接';
      }
      if (errorMessage.contains('No route to host')) {
        return '无法访问服务器，请检查网络配置';
      }
      if (errorMessage.contains('Connection reset')) {
        return '连接被重置，请稍后重试';
      }
      if (errorMessage.contains('Certificate verify failed')) {
        return 'SSL 证书验证失败，请检查网络安全设置';
      }
      if (errorMessage.contains('401')) {
        return '认证失败，请检查 API Key 是否正确';
      }
      if (errorMessage.contains('403')) {
        return '访问被拒绝，请检查账号权限';
      }
      if (errorMessage.contains('404')) {
        return '请求的资源不存在，请检查 API 地址';
      }
      if (errorMessage.contains('429')) {
        return '请求过于频繁，请等待一段时间后再试';
      }
      if (errorMessage.contains('500')) {
        return '服务器内部错误，请稍后重试';
      }
      if (errorMessage.contains('502')) {
        return '网关错误，服务暂时不可用';
      }
      if (errorMessage.contains('503')) {
        return '服务暂时不可用，请稍后重试';
      }
      
      return '操作失败: $errorMessage';
    }

    // 未知错误
    return '未知错误: $error';
  }

  /// 处理 HTTP 响应错误
  static String _handleHttpResponse(http.Response response) {
    final statusCode = response.statusCode;
    
    switch (statusCode) {
      case 400:
        return '请求参数错误，请检查输入内容';
      case 401:
        return 'API Key 无效或已过期，请在设置中更新';
      case 403:
        return '访问被拒绝，您的账号没有此权限';
      case 404:
        return '请求的 API 接口不存在，请检查配置';
      case 405:
        return '请求方法不允许';
      case 408:
        return '请求超时，请稍后重试';
      case 413:
        return '请求数据过大，请减少数据量';
      case 415:
        return '不支持的媒体类型';
      case 422:
        return '请求数据验证失败，请检查输入';
      case 429:
        return '请求过于频繁，请稍等片刻再试（已达到速率限制）';
      case 500:
        return '服务器内部错误，请稍后重试或联系技术支持';
      case 502:
        return '网关错误，服务暂时不可用';
      case 503:
        return '服务维护中，请稍后重试';
      case 504:
        return '网关超时，请稍后重试';
      default:
        if (statusCode >= 500) {
          return '服务器错误 ($statusCode)，请稍后重试';
        } else if (statusCode >= 400) {
          return '请求错误 ($statusCode)，请检查请求参数';
        } else {
          return '未知的 HTTP 状态码: $statusCode';
        }
    }
  }

  /// 处理字符串错误
  static String _handleStringError(String error) {
    final lowerError = error.toLowerCase();
    
    // 网络相关
    if (lowerError.contains('network') || lowerError.contains('connection')) {
      return '网络连接失败: $error';
    }
    
    // 超时相关
    if (lowerError.contains('timeout') || lowerError.contains('timed out')) {
      return '请求超时: $error';
    }
    
    // 认证相关
    if (lowerError.contains('unauthorized') || lowerError.contains('401')) {
      return '认证失败，请检查 API Key';
    }
    
    // 权限相关
    if (lowerError.contains('forbidden') || lowerError.contains('403')) {
      return '访问被拒绝，权限不足';
    }
    
    // 频率限制
    if (lowerError.contains('rate limit') || lowerError.contains('429')) {
      return '请求过于频繁，请稍后再试';
    }
    
    // 服务器错误
    if (lowerError.contains('server error') || lowerError.contains('500')) {
      return '服务器错误: $error';
    }
    
    // 解析错误
    if (lowerError.contains('parse') || lowerError.contains('json')) {
      return '数据解析失败: $error';
    }
    
    // 直接返回原始错误
    return error;
  }

  /// 从异常创建 AppException
  /// 
  /// [error] 原始错误对象
  /// [stackTrace] 堆栈跟踪（可选）
  /// 
  /// 返回统一的 AppException 对象
  static AppException createException(dynamic error, [StackTrace? stackTrace]) {
    // 如果已经是 AppException，直接返回
    if (error is AppException) {
      return error;
    }

    // HTTP 响应错误
    if (error is http.Response) {
      return AppException.server(
        statusCode: error.statusCode,
        message: _handleHttpResponse(error),
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    // 网络连接错误
    if (error is SocketException) {
      return AppException.network(
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    // 超时错误
    if (error is TimeoutException) {
      return AppException.timeout(
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    // 格式化异常（JSON 解析失败）
    if (error is FormatException) {
      return AppException.parse(
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    // 未知错误
    return AppException.unknown(
      message: handle(error, stackTrace),
      originalError: error,
      stackTrace: stackTrace,
    );
  }

  /// 打印友好的错误日志
  /// 
  /// [error] 错误对象
  /// [stackTrace] 堆栈跟踪（可选）
  /// [context] 错误上下文（如 "API 请求", "数据保存" 等）
  static void logError(
    dynamic error, {
    StackTrace? stackTrace,
    String? context,
  }) {
    print('❌ [错误${context != null ? ' - $context' : ''}]');
    print('   消息: ${handle(error, stackTrace)}');
    
    if (error is AppException) {
      if (error.statusCode != null) {
        print('   状态码: ${error.statusCode}');
      }
      if (error.originalError != null) {
        print('   原始错误: ${error.originalError}');
      }
    } else {
      print('   原始错误: $error');
    }
    
    if (stackTrace != null) {
      print('📍 [堆栈跟踪]:');
      print(stackTrace);
    }
  }
}
