import 'dart:io';

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
}
