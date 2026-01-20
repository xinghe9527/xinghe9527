# 星河（Xinghe）- AI 助手文档索引

> 欢迎！本文档帮助AI助手快速了解星河项目的全部信息

---

## 🚀 快速开始

### 5分钟了解项目
1. **什么是星河?** - AI驱动的创作工具，支持图像、视频生成和素材管理
2. **技术栈?** - Flutter 3.x, Dart, Windows桌面应用
3. **核心功能?** - 5个工作空间：创作、绘图、视频、素材库、自动模式
4. **主要文件?** - `lib/main.dart` (约15000行主代码)

### 最关键的3个文档
1. **`AI_ASSISTANT_QUICK_REFERENCE.md`** ⭐⭐⭐
   - 最快上手
   - 关键代码模式
   - 常见任务

2. **`COMPLETE_SYSTEM_DOCUMENTATION.md`** ⭐⭐⭐
   - 完整技术文档
   - 详细架构说明
   - 所有功能模块

3. **`PROJECT_HISTORY_AND_STATUS.md`** ⭐⭐
   - 已解决的问题
   - 当前状态
   - 未来方向

---

## 📚 文档导航

### 📖 技术文档

#### 1. AI_ASSISTANT_QUICK_REFERENCE.md
**用途**: 快速参考指南  
**内容**:
- 项目快照
- 核心文件位置
- 5个工作空间概览
- 关键代码模式
- 已知问题速查
- 常见修改任务

**适合**:
- ✅ 首次了解项目
- ✅ 快速查找信息
- ✅ 解决常见问题

#### 2. COMPLETE_SYSTEM_DOCUMENTATION.md
**用途**: 完整技术文档  
**内容**:
- 详细架构设计
- 所有功能模块
- 数据模型详解
- API集成方案
- 性能优化策略
- 代码规范

**适合**:
- ✅ 深入理解架构
- ✅ 添加新功能
- ✅ 重构和优化

**章节导航**:
1. 项目概述 (基本信息)
2. 技术架构 (技术栈、架构模式)
3. 文件结构 (目录说明)
4. 核心功能模块 (详细功能)
5. 数据模型 (数据结构)
6. 关键业务逻辑 (代码实现)
7. 配置和环境 (环境变量)
8. Windows打包部署 (构建流程)
9. 技术挑战 (问题和解决方案)
10. 数据流图 (流程图)
11. 性能优化 (优化策略)
12. 代码规范 (最佳实践)

#### 3. PROJECT_HISTORY_AND_STATUS.md
**用途**: 项目历史和状态  
**内容**:
- 项目时间线
- 已解决的重大问题（6个）
- UI/UX改进历史
- 打包部署进化
- 当前状态和计划
- 技术债务

**适合**:
- ✅ 了解项目演进
- ✅ 理解设计决策
- ✅ 避免重复问题

---

### 📋 安装和部署文档

#### installer/最终安装指南.txt
**用途**: Windows安装程序使用指南  
**内容**:
- 安装步骤
- 文件隐藏原理
- 故障排除
- 工具文件说明

#### installer/QUICK_START.md
**用途**: 3步创建安装程序  
**内容**:
- 下载Inno Setup
- 构建安装程序
- 分发给用户

---

### 🔧 工具和脚本

#### installer/xinghe-setup.iss
**用途**: Inno Setup安装脚本  
**关键特性**:
- Windows API隐藏文件
- 管理员权限检查
- 快捷方式创建

#### installer/build_installer.ps1
**用途**: 自动构建安装程序  
**功能**:
- 检查环境
- 编译安装程序
- 提示测试

#### installer/complete_cleanup.ps1
**用途**: 完整清理旧版本  
**功能**:
- 删除所有安装目录
- 清理注册表
- 清理快捷方式
- 停止进程

#### installer/manual_hide_files.ps1
**用途**: 手动隐藏文件  
**使用场景**: 安装后文件仍可见时

#### installer/check_hidden_files.ps1
**用途**: 验证文件隐藏状态  
**输出**: 每个文件的隐藏状态

---

## 🎯 使用场景指南

### 场景1: 我是新的AI助手，第一次接触这个项目
**推荐顺序**:
1. 阅读 `AI_ASSISTANT_QUICK_REFERENCE.md` (5-10分钟)
2. 浏览 `COMPLETE_SYSTEM_DOCUMENTATION.md` 的项目概述部分 (5分钟)
3. 查看 `lib/main.dart` 的文件结构 (了解代码组织)

