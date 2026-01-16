# 自动更新功能实现指南

## 📋 方案选择

对于 Flutter 应用的自动更新，有以下几种方案：

### 方案 1：应用商店自动更新（推荐，最简单）
- **Windows**: 上架到 Microsoft Store，用户打开 Microsoft Store 时会自动更新
- **Android**: 上架到 Google Play Store，用户打开 Play Store 时会自动更新
- **iOS**: 上架到 App Store，用户打开 App Store 时会自动更新

**优点**：
- ✅ 最简单，无需自己维护
- ✅ 用户信任度高
- ✅ 自动处理签名和分发

**缺点**：
- ❌ 需要审核时间
- ❌ 可能需要付费开发者账号

### 方案 2：自建更新服务器（当前实现）
- 使用 Supabase 存储版本信息
- 应用启动时检查版本
- 如果有新版本，提示用户下载并安装

**优点**：
- ✅ 完全控制更新流程
- ✅ 无需审核，立即生效
- ✅ 可以使用已有的 Supabase

**缺点**：
- ❌ 需要自己维护更新服务器
- ❌ Windows 需要处理安装权限

### 方案 3：第三方服务
- Firebase App Distribution
- 其他 OTA 更新服务

## 🔧 当前实现（方案 2：自建更新服务器）

### 1. Supabase 表结构

在 Supabase 中创建一个表来存储版本信息：

**表名**: `app_versions`

**字段**:
- `id` (bigint, primary key, auto increment)
- `version` (text) - 版本号，例如 "1.0.0"
- `build_number` (int) - 构建号，例如 1
- `download_url` (text) - 下载链接（Windows: .exe 或 .msix, Android: .apk, iOS: .ipa）
- `release_notes` (text) - 更新说明
- `force_update` (boolean) - 是否强制更新
- `created_at` (timestamp) - 创建时间

**SQL 创建语句**:
```sql
CREATE TABLE app_versions (
  id BIGSERIAL PRIMARY KEY,
  version TEXT NOT NULL,
  build_number INTEGER NOT NULL,
  download_url TEXT NOT NULL,
  release_notes TEXT,
  force_update BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 插入示例数据
INSERT INTO app_versions (version, build_number, download_url, release_notes, force_update)
VALUES ('1.0.1', 2, 'https://your-domain.com/releases/xinghe-1.0.1.exe', '修复了一些bug，优化了性能', false);
```

### 2. 代码实现

代码已经添加到项目中，包括：
- 版本检查服务 (`lib/services/update_service.dart`)
- 更新对话框 UI
- 自动检查更新逻辑

### 3. 使用步骤

1. **在 Supabase 中创建表**（使用上面的 SQL）
2. **上传新版本文件**到你的服务器或云存储（如 Supabase Storage）
3. **在 Supabase 表中插入新版本记录**
4. **用户打开应用时**，会自动检查更新

### 4. 更新流程

1. 应用启动时检查更新（可选：也可以手动点击"检查更新"）
2. 如果有新版本，显示更新对话框
3. 用户点击"立即更新"，下载新版本
4. 下载完成后，自动打开安装程序
5. 用户安装后，应用自动重启

## 📝 注意事项

1. **Windows 安装权限**：
   - 如果使用 `.exe` 安装包，需要管理员权限
   - 建议使用 `.msix` 格式（Windows 10/11 推荐），支持自动更新且无需管理员权限

2. **版本号管理**：
   - 每次发布新版本时，记得更新 `pubspec.yaml` 中的 `version` 字段
   - 格式：`version: 1.0.1+2`（版本号+构建号）

3. **下载链接**：
   - 确保下载链接可公开访问
   - 建议使用 HTTPS
   - 可以使用 Supabase Storage 存储安装包

4. **强制更新**：
   - 如果设置了 `force_update: true`，用户必须更新才能继续使用
   - 适合重大安全更新或关键 bug 修复

## 🚀 快速开始

1. 在 Supabase Dashboard 中执行上面的 SQL 创建表
2. 上传你的安装包到 Supabase Storage 或你的服务器
3. 在表中插入新版本记录
4. 运行应用，测试更新功能
