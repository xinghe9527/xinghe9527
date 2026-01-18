import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../models/auto_mode_project.dart';
import '../../models/scene_model.dart';
import '../../models/prompt_template.dart';
import '../../services/prompt_store.dart';
import '../../services/api_config_manager.dart';

/// 分镜生成 Mixin
/// 
/// 负责 Auto Mode 中分镜设计生成相关的逻辑
mixin StoryboardGenerationMixin on ChangeNotifier {
  // 这些属性需要在主类中定义
  Map<String, AutoModeProject> get projects;
  
  // 这些方法需要在主类中实现
  Future<void> saveToDisk(String projectId, {bool immediate = true});
  void safeNotifyListeners();
  void markDirty(String projectId);
  
  /// 生成分镜设计（针对特定项目）
  Future<void> generateLayout(String projectId, {String? modification}) async {
    final project = projects[projectId];
    if (project == null) {
      throw Exception('项目不存在: $projectId');
    }
    
    final apiConfigManager = ApiConfigManager();
    if (!apiConfigManager.hasLlmConfig) {
      throw Exception('请先在设置中配置 LLM API');
    }

    final apiService = apiConfigManager.createApiService();
    
    // 获取提示词模板
    String systemPrompt = '''你是一个专业的动漫分镜设计师。请根据剧本内容，设计详细的分镜脚本。

要求：
1. 每个镜头包含：镜头类型、景别、角度、运动方式
2. 描述画面构图和视觉元素
3. 标注时长和转场方式
4. 考虑动画制作的可行性

输出格式：JSON数组，每个元素包含 index, script, imagePrompt 字段''';

    final templates = promptStore.getTemplates(PromptCategory.storyboard);
    if (templates.isNotEmpty) {
      systemPrompt = '${templates.first.content}\n\n$systemPrompt';
    }

    // 设置处理状态，立即保存
    project.isProcessing = true;
    project.generationStatus = '正在生成分镜设计...';
    await saveToDisk(projectId, immediate: true);
    
    final userContent = modification ?? project.currentScript;
    final response = await apiService.chatCompletion(
      model: apiConfigManager.llmModel,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': '请根据以下剧本生成分镜设计：\n\n$userContent'},
      ],
      temperature: 0.7,
    );

    try {
      final content = response.choices.first.message.content;
      // 尝试提取 JSON
      final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(content);
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0)!;
        final List<dynamic> parsed = jsonDecode(jsonStr);
        
        project.scenes = parsed.asMap().entries.map((entry) {
          final data = entry.value as Map<String, dynamic>;
          return SceneModel(
            index: entry.key,
            script: data['script'] as String? ?? data['description'] as String? ?? '',
            imagePrompt: data['imagePrompt'] as String? ?? data['prompt'] as String? ?? '',
          );
        }).toList();
      } else {
        // 如果没有 JSON，尝试解析文本格式
        throw Exception('无法解析分镜设计，请确保返回 JSON 格式');
      }
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 解析分镜设计失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
      throw Exception('解析分镜设计失败: $e');
    }

    project.currentLayout = response.choices.first.message.content;
    project.isProcessing = false;
    project.generationStatus = null;
    
    // CRITICAL: 立即保存到磁盘，确保数据不丢失
    await saveToDisk(projectId, immediate: true);
    safeNotifyListeners();
  }

  /// 更新场景的图片提示词（场景描述保持不变）
  Future<void> updateScenePrompt(String projectId, int sceneIndex, {String? imagePrompt}) async {
    final project = projects[projectId];
    if (project == null || sceneIndex < 0 || sceneIndex >= project.scenes.length) {
      return;
    }
    
    if (imagePrompt == null) {
      return; // 没有要更新的内容
    }
    
    final scene = project.scenes[sceneIndex];
    project.scenes[sceneIndex] = scene.copyWith(
      imagePrompt: imagePrompt,
    );
    
    markDirty(projectId);
    await saveToDisk(projectId, immediate: true);
    safeNotifyListeners();
  }
}
