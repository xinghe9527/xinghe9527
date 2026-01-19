# FFmpeg 目录

## 📁 目录用途

此目录用于存放打包到应用程序中的 FFmpeg 可执行文件。

## 📥 下载 FFmpeg

### 方法 1：自动下载（推荐）⭐

在项目根目录运行：

```powershell
.\download_ffmpeg.ps1
```

脚本会自动：
1. 下载最新的 FFmpeg Windows 构建版本
2. 解压并提取 `ffmpeg.exe`
3. 复制到此目录
4. 清理临时文件

### 方法 2：手动下载

1. 访问 [FFmpeg 下载页面](https://github.com/BtbN/FFmpeg-Builds/releases)
2. 下载 `ffmpeg-master-latest-win64-gpl.zip`
3. 解压找到 `bin/ffmpeg.exe`
4. 复制 `ffmpeg.exe` 到此目录

## ✅ 完成后

此目录应包含：

```
windows/ffmpeg/
├── ffmpeg.exe  ← 必须存在（约 100-120 MB）
└── README.md   ← 本文件
```

## 🚀 构建应用

```bash
flutter build windows --release
```

FFmpeg 会自动打包到：
```
build/windows/x64/runner/Release/ffmpeg.exe
```

## 📝 注意事项

- ⚠️ `ffmpeg.exe` 已添加到 `.gitignore`（文件太大）
- 📦 每个开发者需要自行下载
- 🔄 使用 `download_ffmpeg.ps1` 脚本最简单

## 🔗 相关文档

- [FFMPEG_BUNDLING_GUIDE.md](../../FFMPEG_BUNDLING_GUIDE.md) - 完整打包指南
- [FFmpeg 官方网站](https://ffmpeg.org/)
