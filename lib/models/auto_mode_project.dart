import 'scene_model.dart';
import 'auto_mode_step.dart';
import 'character_model.dart';

/// Auto Mode 项目模型
class AutoModeProject {
  final String id;
  final String title;
  AutoModeStep currentStep;
  String currentScript;
  String currentLayout;
  List<CharacterModel> characters;  // 角色列表
  List<SceneModel> scenes;
  bool isProcessing;
  String? errorMessage;
  String? finalVideoUrl;
  DateTime? lastModified;
  bool hasUnsavedChanges;
  bool isSaving;
  String? generationStatus;

  AutoModeProject({
    required this.id,
    required this.title,
    this.currentStep = AutoModeStep.script,
    this.currentScript = '',
    this.currentLayout = '',
    this.characters = const [],
    this.scenes = const [],
    this.isProcessing = false,
    this.errorMessage,
    this.finalVideoUrl,
    this.lastModified,
    this.hasUnsavedChanges = false,
    this.isSaving = false,
    this.generationStatus,
  });

  /// 从 JSON 创建
  /// CRITICAL: 验证所有关键字段是否正确恢复
  factory AutoModeProject.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final title = json['title'] as String? ?? '未命名项目';
    final currentScript = json['currentScript'] as String? ?? '';
    final currentLayout = json['currentLayout'] as String? ?? '';
    
    // CRITICAL: 深度修复角色反序列化
    final charactersJson = json['characters'] as List?;
    final characters = charactersJson?.map((e) {
      try {
        final charMap = Map<String, dynamic>.from(e as Map);
        return CharacterModel.fromJson(charMap);
      } catch (e, stackTrace) {
        print('[AutoModeProject] ✗ 角色解析失败: $e');
        print('[AutoModeProject] 角色原始数据: $e');
        print('[AutoModeProject] 堆栈: $stackTrace');
        return null;
      }
    }).whereType<CharacterModel>().toList() ?? [];
    
    // CRITICAL: 深度修复场景反序列化
    // 确保每个场景项都经过安全的 Map 转换
    final scenesJson = json['scenes'] as List?;
    final scenes = scenesJson?.map((e) {
      try {
        // CRITICAL: 双重安全转换，确保类型正确
        // 先转换为 Map，再转换为 Map<String, dynamic>
        final sceneMap = Map<String, dynamic>.from(e as Map);
        return SceneModel.fromJson(sceneMap);
      } catch (e, stackTrace) {
        print('[AutoModeProject] ✗ 场景解析失败: $e');
        print('[AutoModeProject] 场景原始数据: $e');
        print('[AutoModeProject] 堆栈: $stackTrace');
        return null;
      }
    }).whereType<SceneModel>().toList() ?? [];
    
    // 验证数据完整性
    if (id.isEmpty) {
      print('[AutoModeProject] 警告: 项目 ID 为空');
    }
    
    final project = AutoModeProject(
      id: id,
      title: title,
      currentStep: AutoModeStep.values[
        (json['currentStep'] as int?)?.clamp(0, AutoModeStep.values.length - 1) ?? 0
      ],
      currentScript: currentScript,
      currentLayout: currentLayout,
      characters: characters,
      scenes: scenes,
      isProcessing: json['isProcessing'] as bool? ?? false,
      errorMessage: json['errorMessage'] as String?,
      finalVideoUrl: json['finalVideoUrl'] as String?,
      lastModified: json['lastModified'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastModified'] as int)
          : null,
      hasUnsavedChanges: json['hasUnsavedChanges'] as bool? ?? false,
      isSaving: json['isSaving'] as bool? ?? false,
      generationStatus: json['generationStatus'] as String?,
    );
    
    // 打印验证信息
    print('[AutoModeProject] 从 JSON 恢复: id=$id, 标题=$title, 剧本=${currentScript.isNotEmpty ? "${currentScript.length}字符" : "空"}, 分镜=${currentLayout.isNotEmpty ? "${currentLayout.length}字符" : "空"}, 角色数=${characters.length}, 场景数=${scenes.length}');
    
    return project;
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'currentStep': currentStep.index,
      'currentScript': currentScript,
      'currentLayout': currentLayout,
      'characters': characters.map((c) => c.toJson()).toList(),
      'scenes': scenes.map((s) => s.toJson()).toList(),
      'isProcessing': isProcessing,
      'errorMessage': errorMessage,
      'finalVideoUrl': finalVideoUrl,
      'lastModified': lastModified?.millisecondsSinceEpoch,
      'hasUnsavedChanges': hasUnsavedChanges,
      'isSaving': isSaving,
      'generationStatus': generationStatus,
    };
  }

  /// 创建副本
  AutoModeProject copyWith({
    String? id,
    String? title,
    AutoModeStep? currentStep,
    String? currentScript,
    String? currentLayout,
    List<CharacterModel>? characters,
    List<SceneModel>? scenes,
    bool? isProcessing,
    String? errorMessage,
    String? finalVideoUrl,
    DateTime? lastModified,
    bool? hasUnsavedChanges,
    bool? isSaving,
    String? generationStatus,
  }) {
    return AutoModeProject(
      id: id ?? this.id,
      title: title ?? this.title,
      currentStep: currentStep ?? this.currentStep,
      currentScript: currentScript ?? this.currentScript,
      currentLayout: currentLayout ?? this.currentLayout,
      characters: characters ?? this.characters,
      scenes: scenes ?? this.scenes,
      isProcessing: isProcessing ?? this.isProcessing,
      errorMessage: errorMessage ?? this.errorMessage,
      finalVideoUrl: finalVideoUrl ?? this.finalVideoUrl,
      lastModified: lastModified ?? this.lastModified,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      isSaving: isSaving ?? this.isSaving,
      generationStatus: generationStatus ?? this.generationStatus,
    );
  }
}
