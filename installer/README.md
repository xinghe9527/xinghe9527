# 星河安装程序创建指南

## 📦 概述

使用 Inno Setup 创建专业的 Windows 安装程序，隐藏 Flutter 框架和技术细节。

## 🚀 快速开始

### 步骤 1：安装 Inno Setup

1. 访问 [Inno Setup 官网](https://jrsoftware.org/isdl.php)
2. 下载 **Inno Setup 6** (推荐使用 Unicode 版本)
3. 安装到默认位置：`C:\Program Files (x86)\Inno Setup 6\`

### 步骤 2：构建应用（如果还没有）

```bash
cd d:\dov\load\xinghe
flutter build windows --release
```

### 步骤 3：创建安装程序

**方法 A：使用自动脚本（推荐）**

```powershell
cd d:\dov\load\xinghe\installer
.\build_installer.ps1
```

**方法 B：手动编译**

1. 打开 Inno Setup Compiler
2. 打开文件：`xinghe-setup.iss`
3. 点击 "Compile" (编译)
4. 等待完成

### 步骤 4：获取安装程序

编译完成后，在 `installer\output\` 目录找到：

```
xinghe-setup-1.0.0.exe  (约 80-100 MB)
```

---

## 🎯 安装程序特性

### ✅ 用户体验

- **专业安装向导**：现代化的安装界面
- **自动创建快捷方式**：开始菜单 + 桌面（可选）
- **一键卸载**：在"控制面板">"程序和功能"中卸载
- **隐藏技术细节**：DLL 和数据文件设置为隐藏属性

### ✅ 技术优势

- **完整打包**：包含所有依赖（Flutter、FFmpeg）
- **自动安装**：无需用户配置
- **支持 Windows 10/11**：兼容现代 Windows 系统
- **数字签名支持**：可添加代码签名（需要证书）

---

## 📁 安装后的目录结构

```
C:\Program Files\星河\
├── xinghe.exe                  ← 用户看到的主程序
├── flutter_windows.dll         ← 隐藏属性
├── ffmpeg.exe                  ← 隐藏属性
├── *.dll                       ← 其他插件（隐藏）
└── data\                       ← 应用资源（隐藏）
    └── flutter_assets\
```

**用户体验**：
- 通过开始菜单/桌面快捷方式启动
- 不会直接接触安装目录
- 看不到技术细节文件（除非"显示隐藏文件"）

---

## 🎨 自定义安装程序

### 修改应用信息

编辑 `xinghe-setup.iss`：

```pascal
#define MyAppName "星河"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Xinghe Studio"
```

### 添加自定义图标

替换文件：
```
windows\runner\resources\app_icon.ico
```

### 修改安装目录

```pascal
DefaultDirName={autopf}\{#MyAppName}
```

可改为：
```pascal
DefaultDirName={autopf}\YourCompanyName\{#MyAppName}
```

---

## 🔧 高级功能

### 1. 数字签名（推荐商业应用）

添加到 `[Setup]` 部分：

```pascal
SignTool=signtool sign /f "your-certificate.pfx" /p "password" /t http://timestamp.digicert.com $f
```

### 2. 静默安装

用户可使用：
```cmd
xinghe-setup-1.0.0.exe /VERYSILENT /NORESTART
```

### 3. 自定义安装页面

可在脚本中添加：
- 许可协议页面
- 组件选择页面
- 自定义配置页面

---

## 📦 分发安装程序

### 文件信息

```
文件名: xinghe-setup-1.0.0.exe
大小: 约 80-100 MB
类型: Windows 可执行文件
```

### 分发方式

1. **直接下载**：上传到网站/网盘
2. **更新服务器**：配合自动更新功能
3. **软件商店**：Microsoft Store（需额外打包）

---

## ⚠️ 注意事项

### 文件路径

- 所有路径使用相对路径（`..`）
- 确保 Release 构建存在
- 图标文件必须存在

### 许可证

- 包含 Flutter (BSD License)
- 包含 FFmpeg (GPL License)
- 确保遵守开源许可证

### 测试

安装前务必测试：
1. ✅ 安装过程是否顺利
2. ✅ 快捷方式是否正常
3. ✅ 程序能否启动
4. ✅ FFmpeg 功能是否正常
5. ✅ 卸载是否完整

---

## 🐛 故障排除

### 问题 1：找不到 Inno Setup

**解决**：
- 确认已安装 Inno Setup 6
- 检查安装路径是否为默认路径
- 或修改脚本中的路径

### 问题 2：编译失败

**检查**：
- `xinghe-setup.iss` 语法是否正确
- Release 构建是否存在
- 所有引用的文件是否存在

### 问题 3：安装后无法启动

**原因**：
- DLL 文件缺失
- 文件权限问题

**解决**：
- 检查所有 DLL 是否已包含
- 以管理员权限安装

---

## 📚 参考资源

- [Inno Setup 官方文档](https://jrsoftware.org/ishelp/)
- [Inno Setup 示例](https://jrsoftware.org/ishelp/index.php?topic=samples)
- [Flutter Windows 部署](https://docs.flutter.dev/deployment/windows)

---

## 🎊 完成！

现在您有了一个专业的 Windows 安装程序！

**用户体验**：
- ✅ 双击安装，一键完成
- ✅ 看不到 Flutter 技术细节
- ✅ 专业的软件形象

**开发优势**：
- ✅ 简化分发流程
- ✅ 统一安装体验
- ✅ 易于版本管理

---

_创建日期：2026-01-20_
_版本：1.0.0_
