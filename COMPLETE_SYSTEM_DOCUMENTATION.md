# 星河（Xinghe）- 完整系统技术文档

## 📋 文档版本
- **版本**: v1.0.0
- **更新日期**: 2026-01-20
- **目标受众**: AI助手、开发者、技术顾问

---

## 🎯 项目概述

### 应用简介
**星河（Xinghe）**是一款基于Flutter开发的桌面AI创作工具，主要用于：
- AI驱动的图像生成
- AI驱动的视频生成  
- 场景和角色素材管理
- 自动化创作流程（自动模式）
- 提示词模板管理

### 核心价值
- **创作者工具**：为内容创作者提供AI辅助创作能力
- **工作流自动化**：通过自动模式实现批量创作
- **素材管理**：统一管理角色、场景、物品素材
- **多模型支持**：支持多种LLM、图像和视频生成模型

---

## 🏗️ 技术架构

### 技术栈
```yaml
Framework: Flutter 3.x
语言: Dart
平台: Windows (主要), macOS, Linux
状态管理: ChangeNotifier + Provider模式
本地存储: Hive (NoSQL), SharedPreferences
网络请求: http package
并发处理: Isolate, compute, package:pool
视频处理: FFmpeg (bundled)
UI组件: Material Design + Custom Widgets
字体: Google Fonts (Noto Sans SC)
```

### 架构模式
```
┌─────────────────────────────────────────┐
│           Presentation Layer            │
│  (UI Widgets, Screens, Components)      │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│           Business Logic Layer          │
│  (Providers, State Management)          │
│  - AutoModeProvider                     │
│  - WorkspaceState                       │
│  - GeneratedMediaManager                │
│  - VideoTaskManager                     │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│           Service Layer                 │
│  (API Services, Data Processing)        │
│  - ApiService                           │
│  - ApiManager                           │
│  - FFmpegService                        │
│  - PromptStore                          │
│  - HeavyTaskRunner                      │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│           Data Layer                    │
│  (Models, Storage, External APIs)       │
│  - Hive Database                        │
│  - REST APIs (LLM, Image, Video)        │
│  - Supabase (素材存储)                   │
└─────────────────────────────────────────┘
```

---

## 📁 项目文件结构

```
lib/
├── main.dart                          # 应用入口，包含主要UI
├── logic/
│   └── auto_mode_provider.dart        # 自动模式状态管理
├── models/                            # 数据模型
│   ├── auto_mode_project.dart         # 自动模式项目模型
│   ├── auto_mode_step.dart            # 步骤模型
│   ├── character_model.dart           # 角色模型
│   ├── prompt_template.dart           # 提示词模板
│   ├── scene_model.dart               # 场景模型
│   └── scene_status.dart              # 场景状态
├── providers/mixins/                  # 功能混入
│   ├── character_generation_mixin.dart
│   ├── media_generation_mixin.dart
│   ├── script_generation_mixin.dart
│   └── storyboard_generation_mixin.dart
├── services/                          # 服务层
│   ├── api_config_manager.dart        # API配置管理
│   ├── api_manager.dart               # API管理器
│   ├── api_service.dart               # API服务核心
│   ├── ffmpeg_service.dart            # FFmpeg视频处理
│   ├── generation_queue.dart          # 生成队列
│   ├── heavy_task_runner.dart         # 重任务处理器
│   ├── prompt_store.dart              # 提示词存储
│   ├── sora_api_service.dart          # Sora视频API
│   ├── update_service.dart            # 更新服务
│   └── providers/                     # API提供者插件
│       ├── base_provider.dart
│       └── geeknow_provider.dart
├── utils/                             # 工具类
│   ├── api_error_handler.dart
│   ├── app_exception.dart
│   └── index.dart
├── views/                             # 视图/屏幕
│   ├── auto_mode_screen.dart
│   └── prompt_config_view.dart
└── widgets/                           # 可复用组件
    ├── provider_selector.dart
    └── save_settings_panel.dart

windows/                               # Windows特定配置
├── CMakeLists.txt                     # CMake构建配置
├── ffmpeg/                            # FFmpeg可执行文件
└── runner/                            # Windows Runner

installer/                             # 安装程序配置
├── xinghe-setup.iss                   # Inno Setup脚本
├── build_installer.ps1                # 构建脚本
├── complete_cleanup.ps1               # 清理工具
└── manual_hide_files.ps1              # 文件隐藏工具
```

---

## 🎨 核心功能模块

### 1. 工作空间管理（main.dart: WorkspaceState）

#### 1.1 创作空间
**位置**: `main.dart` - `_CreationSpaceWidget`

**功能**:
- 展示所有创建的作品（图像和视频）
- GridView展示，使用`maxCrossAxisExtent: 200`
- 支持查看、删除作品
- 点击放大查看

**数据存储**:
```dart
// Hive Box: 'generated_media'
{
  'images': [
    {
      'path': String,
      'prompt': String,
      'model': String,
      'createdAt': String (ISO8601)
    }
  ],
  'videos': [
    {
      'path': String,
      'prompt': String,
      'model': String,
      'url': String?,
      'createdAt': String (ISO8601)
    }
  ]
}
```

#### 1.2 绘图空间
**位置**: `main.dart` - `_DrawingSpaceWidgetState`

**核心流程**:
```dart
1. 用户输入提示词
2. 选择图像模型（通过ApiConfigManager）
3. 点击生成 → _generateImage()
4. ApiService.generateImage() → HTTP请求
5. 轮询任务状态（如果异步）
6. 下载并保存图像
7. 更新UI和Hive存储
```

**布局结构**:
```
Row
├── 左侧面板（30%宽度）
│   ├── 提示词输入框
│   ├── 模型选择
│   ├── 提示词配置按钮
│   └── 生成按钮
└── 右侧面板（70%宽度）
    └── GridView（生成结果）
        └── maxCrossAxisExtent: 150
```

