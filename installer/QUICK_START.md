# ⚡ 快速开始 - 3 步创建安装程序

## 📥 步骤 1：下载 Inno Setup（1 分钟）

访问并下载：
```
https://jrsoftware.org/isdl.php
```

**选择**：Inno Setup 6.x (Unicode)  
**文件大小**：约 3 MB  
**安装时间**：30 秒

---

## 🔨 步骤 2：构建安装程序（2 分钟）

在 PowerShell 中运行：

```powershell
cd d:\dov\load\xinghe\installer
.\build_installer.ps1
```

脚本会自动：
1. ✅ 检查 Inno Setup 是否已安装
2. ✅ 检查 Release 构建是否存在
3. ✅ 编译安装程序
4. ✅ 提示测试安装

---

## 🎉 步骤 3：获取安装程序

完成后，在 `installer\output\` 目录找到：

```
xinghe-setup-1.0.0.exe  (80-100 MB)
```

**这就是您的最终安装程序！**

---

## 📦 分发给用户

用户操作：
1. 双击 `xinghe-setup-1.0.0.exe`
2. 点击"下一步"完成安装
3. 从开始菜单启动"星河"

**用户看到的**：
- ✅ 专业的安装向导
- ✅ 只有主程序图标
- ✅ 看不到 Flutter 和 DLL 文件

---

## 🎯 完成！

您现在有：
- ✅ 专业的安装程序（`.exe`）
- ✅ 隐藏了技术细节
- ✅ 一键安装体验

**分发这个 `.exe` 文件给用户即可！**
