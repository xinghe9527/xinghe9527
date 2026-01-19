# FFmpeg 打包指南

## 📋 概述

本应用已配置为将 FFmpeg 打包到可执行文件中，实现**开箱即用**，无需用户手动安装 FFmpeg。

## 🚀 快速开始

### 步骤 1：下载 FFmpeg

**方法 A：使用脚本自动下载（推荐）**

在项目根目录运行以下 PowerShell 脚本：

```powershell
# 下载 FFmpeg 官方 Windows 构建版本（精简版，约 70MB）
$ffmpegUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
$outputZip = ".\ffmpeg.zip"
$extractPath = ".\ffmpeg_temp"
$targetPath = ".\windows\ffmpeg"

Write-Host "正在下载 FFmpeg..." -ForegroundColor Green
Invoke-WebRequest -Uri $ffmpegUrl -OutFile $outputZip

Write-Host "正在解压..." -ForegroundColor Green
Expand-Archive -Path $outputZip -DestinationPath $extractPath -Force

Write-Host "正在复制可执行文件..." -ForegroundColor Green
# 查找 ffmpeg.exe 并复制到目标位置
$ffmpegExe = Get-ChildItem -Path $extractPath -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
if ($ffmpegExe) {
    Copy-Item -Path $ffmpegExe.FullName -Destination "$targetPath\ffmpeg.exe" -Force
    Write-Host "✅ FFmpeg 已成功复制到 $targetPath" -ForegroundColor Green
} else {
    Write-Host "❌ 未找到 ffmpeg.exe" -ForegroundColor Red
}

# 清理临时文件
Remove-Item -Path $outputZip -Force
Remove-Item -Path $extractPath -Recurse -Force
Write-Host "✅ 临时文件已清理" -ForegroundColor Green
Write-Host "完成！您现在可以构建应用程序了。" -ForegroundColor Cyan
```

**方法 B：手动下载**