**关键代码**:
```dart
Future<void> _generateImage() async {
  final prompt = _promptController.text;
  final model = apiConfigManager.imageModel;
  
  // 调用API
  final response = await apiService.generateImage(
    model: model,
    prompt: prompt,
    size: selectedSize,
  );
  
  // 处理响应
  if (response['task_id'] != null) {
    // 异步任务 - 开始轮询
    _pollImageTask(response['task_id']);
  } else {
    // 同步响应 - 直接下载
    _downloadAndSaveImage(response['url']);
  }
}
```

#### 1.3 视频空间
**位置**: `main.dart` - `_VideoSpaceWidgetState`

**特殊功能**:
- **素材库集成**: 可选择已上传的角色素材
- **参考图上传**: 支持本地图片作为参考
- **角色名称自动添加**: 使用上传角色时，自动将角色名称前置到提示词

**视频生成逻辑**:
```dart
Future<void> _generateVideo() async {
  String finalPrompt = _promptController.text;
  File? inputReference;
  
  // 如果选择了素材库的已上传角色
  if (_selectedCharacterId != null && _isFromMaterialLibrary) {
    // 仅将角色名称添加到提示词
    finalPrompt = '$_selectedMaterialName, $finalPrompt';
    // 不传递 inputReference 或 characterUrl
  } else if (_selectedImagePath != null) {
    // 使用本地图片作为参考
    inputReference = File(_selectedImagePath!);
  }
  
  final response = await apiService.createVideo(
    model: model,
    prompt: finalPrompt,
    size: '${width}x${height}',
    seconds: seconds,
    inputReference: inputReference,
  );
  
  // 添加到任务队列并轮询
  videoTaskManager.addTask(response['id'], prompt);
  _startPolling();
}
```

**视频列表排序**:
```dart
// 所有视频按时间倒序排列（最新在前）
List<Map<String, dynamic>> allItems = [
  ...activeTasks.map((t) => {'type': 'active', 'timestamp': t['createdAt']}),
  ...failedTasks.map((t) => {'type': 'failed', 'timestamp': t['failedAt']}),
  ...videos.map((v) => {'type': 'completed', 'timestamp': v['createdAt']}),
];

allItems.sort((a, b) {
  DateTime timeA = DateTime.parse(a['timestamp']);
  DateTime timeB = DateTime.parse(b['timestamp']);
  return timeB.compareTo(timeA); // 降序
});
```

#### 1.4 素材库
**位置**: `main.dart` - `_MaterialsLibraryWidgetState`

**素材分类**:
```dart
enum MaterialType {
  character,  // 角色
  scene,      // 场景
  prop,       // 物品
}
```

**存储结构** (Hive Box: 'materials'):
```dart
{
  'characters': [
    {
      'name': String,
      'path': String (本地路径),
      'characterId': String? (Supabase上传后的ID),
      'uploadedUrl': String? (远程URL),
      'createdAt': String,
    }
  ],
  'scenes': [...],
  'props': [...],
}
```

**上传流程**:
```dart
Future<void> _uploadToSupabase(material) async {
  // 1. 读取图片文件
  final bytes = await File(material['path']).readAsBytes();
  
  // 2. 上传到Supabase Storage
  final filePath = 'characters/${DateTime.now().millisecondsSinceEpoch}.png';
  await supabase.storage.from('materials').uploadBinary(filePath, bytes);
  
  // 3. 获取公开URL
  final url = supabase.storage.from('materials').getPublicUrl(filePath);
  
  // 4. 创建角色 (调用视频API)
  final response = await apiService.createCharacter(imageUrl: url);
  
  // 5. 保存 characterId
  material['characterId'] = response['character_id'];
  material['uploadedUrl'] = url;
  
  // 6. 更新本地存储
  await _saveMaterials();
}
```

### 2. 自动模式（AutoModeProvider）

**位置**: `lib/logic/auto_mode_provider.dart`

**核心概念**:
- **项目**: 一个完整的创作项目（AutoModeProject）
- **步骤**: 项目中的各个执行阶段（AutoModeStep）
- **Mixin**: 功能模块化（角色生成、剧本生成、分镜、媒体生成）

**项目数据模型**:
```dart
class AutoModeProject {
  String id;                    // 唯一标识
  String name;                  // 项目名称
  AutoModeStep currentStep;     // 当前步骤
  
  // 步骤1: 角色生成
  String characterPrompt;
  List<GeneratedCharacter> characters;
  
  // 步骤2: 剧本生成
  String scriptPrompt;
  String? generatedScript;
  
  // 步骤3: 分镜生成
  List<Storyboard> storyboards;
  
  // 步骤4: 媒体生成
  Map<String, List<GeneratedMedia>> sceneMedia;
  
  DateTime createdAt;
  DateTime? lastSavedAt;
}
```

**执行流程**:
```
创建项目
    ↓
步骤1: 角色生成
    ├─ 输入角色描述
    ├─ 生成角色图像（批量）
    └─ 选择确认 → 下一步
    ↓
步骤2: 剧本生成
    ├─ 输入剧本要求
    ├─ LLM生成剧本
    └─ 编辑确认 → 下一步
    ↓
步骤3: 分镜设计
    ├─ 根据剧本自动生成分镜
    ├─ 每个分镜包含：场景描述、角色、动作
    └─ 调整确认 → 下一步
    ↓
步骤4: 媒体生成
    ├─ 批量生成场景图像/视频
    ├─ 使用 GenerationQueue 控制并发
    └─ 完成 → 导出/保存
```

**状态管理**:
```dart
class AutoModeProvider extends ChangeNotifier {
  List<AutoModeProject> _projects = [];
  AutoModeProject? _currentProject;
  
  // 创建新项目
  void createProject(String name) {
    final project = AutoModeProject(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      currentStep: AutoModeStep.characterGeneration,
    );
    _projects.add(project);
    _currentProject = project;
    notifyListeners();
  }
  
  // 执行步骤
  Future<void> executeStep() async {
    switch (_currentProject!.currentStep) {
      case AutoModeStep.characterGeneration:
        await _generateCharacters();
        break;
      case AutoModeStep.scriptGeneration:
        await _generateScript();
        break;
      // ...
    }
  }
  
  // 持久化
  Future<void> saveProject() async {
    final box = await Hive.openBox('auto_mode_projects');
    await box.put(_currentProject!.id, _currentProject!.toJson());
  }
}
```

