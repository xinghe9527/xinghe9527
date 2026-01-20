# 星河项目历史和当前状态

> 本文档记录项目的发展历程、已解决的问题、当前状态和未来方向

---

## 📅 项目时间线

### Phase 1: 核心功能开发 (初期)
- ✅ 实现基础UI框架（5个工作空间）
- ✅ 集成API服务（LLM、图像、视频）
- ✅ 实现图像生成功能
- ✅ 实现视频生成功能
- ✅ 素材库基础功能

### Phase 2: 功能增强 (中期)
- ✅ 自动模式开发
- ✅ 素材上传到Supabase
- ✅ 角色素材与视频生成集成
- ✅ FFmpeg视频处理集成

### Phase 3: 用户体验优化 (当前)
- ✅ 统一图标样式（删除图标 → 垃圾桶）
- ✅ 统一图片显示尺寸
- ✅ 优化图片复制功能（右键复制）
- ✅ 视频空间素材选择分类
- ✅ 视频列表按时间排序
- ✅ 字体优化（Google Fonts - Noto Sans SC）

### Phase 4: 打包和部署 (当前)
- ✅ FFmpeg打包到应用
- ✅ Windows安装程序创建
- ✅ 文件隐藏功能（使用Windows API）
- 🔄 清理和优化安装流程

---

## 🐛 已解决的重大问题

### 1. ParentDataWidget 布局错误
**时间**: 2026-01-19  
**症状**: 切换工作空间时控制台报错，应用可能卡死  
**原因**: 多层嵌套的 `Expanded` 导致 Flutter 布局冲突

**解决方案**:
```dart
// 之前：三层Expanded
Row(children: [
  Expanded(
    child: Column(children: [
      Expanded(  // ❌ 冲突
        child: Container(),
      ),
    ]),
  ),
])

// 修复后：移除内层Expanded
Row(children: [
  Expanded(
    child: Column(children: [
      Container(),  // ✅ 正常
    ]),
  ),
])
```

**影响文件**:
- `main.dart` - `ResponsiveInputWrapper`
- `main.dart` - `_VideoSpaceWidgetState`
- `main.dart` - `_buildSectionCard`
- `main.dart` - `_VideoListWidget._buildCard`

---

### 2. 视频生成角色参数错误
**时间**: 2026-01-19  
**症状**: 使用素材库已上传角色生成视频时报错 `base64 decode failed`

**问题演进**:
1. **第一版**: 将 `_selectedMaterialName` (如 "@username") 作为 `character_url` 发送
   - 结果：API期望URL，收到用户名，base64解码失败

2. **第二版**: 将 `_selectedCharacterId` 作为 `character_url` 发送
   - 结果：API期望视频URL（用于创建角色），收到字符ID，仍然失败

3. **最终方案**: 
   - 在 `prompt` 中添加角色名：`"@username, 动作描述"`
   - **不传递** `character_url` 或 `inputReference`
   - API根据prompt中的 `@username` 识别已创建的角色

**代码修复** (`main.dart` 约13278-13323行):
```dart
String finalPrompt = _promptController.text;

if (_selectedCharacterId != null && _isFromMaterialLibrary) {
  // 仅将角色名称添加到提示词
  if (_selectedMaterialName != null && _selectedMaterialName!.isNotEmpty) {
    finalPrompt = '$_selectedMaterialName, $finalPrompt';
  }
  // 不传递 characterUrl 或 inputReference
}

final response = await apiService.createVideo(
  model: apiConfigManager.videoModel,
  prompt: finalPrompt,
  size: '${selectedSize.width}x${selectedSize.height}',
  seconds: seconds,
  inputReference: null,  // 明确设置为null
  characterUrl: null,    // 明确设置为null
);
```

**教训**: 
- 仔细阅读API文档
- `character_url` 是用于**创建角色**的视频URL
- 使用已存在的角色只需在prompt中引用

---

### 3. 视频列表排序问题
**时间**: 2026-01-19  
**症状**: 新生成的成功视频排在失败视频后面

