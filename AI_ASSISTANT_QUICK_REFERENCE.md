# 星河 AI 助手快速参考指南

> 本文档为 AI 助手提供快速上手信息，完整技术文档请参考 `COMPLETE_SYSTEM_DOCUMENTATION.md`

---

## 🎯 项目快照

**应用名称**: 星河（Xinghe）  
**类型**: AI创作桌面工具  
**框架**: Flutter 3.x  
**平台**: Windows (主), macOS, Linux  
**主要功能**: AI图像生成、AI视频生成、素材管理、自动化创作

---

## 📂 核心文件位置

```
lib/main.dart                      # 主UI和4个工作空间
lib/logic/auto_mode_provider.dart  # 自动模式逻辑
lib/services/api_service.dart      # API核心服务
lib/services/ffmpeg_service.dart   # 视频处理
lib/models/                        # 数据模型
installer/xinghe-setup.iss         # Windows安装程序
```

---

## 🏗️ 架构速览

```
UI Layer (main.dart)
    ↓
State Management (Provider)
    ↓
Services (ApiService, FFmpegService)
    ↓
Data (Hive, SharedPreferences, APIs)
```

---

## 🎨 5个工作空间

### 1. 创作空间（Creation）
- 展示所有生成的图像和视频
- GridView布局，maxCrossAxisExtent: 200

### 2. 绘图空间（Drawing）
- 输入提示词生成图像
- 支持多种图像模型
- GridView: maxCrossAxisExtent: 150

### 3. 视频空间（Video）
- 输入提示词生成视频
- 可选择素材库角色或上传参考图
- **关键逻辑**: 使用已上传角色时，仅在prompt中添加角色名，不传inputReference

### 4. 素材库（Materials）
- 管理角色、场景、物品素材
- 支持上传到Supabase获取characterId
- GridView: maxCrossAxisExtent: 150

### 5. 自动模式（Auto）
- 4步骤自动化创作流程
- 角色生成 → 剧本生成 → 分镜设计 → 媒体生成

---

## 🔑 关键代码模式

### API 调用模式
```dart
// 图像生成
final response = await apiService.generateImage(
  model: 'dall-e-3',
  prompt: '提示词',
  size: '1024x1024',
);

// 视频生成（无参考图）
final response = await apiService.createVideo(
  model: 'sora-2',
  prompt: '@角色名, 动作描述',
  size: '1280x720',
  seconds: 15,
);

// 视频生成（带本地参考图）
final response = await apiService.createVideo(
  model: 'sora-2',
  prompt: '动作描述',
  size: '1280x720',
  seconds: 15,
  inputReference: File('path/to/image.png'),
);
```

### 状态管理模式
```dart
// Provider定义
class MyState extends ChangeNotifier {
  int _value = 0;
  int get value => _value;
  
  void update(int newValue) {
    _value = newValue;
    notifyListeners();
  }
}

// 消费
Consumer<MyState>(
  builder: (context, state, child) {
    return Text('${state.value}');
  },
)
```

### 数据持久化
```dart
// Hive
final box = await Hive.openBox('box_name');
await box.put('key', value);
final value = box.get('key');

// SharedPreferences
final prefs = await SharedPreferences.getInstance();
await prefs.setString('key', 'value');
final value = prefs.getString('key');
```

---

## ⚠️ 已知问题和解决方案

### 1. 视频生成角色参数
**问题**: 使用素材库已上传角色时发送错误参数  
**解决**: 仅在prompt添加角色名（`@username, 动作`），不传inputReference或characterUrl

**代码位置**: `main.dart` - `_VideoSpaceWidgetState._generateVideo()` (约13278-13323行)

### 2. ParentDataWidget 错误
**问题**: 嵌套Expanded导致布局冲突  
**解决**: 移除冗余Expanded，调整mainAxisSize

### 3. 文件隐藏失败
**问题**: Inno Setup的attrib命令不可靠  
**解决**: 使用Windows API (`SetFileAttributesW`) 直接设置

**代码位置**: `installer/xinghe-setup.iss` - `[Code]` section