### 3. API服务架构

**位置**: `lib/services/api_service.dart`

#### 3.1 插件化API提供者

**设计理念**: 支持多个API提供商，统一接口

```dart
// 基类
abstract class BaseApiProvider {
  String get name;
  
  Future<Map<String, dynamic>> generateText(String prompt);
  Future<Map<String, dynamic>> generateImage(String prompt, String size);
  Future<Map<String, dynamic>> createVideo(Map<String, dynamic> params);
}

// 具体实现
class GeeknowProvider extends BaseApiProvider {
  @override
  String get name => 'GeekNow';
  
  @override
  Future<Map<String, dynamic>> generateText(String prompt) async {
    final response = await http.post(
      Uri.parse('$baseUrl/v1/chat/completions'),
      headers: {'Authorization': 'Bearer $apiKey'},
      body: jsonEncode({
        'model': model,
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
      }),
    );
    return jsonDecode(response.body);
  }
  
  // 图像和视频生成类似...
}
```

#### 3.2 ApiManager - 统一管理

```dart
class ApiManager {
  // 单例模式
  static final ApiManager _instance = ApiManager._internal();
  factory ApiManager() => _instance;
  
  // 配置管理
  final ApiConfigManager configManager = ApiConfigManager();
  
  // 当前提供者
  BaseApiProvider get currentProvider {
    return configManager.selectedProvider == 'geeknow'
        ? GeeknowProvider()
        : DefaultProvider();
  }
  
  // 统一调用接口
  Future<String> generateText(String prompt) async {
    final result = await currentProvider.generateText(prompt);
    return _extractText(result);
  }
}
```

#### 3.3 ApiService - 核心服务

**关键功能**:

**1. 图像生成**:
```dart
Future<Map<String, dynamic>> generateImage({
  required String model,
  required String prompt,
  required String size,
}) async {
  final response = await http.post(
    Uri.parse('$baseUrl/v1/images/generations'),
    headers: _headers,
    body: jsonEncode({
      'model': model,
      'prompt': prompt,
      'size': size,
      'n': 1,
    }),
  );
  
  return _handleResponse(response);
}
```

**2. 视频生成**（带参考图）:
```dart
Future<Map<String, dynamic>> createVideo({
  required String model,
  required String prompt,
  required String size,
  required int seconds,
  File? inputReference,
  String? characterUrl,
}) async {
  final request = http.MultipartRequest(
    'POST',
    Uri.parse('$baseUrl/v1/videos'),
  );
  
  request.headers.addAll(_headers);
  
  // 添加字段
  request.fields['model'] = model;
  request.fields['prompt'] = prompt;
  request.fields['size'] = size;
  request.fields['seconds'] = seconds.toString();
  
  // 如果有本地参考图
  if (inputReference != null) {
    request.files.add(await http.MultipartFile.fromPath(
      'input_reference',
      inputReference.path,
    ));
  }
  
  // 如果使用已上传角色，只在prompt中添加名称
  // characterUrl 在新逻辑中不再使用
  
  final response = await request.send();
  return _parseMultipartResponse(response);
}
```

**3. 任务轮询**:
```dart
Future<Map<String, dynamic>> pollTask(String taskId) async {
  while (true) {
    await Future.delayed(Duration(seconds: 3));
    
    final response = await http.get(
      Uri.parse('$baseUrl/v1/tasks/$taskId'),
      headers: _headers,
    );
    
    final data = jsonDecode(response.body);
    
    if (data['status'] == 'completed') {
      return data;
    } else if (data['status'] == 'failed') {
      throw Exception(data['error']);
    }
    
    // 继续等待...
  }
}
```

### 4. 视频任务管理

**位置**: `lib/services/api_service.dart` - `VideoTaskManager`

**功能**:
- 管理视频生成任务的生命周期
- 存储任务状态（active, failed, completed）
- 持久化任务数据

```dart
class VideoTaskManager extends ChangeNotifier {
  List<Map<String, dynamic>> _activeTasks = [];
  List<Map<String, dynamic>> _failedTasks = [];
  
  // 添加任务
  void addTask(String taskId, String prompt) {
    _activeTasks.add({
      'taskId': taskId,
      'prompt': prompt,
      'createdAt': DateTime.now().toIso8601String(),
      'progress': 0,
    });
    notifyListeners();
    _save();
  }
  
  // 更新进度
  void updateProgress(String taskId, int progress) {
    final task = _activeTasks.firstWhere((t) => t['taskId'] == taskId);
    task['progress'] = progress;
    notifyListeners();
    _save();
  }
  
  // 移除任务（完成或失败）
  void removeTask(String taskId, {bool isFailed = false}) {
    final task = _activeTasks.firstWhere((t) => t['taskId'] == taskId);
    _activeTasks.remove(task);
    
    if (isFailed) {
      task['failedAt'] = DateTime.now().toIso8601String();
      _failedTasks.add(task);
    }
    
    notifyListeners();
    _save();
  }
  
  // 持久化
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('video_tasks', jsonEncode({
      'active': _activeTasks,
      'failed': _failedTasks,
    }));
  }
}
```

### 5. FFmpeg 视频处理

**位置**: `lib/services/ffmpeg_service.dart`

**打包方式**: FFmpeg可执行文件打包在应用中

**关键配置** (`windows/CMakeLists.txt`):
```cmake
# 在安装阶段复制 FFmpeg
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/ffmpeg/ffmpeg.exe" 
        DESTINATION "${INSTALL_BUNDLE_LIB_DIR}")
```

