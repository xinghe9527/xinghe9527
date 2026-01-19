# ProviderSelector 组件使用指南

## 概述

`ProviderSelector` 是一个通用的供应商选择器组件，支持快速切换 LLM、图片、视频服务的供应商。

## 功能特性

✅ **三种服务类型支持**: LLM / 图片 / 视频  
✅ **自动配置检测**: 未配置时自动弹出配置对话框  
✅ **双模式显示**: 标准模式和紧凑模式  
✅ **主题色适配**: 可自定义颜色以适配不同界面  
✅ **完整的错误处理**: 包含日志和用户友好的错误提示  
✅ **状态管理**: 自动同步 ApiManager 和 ApiConfigManager  

## 基本使用

### 1. 导入组件

```dart
import 'package:xinghe/widgets/provider_selector.dart';
```

### 2. 标准模式

```dart
// LLM 服务供应商选择器
ProviderSelector(
  type: ProviderType.llm,
  color: Colors.blue,
  onProviderChanged: () {
    print('LLM 供应商已切换');
  },
)

// 图片服务供应商选择器
ProviderSelector(
  type: ProviderType.image,
  color: Colors.pink,
)

// 视频服务供应商选择器
ProviderSelector(
  type: ProviderType.video,
  color: Colors.purple,
)
```

**显示效果**: 
```
[💬 图标] LLM: GeekNow ▼
```

### 3. 紧凑模式

```dart
ProviderSelector(
  type: ProviderType.llm,
  compact: true,
  color: Colors.blue,
)
```

**显示效果**:
```
[💬 GeekNow ▼]
```

## 完整示例

### 在标题栏中使用

```dart
AppBar(
  title: Text('设置'),
  actions: [
    // LLM 供应商选择器（紧凑模式）
    ProviderSelector(
      type: ProviderType.llm,
      compact: true,
      color: Theme.of(context).primaryColor,
      onProviderChanged: () {
        // 刷新页面或执行其他操作
        setState(() {});
      },
    ),
    SizedBox(width: 12),
    
    // 图片供应商选择器（紧凑模式）
    ProviderSelector(
      type: ProviderType.image,
      compact: true,
    ),
    SizedBox(width: 12),
  ],
)
```

### 在设置面板中使用

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text('服务供应商配置', style: TextStyle(fontSize: 18)),
    SizedBox(height: 16),
    
    // LLM 供应商（标准模式）
    ProviderSelector(
      type: ProviderType.llm,
      color: Color(0xFF5DADE2),
      onProviderChanged: _refreshConfig,
    ),
    SizedBox(height: 12),
    
    // 图片供应商（标准模式）
    ProviderSelector(
      type: ProviderType.image,
      color: Color(0xFFEC7063),
      onProviderChanged: _refreshConfig,
    ),
    SizedBox(height: 12),
    
    // 视频供应商（标准模式）
    ProviderSelector(
      type: ProviderType.video,
      color: Color(0xFF9B59B6),
      onProviderChanged: _refreshConfig,
    ),
  ],
)
```

### 在卡片中使用

```dart
Card(
  child: ListTile(
    leading: Icon(Icons.settings),
    title: Text('LLM 服务配置'),
    trailing: ProviderSelector(
      type: ProviderType.llm,
      compact: true,
      onProviderChanged: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('LLM 供应商已更新')),
        );
      },
    ),
  ),
)
```

## API 参数说明

### 必需参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `type` | `ProviderType` | 服务类型：`llm` / `image` / `video` |

### 可选参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `color` | `Color?` | 根据类型自动选择 | 主题色，用于图标和高亮 |
| `compact` | `bool` | `false` | 是否使用紧凑模式 |
| `onProviderChanged` | `VoidCallback?` | `null` | 供应商切换后的回调 |

### 默认颜色

- **LLM**: `#5DADE2` (蓝色)
- **Image**: `#EC7063` (粉色)
- **Video**: `#9B59B6` (紫色)

## 自动配置对话框

当用户选择一个未配置的供应商时，会自动弹出配置对话框：

```
┌─────────────────────────────────┐
│ 💬 配置 GeekNow                 │
├─────────────────────────────────┤
│ 请配置 LLM 服务的 API 信息       │
│                                  │
│ API Key: [输入框]               │
│ Base URL: [输入框]              │
│                                  │
│         [取消]  [保存]           │
└─────────────────────────────────┘
```

### 配置对话框特性

- ✅ GeekNow 供应商会自动预填充默认 Base URL
- ✅ 输入验证（API Key 和 Base URL 不能为空）
- ✅ 保存后自动更新 ApiConfigManager 和 ApiManager
- ✅ 用户可以取消配置

## 工作流程

### 1. 正常切换流程

```
用户点击下拉框
    ↓
选择新供应商
    ↓
检查是否已配置 ──→ 是 ──→ 直接切换
    ↓
    否
    ↓
弹出配置对话框
    ↓
用户输入 API Key 和 URL
    ↓
保存配置到 ApiConfigManager
    ↓
切换 ApiManager 的对应 Provider
    ↓
触发 onProviderChanged 回调
    ↓
显示成功提示
```

### 2. 取消配置流程