### 4. 视频列表排序
**问题**: 新视频未按时间排序  
**解决**: 统一排序所有状态（active, failed, completed）

**代码位置**: `main.dart` - `_VideoListWidget` (约14693-14760行)

---

## 🔧 常见修改任务

### 添加新的图像模型
```dart
// 1. 在 ApiConfigManager 添加模型选项
final imageModels = ['dall-e-3', 'midjourney', '新模型'];

// 2. 在 ApiService.generateImage() 添加逻辑
if (model == '新模型') {
  // 特殊处理
}
```

### 修改GridView布局
```dart
// 找到对应空间的GridView.builder
SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 150,  // 修改这个值
  crossAxisSpacing: 16,
  mainAxisSpacing: 16,
  childAspectRatio: 0.78,
)
```

### 添加新的素材类型
```dart
// 1. 在 MaterialType enum 添加
enum MaterialType {
  character,
  scene,
  prop,
  newType,  // 新增
}

// 2. 在素材库UI添加tab
TabBar(tabs: [
  Tab(text: '角色'),
  Tab(text: '场景'),
  Tab(text: '物品'),
  Tab(text: '新类型'),  // 新增
])
```

---

## 📊 数据模型速查

### 生成媒体 (Hive: 'generated_media')
```json
{
  "images": [
    {
      "path": "本地路径",
      "prompt": "提示词",
      "model": "模型名",
      "createdAt": "ISO8601时间"
    }
  ],
  "videos": [...]
}
```

### 素材 (Hive: 'materials')
```json
{
  "characters": [
    {
      "name": "名称",
      "path": "本地路径",
      "characterId": "上传后ID",
      "uploadedUrl": "远程URL",
      "createdAt": "时间"
    }
  ],
  "scenes": [...],
  "props": [...]
}
```

### 视频任务 (SharedPreferences: 'video_tasks')
```json
{
  "active": [
    {
      "taskId": "任务ID",
      "prompt": "提示词",
      "createdAt": "创建时间",
      "progress": 0-100
    }
  ],
  "failed": [...]
}
```

---

## 🚀 构建和部署

### 开发构建
```bash
flutter run -d windows
```

### Release构建
```bash
flutter clean
flutter pub get
flutter build windows --release

# 输出: build/windows/x64/runner/Release/
```

### 创建安装程序
```powershell
cd installer
.\build_installer.ps1

# 输出: installer/output/xinghe-setup-1.0.0.exe
```

---

## 🔍 调试技巧

### 查看API请求
```dart
// 在 ApiService 的请求方法添加
print('=== API Request ===');
print('URL: $url');
print('Headers: $headers');
print('Body: $body');
print('===================');
```

### 查看状态变化
```dart
// 在 Provider 的 notifyListeners() 前添加
print('[StateUpdate] $_currentState -> $_newState');
notifyListeners();
```

### 查看Hive数据
```dart
final box = await Hive.openBox('box_name');
print('Hive data: ${box.toMap()}');
```

---

## 📝 代码风格

- **类名**: PascalCase (`AutoModeProvider`)
- **变量/函数**: camelCase (`generateImage`)
- **私有成员**: 前缀 `_` (`_currentProject`)
- **常量**: lowerCamelCase (`apiTimeout`)

---

## 🎯 优化建议（为AI助手）

### 性能优化
1. 图像缓存管理（清理策略）
2. 大列表分页加载
3. Isolate处理重任务

### 代码质量
1. 提取重复代码为Mixin或工具函数
2. 统一错误处理
3. 添加单元测试

### 用户体验
1. 加载状态指示
2. 错误提示优化
3. 快捷键支持

---

## 📞 关键联系人/资源

- **主代码**: `lib/main.dart` (约15000行)
- **API文档**: 参考 `COMPLETE_SYSTEM_DOCUMENTATION.md`
- **安装问题**: 参考 `installer/最终安装指南.txt`

---

**快速开始提示**: 
1. 阅读 `COMPLETE_SYSTEM_DOCUMENTATION.md` 了解完整架构
2. 查看 `lib/main.dart` 理解UI结构
3. 查看 `lib/services/api_service.dart` 理解API调用

**最后更新**: 2026-01-20