**动态路径解析**:
```dart
class FFmpegService {
  static Future<String> _getFFmpegPath() async {
    if (Platform.isWindows) {
      // 获取当前可执行文件路径
      final exePath = Platform.resolvedExecutable;
      final exeDir = path.dirname(exePath);
      final bundledFFmpeg = path.join(exeDir, 'ffmpeg.exe');
      
      // 检查打包的 FFmpeg
      if (await File(bundledFFmpeg).exists()) {
        return bundledFFmpeg;
      }
    }
    
    // 回退到系统 FFmpeg
    return 'ffmpeg';
  }
  
  // 图片转视频
  static Future<String> convertImageToVideo(String imagePath) async {
    final ffmpegPath = await _getFFmpegPath();
    final outputPath = '${imagePath}_video.mp4';
    
    final result = await Process.run(ffmpegPath, [
      '-loop', '1',
      '-i', imagePath,
      '-c:v', 'libx264',
      '-t', '5',
      '-pix_fmt', 'yuv420p',
      outputPath,
    ]);
    
    if (result.exitCode != 0) {
      throw Exception('FFmpeg failed: ${result.stderr}');
    }
    
    return outputPath;
  }
  
  // 视频拼接
  static Future<String> concatVideos(List<String> videoPaths) async {
    final ffmpegPath = await _getFFmpegPath();
    // 创建文件列表
    final listFile = 'concat_list.txt';
    await File(listFile).writeAsString(
      videoPaths.map((p) => "file '$p'").join('\n')
    );
    
    final outputPath = 'output_${DateTime.now().millisecondsSinceEpoch}.mp4';
    
    await Process.run(ffmpegPath, [
      '-f', 'concat',
      '-safe', '0',
      '-i', listFile,
      '-c', 'copy',
      outputPath,
    ]);
    
    return outputPath;
  }
}
```

### 6. 并发和性能优化

#### 6.1 GenerationQueue - 批量生成控制

**位置**: `lib/services/generation_queue.dart`

**功能**: 控制并发数量，防止API过载

```dart
class GenerationQueue {
  final Pool _pool = Pool(3); // 最多3个并发任务
  
  Future<T> add<T>(Future<T> Function() task) async {
    final resource = await _pool.request();
    try {
      return await task();
    } finally {
      resource.release();
    }
  }
  
  // 批量执行
  Future<List<T>> addAll<T>(List<Future<T> Function()> tasks) async {
    return Future.wait(tasks.map((task) => add(task)));
  }
}
```

**使用示例**:
```dart
// 在 AutoModeProvider 中
Future<void> _generateMultipleScenes() async {
  final queue = GenerationQueue();
  
  final tasks = storyboards.map((board) => () async {
    return await apiService.generateImage(
      prompt: board.sceneDescription,
      model: imageModel,
      size: '1024x1024',
    );
  }).toList();
  
  // 最多3个并发，自动排队
  final results = await queue.addAll(tasks);
}
```

#### 6.2 HeavyTaskRunner - Isolate处理

**位置**: `lib/services/heavy_task_runner.dart`

**功能**: 将重任务放到独立Isolate，避免UI卡顿

```dart
class HeavyTaskRunner {
  static Future<T> run<T>(ComputeCallback<dynamic, T> callback, dynamic message) async {
    return await compute(callback, message);
  }
}

// 使用示例：大文件处理
Future<Uint8List> processLargeImage(String path) async {
  return await HeavyTaskRunner.run(_processImageIsolate, path);
}

Uint8List _processImageIsolate(String path) {
  // 在独立线程中执行
  final file = File(path);
  return file.readAsBytesSync();
}
```

### 7. 数据持久化

#### 7.1 Hive数据库

**使用的Boxes**:
```dart
// 1. 生成的媒体
Box<Map> generatedMediaBox = Hive.box('generated_media');
// 存储: images[], videos[]

// 2. 素材库
Box<Map> materialsBox = Hive.box('materials');
// 存储: characters[], scenes[], props[]

// 3. 自动模式项目
Box<Map> autoModeProjectsBox = Hive.box('auto_mode_projects');
// 存储: 各个项目的完整数据

// 4. 提示词模板
Box<Map> promptTemplatesBox = Hive.box('prompt_templates');
// 存储: 用户自定义的提示词模板
```

#### 7.2 SharedPreferences

**配置数据**:
```dart
// API配置
'api_config': {
  'provider': 'geeknow',
  'llm_model': 'gpt-4',
  'image_model': 'dall-e-3',
  'video_model': 'sora-2',
  'api_key': 'xxx',
  'base_url': 'https://api.example.com',
}

// 视频任务
'video_tasks': {
  'active': [...],
  'failed': [...],
}

// UI状态
'last_workspace': 'creation', // 上次打开的工作空间
'theme_mode': 'light',
```

### 8. UI设计和布局

#### 8.1 响应式布局

**核心组件**: `ResponsiveInputWrapper`

```dart
class ResponsiveInputWrapper extends StatelessWidget {
  final Widget child;
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.05,
      ),
      child: child,
    );
  }
}
```

#### 8.2 GridView 配置

**统一尺寸**:
```dart
SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 150,      // 每个item最大宽度
  crossAxisSpacing: 16,          // 水平间距
  mainAxisSpacing: 16,           // 垂直间距
  childAspectRatio: 0.78,        // 宽高比
)
```

**应用位置**:
- 创作空间：maxCrossAxisExtent: 200
- 绘图空间：maxCrossAxisExtent: 150
- 视频空间：maxCrossAxisExtent: 150
- 素材库：maxCrossAxisExtent: 150

#### 8.3 主题和字体

```dart
ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
  fontFamily: GoogleFonts.notoSansSc().fontFamily,
  textTheme: GoogleFonts.notoSansSCTextTheme(),
)
```

---

## 🔑 关键业务逻辑

### 1. 图像生成完整流程

