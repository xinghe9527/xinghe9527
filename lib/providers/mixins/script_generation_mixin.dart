import 'package:flutter/foundation.dart';
import '../../models/auto_mode_project.dart';
import '../../models/prompt_template.dart';
import '../../services/prompt_store.dart';
import '../../services/api_config_manager.dart';

/// 剧本生成 Mixin
/// 
/// 负责 Auto Mode 中剧本生成相关的逻辑
mixin ScriptGenerationMixin on ChangeNotifier {
  // 这些属性需要在主类中定义
  Map<String, AutoModeProject> get projects;
  
  // 这些方法需要在主类中实现
  Future<void> saveToDisk(String projectId, {bool immediate = true});
  void safeNotifyListeners();
  
  /// 生成剧本（针对特定项目）
  /// 每次文本更新立即保存，确保零数据丢失
  Future<void> generateScript(String projectId, String userInput) async {
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
    String systemPrompt = '你是一个专业的动漫剧本作家，擅长创作动漫剧本。请根据用户提供的故事创意，生成一个完整的剧本。';
    
    final templates = promptStore.getTemplates(PromptCategory.script);
    if (templates.isNotEmpty) {
      // 使用第一个模板（可以根据需要选择）
      systemPrompt = '${templates.first.content}\n\n$systemPrompt';
    }

    // 设置处理状态，立即保存
    project.isProcessing = true;
    project.generationStatus = '正在生成剧本...';
    await saveToDisk(projectId, immediate: true);
    
    final response = await apiService.chatCompletion(
      model: apiConfigManager.llmModel,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userInput},
      ],
      temperature: 0.7,
    );

    // 立即更新并保存（零数据丢失）
    project.currentScript = response.choices.first.message.content;
    project.isProcessing = false;
    project.generationStatus = null;
    
    // CRITICAL: 立即保存到磁盘，确保数据不丢失
    await saveToDisk(projectId, immediate: true);
    safeNotifyListeners();
  }
}