```
用户点击下拉框
    ↓
选择新供应商
    ↓
弹出配置对话框
    ↓
用户点击"取消"
    ↓
保持当前供应商不变
```

## 状态同步

组件会自动同步以下状态：

1. **ApiManager**: 实际执行 API 调用的 Provider
2. **ApiConfigManager**: 持久化的配置信息
3. **SharedPreferences**: 本地存储

```
ProviderSelector
    ↓
同步更新
    ↓
ApiManager._llmProvider (运行时)
ApiConfigManager._selectedLlmProviderId (配置)
SharedPreferences.selected_llm_provider (持久化)
```

## 样式自定义

### 修改图标

```dart
// 在 provider_selector.dart 的 _getIcon() 方法中修改
IconData _getIcon() {
  switch (widget.type) {
    case ProviderType.llm:
      return Icons.psychology;  // 改为大脑图标
    case ProviderType.image:
      return Icons.brush;       // 改为画笔图标
    case ProviderType.video:
      return Icons.movie;       // 改为电影图标
  }
}
```

### 修改显示标签

```dart
// 在 provider_selector.dart 的 _getLabel() 方法中修改
String _getLabel() {
  switch (widget.type) {
    case ProviderType.llm:
      return 'AI 对话';  // 自定义标签
    case ProviderType.image:
      return '图像';
    case ProviderType.video:
      return '影片';
  }
}
```

## 错误处理

组件包含完整的错误处理机制：

### 1. 切换失败

```dart
try {
  _apiManager.setLlmProvider(...);
} catch (e) {
  // 显示错误提示
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('切换供应商失败: $e')),
  );
}
```

### 2. 配置验证

```dart
if (apiKey.isEmpty || baseUrl.isEmpty) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('请填写完整的 API Key 和 Base URL')),
  );
  return;
}
```

### 3. 日志输出

```dart
print('🔄 [ProviderSelector] 切换 LLM 供应商: geeknow');
print('✅ [ProviderSelector] LLM 供应商切换成功');
print('❌ [CRITICAL ERROR CAUGHT] 切换供应商失败: $e');
```

## 最佳实践

### 1. 在多个位置使用

```dart
// 全局设置页面 - 使用标准模式
ProviderSelector(
  type: ProviderType.llm,
  onProviderChanged: () => setState(() {}),
)

// 快速设置面板 - 使用紧凑模式
ProviderSelector(
  type: ProviderType.llm,
  compact: true,
)
```

### 2. 统一颜色主题

```dart
// 定义颜色常量
const kLlmColor = Color(0xFF5DADE2);
const kImageColor = Color(0xFFEC7063);
const kVideoColor = Color(0xFF9B59B6);

// 使用统一颜色
ProviderSelector(
  type: ProviderType.llm,
  color: kLlmColor,
)
```

### 3. 配合状态管理

```dart
class MyPage extends StatefulWidget {
  @override
  _MyPageState createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  void _onProviderChanged() {
    // 刷新依赖供应商配置的数据
    setState(() {
      // 重新加载数据...
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ProviderSelector(
          type: ProviderType.llm,
          onProviderChanged: _onProviderChanged,
        ),
        // 其他 UI 组件...
      ],
    );
  }
}
```

## 未来扩展

### 添加新供应商

```dart
// 1. 在 _getAvailableProviders() 中添加
List<String> _getAvailableProviders() {
  return ['geeknow', 'custom', 'openai', 'anthropic'];  // 新增供应商
}

// 2. 在 _getProviderDisplayName() 中添加显示名称
String _getProviderDisplayName(String providerId) {
  switch (providerId.toLowerCase()) {
    case 'geeknow':
      return 'GeekNow';
    case 'openai':
      return 'OpenAI';  // 新增
    case 'anthropic':
      return 'Anthropic';  // 新增
    default:
      return providerId;
  }
}
```

### 添加供应商图标

```dart
// 为每个供应商显示专属图标
Widget _buildProviderIcon(String providerId) {
  switch (providerId) {
    case 'geeknow':
      return Icon(Icons.flash_on);
    case 'openai':
      return Icon(Icons.psychology);
    case 'anthropic':
      return Icon(Icons.auto_awesome);
    default:
      return Icon(Icons.business);
  }
}
```

## 常见问题

### Q: 如何检查当前使用的供应商？

```dart
final apiManager = ApiManager();
print('LLM 供应商: ${apiManager.llmProviderName}');
print('图片供应商: ${apiManager.imageProviderName}');
print('视频供应商: ${apiManager.videoProviderName}');
```

### Q: 如何手动触发配置对话框？

```dart
// 组件内部方法，无法直接调用
// 建议：通过选择未配置的供应商自动触发
```

### Q: 如何自定义配置对话框？

修改 `_showConfigDialog()` 方法，添加更多输入字段或验证逻辑。

## 总结

`ProviderSelector` 是一个功能完整、易于使用的供应商选择组件：

- ✅ **零配置**: 开箱即用，自动处理配置
- ✅ **灵活布局**: 支持标准和紧凑两种模式
- ✅ **智能提示**: 自动检测配置状态
- ✅ **完整日志**: 便于调试和追踪
- ✅ **用户友好**: 清晰的错误提示和操作反馈

适合在 API 设置页面、快速设置面板、标题栏等多种场景使用！