```dart
// 步骤1: 用户输入
用户在绘图空间输入提示词 "一只可爱的猫"

// 步骤2: 调用API
Future<void> _generateImage() async {
  final model = apiConfigManager.imageModel; // "dall-e-3"
  final prompt = _promptController.text;
  
  // API请求
  final response = await apiService.generateImage(
    model: model,
    prompt: prompt,
    size: "1024x1024",
  );
  
  // 步骤3: 处理响应
  if (response.containsKey('task_id')) {
    // 异步任务 - 需要轮询
    _pollImageTask(response['task_id']);
  } else {
    // 同步响应 - 直接获取URL
    final imageUrl = response['data'][0]['url'];
    _downloadAndSaveImage(imageUrl, prompt);
  }
}

// 步骤4: 轮询任务（如果是异步）
Future<void> _pollImageTask(String taskId) async {
  while (true) {
    await Future.delayed(Duration(seconds: 3));
    
    final taskData = await apiService.getTask(taskId);
    
    if (taskData['status'] == 'completed') {
      final imageUrl = taskData['result']['url'];
      await _downloadAndSaveImage(imageUrl, prompt);
      break;
    } else if (taskData['status'] == 'failed') {
      _showError(taskData['error']);
      break;
    }
  }
}

// 步骤5: 下载并保存
Future<void> _downloadAndSaveImage(String url, String prompt) async {
  // 下载图像
  final response = await http.get(Uri.parse(url));
  final bytes = response.bodyBytes;
  
  // 保存到本地
  final appDir = await getApplicationDocumentsDirectory();
  final fileName = '${DateTime.now().millisecondsSinceEpoch}.png';
  final filePath = '${appDir.path}/images/$fileName';
  final file = File(filePath);
  await file.create(recursive: true);
  await file.writeAsBytes(bytes);
  
  // 步骤6: 更新Hive数据库
  final mediaManager = GeneratedMediaManager();
  await mediaManager.addImage({
    'path': filePath,
    'prompt': prompt,
    'model': model,
    'createdAt': DateTime.now().toIso8601String(),
  });
  
  // 步骤7: 更新UI
  setState(() {
    _generatedImages.add(filePath);
  });
}
```

### 2. 视频生成（带角色素材）

```dart
// 场景1: 使用素材库的已上传角色
Future<void> _generateVideoWithUploadedCharacter() async {
  // 用户在视频空间：
  // 1. 点击"素材库"选择角色
  // 2. 选择了一个已上传的角色（有 characterId）
  // 3. 输入提示词："在草地上奔跑"
  
  final selectedCharacter = {
    'name': '@e8738c874.nocturne',
    'characterId': 'char_xxxxx',
    'path': '/local/path/character.png',
  };
  
  final userPrompt = "在草地上奔跑";
  
  // 组合提示词：角色名 + 用户描述
  final finalPrompt = '${selectedCharacter['name']}, $userPrompt';
  // 结果: "@e8738c874.nocturne, 在草地上奔跑"
  
  // 调用API - 不传递 inputReference 或 characterUrl
  final response = await apiService.createVideo(
    model: 'sora-2',
    prompt: finalPrompt,  // 只传修改后的提示词
    size: '1280x720',
    seconds: 15,
    inputReference: null,  // 不传参考图
    characterUrl: null,    // 不传角色URL
  );
  
  // API会根据提示词中的 @username 识别角色
}

// 场景2: 使用本地参考图
Future<void> _generateVideoWithLocalReference() async {
  final userPrompt = "在跳舞";
  final referenceImage = File('/local/custom/image.png');
  
  final response = await apiService.createVideo(
    model: 'sora-2',
    prompt: userPrompt,
    size: '1280x720',
    seconds: 15,
    inputReference: referenceImage,  // 传递本地文件
  );
}
```

### 3. 自动模式执行流程

```dart
// 完整的自动化创作流程
class AutoModeProvider with ChangeNotifier {
  AutoModeProject? _currentProject;
  
  // 1. 创建项目
  void createProject(String name) {
    _currentProject = AutoModeProject(
      id: _generateId(),
      name: name,
      currentStep: AutoModeStep.characterGeneration,
    );
    notifyListeners();
  }
  
  // 2. 执行角色生成步骤
  Future<void> generateCharacters(String prompt) async {
    _currentProject!.characterPrompt = prompt;
    
    // 使用队列控制并发
    final queue = GenerationQueue();
    
    // 生成4个角色变体
    final tasks = List.generate(4, (i) => () async {
      return await apiService.generateImage(
        prompt: '$prompt, variant ${i + 1}',
        model: 'dall-e-3',
        size: '1024x1024',
      );
    });
    
    final results = await queue.addAll(tasks);
    
    // 保存角色
    _currentProject!.characters = results.map((r) {
      return GeneratedCharacter(
        imageUrl: r['url'],
        description: prompt,
      );
    }).toList();
    
    notifyListeners();
    await _saveProject();
  }
  
  // 3. 执行剧本生成步骤
  Future<void> generateScript(String requirements) async {
    _currentProject!.scriptPrompt = requirements;
    
    // 构建提示词
    final systemPrompt = """
    你是一个专业的编剧。根据以下角色和要求，创作一个故事剧本：
    
    角色:
    ${_currentProject!.characters.map((c) => c.description).join('\n')}
    
    要求:
    $requirements
    
    请输出结构化的剧本，包含场景、对话和动作描述。
    """;
    
    final script = await apiManager.generateText(systemPrompt);
    
    _currentProject!.generatedScript = script;
    _currentProject!.currentStep = AutoModeStep.storyboardDesign;
    
    notifyListeners();
    await _saveProject();
  }
  
  // 4. 执行分镜生成步骤
  Future<void> generateStoryboards() async {
    // 解析剧本，提取场景
    final scenes = _parseScript(_currentProject!.generatedScript!);
    
    _currentProject!.storyboards = scenes.map((scene) {
      return Storyboard(
        sceneNumber: scene['number'],
        description: scene['description'],
        characters: scene['characters'],
        location: scene['location'],
      );
    }).toList();
    
    _currentProject!.currentStep = AutoModeStep.mediaGeneration;
    
    notifyListeners();
    await _saveProject();
  }
  
  // 5. 执行媒体生成步骤
  Future<void> generateSceneMedia() async {
    final queue = GenerationQueue();
    
    for (final board in _currentProject!.storyboards) {
      // 为每个分镜生成图像/视频
      final mediaTask = () async {
        if (board.requiresVideo) {
          return await apiService.createVideo(
            prompt: board.description,
            model: 'sora-2',
            size: '1280x720',
            seconds: 10,
          );
        } else {
          return await apiService.generateImage(
            prompt: board.description,
            model: 'dall-e-3',
            size: '1024x1024',
          );
        }
      };
      
      final result = await queue.add(mediaTask);
      
      _currentProject!.sceneMedia[board.sceneNumber] = [
        GeneratedMedia.fromResponse(result)
      ];
      
      notifyListeners();
    }
    
    await _saveProject();
  }
  
  // 6. 持久化
  Future<void> _saveProject() async {
    final box = await Hive.openBox('auto_mode_projects');
    await box.put(
      _currentProject!.id,
      _currentProject!.toJson(),
    );
  }
}
```