1. 访问 [FFmpeg 官方下载页面](https://github.com/BtbN/FFmpeg-Builds/releases)
2. 下载 `ffmpeg-master-latest-win64-gpl.zip`
3. 解压 ZIP 文件
4. 找到 `bin/ffmpeg.exe`
5. 将 `ffmpeg.exe` 复制到 `windows/ffmpeg/` 目录

### 步骤 2：验证文件

确保文件结构正确：

```
xinghe/
├── windows/
│   ├── ffmpeg/
│   │   └── ffmpeg.exe  ✅ 必须存在
│   └── CMakeLists.txt
├── lib/
│   └── services/
│       └── ffmpeg_service.dart
└── pubspec.yaml
```

### 步骤 3：构建应用程序

```bash
# 安装依赖
flutter pub get

# 构建 Windows 应用（Release 版本）
flutter build windows --release

# 或构建 Debug 版本
flutter build windows
```

### 步骤 4：验证打包

构建完成后，检查输出目录：

```
build/windows/x64/runner/Release/
├── xinghe.exe
├── ffmpeg.exe  ✅ 应该自动复制到这里
├── flutter_windows.dll
└── data/
    └── flutter_assets/
```

## 🔍 工作原理

### 1. 目录结构

- **源文件位置**：`windows/ffmpeg/ffmpeg.exe`
- **构建后位置**：`build/windows/x64/runner/Release/ffmpeg.exe`
- **安装后位置**：与 `xinghe.exe` 在同一目录

### 2. 自动检测机制

`FFmpegService` 会自动：

1. **首先**检查可执行文件同级目录的 `ffmpeg.exe`（打包版本）
2. **其次**尝试使用系统 PATH 中的 `ffmpeg`（回退方案）

```dart
static Future<String> _getFFmpegPath() async {
  // 1. 尝试使用打包的 FFmpeg
  if (Platform.isWindows) {
    final exePath = Platform.resolvedExecutable;
    final exeDir = path.dirname(exePath);
    final bundledFFmpeg = path.join(exeDir, 'ffmpeg.exe');
    
    if (await File(bundledFFmpeg).exists()) {
      return bundledFFmpeg; // ✅ 使用打包版本
    }
  }
  
  // 2. 回退到系统 FFmpeg
  return 'ffmpeg';
}
```

### 3. CMake 配置

`windows/CMakeLists.txt` 配置了自动复制：

```cmake
set(FFMPEG_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ffmpeg")
if(EXISTS "${FFMPEG_DIR}/ffmpeg.exe")
  install(FILES "${FFMPEG_DIR}/ffmpeg.exe"
    DESTINATION "${CMAKE_INSTALL_PREFIX}"
    COMPONENT Runtime)
endif()
```

## 📦 文件大小

- **FFmpeg 可执行文件**：约 100-120 MB
- **应用总大小**：增加约 100 MB
- **压缩后（ZIP）**：约 40 MB

## ✅ 优点

1. ✨ **开箱即用**：用户无需安装 FFmpeg
2. 🔒 **版本锁定**：避免系统 FFmpeg 版本不兼容
3. 📦 **独立部署**：应用程序自包含所有依赖
4. 🛡️ **回退机制**：如果打包失败，自动使用系统 FFmpeg

## ⚠️ 注意事项

### 1. 许可证

FFmpeg 使用 **GPL 许可证**。如果您的应用是商业软件或闭源软件：

- ✅ **GPL 版本**：可以使用，但您的应用也必须开源（GPL）
- ✅ **LGPL 版本**：可以动态链接，无需开源
- ❌ **不要**：静态链接 GPL 版本到闭源软件

**解决方案**：
- 下载 **LGPL 版本**的 FFmpeg
- 或保持动态调用（当前方案）

### 2. Git 忽略

FFmpeg 文件较大（~100MB），建议添加到 `.gitignore`：

```gitignore
# FFmpeg 可执行文件（太大，不提交到仓库）
windows/ffmpeg/ffmpeg.exe
assets/ffmpeg/
```

### 3. 发布准备

**方法 1：随发布包分发（推荐）**
```bash
# 构建完成后，整个 build/windows/x64/runner/Release/ 目录打包
# 包含 ffmpeg.exe
```

**方法 2：安装脚本**
```powershell
# 创建一个安装脚本，在首次运行时自动下载 FFmpeg
```

## 🔧 故障排除

### 问题 1：构建时警告 "FFmpeg not found"

**原因**：`windows/ffmpeg/ffmpeg.exe` 不存在

**解决**：按照 [步骤 1](#步骤-1下载-ffmpeg) 下载 FFmpeg

### 问题 2：运行时报错 "未找到 FFmpeg"

**检查**：
```powershell
# 1. 检查文件是否存在
ls build/windows/x64/runner/Release/ffmpeg.exe

# 2. 查看日志输出
# 应该显示: [FFmpegService] ✅ 找到打包的 FFmpeg: xxx
```

**解决**：
- 重新构建：`flutter clean && flutter build windows --release`
- 手动复制：`copy windows\ffmpeg\ffmpeg.exe build\windows\x64\runner\Release\`

### 问题 3：FFmpeg 执行失败

**检查**：
```powershell
# 测试 FFmpeg 是否正常工作
cd build/windows/x64/runner/Release
.\ffmpeg.exe -version
```

**可能原因**：
- FFmpeg 文件损坏：重新下载
- 缺少依赖：下载完整版 FFmpeg（包含所有 DLL）

## 📚 参考资源

- [FFmpeg 官方网站](https://ffmpeg.org/)
- [FFmpeg Windows 构建版本](https://github.com/BtbN/FFmpeg-Builds)
- [FFmpeg 许可证说明](https://ffmpeg.org/legal.html)

## 🎯 总结

✅ **已完成的配置**：
- [x] FFmpeg 目录结构
- [x] CMake 打包配置
- [x] FFmpegService 自动检测
- [x] pubspec.yaml 更新

🚀 **下一步操作**：
1. 下载 `ffmpeg.exe` 到 `windows/ffmpeg/`
2. 运行 `flutter pub get`
3. 运行 `flutter build windows --release`
4. 测试上传角色功能

**现在您的应用可以开箱即用，无需用户安装 FFmpeg！** ✨
