import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/auto_mode_project.dart';
import '../../models/character_model.dart';
import '../../models/prompt_template.dart';
import '../../services/prompt_store.dart';
import '../../services/api_config_manager.dart';

/// 角色生成 Mixin
/// 
/// 负责 Auto Mode 中角色生成相关的逻辑
mixin CharacterGenerationMixin on ChangeNotifier {
  // 这些属性需要在主类中定义
  Map<String, AutoModeProject> get projects;
  
  // 这些方法需要在主类中实现
  Future<void> saveToDisk(String projectId, {bool immediate = true});
  void safeNotifyListeners();
  void markDirty(String projectId);
  
  /// 生成角色（针对特定项目）
  Future<void> generateCharacters(String projectId, {String? modification}) async {
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
    String systemPrompt = '''你是一个专业的动漫角色设计师。请根据剧本内容，提取并生成所有角色的详细描述。

要求：
1. 识别剧本中的所有主要角色
2. 为每个角色生成详细的描述，包括：
   - 角色名称
   - 外貌特征（发型、服装、体型等）
   - 性格特点
   - 角色定位
3. 生成适合图片生成的提示词，包含角色外观的详细描述
4. 确保角色描述清晰、具体，适合AI图片生成

输出格式：JSON数组，每个元素包含 name（角色名称）和 prompt（角色提示词）字段''';

    final templates = promptStore.getTemplates(PromptCategory.character);
    if (templates.isNotEmpty) {
      systemPrompt = '${templates.first.content}\n\n$systemPrompt';
    }

    // 设置处理状态，立即保存
    project.isProcessing = true;
    project.generationStatus = '正在生成角色...';
    await saveToDisk(projectId, immediate: true);
    
    final userContent = modification ?? project.currentScript;
    final response = await apiService.chatCompletion(
      model: apiConfigManager.llmModel,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': '请根据以下剧本生成角色列表：\n\n$userContent'},
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
        
        project.characters = parsed.map((data) {
          final charData = data as Map<String, dynamic>;
          return CharacterModel(
            name: charData['name'] as String? ?? '未命名角色',
            prompt: charData['prompt'] as String? ?? charData['description'] as String? ?? '',
          );
        }).toList();
      } else {
        // 如果没有 JSON，尝试解析文本格式
        throw Exception('无法解析角色列表，请确保返回 JSON 格式');
      }
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 解析角色列表失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
      throw Exception('解析角色列表失败: $e');
    }

    project.isProcessing = false;
    project.generationStatus = null;
    
    // CRITICAL: 立即保存到磁盘，确保数据不丢失
    await saveToDisk(projectId, immediate: true);
    safeNotifyListeners();
  }

  /// 生成单个角色图片（针对特定项目）
  Future<void> generateCharacterImage(String projectId, int characterIndex) async {
    final project = projects[projectId];
    if (project == null) {
      throw Exception('项目不存在: $projectId');
    }
    
    if (characterIndex < 0 || characterIndex >= project.characters.length) {
      throw Exception('角色索引无效');
    }
    
    final character = project.characters[characterIndex];
    
    if (character.prompt.isEmpty) {
      throw Exception('角色提示词为空，无法生成图片');
    }
    
    final apiConfigManager = ApiConfigManager();
    if (!apiConfigManager.hasImageConfig) {
      throw Exception('请先在设置中配置图片生成 API');
    }
    
    final apiService = apiConfigManager.createApiService();
    
    // 更新状态
    project.characters[characterIndex] = character.copyWith(
      isGeneratingImage: true,
      imageGenerationProgress: 0.0,
      generationStatus: 'processing',
      errorMessage: null,
    );
    safeNotifyListeners();
    
    try {
      // 调用 API 生成图片
      final response = await apiService.generateImage(
        prompt: character.prompt,
        model: apiConfigManager.imageModel,
        width: 1024,
        height: 1024,
      );
      
      // 保存图片到本地
      final imageUrl = response.imageUrl;
      if (imageUrl.isNotEmpty) {
        // 保存角色图片到本地（使用临时目录或保存设置）
        final localPath = await saveCharacterImageToLocal(imageUrl, character.name);
        
        project.characters[characterIndex] = character.copyWith(
          imageUrl: imageUrl,
          localImagePath: localPath,
          isGeneratingImage: false,
          imageGenerationProgress: 1.0,
          generationStatus: null,
        );
      } else {
        throw Exception('图片生成失败：未返回图片 URL');
      }
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 生成角色图片失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
      project.characters[characterIndex] = character.copyWith(
        isGeneratingImage: false,
        imageGenerationProgress: 0.0,
        generationStatus: null,
        errorMessage: e.toString(),
      );
      rethrow;
    }
    
    markDirty(projectId);
    safeNotifyListeners();
  }

  /// 保存角色图片到本地
  Future<String?> saveCharacterImageToLocal(String imageUrl, String characterName) async {
    try {
      Uint8List imageBytes;
      
      // 检查是否是 Base64 数据URI
      if (imageUrl.startsWith('data:image/')) {
        // 从 Base64 数据URI 中提取数据
        final base64Index = imageUrl.indexOf('base64,');
        if (base64Index == -1) {
          print('[CharacterGenerationMixin] Base64 数据URI 格式无效');
          return null;
        }
        final base64Data = imageUrl.substring(base64Index + 7);
        try {
          imageBytes = Uint8List.fromList(base64Decode(base64Data));
        } catch (e, stackTrace) {
          print('❌ [CRITICAL ERROR CAUGHT] Base64 解码失败');
          print('❌ [Error Details]: $e');
          print('📍 [Stack Trace]: $stackTrace');
          return null;
        }
      } else if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
        // HTTP URL，下载图片
        final response = await http.get(Uri.parse(imageUrl));
        if (response.statusCode != 200) {
          print('[CharacterGenerationMixin] 下载图片失败: ${response.statusCode}');
          return null;
        }
        imageBytes = response.bodyBytes;
      } else {
        // 可能是本地文件路径，直接返回
        if (await File(imageUrl).exists()) {
          return imageUrl;
        }
        print('[CharacterGenerationMixin] 不支持的图片URL格式: $imageUrl');
        return null;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final autoSave = prefs.getBool('auto_save_images') ?? false;
      final savePath = prefs.getString('image_save_path') ?? '';

      Directory dir;
      if (!autoSave || savePath.isEmpty) {
        // 如果不自动保存，保存到临时目录
        final tempDir = await getTemporaryDirectory();
        dir = Directory('${tempDir.path}/xinghe_characters');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } else {
        // 确保目录存在
        dir = Directory(savePath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      }
      
      final fileName = 'character_${characterName}_${DateTime.now().millisecondsSinceEpoch}.png';
      final filePath = autoSave && savePath.isNotEmpty
          ? '$savePath${Platform.pathSeparator}$fileName'
          : '${dir.path}${Platform.pathSeparator}$fileName';
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);
      print('[CharacterGenerationMixin] 角色图片已保存到本地: $filePath');
      return filePath;
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 保存角色图片失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
      return null;
    }
  }
}
