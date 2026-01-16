import 'scene_status.dart';

/// 场景模型 - 用于 Auto Mode 工作流
class SceneModel {
  final int index;
  String script;
  String imagePrompt;
  String? imageUrl;
  String? videoUrl;
  String? localImagePath;  // 本地图片文件路径
  String? localVideoPath;  // 本地视频文件路径
  bool isGeneratingImage;
  bool isGeneratingVideo;
  double imageGenerationProgress;  // 图片生成进度 (0.0 - 1.0)
  double videoGenerationProgress;  // 视频生成进度 (0.0 - 1.0)
  String? generationStatus;  // 生成状态: "queueing", "processing", null
  SceneStatus status;  // 场景状态
  String? errorMessage;  // 错误消息

  SceneModel({
    required this.index,
    required this.script,
    this.imagePrompt = '',
    this.imageUrl,
    this.videoUrl,
    this.localImagePath,
    this.localVideoPath,
    this.isGeneratingImage = false,
    this.isGeneratingVideo = false,
    this.imageGenerationProgress = 0.0,
    this.videoGenerationProgress = 0.0,
    this.generationStatus,
    this.status = SceneStatus.idle,
    this.errorMessage,
  });

  /// 从 JSON 创建
  factory SceneModel.fromJson(Map<String, dynamic> json) {
    return SceneModel(
      index: json['index'] as int,
      script: json['script'] as String,
      imagePrompt: json['imagePrompt'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      videoUrl: json['videoUrl'] as String?,
      localImagePath: json['localImagePath'] as String?,
      localVideoPath: json['localVideoPath'] as String?,
      isGeneratingImage: json['isGeneratingImage'] as bool? ?? false,
      isGeneratingVideo: json['isGeneratingVideo'] as bool? ?? false,
      imageGenerationProgress: (json['imageGenerationProgress'] as num?)?.toDouble() ?? 0.0,
      videoGenerationProgress: (json['videoGenerationProgress'] as num?)?.toDouble() ?? 0.0,
      generationStatus: json['generationStatus'] as String?,
      status: json['status'] != null
          ? SceneStatus.values.firstWhere(
              (e) => e.name == json['status'],
              orElse: () => SceneStatus.idle,
            )
          : SceneStatus.idle,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'script': script,
      'imagePrompt': imagePrompt,
      'imageUrl': imageUrl,
      'videoUrl': videoUrl,
      'localImagePath': localImagePath,
      'localVideoPath': localVideoPath,
      'isGeneratingImage': isGeneratingImage,
      'isGeneratingVideo': isGeneratingVideo,
      'imageGenerationProgress': imageGenerationProgress,
      'videoGenerationProgress': videoGenerationProgress,
      'generationStatus': generationStatus,
      'status': status.name,
      'errorMessage': errorMessage,
    };
  }

  /// 创建副本
  SceneModel copyWith({
    int? index,
    String? script,
    String? imagePrompt,
    String? imageUrl,
    String? videoUrl,
    String? localImagePath,
    String? localVideoPath,
    bool? isGeneratingImage,
    bool? isGeneratingVideo,
    double? imageGenerationProgress,
    double? videoGenerationProgress,
    String? generationStatus,
    SceneStatus? status,
    String? errorMessage,
  }) {
    return SceneModel(
      index: index ?? this.index,
      script: script ?? this.script,
      imagePrompt: imagePrompt ?? this.imagePrompt,
      imageUrl: imageUrl ?? this.imageUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      localImagePath: localImagePath ?? this.localImagePath,
      localVideoPath: localVideoPath ?? this.localVideoPath,
      isGeneratingImage: isGeneratingImage ?? this.isGeneratingImage,
      isGeneratingVideo: isGeneratingVideo ?? this.isGeneratingVideo,
      imageGenerationProgress: imageGenerationProgress ?? this.imageGenerationProgress,
      videoGenerationProgress: videoGenerationProgress ?? this.videoGenerationProgress,
      generationStatus: generationStatus ?? this.generationStatus,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
