import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/prompt_template.dart';

/// 提示词模板存储服务
/// 使用 ChangeNotifier 进行状态管理，与项目其他服务保持一致
class PromptStore extends ChangeNotifier {
  static final PromptStore _instance = PromptStore._internal();
  factory PromptStore() => _instance;
  PromptStore._internal();

  final Map<PromptCategory, List<PromptTemplate>> _templates = {};
  bool _isInitialized = false;

  /// 获取指定类别的模板列表
  List<PromptTemplate> getTemplates(PromptCategory category) {
    return _templates[category] ?? [];
  }

  /// 获取所有模板
  Map<PromptCategory, List<PromptTemplate>> get allTemplates => Map.unmodifiable(_templates);

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 初始化并加载模板
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    await _loadTemplates();
    
    // 如果没有模板，初始化默认模板
    if (_templates.isEmpty || _templates.values.every((list) => list.isEmpty)) {
      await _initializeDefaultTemplates();
    }
    
    _isInitialized = true;
    notifyListeners();
  }

  /// 从 SharedPreferences 加载模板
  Future<void> _loadTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final templatesJson = prefs.getString('prompt_templates_v2');
      
      if (templatesJson != null) {
        final decoded = jsonDecode(templatesJson) as Map<String, dynamic>;
        
        for (final category in PromptCategory.values) {
          final categoryTemplates = decoded[category.id] as List<dynamic>?;
          if (categoryTemplates != null) {
            _templates[category] = categoryTemplates
                .map((json) => PromptTemplate.fromJson(json as Map<String, dynamic>))
                .toList();
          } else {
            _templates[category] = [];
          }
        }
      } else {
        // 如果没有新格式的数据，尝试从旧格式迁移
        await _migrateFromOldFormat();
      }
    } catch (e) {
      print('[PromptStore] 加载模板失败: $e');
      // 初始化空模板
      for (final category in PromptCategory.values) {
        _templates[category] = [];
      }
    }
  }

  /// 从旧格式迁移数据
  Future<void> _migrateFromOldFormat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final oldPromptsJson = prefs.getString('prompts');
      
      if (oldPromptsJson != null) {
        final decoded = jsonDecode(oldPromptsJson) as Map<String, dynamic>;
        
        // 映射旧格式到新格式
        final categoryMap = {
          'story': PromptCategory.script,  // 故事生成 -> 剧本生成
          'script': PromptCategory.script,
          'video': PromptCategory.script,
          'character': PromptCategory.character,  // 角色生成
          'storyboard': PromptCategory.storyboard,  // 分镜设计 -> 分镜生成
          'layout': PromptCategory.storyboard,
          'image': PromptCategory.image,
          'scene': PromptCategory.image,
          'prop': PromptCategory.image,
        };
        
        for (final entry in decoded.entries) {
          final oldCategory = entry.key;
          final templates = entry.value as Map<String, dynamic>?;
          
          if (templates != null) {
            final category = categoryMap[oldCategory] ?? PromptCategory.script;
            final now = DateTime.now();
            
            _templates[category] = templates.entries.map((e) {
              return PromptTemplate(
                id: '${category.id}_${e.key}_${now.millisecondsSinceEpoch}',
                category: category,
                name: e.key,
                content: e.value as String,
                createdAt: now,
              );
            }).toList();
          }
        }
        
        // 保存新格式
        await _saveTemplates();
      }
    } catch (e) {
      print('[PromptStore] 迁移旧数据失败: $e');
    }
  }

  /// 保存模板到 SharedPreferences
  Future<void> _saveTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> data = {};
      
      for (final category in PromptCategory.values) {
        data[category.id] = (_templates[category] ?? [])
            .map((t) => t.toJson())
            .toList();
      }
      
      await prefs.setString('prompt_templates_v2', jsonEncode(data));
    } catch (e) {
      print('[PromptStore] 保存模板失败: $e');
      rethrow;
    }
  }

  /// 初始化默认模板
  Future<void> _initializeDefaultTemplates() async {
    final now = DateTime.now();

    // LLM提示词默认模板（用于故事生成等通用场景）
    _templates[PromptCategory.llm] = [
      PromptTemplate(
        id: 'llm_general_1',
        category: PromptCategory.llm,
        name: '通用',
        content: '请根据以下创意生成一个完整的故事：\n\n{{input}}\n\n请包含：故事背景、主要情节、角色发展、高潮和结局。',
        createdAt: now,
      ),
      PromptTemplate(
        id: 'llm_suspense_1',
        category: PromptCategory.llm,
        name: '悬疑',
        content: '请根据以下线索创作一个悬疑故事：\n\n{{input}}\n\n要求：设置悬念、埋下伏笔、制造反转、最后揭秘真相。',
        createdAt: now,
      ),
      PromptTemplate(
        id: 'llm_romance_1',
        category: PromptCategory.llm,
        name: '言情',
        content: '请根据以下设定创作一个浪漫爱情故事：\n\n{{input}}\n\n要求：细腻的情感描写、甜蜜的互动、感人的情节发展。',
        createdAt: now,
      ),
      PromptTemplate(
        id: 'llm_scifi_1',
        category: PromptCategory.llm,
        name: '科幻',
        content: '请根据以下科幻设定创作故事：\n\n{{input}}\n\n要求：合理的科技设定、宏大的世界观、深刻的主题思考。',
        createdAt: now,
      ),
    ];

    // 剧本生成默认模板
    _templates[PromptCategory.script] = [
      PromptTemplate(
        id: 'script_default_1',
        category: PromptCategory.script,
        name: '标准剧本模板',
        content: '''你是一个专业的动漫剧本作家。请根据故事内容，生成一个完整的剧本，包含：

1. 场景描述（时间、地点、氛围）
2. 角色对话（自然、符合人物性格）
3. 动作提示（角色动作、表情、镜头提示）
4. 转场说明

格式要求：
- 使用标准的剧本格式
- 场景切换清晰
- 对话简洁有力
- 适合动画制作''',
        createdAt: now,
      ),
    ];

    // 角色生成默认模板
    _templates[PromptCategory.character] = [
      PromptTemplate(
        id: 'character_default_1',
        category: PromptCategory.character,
        name: '角色生成模板',
        content: '''你是一个专业的动漫角色设计师。请根据剧本内容，提取并生成所有角色的详细描述。

要求：
1. 识别剧本中的所有主要角色
2. 为每个角色生成详细的描述，包括：
   - 角色名称
   - 外貌特征（发型、服装、体型等）
   - 性格特点
   - 角色定位
3. 生成适合图片生成的提示词，包含角色外观的详细描述
4. 确保角色描述清晰、具体，适合AI图片生成

输出格式：JSON数组，每个元素包含 name（角色名称）和 prompt（角色提示词）字段''',
        createdAt: now,
      ),
    ];

    // 分镜生成默认模板
    _templates[PromptCategory.storyboard] = [
      PromptTemplate(
        id: 'storyboard_default_1',
        category: PromptCategory.storyboard,
        name: '分镜生成模板',
        content: '''你是一个专业的动漫分镜设计师。请根据剧本内容，生成详细的分镜脚本。

要求：
1. 每个镜头包含：镜头类型、景别、角度、运动方式
2. 描述画面构图和视觉元素
3. 标注时长和转场方式
4. 考虑动画制作的可行性

输出格式：JSON数组，每个元素包含 title, description, duration, shotType 等字段''',
        createdAt: now,
      ),
    ];

    // 图片生成默认模板
    _templates[PromptCategory.image] = [
      PromptTemplate(
        id: 'image_default_1',
        category: PromptCategory.image,
        name: '动漫风格图片',
        content: '''生成高质量的动漫风格图片。要求：
- 二次元风格，色彩鲜艳
- 细节丰富，画面精美
- 符合描述的场景和角色
- 适合动画制作''',
        createdAt: now,
      ),
    ];

    // 视频生成默认模板
    _templates[PromptCategory.video] = [
      PromptTemplate(
        id: 'video_default_1',
        category: PromptCategory.video,
        name: '视频生成模板',
        content: '''生成流畅的动漫风格视频。要求：
- 画面连贯，动作自然
- 保持角色一致性
- 场景转换流畅
- 符合分镜设计
- 根据分镜提示词和生成的图片，生成对应的视频''',
        createdAt: now,
      ),
    ];

    // 场景生成默认模板
    _templates[PromptCategory.scene] = [
      PromptTemplate(
        id: 'scene_default_1',
        category: PromptCategory.scene,
        name: '场景生成模板',
        content: '''你是一个专业的场景设计师。请根据剧本内容，提取并生成所有场景的详细描述。

要求：
1. 识别剧本中的所有主要场景
2. 为每个场景生成详细的描述，包括：
   - 场景名称
   - 环境特征（室内/室外、时间、天气等）
   - 视觉元素（建筑、家具、道具等）
   - 氛围和色调
3. 生成适合图片生成的提示词，包含场景的详细视觉描述
4. 确保场景描述清晰、具体，适合AI图片生成

输出格式：JSON数组，每个元素包含 name（场景名称）和 prompt（场景提示词）字段''',
        createdAt: now,
      ),
    ];

    // 物品生成默认模板
    _templates[PromptCategory.prop] = [
      PromptTemplate(
        id: 'prop_default_1',
        category: PromptCategory.prop,
        name: '物品生成模板',
        content: '''你是一个专业的道具设计师。请根据剧本内容，提取并生成所有重要物品的详细描述。

要求：
1. 识别剧本中的所有关键物品和道具
2. 为每个物品生成详细的描述，包括：
   - 物品名称
   - 外观特征（形状、颜色、材质等）
   - 功能和用途
   - 风格特点
3. 生成适合图片生成的提示词，包含物品的详细视觉描述
4. 确保物品描述清晰、具体，适合AI图片生成

输出格式：JSON数组，每个元素包含 name（物品名称）和 prompt（物品提示词）字段''',
        createdAt: now,
      ),
    ];

    // 综合提示词默认模板（同时生成图片和视频提示词）
    _templates[PromptCategory.comprehensive] = [
      PromptTemplate(
        id: 'comprehensive_default_1',
        category: PromptCategory.comprehensive,
        name: '综合分镜提示词',
        content: '''你是一个专业的动漫分镜设计师和提示词专家。请根据以下分镜内容，同时生成图片提示词和视频提示词。

分镜内容：
{{input}}

要求：
1. 图片提示词：
   - 详细描述画面构图、角色姿态、场景细节
   - 包含画面风格、色调、光影效果
   - 适合静态图片生成

2. 视频提示词：
   - 描述动作、运镜、节奏
   - 包含转场、运动轨迹
   - 适合动态视频生成

输出格式（JSON）：
{
  "imagePrompt": "图片提示词内容",
  "videoPrompt": "视频提示词内容"
}''',
        createdAt: now,
      ),
      PromptTemplate(
        id: 'comprehensive_anime_1',
        category: PromptCategory.comprehensive,
        name: '动漫风格综合',
        content: '''作为动漫分镜专家，根据分镜内容生成配套的图片和视频提示词。

分镜内容：
{{input}}

图片提示词要求：
- 二次元动漫风格，高清细腻
- 精准描述角色表情、动作、服装
- 场景氛围、色调、光效

视频提示词要求：
- 流畅自然的动作设计
- 镜头运动和角度变化
- 保持角色一致性

以JSON格式输出：{"imagePrompt": "...", "videoPrompt": "..."}''',
        createdAt: now,
      ),
    ];

    await _saveTemplates();
  }

  /// 添加模板
  Future<void> addTemplate(PromptTemplate template) async {
    final category = template.category;
    if (!_templates.containsKey(category)) {
      _templates[category] = [];
    }
    
    _templates[category]!.add(template);
    await _saveTemplates();
    notifyListeners();
  }

  /// 更新模板
  Future<void> updateTemplate(PromptTemplate template) async {
    final category = template.category;
    final index = _templates[category]?.indexWhere((t) => t.id == template.id);
    
    if (index != null && index >= 0) {
      _templates[category]![index] = template.copyWith(
        updatedAt: DateTime.now(),
      );
      await _saveTemplates();
      notifyListeners();
    }
  }

  /// 删除模板
  Future<void> deleteTemplate(String id, PromptCategory category) async {
    _templates[category]?.removeWhere((t) => t.id == id);
    await _saveTemplates();
    notifyListeners();
  }

  /// 根据 ID 获取模板
  PromptTemplate? getTemplateById(String id, PromptCategory category) {
    try {
      return _templates[category]?.firstWhere(
        (t) => t.id == id,
      );
    } catch (e) {
      return null;
    }
  }
}

/// 全局实例
final promptStore = PromptStore();
