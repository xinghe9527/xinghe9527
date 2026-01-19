# 星河（Xinghe）AI 视频创作软件 - 完整技术文档

> **文档版本**: 2.0  
> **更新日期**: 2026-01-19  
> **目标读者**: AI 大语言模型、开发者、架构师

---

## 📖 目录

1. [项目概述](#1-项目概述)
2. [技术栈](#2-技术栈)
3. [核心架构](#3-核心架构)
4. [API 架构（重点）](#4-api-架构重点)
5. [自动模式详解](#5-自动模式详解)
6. [手动模式详解](#6-手动模式详解)
7. [数据存储架构](#7-数据存储架构)
8. [服务层设计](#8-服务层设计)
9. [状态管理](#9-状态管理)
10. [性能优化](#10-性能优化)
11. [代码规范](#11-代码规范)
12. [已知问题和解决方案](#12-已知问题和解决方案)
13. [未来扩展方向](#13-未来扩展方向)

---

## 1. 项目概述

### 1.1 项目定位

**星河（Xinghe）** 是一款基于 Flutter 开发的 **AI 驱动的视频创作软件**，旨在通过 AI 技术简化视频创作流程，让用户仅需输入创意即可生成完整视频。

### 1.2 核心能力

- ✅ **AI 剧本生成**: 基于 LLM 生成完整剧本
- ✅ **AI 分镜设计**: 自动生成分镜设计和提示词
- ✅ **AI 图片生成**: 批量生成场景图片
- ✅ **AI 视频生成**: 将图片转换为视频
- ✅ **视频合成**: 使用 FFmpeg 合并所有场景视频
- ✅ **多模式工作流**: 自动模式和手动模式
- ✅ **多供应商支持**: 可为 LLM/图片/视频分别配置 API 供应商

### 1.3 应用场景

- **短视频创作**: 快速生成社交媒体短视频
- **故事可视化**: 将文字故事转换为视频
- **教育内容**: 生成教学演示视频
- **营销素材**: 批量生成产品展示视频

---

## 2. 技术栈

### 2.1 核心框架

- **Flutter 3.10.4+**: 跨平台 UI 框架
- **Dart SDK 3.10.4+**: 编程语言

### 2.2 主要依赖

#### UI 和媒体
```yaml
video_player: ^2.8.3          # 视频播放
image_picker: ^1.2.1          # 图片选择
file_picker: ^10.3.8          # 文件选择
```

#### 网络和 API
```yaml
http: ^1.2.1                  # HTTP 请求
dio: ^5.9.0                   # 高级 HTTP 客户端
supabase_flutter: ^2.5.6      # Supabase 集成（文件存储）
```

#### 数据持久化
```yaml
hive: ^2.2.3                  # NoSQL 数据库
hive_flutter: ^1.1.0          # Hive Flutter 集成
shared_preferences: ^2.2.2    # 键值对存储
```

#### 状态管理
```yaml
provider: ^6.1.2              # 状态管理库
```

#### 并发和性能
```yaml
pool: ^1.5.1                  # 并发任务池
synchronized: ^3.1.0+1        # 同步控制
```

#### 工具类
```yaml
path_provider: ^2.1.5         # 路径获取
crypto: ^3.0.5                # 加密
flutter_dotenv: ^5.1.0        # 环境变量
package_info_plus: ^8.0.2     # 应用信息
url_launcher: ^6.3.2          # URL 启动
```

### 2.3 外部工具

- **FFmpeg**: 视频处理（需用户安装）
- **Supabase**: 文件存储和托管

---

## 3. 核心架构

### 3.1 整体架构图

```
┌─────────────────────────────────────────────────────────────┐
│                         应用层 (UI)                          │
├──────────────┬────────────────────────────────┬──────────────┤
│  自动模式 UI  │       手动模式 UI              │   设置 UI     │
│ (AutoMode    │  (Workspace Panels)           │ (Settings)   │
│  Screen)     │                               │              │
└──────────────┴────────────────────────────────┴──────────────┘
       ↓                     ↓                        ↓
┌─────────────────────────────────────────────────────────────┐
│                      状态管理层                              │
├──────────────┬────────────────────────────────┬──────────────┤
│ AutoMode     │     StatefulWidget            │  Config      │
│ Provider     │     (各面板独立状态)           │  Managers    │
└──────────────┴────────────────────────────────┴──────────────┘
       ↓                     ↓                        ↓
┌─────────────────────────────────────────────────────────────┐
│                       服务层 (Services)                      │
├──────────────┬──────────────┬──────────────┬─────────────────┤
│ ApiManager   │ ApiService   │ FFmpegService│ PromptStore    │
│ (多供应商)    │              │              │                │
├──────────────┼──────────────┼──────────────┼─────────────────┤
│ ApiConfig    │ HeavyTask    │ Generation   │ UpdateService  │
│ Manager      │ Runner       │ Queue        │                │
└──────────────┴──────────────┴──────────────┴─────────────────┘
       ↓                     ↓                        ↓
┌─────────────────────────────────────────────────────────────┐
│                      数据存储层                              │
├──────────────┬────────────────────────────────┬──────────────┤
│ Hive Box     │   SharedPreferences           │  Supabase    │
│ (自动模式)    │   (手动模式+配置)              │  (文件存储)   │
└──────────────┴────────────────────────────────┴──────────────┘
       ↓                     ↓                        ↓
┌─────────────────────────────────────────────────────────────┐
│                     外部服务和工具                            │
├──────────────┬────────────────────────────────┬──────────────┤
│ LLM API      │   Image API                   │  Video API   │
│ (Geeknow等)  │   (Geeknow等)                 │  (Geeknow等) │
├──────────────┴────────────────────────────────┴──────────────┤
│                     FFmpeg (视频处理)                        │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 项目文件结构

```
lib/
├── main.dart                          # 应用入口 + 手动模式 UI
├── logic/
│   └── auto_mode_provider.dart        # 自动模式状态管理（单例）
├── models/
│   ├── auto_mode_project.dart         # 自动模式项目模型
│   ├── auto_mode_step.dart            # 工作流步骤枚举
│   ├── scene_model.dart               # 场景模型
│   ├── scene_status.dart              # 场景状态枚举
│   ├── character_model.dart           # 角色模型
│   └── prompt_template.dart           # 提示词模板模型
├── views/
│   ├── auto_mode_screen.dart          # 自动模式 UI
│   └── prompt_config_view.dart        # 提示词配置 UI
├── services/
│   ├── api_manager.dart               # API 管理器（混合供应商）
│   ├── api_config_manager.dart        # API 配置管理
│   ├── api_service.dart               # API 调用服务
│   ├── ffmpeg_service.dart            # FFmpeg 视频处理
│   ├── heavy_task_runner.dart         # 并发任务管理
│   ├── generation_queue.dart          # 生成队列管理
│   ├── prompt_store.dart              # 提示词模板存储
│   ├── update_service.dart            # 自动更新服务
│   ├── sora_api_service.dart          # 旧 API 服务（已废弃）
│   ├── providers/
│   │   ├── base_provider.dart         # API 供应商基类
│   │   └── geeknow_provider.dart      # Geeknow 供应商实现
│   └── index.dart                     # 服务导出
├── widgets/
│   ├── provider_selector.dart         # 供应商选择器组件
│   └── README_PROVIDER_SELECTOR.md    # 组件文档
└── save_settings_panel.dart           # 保存设置面板
```

---

## 4. API 架构（重点）

### 4.1 架构演进

#### **第一代：单一服务架构**（已废弃）
```dart
SoraApiService
  ↓
所有 API 调用（LLM、图片、视频）
```

#### **第二代：插件化架构**（当前版本）
```dart
┌────────────────────────────────────────────────────┐
│              ApiManager (单例)                     │
├────────────────────────────────────────────────────┤
│  _llmProvider      → BaseApiProvider              │
│  _imageProvider    → BaseApiProvider              │
│  _videoProvider    → BaseApiProvider              │
├────────────────────────────────────────────────────┤
│  _providersCache   → Map<String, BaseApiProvider> │
└────────────────────────────────────────────────────┘
         ↓                 ↓                ↓
┌────────────────┐ ┌─────────────┐ ┌──────────────┐
│ GeeknowProvider│ │OpenAIProvider│ │CustomProvider│
│ (继承Base)      │ │ (未来)       │ │ (未来)        │
└────────────────┘ └─────────────┘ └──────────────┘
```

### 4.2 核心类详解

#### **BaseApiProvider（抽象基类）**

```dart
// 位置: lib/services/providers/base_provider.dart

/// API 供应商基类 - 定义统一接口
abstract class BaseApiProvider {
  final String baseUrl;
  final String apiKey;
  final String providerName;
  
  BaseApiProvider({
    required this.baseUrl,
    required this.apiKey,
    required this.providerName,
  });
  
  // 抽象方法（子类必须实现）
  
  /// LLM 聊天补全
  Future<String> chatCompletion({
    required String model,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.7,
    int maxTokens = 2048,
  });
  
  /// 图片生成
  Future<String> generateImage({
    required String prompt,
    required String model,
    String? size,
    String? negativePrompt,
  });
  
  /// 创建视频任务
  Future<String> createVideo({
    required String prompt,
    required String model,
    String? imageUrl,
  });
  
  /// 查询视频任务状态
  Future<VideoTaskStatus> getVideoTask({
    required String taskId,
  });
  
  /// 上传视频到 OSS
  Future<String> uploadVideoToOss(File videoFile);
  
  /// 创建角色
  Future<Map<String, dynamic>> createCharacter(String videoUrl);
}
```

#### **ApiManager（单例管理器）**

```dart
// 位置: lib/services/api_manager.dart

/// API 管理器 - 支持混合供应商模式
class ApiManager {
  static final ApiManager _instance = ApiManager._internal();
  factory ApiManager() => _instance;
  
  // 三个独立的 Provider
  BaseApiProvider? _llmProvider;
  BaseApiProvider? _imageProvider;
  BaseApiProvider? _videoProvider;
  
  // Provider 缓存（避免重复创建）
  final Map<String, BaseApiProvider> _providersCache = {};
  
  /// 设置 LLM 供应商
  void setLlmProvider(String providerName, {
    required String baseUrl,
    required String apiKey,
  }) {
    _llmProvider = _getOrCreateProvider(
      providerName: providerName,
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
  }
  
  /// 设置图片供应商
  void setImageProvider(String providerName, {...});
  
  /// 设置视频供应商
  void setVideoProvider(String providerName, {...});
  
  /// LLM 聊天补全（转发到 _llmProvider）
  Future<String> chatCompletion({...}) async {
    if (_llmProvider == null) {
      throw Exception('未设置 LLM 服务供应商');
    }
    return await _llmProvider!.chatCompletion(...);
  }
  
  // 其他方法类似...
}
```

### 4.3 配置管理

#### **ApiConfigManager**

```dart
// 位置: lib/services/api_config_manager.dart

/// API 配置管理器 - 持久化 API 配置
class ApiConfigManager extends ChangeNotifier {
  // 三个独立的供应商选择
  String _selectedLlmProviderId = 'geeknow';
  String _selectedImageProviderId = 'geeknow';
  String _selectedVideoProviderId = 'geeknow';
  
  // LLM 配置
  String _llmApiKey = '';
  String _llmBaseUrl = '';
  String _llmModel = '';
  
  // 图片配置
  String _imageApiKey = '';
  String _imageBaseUrl = '';
  String _imageModel = '';
  
  // 视频配置
  String _videoApiKey = '';
  String _videoBaseUrl = '';
  String _videoModel = '';
  
  /// 加载配置（从 SharedPreferences）
  Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 加载供应商选择
    _selectedLlmProviderId = prefs.getString('selected_llm_provider') ?? 'geeknow';
    _selectedImageProviderId = prefs.getString('selected_image_provider') ?? 'geeknow';
    _selectedVideoProviderId = prefs.getString('selected_video_provider') ?? 'geeknow';
    
    // 加载 API Key 和 Base URL
    _llmApiKey = prefs.getString('llm_api_key') ?? '';
    _llmBaseUrl = prefs.getString('llm_base_url') ?? '';
    // ...
  }
  
  /// 保存配置
  Future<void> saveConfig() async {...}
  
  /// 批量更新配置
  void updateConfigBatch({
    String? selectedLlmProviderId,
    String? selectedImageProviderId,
    String? selectedVideoProviderId,
    String? llmApiKey,
    String? llmBaseUrl,
    // ...
  }) {...}
}
```

### 4.4 使用示例

#### **初始化（应用启动时）**

```dart
// 在 main.dart 中
void _initializeApiManager() {
  // 读取配置
  final llmProviderId = apiConfigManager.selectedLlmProviderId;
  final imageProviderId = apiConfigManager.selectedImageProviderId;
  final videoProviderId = apiConfigManager.selectedVideoProviderId;
  
  // 分别初始化三个 Provider
  ApiManager().setLlmProvider(
    llmProviderId,
    baseUrl: apiConfigManager.llmBaseUrl,
    apiKey: apiConfigManager.llmApiKey,
  );
  
  ApiManager().setImageProvider(
    imageProviderId,
    baseUrl: apiConfigManager.imageBaseUrl,
    apiKey: apiConfigManager.imageApiKey,
  );
  
  ApiManager().setVideoProvider(
    videoProviderId,
    baseUrl: apiConfigManager.videoBaseUrl,
    apiKey: apiConfigManager.videoApiKey,
  );
}
```

#### **调用 API**

```dart
// 在任何地方调用
final result = await ApiManager().chatCompletion(
  model: 'gpt-3.5-turbo',
  messages: [
    {'role': 'user', 'content': 'Hello'},
  ],
);
```

### 4.5 扩展新供应商

要添加新的 API 供应商（如 OpenAI），只需：

1. **创建 Provider 类**

```dart
// lib/services/providers/openai_provider.dart
class OpenAIProvider extends BaseApiProvider {
  OpenAIProvider({required super.baseUrl, required super.apiKey})
      : super(providerName: 'openai');
  
  @override
  Future<String> chatCompletion({...}) async {
    // OpenAI 特定实现
  }
  
  // 实现其他抽象方法...
}
```

2. **更新 ApiManager 工厂方法**

```dart
// 在 _getOrCreateProvider 中添加 case
BaseApiProvider _getOrCreateProvider({...}) {
  switch (providerName) {
    case 'geeknow':
      return GeeknowProvider(...);
    case 'openai':  // 新增
      return OpenAIProvider(...);
    default:
      throw Exception('不支持的供应商: $providerName');
  }
}
```

3. **更新配置管理**

```dart
// 在 ApiConfigManager 中添加
List<String> getSupportedProviders() {
  return ['geeknow', 'openai'];  // 新增
}

String getProviderDisplayName(String providerId) {
  switch (providerId) {
    case 'openai':
      return 'OpenAI';  // 新增
    // ...
  }
}
```

---

## 5. 自动模式详解

### 5.1 工作流程

```
┌──────────────────────────────────────────────────────────────┐
│                        用户输入创意                           │
│                  "一个关于勇敢小猫的故事"                      │
└───────────────────────────┬──────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│  步骤 1: 剧本生成 (AutoModeStep.script)                      │
│  ────────────────────────────────────────                   │
│  • 调用 LLM API                                             │
│  • 使用提示词模板                                            │
│  • 生成完整剧本                                              │
│  • 用户确认或修改                                            │
└───────────────────────────┬──────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│  步骤 2: 分镜设计 (AutoModeStep.layout)                      │
│  ────────────────────────────────────────                   │
│  • 基于剧本调用 LLM                                          │
│  • 生成分镜设计                                              │
│  • 为每个场景生成图片提示词                                   │
│  • 解析为 SceneModel 列表                                    │
└───────────────────────────┬──────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│  步骤 3: 图片生成 (AutoModeStep.image)                       │
│  ────────────────────────────────────────                   │
│  • 并发生成所有场景图片                                       │
│  • 使用 Pool 限制并发数（最多 2 个）                          │
│  • 每个场景独立任务，失败不影响其他                            │
│  • 图片下载到本地                                            │
│  • 实时更新进度                                              │
└───────────────────────────┬──────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│  步骤 4: 视频生成 (AutoModeStep.video)                       │
│  ────────────────────────────────────────────                │
│  • 批量提交视频生成任务                                       │
│  • 轮询任务状态（带退避策略）                                 │
│  • 视频下载到本地                                            │
│  • 实时更新进度                                              │
└───────────────────────────┬──────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│  步骤 5: 最终合并 (AutoModeStep.finalize)                    │
│  ────────────────────────────────────────                   │
│  • 使用 FFmpeg 合并所有视频                                  │
│  • 生成 filelist.txt                                        │
│  • 执行 concat demuxer                                      │
│  • 上传最终视频到 Supabase                                   │
│  • 保存视频 URL                                             │
└───────────────────────────┬──────────────────────────────────┘
                            ↓
                         ✅ 完成
```

### 5.2 数据模型

#### **AutoModeProject**

```dart
// lib/models/auto_mode_project.dart

class AutoModeProject {
  final String id;                    // 项目 ID（时间戳）
  final String title;                 // 项目标题
  AutoModeStep currentStep;           // 当前步骤
  String currentScript;               // 生成的剧本
  String currentLayout;               // 生成的分镜设计
  List<SceneModel> scenes;            // 场景列表
  bool isProcessing;                  // 是否正在处理
  String? errorMessage;               // 错误消息
  String? finalVideoUrl;              // 最终视频 URL
  DateTime? lastModified;             // 最后修改时间
  bool hasUnsavedChanges;            // 是否有未保存的更改
  bool isSaving;                      // 是否正在保存
  String? generationStatus;           // 生成状态
  
  // 序列化
  Map<String, dynamic> toJson() {...}
  factory AutoModeProject.fromJson(Map<String, dynamic> json) {...}
}
```

#### **SceneModel**

```dart
// lib/models/scene_model.dart

class SceneModel {
  final int index;                     // 场景索引
  String script;                       // 场景剧本
  String imagePrompt;                  // 图片生成提示词
  String? imageUrl;                    // 图片 URL
  String? videoUrl;                    // 视频 URL
  String? localImagePath;              // 本地图片路径
  String? localVideoPath;              // 本地视频路径
  SceneStatus status;                  // 场景状态
  String? errorMessage;                // 错误消息
  double imageGenerationProgress;      // 图片生成进度
  double videoGenerationProgress;      // 视频生成进度
  
  Map<String, dynamic> toJson() {...}
  factory SceneModel.fromJson(Map<String, dynamic> json) {...}
}
```

#### **AutoModeStep（枚举）**

```dart
// lib/models/auto_mode_step.dart

enum AutoModeStep {
  script,    // 剧本生成
  layout,    // 分镜设计
  image,     // 图片生成
  video,     // 视频合成
  finalize,  // 最终合并
}
```

#### **SceneStatus（枚举）**

```dart
// lib/models/scene_status.dart

enum SceneStatus {
  idle,        // 空闲
  queueing,    // 队列中
  processing,  // 处理中
  success,     // 成功
  error,       // 错误
}
```

### 5.3 AutoModeProvider（核心状态管理）

```dart
// lib/logic/auto_mode_provider.dart

/// 自动模式状态管理 Provider（单例）
class AutoModeProvider extends ChangeNotifier {
  static const String _boxName = 'xinghe_auto_mode_v2';
  static Box? _projectsBox;
  
  // 单例实例
  static AutoModeProvider? _instance;
  factory AutoModeProvider() {
    _instance ??= AutoModeProvider._internal();
    return _instance!;
  }
  
  // 项目映射：projectId -> AutoModeProject
  final Map<String, AutoModeProject> _projects = {};
  
  // 当前活动的项目 ID
  String? _currentProjectId;
  
  // 自动保存 Timer
  final Map<String, Timer> _saveTimers = {};
  
  // 并发控制（图片生成限制为 2 个）
  final _imagePool = Pool(2);
  
  // 生命周期安全标志
  bool _isDisposed = false;
  
  /// 初始化（加载所有项目）
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // 打开 Hive Box
      _projectsBox = await Hive.openBox(_boxName);
      
      // 加载所有项目
      final keys = _projectsBox!.keys.toList();
      for (var key in keys) {
        if (key.toString().startsWith('project_')) {
          final data = _projectsBox!.get(key);
          if (data is Map) {
            final project = AutoModeProject.fromJson(
              Map<String, dynamic>.from(data)
            );
            _projects[project.id] = project;
          }
        }
      }
      
      _isInitialized = true;
      notifyListeners();
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 初始化失败: $e');
      print('📍 [Stack Trace]: $stackTrace');
    }
  }
  
  /// 创建新项目（仅由 UI 调用）
  Future<String> createNewProject(String title) async {
    final projectId = DateTime.now().millisecondsSinceEpoch.toString();
    final project = AutoModeProject(
      id: projectId,
      title: title,
      currentStep: AutoModeStep.script,
      currentScript: '',
      currentLayout: '',
      scenes: [],
      isProcessing: false,
      lastModified: DateTime.now(),
      hasUnsavedChanges: false,
      isSaving: false,
    );
    
    _projects[projectId] = project;
    _currentProjectId = projectId;
    
    // 立即保存
    await _saveProjectToBox(projectId);
    
    notifyListeners();
    return projectId;
  }
  
  /// 处理用户输入（剧本/分镜）
  Future<void> processInput(String projectId, String input) async {
    final project = _projects[projectId];
    if (project == null) return;
    
    project.isProcessing = true;
    notifyListeners();
    
    try {
      if (project.currentStep == AutoModeStep.script) {
        await _generateScript(projectId, input);
      } else if (project.currentStep == AutoModeStep.layout) {
        await _generateLayout(projectId, input);
      }
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 处理输入失败: $e');
      print('📍 [Stack Trace]: $stackTrace');
      project.errorMessage = e.toString();
    } finally {
      project.isProcessing = false;
      notifyListeners();
    }
  }
  
  /// 生成剧本
  Future<void> _generateScript(String projectId, String input) async {
    print('🎬 [Script] 开始生成剧本...');
    
    final project = _projects[projectId]!;
    
    // 调用 LLM API
    final apiService = apiConfigManager.createApiService();
    final prompt = promptStore.getScriptPrompt(input);
    
    final result = await apiService.chatCompletion(
      model: apiConfigManager.llmModel,
      messages: [
        {'role': 'user', 'content': prompt},
      ],
    );
    
    print('🎬 [Script] 收到 API 结果，长度: ${result.length}');
    
    // 保存剧本
    project.currentScript = result;
    
    print('🎬 [Script] 状态已更新，剧本内容: ${result.substring(0, 20)}...');
    
    // 保存并通知
    await _saveProjectToBox(projectId);
    print('📢 [UI Update] 通知 UI 更新，当前步骤: ${project.currentStep}, 处理中: ${project.isProcessing}');
    notifyListeners();
  }
  
  /// 生成分镜
  Future<void> _generateLayout(String projectId, String input) async {
    // 类似 _generateScript...
  }
  
  /// 批量生成图片（并发控制）
  Future<void> _generateAllImages(String projectId) async {
    final project = _projects[projectId]!;
    
    // 使用 Pool 限制并发数
    final tasks = project.scenes.map((scene) {
      return _imagePool.withResource(() => _generateImage(projectId, scene));
    }).toList();
    
    await Future.wait(tasks, eagerError: false);
  }
  
  /// 生成单个场景图片
  Future<void> _generateImage(String projectId, SceneModel scene) async {
    // 调用图片生成 API
    // 下载图片到本地
    // 更新场景状态
    // 保存项目
  }
  
  /// 批量生成视频
  Future<void> _generateAllVideos(String projectId) async {
    // 提交视频任务
    // 轮询任务状态
    // 下载视频
  }
  
  /// 最终合并视频
  Future<void> _finalizeVideo(String projectId) async {
    // 使用 FFmpeg 合并所有视频
    // 上传到 Supabase
    // 保存视频 URL
  }
  
  /// 保存项目到 Hive Box
  Future<void> _saveProjectToBox(String projectId) async {
    final project = _projects[projectId];
    if (project == null) return;
    
    final key = 'project_$projectId';
    await _projectsBox!.put(key, project.toJson());
    await _projectsBox!.flush();  // 强制写入磁盘
    
    print('💾 [Storage] 项目已保存: $key');
  }
  
  /// 删除项目
  Future<void> deleteProject(String projectId) async {
    _projects.remove(projectId);
    final key = 'project_$projectId';
    await _projectsBox!.delete(key);
    await _projectsBox!.flush();
    
    if (_currentProjectId == projectId) {
      _currentProjectId = null;
    }
    
    notifyListeners();
  }
}
```

### 5.4 UI 界面（AutoModeScreen）

```dart
// lib/views/auto_mode_screen.dart

class AutoModeScreen extends StatefulWidget {
  final String projectId;
  
  const AutoModeScreen({required this.projectId});
  
  @override
  _AutoModeScreenState createState() => _AutoModeScreenState();
}

class _AutoModeScreenState extends State<AutoModeScreen> {
  late AutoModeProvider _provider;
  
  @override
  void initState() {
    super.initState();
    _provider = AutoModeProvider();
  }
  
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _provider,
      builder: (context, _) {
        final project = _provider.getProjectById(widget.projectId);
        
        return Scaffold(
          body: Column(
            children: [
              _buildTopBar(project),        // 顶部栏
              _buildStepIndicator(project), // 步骤指示器
              Expanded(
                child: _buildContentArea(project), // 内容区域
              ),
              if (project.currentStep == AutoModeStep.script ||
                  project.currentStep == AutoModeStep.layout)
                _buildInputArea(project),   // 输入区域
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildContentArea(AutoModeProject project) {
    switch (project.currentStep) {
      case AutoModeStep.script:
      case AutoModeStep.layout:
        return _buildChatArea(project);
      case AutoModeStep.image:
        return _buildImageGenerationArea(project);
      case AutoModeStep.video:
        return _buildVideoGenerationArea(project);
      case AutoModeStep.finalize:
        return _buildFinalizeArea(project);
    }
  }
}
```

---

## 6. 手动模式详解

### 6.1 工作流程

```
用户进入 WorkspaceShell
    ↓
选择功能面板（导航栏）
    ├─ 📖 故事生成
    ├─ 📝 剧本生成
    ├─ 🎬 分镜生成
    ├─ 👤 角色生成
    ├─ 🏞️ 场景生成
    └─ 🎨 物品生成
    ↓
在面板中独立操作
    - 输入提示词
    - 选择模板
    - 生成内容
    - 编辑和保存
```

### 6.2 功能面板详解

#### **1. 故事生成面板**

```dart
class StoryGenerationPanel extends StatefulWidget {
  // 功能：
  // - 输入故事创意
  // - 选择提示词模板（科幻/爱情/悬疑等）
  // - 生成完整故事
  // - 显示结果
  
  // 数据存储：
  // - story_input: 输入内容
  // - story_output: 生成结果
  // - story_prompt_template: 选中的模板
}
```

#### **2. 剧本生成面板**

```dart
class ScriptGenerationPanel extends StatefulWidget {
  // 功能：
  // - 输入剧本需求或从故事导入
  // - 选择剧本风格模板
  // - 生成剧本
  // - 显示结果
  
  // 数据存储：
  // - script_input: 输入内容
  // - script_output: 生成结果
  // - script_prompt_template: 选中的模板
}
```

#### **3. 分镜生成面板**

```dart
class StoryboardGenerationPanel extends StatefulWidget {
  // 功能：
  // - 输入剧本或从剧本面板导入
  // - 选择图片/视频提示词风格
  // - 生成分镜列表
  // - 添加/删除/编辑分镜
  
  // 数据结构：
  // List<Map<String, dynamic>> storyboards = [
  //   {
  //     'scene': '场景1',
  //     'script': '剧本内容',
  //     'imagePrompt': '图片提示词',
  //     'videoPrompt': '视频提示词',
  //   },
  // ];
}
```

#### **4. 角色生成面板**

```dart
class CharacterGenerationPanel extends StatefulWidget {
  // 功能：
  // - 输入角色描述
  // - 根据剧本自动提取角色
  // - 上传参考图片（图生图）
  // - 生成角色图片
  // - 创建数字分身（Character）
  
  // 特殊功能：
  // - 参考风格功能
  // - 视频上传创建角色
  // - Supabase 存储
}
```

#### **5. 场景生成面板**

```dart
class SceneGenerationPanel extends StatefulWidget {
  // 功能：
  // - 输入场景描述
  // - 选择场景风格模板
  // - 生成场景图片
  // - 管理场景库
}
```

#### **6. 物品生成面板**

```dart
class PropGenerationPanel extends StatefulWidget {
  // 功能：
  // - 输入物品描述
  // - 选择物品风格模板
  // - 生成物品图片
  // - 管理物品库
}
```

### 6.3 WorkspaceShell（主界面）

```dart
// lib/main.dart

class WorkspaceShell extends StatefulWidget {
  @override
  _WorkspaceShellState createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  int _selectedIndex = 0;
  
  // 面板列表
  final List<Widget> _panels = [
    StoryGenerationPanel(),
    ScriptGenerationPanel(),
    StoryboardGenerationPanel(),
    CharacterGenerationPanel(),
    SceneGenerationPanel(),
    PropGenerationPanel(),
  ];
  
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    
    return Scaffold(
      body: Row(
        children: [
          // 左侧导航栏（桌面）
          if (!isMobile) _buildNavigationRail(),
          
          // 主内容区
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: Duration(milliseconds: 300),
                    child: _panels[_selectedIndex],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      
      // 底部导航栏（移动端）
      bottomNavigationBar: isMobile ? _buildBottomNavigationBar() : null,
    );
  }
  
  Widget _buildNavigationRail() {
    return NavigationRail(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) {
        setState(() => _selectedIndex = index);
      },
      destinations: [
        NavigationRailDestination(
          icon: Icon(Icons.book_outlined),
          selectedIcon: Icon(Icons.book),
          label: Text('故事生成'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.description_outlined),
          selectedIcon: Icon(Icons.description),
          label: Text('剧本生成'),
        ),
        // ... 其他导航项
      ],
    );
  }
}
```

---

## 7. 数据存储架构

### 7.1 存储方案对比

| 模式 | 存储方式 | 存储内容 | 特点 |
|------|---------|---------|------|
| **自动模式** | Hive Box (`xinghe_auto_mode_v2`) | 完整项目数据（剧本、分镜、场景、URL） | ✅ 快速读写<br>✅ 支持复杂对象<br>✅ 多项目隔离 |
| **手动模式** | SharedPreferences | 面板输入/输出、配置 | ✅ 简单键值对<br>✅ 跨平台兼容 |
| **API 配置** | SharedPreferences | API Key、Base URL、模型选择 | ✅ 持久化配置 |
| **文件存储** | Supabase | 图片、视频、角色文件 | ✅ 云端存储<br>✅ CDN 加速 |

### 7.2 自动模式存储详解

#### **Hive Box 结构**

```
Hive Box: xinghe_auto_mode_v2
├── project_1768368504491
│   └── {
│         "id": "1768368504491",
│         "title": "勇敢的小猫",
│         "currentStep": "script",
│         "currentScript": "...",
│         "currentLayout": "...",
│         "scenes": [
│           {
│             "index": 0,
│             "script": "...",
│             "imagePrompt": "...",
│             "imageUrl": "https://...",
│             "videoUrl": "https://...",
│             "status": "success",
│             ...
│           }
│         ],
│         "finalVideoUrl": "https://...",
│         ...
│       }
├── project_1768368512345
│   └── { ... }
└── ...
```

#### **关键操作**

```dart
// 保存项目
Future<void> _saveProjectToBox(String projectId) async {
  final project = _projects[projectId];
  final key = 'project_$projectId';
  await _projectsBox!.put(key, project.toJson());
  await _projectsBox!.flush();  // 强制写入磁盘（防止数据丢失）
}

// 加载项目
Future<void> _loadAllProjects() async {
  final keys = _projectsBox!.keys.toList();
  for (var key in keys) {
    if (key.toString().startsWith('project_')) {
      final data = _projectsBox!.get(key);
      final project = AutoModeProject.fromJson(
        Map<String, dynamic>.from(data)
      );
      _projects[project.id] = project;
    }
  }
}

// 删除项目
Future<void> deleteProject(String projectId) async {
  _projects.remove(projectId);
  await _projectsBox!.delete('project_$projectId');
  await _projectsBox!.flush();
}
```

### 7.3 手动模式存储详解

#### **SharedPreferences 键值对**

```
SharedPreferences
├── story_input: "用户输入的故事创意"
├── story_output: "生成的故事内容"
├── story_prompt_template: "selected_template_id"
├── script_input: "..."
├── script_output: "..."
├── storyboards: "[{...}, {...}]" (JSON 数组)
├── workspace_characters: "[{...}]" (角色列表)
├── character_reference_style_image: "/path/to/image"
├── character_reference_style_prompt: "..."
└── ...
```

#### **关键操作**

```dart
// 保存数据
Future<void> _saveStory() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('story_input', _inputController.text);
  await prefs.setString('story_output', _generatedStory);
}

// 加载数据
Future<void> _loadStory() async {
  final prefs = await SharedPreferences.getInstance();
  _inputController.text = prefs.getString('story_input') ?? '';
  _generatedStory = prefs.getString('story_output') ?? '';
  setState(() {});
}

// 保存列表数据
Future<void> _saveStoryboards() async {
  final prefs = await SharedPreferences.getInstance();
  final json = jsonEncode(_storyboards);
  await prefs.setString('storyboards', json);
}

// 加载列表数据
Future<void> _loadStoryboards() async {
  final prefs = await SharedPreferences.getInstance();
  final json = prefs.getString('storyboards');
  if (json != null) {
    _storyboards = List<Map<String, dynamic>>.from(
      jsonDecode(json)
    );
  }
}
```

### 7.4 API 配置存储

```
SharedPreferences (API 配置)
├── selected_llm_provider: "geeknow"
├── selected_image_provider: "geeknow"
├── selected_video_provider: "geeknow"
├── llm_api_key: "..."
├── llm_base_url: "https://..."
├── llm_model: "gpt-3.5-turbo"
├── image_api_key: "..."
├── image_base_url: "https://..."
├── image_model: "..."
├── video_api_key: "..."
├── video_base_url: "https://..."
└── video_model: "..."
```

### 7.5 Supabase 文件存储

```
Supabase Storage
├── Buckets
│   ├── videos/           # 视频文件
│   │   ├── user-upload-xxx.mp4
│   │   └── final-video-xxx.mp4
│   ├── characters/       # 角色文件
│   │   └── character-xxx.mp4
│   └── images/           # 图片文件（可选）
│       └── scene-xxx.png
```

---

## 8. 服务层设计

### 8.1 服务层架构

```
Services 层
├── API 服务
│   ├── ApiManager (混合供应商管理)
│   ├── ApiService (统一 API 接口)
│   ├── ApiConfigManager (配置管理)
│   └── Providers (供应商实现)
│       ├── BaseApiProvider (基类)
│       ├── GeeknowProvider (Geeknow 实现)
│       └── [未来] OpenAIProvider, StabilityAIProvider...
├── 任务管理
│   ├── HeavyTaskRunner (重任务执行)
│   ├── GenerationQueue (生成队列)
│   └── FFmpegService (视频处理)
├── 数据服务
│   └── PromptStore (提示词模板管理)
└── 工具服务
    └── UpdateService (自动更新)
```

### 8.2 HeavyTaskRunner（并发任务管理）

```dart
// lib/services/heavy_task_runner.dart

/// 重任务执行器 - 在 Isolate 中执行重操作
class HeavyTaskRunner {
  /// 在 Isolate 中解析 JSON（避免阻塞 UI）
  static Future<dynamic> parseJson(String jsonString) async {
    return await compute(_parseJsonIsolate, jsonString);
  }
  
  static dynamic _parseJsonIsolate(String jsonString) {
    return jsonDecode(jsonString);
  }
  
  /// 在 Isolate 中解码 Base64
  static Future<Uint8List> decodeBase64(String base64String) async {
    return await compute(_decodeBase64Isolate, base64String);
  }
  
  static Uint8List _decodeBase64Isolate(String base64String) {
    return base64Decode(base64String);
  }
  
  /// 在 Isolate 中写入文件
  static Future<void> writeFile(String path, Uint8List bytes) async {
    await compute(_writeFileIsolate, {'path': path, 'bytes': bytes});
  }
  
  static void _writeFileIsolate(Map<String, dynamic> params) {
    final file = File(params['path']);
    file.writeAsBytesSync(params['bytes']);
  }
  
  /// 清理图片缓存
  static void clearImageCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}
```

### 8.3 PromptStore（提示词模板管理）

```dart
// lib/services/prompt_store.dart

/// 提示词模板管理器
class PromptStore {
  static final PromptStore _instance = PromptStore._internal();
  factory PromptStore() => _instance;
  
  final List<PromptTemplate> _templates = [];
  
  /// 初始化（加载内置模板）
  Future<void> initialize() async {
    _templates.addAll([
      PromptTemplate(
        id: 'story_scifi',
        category: 'story',
        name: '科幻故事',
        content: '请根据以下创意生成一个科幻故事...',
      ),
      PromptTemplate(
        id: 'script_drama',
        category: 'script',
        name: '剧情片剧本',
        content: '请将以下故事改编为剧情片剧本...',
      ),
      // ... 更多模板
    ]);
  }
  
  /// 获取分类模板
  List<PromptTemplate> getTemplatesByCategory(String category) {
    return _templates.where((t) => t.category == category).toList();
  }
  
  /// 获取剧本生成提示词
  String getScriptPrompt(String userInput) {
    return '''
你是一个专业的编剧。请根据以下创意生成一个完整的剧本。

创意：$userInput

要求：
1. 包含开头、发展、高潮、结尾
2. 角色性格鲜明
3. 对话自然
4. 场景描写详细
''';
  }
  
  /// 获取分镜生成提示词
  String getLayoutPrompt(String script) {
    return '''
你是一个专业的分镜设计师。请根据以下剧本生成分镜设计。

剧本：$script

要求：
1. 将剧本分为 3-6 个场景
2. 为每个场景生成图片提示词（用于 AI 图片生成）
3. 严格按照以下 JSON 格式输出：

{
  "scenes": [
    {
      "index": 0,
      "script": "场景剧本内容",
      "imagePrompt": "英文图片提示词，描述场景的视觉元素"
    },
    ...
  ]
}

注意：只输出 JSON，不要有其他内容。
''';
  }
}
```

### 8.4 FFmpegService（视频处理）

```dart
// lib/services/ffmpeg_service.dart

/// FFmpeg 视频处理服务
class FFmpegService {
  /// 合并多个视频
  /// 
  /// [videoPaths] 视频文件路径列表
  /// [outputPath] 输出文件路径
  /// 返回是否成功
  static Future<bool> concatVideos(
    List<String> videoPaths,
    String outputPath,
  ) async {
    try {
      // 创建临时文件列表
      final tempDir = await getTemporaryDirectory();
      final fileListPath = '${tempDir.path}/filelist.txt';
      
      // 写入文件列表
      final fileListContent = videoPaths
          .map((path) => "file '$path'")
          .join('\n');
      await File(fileListPath).writeAsString(fileListContent);
      
      // 执行 FFmpeg 命令
      final result = await Process.run('ffmpeg', [
        '-f', 'concat',
        '-safe', '0',
        '-i', fileListPath,
        '-c', 'copy',
        outputPath,
      ]);
      
      if (result.exitCode != 0) {
        print('❌ FFmpeg 错误: ${result.stderr}');
        return false;
      }
      
      print('✅ 视频合并成功: $outputPath');
      return true;
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] FFmpeg 合并失败: $e');
      print('📍 [Stack Trace]: $stackTrace');
      return false;
    }
  }
  
  /// 转换视频格式
  static Future<bool> convertVideo(
    String inputPath,
    String outputPath,
    String format,
  ) async {
    // 实现视频格式转换
  }
}
```

---

## 9. 状态管理

### 9.1 状态管理策略

| 场景 | 方案 | 原因 |
|------|------|------|
| **自动模式** | `ChangeNotifier` (AutoModeProvider) | ✅ 复杂状态<br>✅ 多组件共享<br>✅ 单例模式 |
| **手动模式** | `StatefulWidget` 的 `setState` | ✅ 简单状态<br>✅ 局部刷新<br>✅ 面板独立 |
| **API 配置** | `ChangeNotifier` (ApiConfigManager) | ✅ 全局配置<br>✅ 持久化 |
| **主题** | `ChangeNotifier` (ThemeManager) | ✅ 全局主题 |

### 9.2 AutoModeProvider 状态管理详解

```dart
// 使用示例：在 UI 中监听状态变化

class AutoModeScreen extends StatefulWidget {
  @override
  _AutoModeScreenState createState() => _AutoModeScreenState();
}

class _AutoModeScreenState extends State<AutoModeScreen> {
  late AutoModeProvider _provider;
  
  @override
  void initState() {
    super.initState();
    _provider = AutoModeProvider();
    _provider.addListener(_onProviderUpdate);
  }
  
  @override
  void dispose() {
    _provider.removeListener(_onProviderUpdate);
    super.dispose();
  }
  
  void _onProviderUpdate() {
    // 状态更新时调用
    if (mounted) {
      setState(() {});
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // 使用 _provider 的数据构建 UI
  }
}

// 或使用 ListenableBuilder
Widget build(BuildContext context) {
  return ListenableBuilder(
    listenable: AutoModeProvider(),
    builder: (context, _) {
      final provider = AutoModeProvider();
      return Text(provider.currentScript);
    },
  );
}
```

---

## 10. 性能优化

### 10.1 自动模式性能优化

#### **1. 并发控制**

```dart
// 使用 Pool 限制并发数（避免 UI 冻结）
final _imagePool = Pool(2);  // 最多 2 个并发图片生成任务

Future<void> _generateAllImages(String projectId) async {
  final project = _projects[projectId]!;
  
  final tasks = project.scenes.map((scene) {
    return _imagePool.withResource(() => _generateImage(projectId, scene));
  }).toList();
  
  await Future.wait(tasks, eagerError: false);
}
```

#### **2. Isolate 处理重操作**

```dart
// 在 Isolate 中解析 JSON（避免阻塞 UI）
final parsed = await HeavyTaskRunner.parseJson(response.body);

// 在 Isolate 中写入文件
await HeavyTaskRunner.writeFile(filePath, bytes);
```

#### **3. 图片缓存管理**

```dart
// 定期清理图片缓存（避免内存溢出）
HeavyTaskRunner.clearImageCache();
```

#### **4. 防抖保存**

```dart
// 延迟保存（避免频繁磁盘写入）
void _scheduleSave(String projectId) {
  _saveTimers[projectId]?.cancel();
  _saveTimers[projectId] = Timer(Duration(milliseconds: 500), () {
    _saveProjectToBox(projectId);
  });
}
```

### 10.2 手动模式性能优化

#### **1. 面板懒加载**

```dart
// 只渲染当前选中的面板
AnimatedSwitcher(
  duration: Duration(milliseconds: 300),
  child: _panels[_selectedIndex],  // 只构建一个面板
)
```

#### **2. 响应式布局**

```dart
// 根据屏幕大小调整布局
final isMobile = MediaQuery.of(context).size.width < 800;

if (isMobile) {
  // 移动端布局
} else {
  // 桌面布局
}
```

### 10.3 API 调用优化

#### **1. Provider 缓存**

```dart
// 避免为相同配置重复创建 Provider
final Map<String, BaseApiProvider> _providersCache = {};

BaseApiProvider _getOrCreateProvider({...}) {
  final cacheKey = '$providerName:$baseUrl:$apiKey';
  
  if (_providersCache.containsKey(cacheKey)) {
    return _providersCache[cacheKey]!;
  }
  
  final provider = GeeknowProvider(...);
  _providersCache[cacheKey] = provider;
  return provider;
}
```

#### **2. 指数退避轮询**

```dart
// 视频生成任务轮询（指数退避）
int pollInterval = 2000;  // 初始 2 秒
final maxInterval = 30000;  // 最大 30 秒

while (true) {
  final status = await _apiService.getVideoTask(taskId: taskId);
  
  if (status.completed) break;
  
  await Future.delayed(Duration(milliseconds: pollInterval));
  
  // 指数增长，但不超过最大值
  pollInterval = (pollInterval * 1.5).toInt().clamp(2000, maxInterval);
}
```

---

## 11. 代码规范

### 11.1 Flutter 专家设置（已配置）

根据项目中的 `repo_specific_rule`，已配置以下规范：

#### **1. 性能优先（非阻塞）**

```dart
// ❌ 错误：在 Main Thread 解析 JSON
final data = jsonDecode(response.body);  // 阻塞 UI

// ✅ 正确：在 Isolate 中解析
final data = await compute(jsonDecode, response.body);
// 或使用
final data = await HeavyTaskRunner.parseJson(response.body);
```

#### **2. FFmpeg 处理**

```dart
// ✅ 所有 FFmpeg 操作必须异步
final success = await FFmpegService.concatVideos(videoPaths, outputPath);
```

#### **3. 图片缓存**

```dart
// ✅ 使用 cached_network_image（未来集成）
CachedNetworkImage(
  imageUrl: scene.imageUrl,
  placeholder: (context, url) => CircularProgressIndicator(),
)
```

### 11.2 API 智能轮询

```dart
// ❌ 错误：固定间隔轮询
Timer.periodic(Duration(seconds: 5), (_) => checkStatus());

// ✅ 正确：指数退避轮询
int interval = 2000;
while (!completed) {
  await checkStatus();
  await Future.delayed(Duration(milliseconds: interval));
  interval = (interval * 1.5).toInt().clamp(2000, 30000);
}
```

### 11.3 错误处理

```dart
// ✅ 所有 API 调用必须包含 try-catch
try {
  final result = await apiService.chatCompletion(...);
} catch (e, stackTrace) {
  print('❌ [CRITICAL ERROR CAUGHT] API 调用失败: $e');
  print('📍 [Stack Trace]: $stackTrace');
  // 处理错误
}

// ❌ 禁止空 catch 块
try {
  // ...
} catch (e) {
  // 空的 catch 块 - 静默失败，难以调试
}
```

### 11.4 日志规范

```dart
// ✅ 请求日志
print('🚀 [API Request] URL: $url');
print('📦 [API Payload]: $body');

// ✅ 响应日志
print('✅ [API Response] Code: ${response.statusCode}');
print('📄 [API Body Raw]: ${response.body}');

// ✅ 步骤日志
print('📢 [UI Update] 通知 UI 更新，当前步骤: $currentStep');

// ✅ 错误日志
print('❌ [CRITICAL ERROR CAUGHT] $e');
print('📍 [Stack Trace]: $stackTrace');
```

---

## 12. 已知问题和解决方案

### 12.1 已解决的问题

#### **1. 数据丢失问题** ✅

**问题**: Hive Box 数据未及时写入磁盘

**解决方案**:
```dart
await _projectsBox!.put(key, data);
await _projectsBox!.flush();  // 强制写入磁盘
```

#### **2. 项目重复问题** ✅

**问题**: 项目 ID 前缀不一致导致重复

**解决方案**:
```dart
// 统一存储键格式
final key = 'project_$projectId';
await _projectsBox!.put(key, data);

// 自动处理前缀问题
AutoModeProject? getProjectById(String projectId) {
  if (_projects.containsKey(projectId)) {
    return _projects[projectId];
  }
  if (!projectId.startsWith('project_')) {
    return _projects['project_$projectId'];
  }
  // ...
}
```

#### **3. 并发崩溃问题** ✅

**问题**: 同时生成大量图片导致 UI 冻结

**解决方案**:
```dart
// 使用 Pool 限制并发数
final _imagePool = Pool(2);

final tasks = scenes.map((scene) {
  return _imagePool.withResource(() => _generateImage(scene));
}).toList();
```

#### **4. 生命周期错误** ✅

**问题**: Provider disposed 后仍调用 `notifyListeners()`

**解决方案**:
```dart
bool _isDisposed = false;

void _safeNotifyListeners() {
  if (!_isDisposed) {
    notifyListeners();
  }
}

@override
void dispose() {
  _isDisposed = true;
  super.dispose();
}
```

### 12.2 当前限制

1. **FFmpeg 依赖**: 用户需手动安装 FFmpeg 并配置 PATH
2. **单供应商**: 目前只支持 Geeknow API
3. **无离线模式**: 需要网络连接才能使用 AI 功能

---

## 13. 未来扩展方向

### 13.1 API 供应商扩展

```
当前支持：
├── Geeknow ✅

计划支持：
├── OpenAI (GPT, DALL-E)
├── Anthropic (Claude)
├── Stability AI (Stable Diffusion)
├── Runway (Gen-2)
└── 本地模型 (Ollama)
```

### 13.2 功能扩展

- [ ] **音频生成**: TTS（文字转语音）、BGM 生成
- [ ] **字幕生成**: 自动为视频添加字幕
- [ ] **特效和转场**: 更丰富的视频效果
- [ ] **协作模式**: 多人协作创作
- [ ] **模板市场**: 预设模板和风格

### 13.3 性能优化

- [ ] **增量保存**: 只保存变更的数据
- [ ] **后台任务**: 使用 WorkManager 进行后台处理
- [ ] **CDN 加速**: 图片和视频 CDN 缓存

### 13.4 平台扩展

- [ ] **移动端优化**: 更好的触摸体验
- [ ] **Web 版本**: 浏览器中使用
- [ ] **桌面原生**: Electron 或原生应用

---

## 14. 快速参考

### 14.1 关键文件速查

| 功能 | 文件路径 |
|------|---------|
| **应用入口** | `lib/main.dart` |
| **自动模式状态** | `lib/logic/auto_mode_provider.dart` |
| **自动模式 UI** | `lib/views/auto_mode_screen.dart` |
| **API 管理** | `lib/services/api_manager.dart` |
| **API 配置** | `lib/services/api_config_manager.dart` |
| **API 供应商基类** | `lib/services/providers/base_provider.dart` |
| **Geeknow 实现** | `lib/services/providers/geeknow_provider.dart` |
| **FFmpeg 服务** | `lib/services/ffmpeg_service.dart` |
| **项目模型** | `lib/models/auto_mode_project.dart` |
| **场景模型** | `lib/models/scene_model.dart` |

### 14.2 常用命令

```bash
# 运行应用
flutter run

# 构建 Windows 版本
flutter build windows

# 清理构建缓存
flutter clean

# 获取依赖
flutter pub get

# 检查代码
flutter analyze
```

### 14.3 环境变量配置

```bash
# .env 文件
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

---

## 15. 总结

**星河（Xinghe）** 是一款功能完整、架构清晰的 AI 视频创作软件：

✅ **双模式工作流**: 自动模式 + 手动模式  
✅ **插件化 API 架构**: 支持多供应商 Mix & Match  
✅ **完整的状态管理**: ChangeNotifier + StatefulWidget  
✅ **健壮的数据存储**: Hive + SharedPreferences + Supabase  
✅ **性能优化**: Isolate + 并发控制 + 缓存  
✅ **代码质量**: 完整错误处理 + 详细日志  
✅ **可扩展性**: 易于添加新供应商和功能  

这份文档提供了软件的完整技术视图，适合用于：
- 向其他 AI 大语言模型介绍项目
- 新开发者快速了解架构
- 规划未来的功能扩展
- 故障排查和性能优化

---

**文档结束**
