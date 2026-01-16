/// 角色模型 - 用于 Auto Mode 角色生成步骤
class CharacterModel {
  final String name;           // 角色名称
  String prompt;                // 角色提示词
  String? imageUrl;             // 角色图片 URL
  String? localImagePath;      // 本地图片文件路径
  bool isGeneratingImage;       // 是否正在生成图片
  double imageGenerationProgress; // 图片生成进度 (0.0 - 1.0)
  String? generationStatus;     // 生成状态: "queueing", "processing", null
  String? errorMessage;         // 错误消息

  CharacterModel({
    required this.name,
    this.prompt = '',
    this.imageUrl,
    this.localImagePath,
    this.isGeneratingImage = false,
    this.imageGenerationProgress = 0.0,
    this.generationStatus,
    this.errorMessage,
  });

  /// 从 JSON 创建
  factory CharacterModel.fromJson(Map<String, dynamic> json) {
    return CharacterModel(
      name: json['name'] as String,
      prompt: json['prompt'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      localImagePath: json['localImagePath'] as String?,
      isGeneratingImage: json['isGeneratingImage'] as bool? ?? false,
      imageGenerationProgress: (json['imageGenerationProgress'] as num?)?.toDouble() ?? 0.0,
      generationStatus: json['generationStatus'] as String?,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'prompt': prompt,
      'imageUrl': imageUrl,
      'localImagePath': localImagePath,
      'isGeneratingImage': isGeneratingImage,
      'imageGenerationProgress': imageGenerationProgress,
      'generationStatus': generationStatus,
      'errorMessage': errorMessage,
    };
  }

  /// 创建副本
  CharacterModel copyWith({
    String? name,
    String? prompt,
    String? imageUrl,
    String? localImagePath,
    bool? isGeneratingImage,
    double? imageGenerationProgress,
    String? generationStatus,
    String? errorMessage,
  }) {
    return CharacterModel(
      name: name ?? this.name,
      prompt: prompt ?? this.prompt,
      imageUrl: imageUrl ?? this.imageUrl,
      localImagePath: localImagePath ?? this.localImagePath,
      isGeneratingImage: isGeneratingImage ?? this.isGeneratingImage,
      imageGenerationProgress: imageGenerationProgress ?? this.imageGenerationProgress,
      generationStatus: generationStatus ?? this.generationStatus,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
