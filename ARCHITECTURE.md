# XINGHE 项目架构文档

## 📋 目录
1. [自动模式 (Auto Mode)](#自动模式-auto-mode)
2. [手动模式 (Manual Mode)](#手动模式-manual-mode)
3. [数据存储架构](#数据存储架构)
4. [核心组件](#核心组件)

---

## 🚀 自动模式 (Auto Mode)

### 概述
自动模式是一个**AI 驱动的智能创作工作流**，用户只需输入故事创意，系统会自动完成从剧本到最终视频的全流程生成。

### 工作流程

```
用户输入故事创意
    ↓
[步骤1] 剧本生成 (AutoModeStep.script)
    ↓ (用户点击"继续")
[步骤2] 分镜设计 (AutoModeStep.layout)
    ↓ (用户点击"继续")
[步骤3] 图片生成 (AutoModeStep.image)
    ↓ (批量生成所有场景图片)
[步骤4] 视频合成 (AutoModeStep.video)
    ↓ (批量生成所有场景视频)
[步骤5] 最终合并 (AutoModeStep.finalize)
    ↓ (使用 FFmpeg 合并所有视频)
完成 ✅
```

### 核心文件

#### 1. **状态管理 - `lib/logic/auto_mode_provider.dart`**
- **类**: `AutoModeProvider extends ChangeNotifier`
- **模式**: 单例模式（确保所有实例共享数据）
- **职责**:
  - 管理多个项目（`Map<String, AutoModeProject> _projects`）
  - 处理工作流状态机（`AutoModeStep`）
  - 调用 AI API（剧本、分镜、图片、视频生成）
  - 数据持久化（Hive Box: `xinghe_auto_mode_v2`）
  - 并发任务管理（使用 `package:pool` 限制并发数）

**关键方法**:
```dart
- initialize()                    // 初始化，加载所有项目
- createNewProject()              // 创建新项目（仅由 UI 调用）
- initializeProject(projectId)   // 加载已存在的项目（不创建）
- processInput(projectId, input) // 处理用户输入
- _generateScript()               // 生成剧本
- _generateLayout()               // 生成分镜设计
- _generateAllImages()            // 批量生成图片（并发控制）
- _generateAllVideos()             // 批量生成视频
- deleteProject(projectId)        // 永久删除项目
- forceClearAllData()             // 核清理所有数据
```

#### 2. **数据模型 - `lib/models/auto_mode_project.dart`**
```dart
class AutoModeProject {
  final String id;                    // 项目唯一 ID（时间戳）
  final String title;                 // 项目标题
  AutoModeStep currentStep;           // 当前工作流步骤
  String currentScript;               // 生成的剧本内容
  String currentLayout;                // 生成的分镜设计
  List<SceneModel> scenes;            // 场景列表
  bool isProcessing;                  // 是否正在处理
  String? errorMessage;               // 错误消息
  String? finalVideoUrl;              // 最终合并的视频 URL
  DateTime? lastModified;             // 最后修改时间
  bool hasUnsavedChanges;            // 是否有未保存的更改
  bool isSaving;                      // 是否正在保存
  String? generationStatus;           // 生成状态
}
```

#### 3. **场景模型 - `lib/models/scene_model.dart`**
```dart
class SceneModel {
  final int index;                     // 场景索引
  String script;                       // 场景剧本
  String imagePrompt;                  // 图片生成提示词
  String? imageUrl;                    // 图片 URL
  String? videoUrl;                    // 视频 URL
  String? localImagePath;              // 本地图片路径
  String? localVideoPath;              // 本地视频路径
  SceneStatus status;                  // 场景状态（idle/queueing/processing/success/error）
  String? errorMessage;                // 错误消息
  double imageGenerationProgress;      // 图片生成进度
  double videoGenerationProgress;      // 视频生成进度
}
```

#### 4. **工作流步骤 - `lib/models/auto_mode_step.dart`**
```dart
enum AutoModeStep {
  script,    // 剧本生成
  layout,    // 分镜设计
  image,     // 图片生成
  video,     // 视频合成
  finalize,  // 最终合并
}
```

#### 5. **UI 界面 - `lib/views/auto_mode_screen.dart`**
- **类**: `AutoModeScreen extends StatefulWidget`
- **布局结构**:
  ```
  Scaffold
    └─ Column
        ├─ _buildTopBar()           // 顶部栏（标题、保存状态、删除按钮）
        ├─ _buildStepIndicator()    // 步骤指示器
        ├─ Expanded
        │   └─ _buildContentArea()  // 内容区域（根据步骤显示不同内容）
        └─ _buildInputArea()        // 输入区域（仅在 script/layout 步骤显示）
  ```

**内容区域根据步骤显示**:
- `script/layout`: 聊天式界面，显示剧本/分镜内容，底部输入框
- `image`: 场景卡片列表，每个卡片显示图片生成状态
- `video`: 场景卡片列表，每个卡片显示视频生成状态
- `finalize`: 最终视频预览和下载

### 数据存储
- **存储方式**: Hive Box (`xinghe_auto_mode_v2`)
- **存储键格式**: `project_<projectId>` (例如: `project_1768368504491`)
- **数据格式**: JSON (通过 `AutoModeProject.toJson()` / `fromJson()`)
- **自动保存**: 每次状态变更立即保存，使用 `flush()` 强制写入磁盘

### 并发控制
- **图片生成**: 使用 `package:pool` 限制最多 2 个并发任务
- **任务隔离**: 每个场景的生成任务独立，失败不影响其他场景
- **内存管理**: 使用 `PaintingBinding.instance.imageCache.clear()` 清理图片缓存

---

## 🎨 手动模式 (Manual Mode)

### 概述
手动模式是一个**模块化的创作工作区**，用户可以在不同的面板中独立进行故事、剧本、分镜、角色、场景、物品的生成和编辑。

### 工作流程

```
用户进入 WorkspaceShell
    ↓
选择功能面板（通过导航栏）
    ├─ 故事生成 (StoryGenerationPanel)
    ├─ 剧本生成 (ScriptGenerationPanel)
    ├─ 分镜生成 (StoryboardGenerationPanel)
    ├─ 角色生成 (CharacterGenerationPanel)
    ├─ 场景生成 (SceneGenerationPanel)
    └─ 物品生成 (PropGenerationPanel)
    ↓
在每个面板中独立操作
    - 输入提示词
    - 选择提示词模板
    - 生成内容
    - 编辑和保存
```

### 核心文件

#### 1. **主界面 - `lib/main.dart` (WorkspaceShell)**
- **类**: `WorkspaceShell extends StatefulWidget`
- **布局结构**:
  ```
  Scaffold
    └─ Row (桌面) / Column (移动端)
        ├─ _buildNavigationRail()  // 左侧导航栏（桌面）
        └─ Expanded
            └─ Column
                ├─ _buildTopBar()  // 顶部栏
                └─ Expanded
                    └─ AnimatedSwitcher
                        └─ 当前选中的面板
  ```

**响应式布局**:
- **桌面/平板**: 左侧 `NavigationRail` + 右侧内容区
- **移动端**: 顶部栏 + 内容区 + 底部 `BottomNavigationBar`

#### 2. **功能面板**
所有面板都在 `lib/main.dart` 中定义：

**StoryGenerationPanel** (故事生成)
- 输入框：用户输入故事创意
- 提示词模板选择
- 生成按钮
- 结果显示区域

**ScriptGenerationPanel** (剧本生成)
- 输入框：用户输入或从故事生成结果导入
- 提示词模板选择
- 生成按钮
- 结果显示区域

**StoryboardGenerationPanel** (分镜生成)
- 输入框：用户输入或从剧本导入
- 图片/视频提示词模板选择
- 生成按钮
- 分镜列表（可添加、删除、编辑）

**CharacterGenerationPanel** (角色生成)
- 输入框：角色描述
- "根据剧本生成"按钮（从剧本提取角色）
- "参考风格"功能（图生图）
- 角色卡片列表（可删除、上传、创建角色）

**SceneGenerationPanel** (场景生成)
- 输入框：场景描述
- 提示词模板选择
- 生成按钮
- 场景列表

**PropGenerationPanel** (物品生成)
- 输入框：物品描述
- 提示词模板选择
- 生成按钮
- 物品列表

### 数据存储
- **存储方式**: `SharedPreferences`
- **存储键**: `'projects'` (项目列表元数据)
- **数据格式**: JSON 数组
- **存储内容**: 仅存储项目元数据（标题、日期、类型、模式），不存储具体内容

### 状态管理
- **方式**: 每个面板使用 `StatefulWidget` 的 `setState`
- **数据持久化**: 使用 `SharedPreferences` 保存输入和生成结果
- **提示词模板**: 使用 `PromptStore` 管理

---

## 💾 数据存储架构

### 自动模式存储

**Hive Box**: `xinghe_auto_mode_v2`
- **键格式**: `project_<projectId>`
- **值格式**: `AutoModeProject.toJson()` (Map<String, dynamic>)
- **特点**:
  - 完全隔离自动模式数据
  - 支持多项目并发
  - 自动保存和恢复
  - 使用 `flush()` 确保数据写入磁盘

**SharedPreferences**:
- `last_active_project`: 最后活动的项目 ID

### 手动模式存储

**SharedPreferences**:
- `projects`: 项目列表元数据（JSON 数组）
- `story_input` / `story_output`: 故事生成输入/输出
- `script_input` / `script_output`: 剧本生成输入/输出
- `storyboards`: 分镜列表
- `workspace_characters`: 角色列表
- `character_reference_style_image`: 参考风格图片路径
- `character_reference_style_prompt`: 参考风格提示词
- 各面板的提示词模板选择状态

### 数据隔离

✅ **完全隔离**: 自动模式和手动模式使用不同的存储机制
- 自动模式: Hive Box (`xinghe_auto_mode_v2`)
- 手动模式: SharedPreferences

---

## 🔧 核心组件

### 1. **AutoModeProvider** (自动模式状态管理)
```dart
// 单例模式
factory AutoModeProvider() {
  _instance ??= AutoModeProvider._internal();
  return _instance!;
}

// 核心数据结构
Map<String, AutoModeProject> _projects;  // 项目映射
String? _currentProjectId;              // 当前项目 ID
Box? _projectsBox;                       // Hive Box 实例
```

**关键特性**:
- ✅ 多项目支持（每个项目独立 ID）
- ✅ 状态机管理（5 个工作流步骤）
- ✅ 并发控制（图片生成限制为 2 个并发）
- ✅ 错误隔离（单个场景失败不影响其他场景）
- ✅ 生命周期安全（`_isDisposed` 标志）
- ✅ 零数据丢失（立即保存 + `flush()`）

### 2. **HeavyTaskRunner** (并发任务管理)
```dart
// 位置: lib/services/heavy_task_runner.dart
// 功能: 管理并发任务，限制并发数，使用 Isolate 处理重操作
```

**关键方法**:
- `parseJson()`: 在 Isolate 中解析 JSON
- `decodeBase64()`: 在 Isolate 中解码 Base64
- `writeFile()`: 在 Isolate 中写入文件
- `clearImageCache()`: 清理图片缓存

### 3. **PromptStore** (提示词模板管理)
```dart
// 位置: lib/services/prompt_store.dart
// 功能: 管理提示词模板（故事、剧本、分镜、图片、视频）
```

### 4. **ApiService** (API 调用)
```dart
// 位置: lib/services/api_service.dart
// 功能: 统一的 API 调用接口
// 方法:
- chatCompletion()      // LLM 对话
- generateImage()       // 图片生成
- createVideo()         // 视频生成
- getVideoTask()        // 查询视频任务状态
```

### 5. **FFmpegService** (视频处理)
```dart
// 位置: lib/services/ffmpeg_service.dart
// 功能: 视频合并、格式转换
// 方法:
- concatVideos()        // 合并多个视频
```

---

## 🔄 工作流对比

### 自动模式工作流
```
用户输入 → AI 生成剧本 → AI 生成分镜 → 
批量生成图片 → 批量生成视频 → FFmpeg 合并 → 完成
```
- **特点**: 全自动，用户只需输入和确认
- **数据流**: 线性的，每个步骤依赖上一步的结果
- **状态管理**: 集中式（AutoModeProvider）

### 手动模式工作流
```
用户选择面板 → 输入提示词 → 生成内容 → 
编辑/保存 → 切换到其他面板 → 重复
```
- **特点**: 模块化，用户可自由选择功能
- **数据流**: 并行的，各面板独立
- **状态管理**: 分散式（每个面板独立管理）

---

## 📁 文件结构

```
lib/
├── logic/
│   └── auto_mode_provider.dart      # 自动模式状态管理
├── models/
│   ├── auto_mode_project.dart       # 自动模式项目模型
│   ├── auto_mode_step.dart          # 工作流步骤枚举
│   ├── scene_model.dart             # 场景模型
│   └── scene_status.dart            # 场景状态枚举
├── views/
│   ├── auto_mode_screen.dart        # 自动模式 UI
│   └── prompt_config_view.dart     # 提示词模板管理 UI
├── services/
│   ├── api_service.dart            # API 调用服务
│   ├── api_config_manager.dart     # API 配置管理
│   ├── ffmpeg_service.dart         # FFmpeg 视频处理
│   ├── heavy_task_runner.dart      # 并发任务管理
│   └── prompt_store.dart           # 提示词模板存储
└── main.dart                        # 手动模式 UI 和主应用
```

---

## 🔐 数据安全特性

### 自动模式
- ✅ 项目隔离（每个项目独立 ID）
- ✅ 存储键标准化（`project_<id>`）
- ✅ 自动清理损坏的键（`_purgeCorruptedKeys()`）
- ✅ 立即保存 + 强制刷新（`flush()`）
- ✅ 生命周期安全（防止在 disposed 后操作）

### 手动模式
- ✅ 数据持久化（SharedPreferences）
- ✅ 各面板数据独立存储
- ✅ 提示词模板统一管理

---

## 🎯 关键设计决策

1. **单例模式**: `AutoModeProvider` 使用单例确保数据一致性
2. **项目隔离**: 使用 Map 管理多个项目，每个项目独立 ID
3. **存储隔离**: 自动模式和手动模式使用不同的存储机制
4. **并发控制**: 使用 `package:pool` 限制并发数，防止 UI 冻结
5. **错误隔离**: 单个任务失败不影响其他任务
6. **零数据丢失**: 立即保存 + `flush()` 确保数据写入磁盘
7. **生命周期安全**: 使用 `_isDisposed` 标志防止在 disposed 后操作

---

## 📊 性能优化

### 自动模式
- ✅ 并发任务限制（最多 2 个图片生成任务）
- ✅ Isolate 处理重操作（JSON 解析、Base64 解码、文件写入）
- ✅ 图片缓存管理（定期清理）
- ✅ 防抖保存（避免频繁磁盘写入）

### 手动模式
- ✅ 响应式布局（根据屏幕大小调整）
- ✅ 面板懒加载（只渲染当前选中的面板）
- ✅ 动画过渡（`AnimatedSwitcher`）

---

## 🐛 已知问题和解决方案

### 已解决的问题
1. ✅ **数据丢失**: 使用 `flush()` 强制写入磁盘
2. ✅ **项目重复**: 修复存储键前缀问题
3. ✅ **场景解析失败**: 使用安全的 Map 转换
4. ✅ **并发崩溃**: 使用 `package:pool` 限制并发
5. ✅ **生命周期错误**: 使用 `_isDisposed` 标志
6. ✅ **自动创建项目**: 移除自动创建逻辑，只有用户点击才创建

### 当前状态
- ✅ 自动模式和手动模式完全隔离
- ✅ 数据持久化正常工作
- ✅ 错误处理完善
- ✅ 性能优化到位

---

## 📝 总结

**自动模式**适合快速生成完整视频，用户只需输入创意，系统自动完成所有步骤。

**手动模式**适合精细控制，用户可以在不同面板中独立操作，灵活组合各种功能。

两种模式数据完全隔离，互不干扰，可以同时使用。