**关键理解**:
- 5个工作空间的作用
- API调用模式
- 数据持久化方式

### 场景2: 用户报告了一个Bug
**步骤**:
1. 在 `PROJECT_HISTORY_AND_STATUS.md` 搜索类似问题
2. 查看 `AI_ASSISTANT_QUICK_REFERENCE.md` 的已知问题部分
3. 参考 `COMPLETE_SYSTEM_DOCUMENTATION.md` 的故障排除章节

**常见Bug**:
- ParentDataWidget错误 → 查看已解决问题#1
- 视频生成失败 → 查看已解决问题#2
- 文件未隐藏 → 查看已解决问题#5

### 场景3: 用户想添加新功能
**步骤**:
1. 理解现有架构（`COMPLETE_SYSTEM_DOCUMENTATION.md` 架构部分）
2. 找到相似功能的实现（搜索主文档）
3. 参考代码规范（主文档代码规范章节）
4. 查看技术债务（`PROJECT_HISTORY_AND_STATUS.md`）

**示例任务**:
- 添加新模型 → 参考 `AI_ASSISTANT_QUICK_REFERENCE.md` 常见修改任务
- 修改UI布局 → 参考主文档UI设计章节
- 优化性能 → 参考主文档性能优化章节

### 场景4: 用户遇到安装问题
**步骤**:
1. 查看 `installer/最终安装指南.txt`
2. 引导使用清理脚本 `complete_cleanup.ps1`
3. 检查文件隐藏状态 `check_hidden_files.ps1`
4. 必要时手动隐藏 `manual_hide_files.ps1`

**关键检查**:
- 是否以管理员身份安装？
- 是否使用默认路径？
- 文件是否隐藏？

### 场景5: 代码审查或重构
**关注点**:
1. `PROJECT_HISTORY_AND_STATUS.md` 的技术债务部分
2. `COMPLETE_SYSTEM_DOCUMENTATION.md` 的代码规范
3. 主文档的优化建议章节

**优先级**:
- 高: main.dart拆分、错误处理统一
- 中: 状态管理改进、缓存策略
- 低: 代码文档、性能监控

---

## 🔍 快速搜索指南

### 按关键词查找

#### 功能相关
- **图像生成**: `AI_ASSISTANT_QUICK_REFERENCE.md` → API调用模式
- **视频生成**: `COMPLETE_SYSTEM_DOCUMENTATION.md` → 核心功能模块 → 视频空间
- **素材管理**: 主文档 → 素材库章节
- **自动模式**: 主文档 → 自动模式 Provider

#### 技术问题
- **布局错误**: `PROJECT_HISTORY_AND_STATUS.md` → 已解决问题 #1
- **API错误**: `COMPLETE_SYSTEM_DOCUMENTATION.md` → API错误处理
- **性能优化**: 主文档 → 性能优化策略
- **数据存储**: 主文档 → 数据持久化

#### 代码位置
- **主UI**: `lib/main.dart`
- **API服务**: `lib/services/api_service.dart`
- **FFmpeg**: `lib/services/ffmpeg_service.dart`
- **自动模式**: `lib/logic/auto_mode_provider.dart`

---

## 📊 文档关系图

```
README_FOR_AI.md (您在这里)
    │
    ├─→ AI_ASSISTANT_QUICK_REFERENCE.md
    │   ├─ 项目快照
    │   ├─ 核心文件
    │   ├─ 代码模式
    │   └─ 常见任务
    │
    ├─→ COMPLETE_SYSTEM_DOCUMENTATION.md
    │   ├─ 完整架构
    │   ├─ 所有功能
    │   ├─ 数据模型
    │   └─ 实现细节
    │
    └─→ PROJECT_HISTORY_AND_STATUS.md
        ├─ 时间线
        ├─ 已解决问题
        ├─ 当前状态
        └─ 未来计划
```

---

## ⚡ 高频问题速查

### Q1: 如何修改图像生成的默认尺寸?
**A**: 
1. 文件: `lib/main.dart` - `_DrawingSpaceWidgetState`
2. 查找: `selectedSize` 变量
3. 修改: 尺寸选择列表或默认值

### Q2: 如何添加新的API提供商?
**A**:
1. 创建: `lib/services/providers/new_provider.dart`
2. 继承: `BaseApiProvider`
3. 实现: `generateText`, `generateImage`, `createVideo`
4. 注册: 在 `ApiManager` 中添加

