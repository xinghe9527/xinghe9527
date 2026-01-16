# Supabase 配置说明

## 📋 迁移完成

项目已成功从阿里云 OSS 迁移到 Supabase Storage。

## 🔧 配置步骤

### 1. 创建 Supabase 项目

1. 访问 [Supabase](https://supabase.com) 并登录
2. 创建一个新项目（或使用现有项目）
3. 等待项目初始化完成

### 2. 创建 Storage Bucket

1. 在 Supabase Dashboard 中，进入 **Storage** 页面
2. 点击 **New bucket** 创建新存储桶
3. 设置存储桶名称：`characters-video`
4. 设置为 **Public bucket**（公开访问，用于获取视频 URL）
5. 点击 **Create bucket**

### 3. 获取 API 密钥

1. 在 Supabase Dashboard 中，进入 **Project Settings** -> **API**
2. 复制以下信息：
   - **Project URL**（例如：`https://xxxxx.supabase.co`）
   - **anon/public key**（anon 密钥）

### 4. 配置环境变量

1. 在项目根目录创建 `.env` 文件（如果不存在）
2. 填入你的 Supabase 配置：

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here
```

**⚠️ 重要：**
- `.env` 文件已添加到 `.gitignore`，不会被提交到 Git
- 请妥善保管你的 API 密钥，不要泄露

### 5. 运行项目

```bash
flutter pub get
flutter run
```

## 📝 代码变更说明

### 已修改的文件：

1. **pubspec.yaml**
   - 添加了 `supabase_flutter: ^2.5.6`
   - 添加了 `flutter_dotenv: ^5.1.0`
   - 添加了 `.env` 到 assets

2. **lib/main.dart**
   - 添加了 Supabase 和 dotenv 的导入
   - 在 `main()` 函数中初始化 Supabase

3. **lib/services/sora_api_service.dart**
   - 移除了阿里云 OSS 相关代码
   - 使用 Supabase Storage 替代 OSS 上传
   - 方法名保持 `uploadVideoToOss()` 以保持兼容性

### 主要变化：

- ✅ 不再需要阿里云 OSS 的 AccessKey 和 SecretKey
- ✅ 使用 Supabase 的认证系统（更安全）
- ✅ 文件上传到 Supabase Storage
- ✅ 自动获取公共 URL

## 🐛 故障排除

### 问题：无法加载 .env 文件

**解决方案：**
- 确保 `.env` 文件在项目根目录
- 确保 `pubspec.yaml` 中已添加 `.env` 到 assets
- 重新运行 `flutter pub get`

### 问题：上传失败，提示权限错误

**解决方案：**
1. 检查 Storage bucket 是否设置为 Public
2. 在 Supabase Dashboard -> Storage -> Policies 中检查权限策略
3. 确保 anon key 有上传权限

### 问题：无法获取公共 URL

**解决方案：**
- 确保 bucket 设置为 Public
- 检查文件路径是否正确
- 查看控制台日志获取详细错误信息

## 📚 相关文档

- [Supabase Storage 文档](https://supabase.com/docs/guides/storage)
- [Supabase Flutter SDK](https://supabase.com/docs/reference/dart/introduction)