---

## 🔐 配置和环境

### 环境变量 (.env)
```env
# API配置
GEEKNOW_API_KEY=your_api_key_here
GEEKNOW_BASE_URL=https://www.geeknow.top

# Supabase配置
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your_anon_key_here

# 默认模型
DEFAULT_LLM_MODEL=gpt-4
DEFAULT_IMAGE_MODEL=dall-e-3
DEFAULT_VIDEO_MODEL=sora-2
```

### 配置管理
```dart
class ApiConfigManager {
  static final ApiConfigManager _instance = ApiConfigManager._internal();
  factory ApiConfigManager() => _instance;
  
  late SharedPreferences _prefs;
  
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadEnv();
  }
  
  Future<void> _loadEnv() async {
    await dotenv.load(fileName: ".env");
  }
  
  // Getters
  String get apiKey => _prefs.getString('api_key') ?? dotenv.env['GEEKNOW_API_KEY']!;
  String get baseUrl => _prefs.getString('base_url') ?? dotenv.env['GEEKNOW_BASE_URL']!;
  String get llmModel => _prefs.getString('llm_model') ?? dotenv.env['DEFAULT_LLM_MODEL']!;
  String get imageModel => _prefs.getString('image_model') ?? dotenv.env['DEFAULT_IMAGE_MODEL']!;
  String get videoModel => _prefs.getString('video_model') ?? dotenv.env['DEFAULT_VIDEO_MODEL']!;
  
  // Setters
  Future<void> setApiKey(String key) async {
    await _prefs.setString('api_key', key);
  }
  
  Future<void> setModel(String type, String model) async {
    await _prefs.setString('${type}_model', model);
  }
}
```

---

## 📱 Windows 打包和部署

### 构建流程

```bash
# 1. 清理
flutter clean

# 2. 获取依赖
flutter pub get

# 3. 构建 Release
flutter build windows --release

# 输出位置：
# build/windows/x64/runner/Release/
```

### Windows 特定配置

**CMakeLists.txt** - FFmpeg打包:
```cmake
# 复制 FFmpeg 到输出目录
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/ffmpeg/ffmpeg.exe"
        DESTINATION "${INSTALL_BUNDLE_LIB_DIR}")
```

### Inno Setup 安装程序

**位置**: `installer/xinghe-setup.iss`

**关键特性**:
1. **Windows API隐藏文件**: 使用 `SetFileAttributesW` API直接设置隐藏属性
2. **管理员权限**: 确保有足够权限设置文件属性
3. **完整卸载**: 清理所有文件和注册表项

**隐藏文件实现**:
```pascal
[Code]
// Windows API 声明
function SetFileAttributes(lpFileName: String; dwFileAttributes: DWORD): BOOL;
  external 'SetFileAttributesW@kernel32.dll stdcall';

function GetFileAttributes(lpFileName: String): DWORD;
  external 'GetFileAttributesW@kernel32.dll stdcall';

// 隐藏文件函数
procedure HideFileOrFolder(FileName: String);
var
  Attrs: DWORD;
begin
  Attrs := GetFileAttributes(FileName);
  if Attrs <> $FFFFFFFF then
  begin
    // 添加隐藏属性 ($00000002)
    if SetFileAttributes(FileName, Attrs or $00000002) then
      Log('成功隐藏: ' + FileName)
    else
      Log('隐藏失败: ' + FileName);
  end;
end;

// 安装后执行
procedure CurStepChanged(CurStep: TSetupStep);
var
  AppPath: string;
begin
  if CurStep = ssPostInstall then
  begin
    AppPath := ExpandConstant('{app}');
    
    // 隐藏所有技术文件
    HideFileOrFolder(AppPath + '\flutter_windows.dll');
    HideFileOrFolder(AppPath + '\app_links_plugin.dll');
    HideFileOrFolder(AppPath + '\file_selector_windows_plugin.dll');
    HideFileOrFolder(AppPath + '\url_launcher_windows_plugin.dll');
    HideFileOrFolder(AppPath + '\ffmpeg.exe');
    HideFileOrFolder(AppPath + '\data');
  end;
end;
```

**构建安装程序**:
```powershell
cd installer
.\build_installer.ps1

# 输出：installer/output/xinghe-setup-1.0.0.exe
```

---

## 🎯 核心技术挑战和解决方案

### 1. ParentDataWidget 布局错误

**问题**: 嵌套 `Expanded` 或 `Flexible` 导致布局冲突

**错误示例**:
```dart
Row(
  children: [
    Expanded(  // 外层
      child: Column(
        children: [
          Expanded(  // 内层 - 冲突！
            child: Container(),
          ),
        ],
      ),
    ),
  ],
)
```

**解决方案**:
- 移除冗余的 `Expanded`
- 使用 `Flexible` 替代，或调整 `mainAxisSize`
- 将 `Expanded` 提升到更高层级

### 2. 图像缓存和内存管理

**问题**: 大量图像导致内存溢出

**解决方案**:
```dart
// 清理缓存
PaintingBinding.instance.imageCache.clear();
PaintingBinding.instance.imageCache.clearLiveImages();

// 限制缓存大小
PaintingBinding.instance.imageCache.maximumSize = 100;
PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024; // 50MB
```

### 3. API 错误处理

**挑战**: 不同API提供商的错误格式不统一