### Q3: 视频生成报错怎么办?
**A**:
1. 检查: 是否使用已上传角色（有characterId）
2. 确认: prompt中是否包含角色名（`@username`）
3. 验证: inputReference和characterUrl应为null
4. 参考: `PROJECT_HISTORY_AND_STATUS.md` 已解决问题 #2

### Q4: 如何优化大图列表的性能?
**A**:
1. 参考: `COMPLETE_SYSTEM_DOCUMENTATION.md` 性能优化章节
2. 实现: 图像缓存策略
3. 使用: `ListView.builder` 懒加载
4. 限制: 图像缓存大小

### Q5: 安装后文件未隐藏?
**A**:
1. 确认: 是否以管理员身份安装
2. 检查: 是否使用默认路径
3. 运行: `installer/check_hidden_files.ps1`
4. 修复: `installer/manual_hide_files.ps1`

---

## 🎓 学习路径

### 初级（了解项目）
**时间**: 1-2小时  
**目标**: 理解项目结构和核心功能

1. 阅读 `AI_ASSISTANT_QUICK_REFERENCE.md`
2. 浏览 `lib/main.dart` 代码结构
3. 运行应用，体验5个工作空间
4. 查看已解决问题（`PROJECT_HISTORY_AND_STATUS.md`）

### 中级（深入理解）
**时间**: 3-5小时  
**目标**: 掌握架构设计和实现细节

1. 完整阅读 `COMPLETE_SYSTEM_DOCUMENTATION.md`
2. 研究关键模块实现
   - API服务 (`lib/services/api_service.dart`)
   - 自动模式 (`lib/logic/auto_mode_provider.dart`)
3. 理解数据流和状态管理
4. 查看技术挑战和解决方案

### 高级（贡献代码）
**时间**: 持续学习  
**目标**: 能够修改、优化和扩展项目

1. 研究技术债务和优化方向
2. 实践代码规范和最佳实践
3. 阅读Flutter和Dart官方文档
4. 贡献代码或提出改进建议

---

## 🛠️ 开发工具推荐

### 必备
- **Flutter SDK**: 3.x
- **IDE**: VS Code / Android Studio
- **版本控制**: Git

### 推荐
- **数据库查看**: Hive Admin
- **API测试**: Postman / Insomnia
- **性能分析**: Flutter DevTools

---

## 📞 获取帮助

### 文档内查找
1. 使用IDE的搜索功能（Ctrl+F / Cmd+F）
2. 搜索关键词
3. 查看相关章节

### 代码内查找
1. 使用IDE的全局搜索（Ctrl+Shift+F / Cmd+Shift+F）
2. 搜索函数名、类名或变量名
3. 查看实现和调用

### 外部资源
- Flutter官方文档: https://flutter.dev/docs
- Dart语言指南: https://dart.dev/guides
- Provider文档: https://pub.dev/packages/provider

---

## ✅ 检查清单

### 理解项目前
- [ ] 已阅读 `AI_ASSISTANT_QUICK_REFERENCE.md`
- [ ] 了解5个工作空间的功能
- [ ] 知道主要代码文件位置
- [ ] 理解API调用模式

### 修改代码前
- [ ] 已查看相关功能的实现
- [ ] 理解现有架构设计
- [ ] 查看已知问题避免重复
- [ ] 遵循代码规范

### 部署应用前
- [ ] 完成本地测试
- [ ] 检查FFmpeg是否正确打包
- [ ] 验证文件隐藏功能
- [ ] 测试安装和卸载流程

---

## 🎯 总结

### 核心文档（必读）
1. **AI_ASSISTANT_QUICK_REFERENCE.md** - 快速上手
2. **COMPLETE_SYSTEM_DOCUMENTATION.md** - 完整参考
3. **PROJECT_HISTORY_AND_STATUS.md** - 历史和现状

### 关键代码文件
1. **lib/main.dart** - 主UI和工作空间
2. **lib/services/api_service.dart** - API服务
3. **lib/logic/auto_mode_provider.dart** - 自动模式
4. **lib/services/ffmpeg_service.dart** - 视频处理

### 重要工具脚本
1. **installer/build_installer.ps1** - 构建安装程序
2. **installer/complete_cleanup.ps1** - 清理工具
3. **installer/manual_hide_files.ps1** - 手动隐藏

---

**欢迎探索星河项目！如有任何问题，请参考相应的文档章节。** 🚀

**最后更新**: 2026-01-20  
**版本**: v1.0.0  
**维护者**: Xinghe Development Team
