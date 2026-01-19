import 'dart:io';
import '../../utils/index.dart';

/// 视频任务状态
class VideoTaskStatus {
  final String id;
  final String status;
  final int progress;
  final String? videoUrl;
  final String? errorMessage;

  VideoTaskStatus({
    required this.id,
    required this.status,
    required this.progress,
    this.videoUrl,
    this.errorMessage,
  });

  factory VideoTaskStatus.fromJson(Map<String, dynamic> json) {
    return VideoTaskStatus(
      id: json['id'] ?? '',
      status: json['status'] ?? 'unknown',
      progress: json['progress'] ?? 0,
      videoUrl: json['video_url'] ?? json['url'],
      errorMessage: json['error']?['message'],
    );
  }
}

/// API 供应商基础抽象类
/// 所有供应商实现必须继承此类并实现所有抽象方法
abstract class BaseApiProvider {
  /// 基础 URL
  String get baseUrl;
  
  /// API 密钥
  String get apiKey;
  
  /// 供应商名称（用于识别）
  String get providerName;

  /// LLM 聊天补全
  /// 
  /// [model] 模型名称
  /// [messages] 消息列表
  /// [temperature] 温度参数
  /// [maxTokens] 最大 token 数
  /// 返回生成的文本内容
  Future<String> chatCompletion({
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int? maxTokens,
  });

  /// 生成图片
  /// 
  /// [model] 模型名称
  /// [prompt] 提示词
  /// [width] 图片宽度
  /// [height] 图片高度
  /// [referenceImages] 参考图片路径列表（可选）
  /// 返回图片 URL（可能是网络 URL 或 Base64 data URI）
  Future<String> generateImage({
    required String model,
    required String prompt,
    int width = 1024,
    int height = 1024,
    List<String>? referenceImages,
  });

  /// 创建视频生成任务
  /// 
  /// [model] 模型名称
  /// [prompt] 提示词
  /// [size] 视频尺寸（如 '720x1280'）
  /// [seconds] 视频时长（秒）
  /// [inputReference] 参考图片/视频文件（可选）
  /// 返回任务 ID
  Future<String> createVideo({
    required String model,
    required String prompt,
    String size = '720x1280',
    int? seconds,
    File? inputReference,
  });

  /// 获取视频任务状态
  /// 
  /// [taskId] 任务 ID
  /// 返回任务状态信息
  Future<VideoTaskStatus> getVideoTask({
    required String taskId,
  });

  /// 上传视频到 OSS（可选，某些供应商可能需要）
  /// 
  /// [videoFile] 视频文件
  /// 返回上传后的公网 URL
  Future<String> uploadVideoToOss(File videoFile);

  /// 创建角色（可选，某些供应商可能需要）
  /// 
  /// [videoUrl] 视频 URL
  /// 返回角色创建响应数据
  Future<Map<String, dynamic>> createCharacter(String videoUrl);

  // ==================== 受保护的通用方法 ====================

  /// 安全的 API 调用包装器（受保护方法，供子类使用）
  /// 
  /// 统一处理所有 API 调用的错误，包括：
  /// - 网络连接错误（SocketException）
  /// - 请求超时（TimeoutException）
  /// - HTTP 错误响应（4xx, 5xx）
  /// - 数据解析错误（FormatException）
  /// - 其他未知错误
  /// 
  /// **使用示例**：
  /// ```dart
  /// // 子类中使用
  /// Future<String> chatCompletion({...}) async {
  ///   return await safeApiCall(
  ///     apiCall: () async {
  ///       final response = await http.post(...);
  ///       if (response.statusCode != 200) {
  ///         throw response;
  ///       }
  ///       return jsonDecode(response.body)['content'];
  ///     },
  ///     context: 'LLM 聊天补全',
  ///   );
  /// }
  /// ```
  /// 
  /// [apiCall] 实际的 API 调用函数
  /// [context] 错误上下文（如 "图片生成", "视频任务查询"），用于日志记录
  /// 
  /// 返回 API 调用的结果，或抛出 AppException
  Future<T> safeApiCall<T>({
    required Future<T> Function() apiCall,
    String? context,
  }) async {
    try {
      // 执行 API 调用
      return await apiCall();
      
    } on AppException {
      // 如果已经是 AppException，直接重新抛出
      rethrow;
      
    } catch (e, stackTrace) {
      // 捕获所有其他异常，统一处理
      
      // 记录详细的错误日志（包含上下文）
      ApiErrorHandler.logError(
        e,
        stackTrace: stackTrace,
        context: context ?? '${providerName} API 调用',
      );
      
      // 创建统一的 AppException 并抛出
      // ApiErrorHandler.createException 会根据错误类型生成合适的中文提示
      throw ApiErrorHandler.createException(e, stackTrace);
    }
  }

  /// 安全的 HTTP 响应检查（受保护方法，供子类使用）
  /// 
  /// 检查 HTTP 响应状态码，如果不是 200，则抛出 AppException
  /// 
  /// **使用示例**：
  /// ```dart
  /// final response = await http.post(...);
  /// checkHttpResponse(response, context: '图片生成');
  /// ```
  /// 
  /// [response] HTTP 响应对象
  /// [context] 错误上下文
  /// [expectedStatusCode] 期望的状态码（默认 200）
  void checkHttpResponse(
    dynamic response, {
    String? context,
    int expectedStatusCode = 200,
  }) {
    // 检查响应对象是否有 statusCode 属性
    if (response is! Object || 
        !response.toString().contains('statusCode')) {
      return;
    }
    
    // 尝试获取状态码
    int? statusCode;
    try {
      statusCode = (response as dynamic).statusCode as int?;
    } catch (_) {
      return;
    }
    
    // 如果状态码不符合期望，抛出异常
    if (statusCode != null && statusCode != expectedStatusCode) {
      final errorContext = context ?? '${providerName} API 请求';
      print('❌ [$errorContext] HTTP 错误: $statusCode');
      
      // 创建服务器错误异常
      throw AppException.server(
        statusCode: statusCode,
        originalError: response,
      );
    }
  }
}