**解决方案**: 统一错误处理器
```dart
class ApiErrorHandler {
  static String parseError(dynamic error) {
    if (error is http.Response) {
      final body = jsonDecode(error.body);
      return body['error']?['message'] ?? 'Unknown error';
    } else if (error is Exception) {
      return error.toString();
    }
    return 'Unknown error occurred';
  }
  
  static void handle(dynamic error, BuildContext context) {
    final message = parseError(error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
```

### 4. 视频生成字符 ID 问题

**问题**: 使用素材库已上传角色时，发送错误的参数导致 `base64 decode` 错误

**原因**: 
- 最初将 `characterId` 作为 `character_url` 发送
- 后来发现应该在 `prompt` 中添加角色名称，不发送额外参数

**最终解决方案**:
```dart
String finalPrompt = _promptController.text;

if (_selectedCharacterId != null && _isFromMaterialLibrary) {
  // 仅将角色名称添加到提示词
  finalPrompt = '$_selectedMaterialName, $finalPrompt';
  // 不传递 inputReference 或 characterUrl
}

await apiService.createVideo(
  prompt: finalPrompt,  // 包含角色名称的提示词
  inputReference: null,
  characterUrl: null,
);
```

### 5. 视频列表排序

**问题**: 新生成的成功视频出现在失败视频后面

**解决方案**: 统一排序所有状态的视频
```dart
List<Map<String, dynamic>> allItems = [
  ...activeTasks.map((t) => {
    'type': 'active',
    'data': t,
    'timestamp': DateTime.parse(t['createdAt']),
  }),
  ...failedTasks.map((t) => {
    'type': 'failed',
    'data': t,
    'timestamp': DateTime.parse(t['failedAt']),
  }),
  ...videos.map((v) => {
    'type': 'completed',
    'data': v,
    'timestamp': DateTime.parse(v['createdAt']),
  }),
];

// 按时间倒序排序（最新在前）
allItems.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
```

### 6. FFmpeg 打包

**挑战**: Windows 应用需要 FFmpeg，但不能要求用户手动安装

**解决方案**:
1. 下载 FFmpeg 静态构建版本
2. 放置在 `windows/ffmpeg/` 目录
3. CMake 配置在构建时复制
4. 运行时动态查找打包的 FFmpeg

**好处**:
- 开箱即用
- 无需用户配置
- 跨版本兼容

### 7. 文件隐藏失败

**挑战**: Inno Setup 的 `attrib +h` 命令不可靠

**解决方案**: 使用 Windows API 直接设置文件属性
- 调用 `SetFileAttributesW` kernel32.dll 函数
- 在安装后 (`ssPostInstall`) 立即执行
- 添加日志跟踪

---

## 📊 数据流图

### 图像生成数据流
```
┌─────────────┐
│   用户输入   │ 提示词、参数
└──────┬──────┘
       │
       ▼
┌─────────────────────┐
│  _generateImage()   │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│   ApiService        │ HTTP POST
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│  远程 API 服务器     │ 处理请求
└──────┬──────────────┘
       │
       ├─ 同步响应
       │    │
       │    ▼
       │  ┌──────────────┐
       │  │ 返回图像 URL  │
       │  └──────┬───────┘
       │         │
       └─ 异步响应
            │
            ▼
       ┌──────────────┐
       │ 返回 task_id  │
       └──────┬───────┘
              │
              ▼
       ┌─────────────┐
       │  轮询任务    │ 每3秒查询
       └──────┬──────┘
              │
              ▼
       ┌─────────────┐
       │ 获取图像 URL │
       └──────┬──────┘
              │
       ┌──────▼───────┐
       │  下载图像     │
       └──────┬───────┘
              │
       ┌──────▼───────┐
       │  保存本地     │
       └──────┬───────┘
              │
       ┌──────▼───────┐
       │  更新 Hive    │
       └──────┬───────┘
              │
       ┌──────▼───────┐
       │   更新 UI     │
       └──────────────┘
```

---

## 🔄 状态管理流程

### ChangeNotifier 模式
```dart
// 1. Provider定义
class WorkspaceState extends ChangeNotifier {
  int _currentWorkspaceIndex = 0;
  
  int get currentWorkspaceIndex => _currentWorkspaceIndex;
  
  void setWorkspace(int index) {
    _currentWorkspaceIndex = index;
    notifyListeners();  // 通知所有监听者
  }
}

// 2. 在main.dart中提供
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => WorkspaceState()),
    ChangeNotifierProvider(create: (_) => AutoModeProvider()),
    ChangeNotifierProvider(create: (_) => VideoTaskManager()),
  ],
  child: MyApp(),
)

// 3. 在Widget中消费
class WorkspaceSelector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // 监听变化并自动重建
    return Consumer<WorkspaceState>(
      builder: (context, state, child) {
        return Row(
          children: [
            _buildButton('创作', 0, state),
            _buildButton('绘图', 1, state),
            _buildButton('视频', 2, state),
            _buildButton('素材', 3, state),
            _buildButton('自动', 4, state),
          ],
        );
      },
    );
  }
  
  Widget _buildButton(String label, int index, WorkspaceState state) {
    return TextButton(
      onPressed: () => state.setWorkspace(index),
      child: Text(label),
      style: TextButton.styleFrom(
        backgroundColor: state.currentWorkspaceIndex == index
            ? Colors.blue
            : Colors.transparent,
      ),
    );
  }
}
```

---

## 🚀 性能优化策略

### 1. 懒加载
```dart
// 仅在需要时加载大数据
class MaterialsLibrary extends StatefulWidget {
  @override
  _MaterialsLibraryState createState() => _MaterialsLibraryState();
}

class _MaterialsLibraryState extends State<MaterialsLibrary>
    with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => false;  // 不保持状态，节省内存
  
  List<Material>? _materials;
  
  @override
  void initState() {
    super.initState();
    _loadMaterials();  // 首次显示时加载
  }
  
  Future<void> _loadMaterials() async {
    _materials = await MaterialsManager.loadAll();
    setState(() {});
  }
}
```

### 2. 分页和虚拟滚动
```dart
// 使用ListView.builder进行懒渲染
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) {
    // 仅渲染可见的items
    return _buildItem(items[index]);
  },
)
```