**原因**: 三个列表（active, failed, completed）独立显示，未统一排序

**解决方案** (`main.dart` 约14693-14760行):
```dart
// 收集所有items
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

// 按时间倒序排序
allItems.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));

// 使用switch渲染不同类型
itemBuilder: (context, index) {
  final item = allItems[index];
  switch (item['type']) {
    case 'active':
      return _GeneratingVideoCardWidget(task: item['data']);
    case 'failed':
      return _FailedVideoCardWidget(task: item['data']);
    case 'completed':
      return _VideoCardWidget(video: item['data']);
  }
}
```

**影响**:
- 添加 `createdAt` 到 `VideoTaskManager.addTask()`
- 添加 `failedAt` 到 `VideoTaskManager.removeTask()`
- 确保所有videos有 `createdAt` 字段

---

### 4. FFmpeg打包问题
**时间**: 2026-01-19-20  
**症状**: 用户需要手动安装FFmpeg才能使用视频处理功能

**解决方案**:
1. 下载FFmpeg静态构建
2. 放置在 `windows/ffmpeg/ffmpeg.exe`
3. CMake配置在构建时复制
4. 运行时动态查找打包的FFmpeg

**实现** (`lib/services/ffmpeg_service.dart`):
```dart
static Future<String> _getFFmpegPath() async {
  if (Platform.isWindows) {
    final exePath = Platform.resolvedExecutable;
    final exeDir = path.dirname(exePath);
    final bundledFFmpeg = path.join(exeDir, 'ffmpeg.exe');
    
    if (await File(bundledFFmpeg).exists()) {
      print('[FFmpegService] ✅ 找到打包的 FFmpeg: $bundledFFmpeg');
      return bundledFFmpeg;
    }
  }
  
  // 回退到系统FFmpeg
  return 'ffmpeg';
}
```

**CMake配置** (`windows/CMakeLists.txt`):
```cmake
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/ffmpeg/ffmpeg.exe"
        DESTINATION "${INSTALL_BUNDLE_LIB_DIR}")
```

**结果**: 应用开箱即用，无需用户配置

---

### 5. 文件隐藏功能失败
**时间**: 2026-01-20  
**症状**: 安装后Flutter DLL文件仍然可见，暴露技术细节

**尝试方案1 (失败)**: 
```pascal
[Run]
Filename: "{cmd}"; Parameters: "/c attrib +h file.dll"; Flags: runhidden
```
- **问题**: 命令在Inno Setup中不可靠执行

**最终方案 (成功)**:
```pascal
[Code]
// 调用Windows API
function SetFileAttributes(lpFileName: String; dwFileAttributes: DWORD): BOOL;
  external 'SetFileAttributesW@kernel32.dll stdcall';

procedure HideFileOrFolder(FileName: String);
var
  Attrs: DWORD;
begin
  Attrs := GetFileAttributes(FileName);
  if Attrs <> $FFFFFFFF then
  begin
    // 添加隐藏属性 ($00000002)
    SetFileAttributes(FileName, Attrs or $00000002);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    AppPath := ExpandConstant('{app}');
    HideFileOrFolder(AppPath + '\flutter_windows.dll');
    HideFileOrFolder(AppPath + '\ffmpeg.exe');
    // ... 其他文件
  end;
end;
```

**关键点**:
- 必须以管理员身份安装
- 使用默认安装路径 `C:\Program Files\星河\`
- 直接调用Windows API更可靠

---

### 6. 卸载残留问题
**时间**: 2026-01-20  
**症状**: 多次安装测试导致多个残留目录

**解决方案**: 创建完整清理脚本
```powershell
# complete_cleanup.ps1
# 清理所有可能的安装目录
$possiblePaths = @(
    "${env:ProgramFiles}\星河",
    "D:\星河", "D:\星河2", "D:\星河3",
    # ... 更多路径
)

foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        # 移除所有文件属性
        Get-ChildItem $path -Recurse -Force | ForEach-Object {
            $_.Attributes = 'Normal'
        }
        # 删除目录
        Remove-Item $path -Recurse -Force
    }
}

# 清理注册表、快捷方式、应用数据
# ...
```

**额外工具**:
- `manual_hide_files.ps1`: 安装后手动隐藏文件
- `check_hidden_files.ps1`: 验证隐藏状态

---

## 🎨 UI/UX 改进历史

### 图标统一化
**变更**: 删除图标从 ❌ 改为 🗑️（`Icons.delete_outline`）

**影响位置**:
- 创作空间作品卡片
- 绘图空间生成结果
- 视频空间视频卡片
- 素材库素材卡片

### 图片尺寸统一
**变更**: 所有GridView使用一致的尺寸配置

**配置**:
```dart
// 创作空间
maxCrossAxisExtent: 200

// 绘图/视频/素材空间
maxCrossAxisExtent: 150
childAspectRatio: 0.78
```

### 复制功能优化
**之前**: 图片右下角有复制图标按钮  
**现在**: 
- 移除右下角图标
- 点击图片放大
- 右键显示"复制图片"选项
- 跨平台支持（Windows/macOS）

**实现**:
```dart
GestureDetector(
  onSecondaryTapDown: (details) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'copy',
          child: Text('复制图片'),
        ),
      ],
    ).then((value) {
      if (value == 'copy') {
        _copyImageToClipboard(imagePath);
      }
    });
  },
  child: Image.file(File(imagePath)),
)
```

### 素材选择分类
**变更**: 视频空间选择素材时，按类型分Tab显示

**之前**: 所有素材混在一起  
**现在**: 
- Tab 1: 角色素材（优先）
- Tab 2: 场景素材
- Tab 3: 物品素材

**实现**:
```dart
class _MaterialPickerDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(tabs: [
            Tab(text: '角色素材'),
            Tab(text: '场景素材'),
            Tab(text: '物品素材'),
          ]),
          Expanded(
            child: TabBarView(
              children: [
                _buildMaterialGrid(characters),
                _buildMaterialGrid(scenes),
                _buildMaterialGrid(props),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

### 字体优化
**变更**: 使用Google Fonts - Noto Sans SC

**配置** (`main.dart`):
```dart
ThemeData(
  fontFamily: GoogleFonts.notoSansSc().fontFamily,
  textTheme: GoogleFonts.notoSansSCTextTheme(),
)
```

**依赖** (`pubspec.yaml`):
```yaml
dependencies:
  google_fonts: ^6.2.1
```

---

## 📦 打包和部署进化

### 版本1: ZIP包 (弃用)
**优点**: 简单直接  
**缺点**:
- 用户看到所有文件（包括DLL）
- 需要手动创建快捷方式
- 卸载需要手动删除
- 暴露Flutter技术栈

### 版本2: Inno Setup (当前)
**优点**:
- 专业安装界面
- 自动创建快捷方式
- 控制面板卸载
- 隐藏技术文件
- 打包FFmpeg

**关键文件**:
- `installer/xinghe-setup.iss`: 安装脚本
- `installer/build_installer.ps1`: 构建工具
- `installer/complete_cleanup.ps1`: 清理工具
- `installer/manual_hide_files.ps1`: 手动隐藏工具

**安装流程**:
1. 用户以管理员身份运行 `xinghe-setup-1.0.0.exe`
2. 选择安装路径（默认 `C:\Program Files\星河\`）
3. 复制文件到安装目录
4. 执行 `CurStepChanged(ssPostInstall)`:
   - 调用Windows API隐藏DLL
   - 隐藏FFmpeg
   - 隐藏data文件夹
5. 创建开始菜单和桌面快捷方式
6. 完成

**用户体验**:
- 看到: `xinghe.exe`, `unins000.exe`
- 看不到: DLL文件, FFmpeg, data文件夹（除非显示隐藏文件）

---

## 🔄 当前状态

### ✅ 已完成
1. **核心功能**: 图像、视频生成，素材管理，自动模式
2. **API集成**: 支持多模型，插件化架构
3. **数据持久化**: Hive + SharedPreferences
4. **视频处理**: FFmpeg集成并打包
5. **UI优化**: 统一尺寸、图标、字体
6. **打包部署**: Windows安装程序，文件隐藏

### 🔄 进行中
1. **安装测试**: 确保文件隐藏功能在所有场景生效
2. **性能优化**: 图像缓存策略
3. **用户反馈**: 收集并处理bug报告

### 📋 待优化
1. **性能**: 
   - 大图列表加载优化
   - 内存使用优化
   - 启动速度优化

2. **功能**:
   - 批量操作（删除、导出）
   - 历史记录和撤销
   - 快捷键支持
   - 拖拽上传

3. **代码质量**:
   - 单元测试覆盖
   - 集成测试
   - 代码文档化
   - 性能监控

4. **跨平台**:
   - macOS打包和测试
   - Linux打包和测试

---

## 🎯 下一步计划

### 短期 (1-2周)
1. ✅ 完成Windows安装程序优化
2. 性能分析和优化
3. 添加错误日志收集
4. 用户反馈收集机制

### 中期 (1-2月)
1. macOS和Linux支持
2. 云同步功能（项目和素材）
3. 批量操作和导出
4. 插件市场（第三方API提供商）

### 长期 (3-6月)
1. Web版本开发
2. 协作功能（多人项目）
3. AI模型训练集成
4. 社区和分享功能

---

## 📊 技术债务

### 高优先级
1. **main.dart 文件过大** (约15000行)
   - 建议: 拆分为多个文件
   - 每个工作空间独立文件

2. **错误处理不统一**
   - 建议: 统一错误处理器
   - 更好的用户提示

3. **缺少单元测试**
   - 建议: 添加核心逻辑测试
   - API mock测试

### 中优先级
1. **状态管理可以改进**
   - 考虑: Riverpod或Bloc
   - 更细粒度的状态控制

2. **图像缓存策略**
   - 实现: 多级缓存
   - 自动清理策略

3. **日志系统**
   - 添加: 结构化日志
   - 错误追踪和上报

### 低优先级
1. **代码文档**
   - 添加: 函数和类注释
   - API文档生成

2. **性能监控**
   - 集成: 性能分析工具
   - 用户体验指标

---

## 📝 开发笔记

### 重要决策记录

**决策1: 为什么使用Hive而不是SQLite?**
- Hive更轻量，适合桌面应用
- 纯Dart实现，无需native依赖
- 性能足够满足需求

**决策2: 为什么main.dart这么大?**
- 快速原型开发
- UI紧密耦合，拆分复杂度高
- 计划重构，但优先级较低

**决策3: 为什么不使用Bloc或Riverpod?**
- Provider足够简单
- 学习成本低
- 满足当前需求

**决策4: FFmpeg打包策略**
- 选择静态链接版本（单一exe）
- 避免依赖系统FFmpeg
- 提供开箱即用体验

**决策5: 文件隐藏使用Windows API**
- 命令行工具不可靠
- API调用更直接
- 需要管理员权限

---

## 🤝 贡献指南

### 代码提交
1. 遵循现有代码风格
2. 添加必要的注释
3. 更新相关文档
4. 测试修改的功能

### Bug报告
1. 提供复现步骤
2. 附上错误日志
3. 说明环境信息（OS版本、Flutter版本）

### 功能建议
1. 描述使用场景
2. 说明预期效果
3. 考虑实现难度

---

## 📚 相关文档

- `COMPLETE_SYSTEM_DOCUMENTATION.md`: 完整技术文档
- `AI_ASSISTANT_QUICK_REFERENCE.md`: 快速参考
- `ARCHITECTURE.md`: 架构文档（如果有）
- `installer/最终安装指南.txt`: 安装说明

---

**最后更新**: 2026-01-20  
**当前版本**: v1.0.0  
**项目状态**: 活跃开发中