### 3. 图像缓存策略
```dart
// 自定义图像缓存
class CachedImageProvider extends ImageProvider<CachedImageProvider> {
  final String imagePath;
  
  @override
  Future<CachedImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<CachedImageProvider>(this);
  }
  
  @override
  ImageStreamCompleter load(CachedImageProvider key, DecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
    );
  }
  
  Future<Codec> _loadAsync(CachedImageProvider key, DecoderCallback decode) async {
    // 检查缓存
    final cached = await _cache.get(key.imagePath);
    if (cached != null) {
      return decode(cached);
    }
    
    // 加载并缓存
    final bytes = await File(key.imagePath).readAsBytes();
    await _cache.put(key.imagePath, bytes);
    return decode(bytes);
  }
}
```

---

## 📝 代码规范和最佳实践

### 1. 命名约定
```dart
// 类名：PascalCase
class AutoModeProvider {}

// 变量和函数：camelCase
String userName = 'John';
void loadUserData() {}

// 常量：lowerCamelCase
const apiTimeout = Duration(seconds: 30);

// 私有成员：前缀 _
class MyClass {
  String _privateMember;
  String publicMember;
}
```

### 2. 文件组织
```dart
// 导入顺序
import 'dart:io';  // Dart SDK
import 'dart:async';

import 'package:flutter/material.dart';  // Flutter
import 'package:provider/provider.dart';  // 外部包

import '../models/user.dart';  // 项目内部
import '../services/api_service.dart';
```

### 3. 错误处理
```dart
Future<void> fetchData() async {
  try {
    final data = await apiService.getData();
    // 处理数据
  } on HttpException catch (e) {
    // 处理网络错误
    print('HTTP Error: $e');
  } on FormatException catch (e) {
    // 处理格式错误
    print('Format Error: $e');
  } catch (e, stackTrace) {
    // 处理其他错误
    print('Error: $e');
    print('Stack: $stackTrace');
  } finally {
    // 清理资源
  }
}
```

### 4. Async/Await 模式
```dart
// ✅ 好的做法
Future<String> fetchUserName() async {
  final response = await http.get(userUrl);
  final data = jsonDecode(response.body);
  return data['name'];
}

// ❌ 避免
Future<String> fetchUserName() {
  return http.get(userUrl).then((response) {
    return jsonDecode(response.body)['name'];
  });
}
```

---

## 🔍 调试和日志

### 日志系统
```dart
class AppLogger {
  static void info(String message) {
    print('[INFO] ${DateTime.now()}: $message');
  }
  
  static void error(String message, [dynamic error, StackTrace? stack]) {
    print('[ERROR] ${DateTime.now()}: $message');
    if (error != null) print('Error: $error');
    if (stack != null) print('Stack: $stack');
  }
  
  static void debug(String message) {
    if (kDebugMode) {
      print('[DEBUG] ${DateTime.now()}: $message');
    }
  }
}

// 使用
AppLogger.info('Starting image generation...');
AppLogger.error('Failed to load image', e, stackTrace);
```

### 性能监控
```dart
Future<T> measurePerformance<T>(
  String operation,
  Future<T> Function() task,
) async {
  final stopwatch = Stopwatch()..start();
  try {
    final result = await task();
    stopwatch.stop();
    AppLogger.debug('$operation completed in ${stopwatch.elapsedMilliseconds}ms');
    return result;
  } catch (e) {
    stopwatch.stop();
    AppLogger.error('$operation failed after ${stopwatch.elapsedMilliseconds}ms', e);
    rethrow;
  }
}

// 使用
final images = await measurePerformance(
  'Image generation',
  () => apiService.generateImage(prompt, model, size),
);
```

---

## 📚 依赖库列表

### pubspec.yaml 关键依赖
```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # 状态管理
  provider: ^6.1.1
  
  # 本地存储
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  shared_preferences: ^2.2.2
  path_provider: ^2.1.1
  
  # 网络请求
  http: ^1.1.2
  
  # 后端服务
  supabase_flutter: ^2.0.0
  
  # UI增强
  google_fonts: ^6.2.1
  
  # 文件处理
  file_picker: ^6.1.1
  image_picker: ^1.0.5
  path: ^1.9.0
  
  # 环境变量
  flutter_dotenv: ^5.1.0
  
  # 并发控制
  pool: ^1.5.1
  
  # 其他
  package_info_plus: ^5.0.1
  url_launcher: ^6.2.2
  video_player: ^2.8.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.6
  hive_generator: ^2.0.1
```

---

## 🎯 未来优化方向

### 1. 架构改进
- **模块化**: 将各工作空间拆分为独立的package
- **依赖注入**: 使用 get_it 或 riverpod 替代 Provider
- **MVVM模式**: 更清晰的业务逻辑分离

### 2. 性能优化
- **增量加载**: 大列表使用分页
- **图像压缩**: 生成缩略图减少内存
- **缓存策略**: 实现多级缓存（内存+磁盘）

### 3. 功能增强
- **批量操作**: 批量删除、导出
- **历史记录**: 操作历史和撤销
- **云同步**: 跨设备同步项目

### 4. 用户体验
- **快捷键**: 添加键盘快捷键
- **拖拽**: 支持文件拖拽导入
- **预览**: 实时预览生成结果

---

## 📖 总结

### 应用特点
1. **功能完整**: 涵盖图像、视频生成和素材管理
2. **架构清晰**: 分层设计，职责明确
3. **可扩展**: 插件化API，易于添加新提供商
4. **用户友好**: 直观的UI和工作流

### 技术亮点
1. **Flutter跨平台**: 一套代码支持多平台
2. **并发控制**: 队列和Isolate优化性能
3. **持久化**: Hive和SharedPreferences双重保障
4. **FFmpeg集成**: 打包视频处理能力

### 适用场景
- AI内容创作
- 批量素材生成
- 创意工作流自动化
- 个人或小团队使用

---

**最后更新**: 2026-01-20  
**版本**: v1.0.0  
**维护者**: Xinghe Development Team
