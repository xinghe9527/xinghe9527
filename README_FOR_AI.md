# 星河（Xinghe）技术文档索引 - 给 AI 的快速指南

> 这是一份为 AI 大语言模型准备的快速索引，帮助快速定位所需信息。

---

## 📚 文档导航

### 主要文档

1. **[COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md)** ⭐ **最推荐**
   - **内容**：完整的技术文档，特别详细说明手动模式
   - **适用于**：
     - 想要完整理解项目架构
     - 需要了解手动模式的创作流程
     - 要修改或扩展手动模式功能
   - **篇幅**：约 2000 行，非常详细

2. **[ARCHITECTURE.md](./ARCHITECTURE.md)**
   - **内容**：项目架构概览，侧重自动模式
   - **适用于**：
     - 快速了解双模式架构
     - 理解数据存储架构
     - 查看已解决的问题

3. **[COMPREHENSIVE_GUIDE.md](./COMPREHENSIVE_GUIDE.md)**
   - **内容**：API 架构详解
   - **适用于**：
     - 理解混合供应商架构
     - 添加新的 API 供应商
     - 修改 API 调用逻辑

4. **[AUTO_UPDATE_GUIDE.md](./AUTO_UPDATE_GUIDE.md)**
   - **内容**：自动更新机制
   - **适用于**：修改更新功能

5. **[SUPABASE_SETUP.md](./SUPABASE_SETUP.md)**
   - **内容**：Supabase 配置指南
   - **适用于**：配置文件存储

---

## 🎯 快速查找指南

### 我想了解...

#### 手动模式如何运作？
→ **[COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md#3-手动模式详解重点)**
- 第 3 节：手动模式详解（重点）
- 包含 6 个面板的完整说明
- 数据流和关联方式

#### 手动模式的界面结构？
→ **[COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md#5-界面架构)**
- 第 5 节：界面架构
- WorkspaceShell 详解
- 响应式布局

#### 手动模式的数据如何存储？
→ **[COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md#4-数据模型和关联)**
- 第 4 节：数据模型和关联
- SharedPreferences 键值表
- 全局管理器（Managers）

#### 面板之间如何关联？
→ **[COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md#34-手动模式的数据关联)**
- 第 3.4 节：手动模式的数据关联
- 三种关联方式详解

#### API 架构是怎样的？
→ **[COMPREHENSIVE_GUIDE.md](./COMPREHENSIVE_GUIDE.md#4-api-架构重点)**
- 第 4 节：API 架构（重点）
- 混合供应商架构
- 如何扩展新供应商

#### 如何修改现有功能？
→ **[COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md#11-修改指南)**
- 第 11 节：修改指南
- 添加新面板
- 修改 API 调用
- 常见修改任务

#### 自动模式如何运作？
→ **[ARCHITECTURE.md](./ARCHITECTURE.md#自动模式-auto-mode)**
- 自动模式详解
- AutoModeProvider 说明
- 工作流程

---

## 📖 按需求选择文档

### 场景 1：我要给另一个 AI 介绍这个项目

**推荐阅读**：
1. [COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md) （完整版）
   - 或者只看前 6 节（项目概述 → API 架构）

**提供给 AI 的信息**：
```
这是一个 Flutter 开发的 AI 视频创作工具。

核心特点：
- 双模式：自动模式（全自动流程）+ 手动模式（模块化创作）
- 手动模式有 6 个独立面板：故事、剧本、分镜、角色、场景、物品
- 数据存储：自动模式用 Hive，手动模式用 SharedPreferences
- API 架构：混合供应商，可为 LLM/图片/视频分别配置

详细文档：COMPLETE_TECHNICAL_DOCUMENTATION.md
```

### 场景 2：我要修改手动模式的某个面板

**推荐阅读**：
1. [COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md#33-六大功能面板详解) - 第 3.3 节
2. [COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md#11-修改指南) - 第 11 节

**关键信息**：
- 所有面板都在 `lib/main.dart` 中
- 每个面板是一个 `StatefulWidget`
- 数据保存在 `SharedPreferences`
- 面板通过 `WorkspaceShell` 的导航栏切换

### 场景 3：我要添加新的 API 供应商

**推荐阅读**：
1. [COMPREHENSIVE_GUIDE.md](./COMPREHENSIVE_GUIDE.md#45-扩展新供应商)
2. [COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md#6-api-架构)

**关键步骤**：
1. 创建新的 Provider 类（继承 `BaseApiProvider`）
2. 更新 `ApiManager` 的工厂方法
3. 更新 `ApiConfigManager` 的配置选项

### 场景 4：我要理解数据流

**推荐阅读**：
1. [COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md#7-数据流)

**关键流程**：
```
用户操作 → UI State → ApiManager → API Provider → 
SharedPreferences → UI 更新
```

---

## 🔧 代码位置速查

| 功能 | 文件位置 |
|------|---------|
| **手动模式主界面** | `lib/main.dart` (WorkspaceShell) |
| **故事生成面板** | `lib/main.dart` (StoryGenerationPanel) |
| **剧本生成面板** | `lib/main.dart` (ScriptGenerationPanel) |
| **分镜生成面板** | `lib/main.dart` (StoryboardGenerationPanel) |
| **角色生成面板** | `lib/main.dart` (CharacterGenerationPanel) |
| **场景生成面板** | `lib/main.dart` (SceneGenerationPanel) |
| **物品生成面板** | `lib/main.dart` (PropGenerationPanel) |
| **自动模式状态** | `lib/logic/auto_mode_provider.dart` |
| **自动模式 UI** | `lib/views/auto_mode_screen.dart` |
| **API 管理器** | `lib/services/api_manager.dart` |
| **API 配置** | `lib/services/api_config_manager.dart` |
| **API 供应商基类** | `lib/services/providers/base_provider.dart` |
| **Geeknow 实现** | `lib/services/providers/geeknow_provider.dart` |

---

## 💡 常见问题快速解答

### Q1: 手动模式有项目概念吗？
**A:** ❌ 没有。手动模式只有一个全局工作区，数据保存在 SharedPreferences。

### Q2: 手动模式的面板之间如何传递数据？
**A:** 三种方式：
1. 手动复制粘贴（用户操作）
2. 从 SharedPreferences 读取（如"根据剧本生成"按钮）
3. 通过全局 WorkspaceState 共享

### Q3: 自动模式和手动模式的数据互通吗？
**A:** ❌ 不互通。完全隔离，使用不同的存储机制。

### Q4: 如何添加新的功能面板？
**A:** 参考 [COMPLETE_TECHNICAL_DOCUMENTATION.md - 11.1 节](./COMPLETE_TECHNICAL_DOCUMENTATION.md#111-如何添加新的功能面板)

### Q5: API 调用流程是怎样的？
**A:** 
```
UI → ApiManager().chatCompletion() → 
_llmProvider.chatCompletion() → 
HTTP 请求 → 解析响应 → 返回 UI
```

### Q6: 如何修改生成的提示词？
**A:** 
- 内置提示词：修改 `lib/services/prompt_store.dart`
- 用户自定义：在面板中添加输入框让用户输入

---

## 🎯 推荐阅读路径

### 路径 1：全面了解（适合首次接触）
1. [COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md) - 完整阅读
   - 第 1-2 节：项目概述和双模式架构（15 分钟）
   - 第 3 节：手动模式详解（30 分钟）⭐
   - 第 4-5 节：数据模型和界面架构（20 分钟）
   - 第 6 节：API 架构（15 分钟）

### 路径 2：快速上手（适合有经验的开发者）
1. [ARCHITECTURE.md](./ARCHITECTURE.md) - 快速浏览（10 分钟）
2. [COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md#3-手动模式详解重点) - 第 3 节（20 分钟）
3. [COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md#11-修改指南) - 第 11 节（10 分钟）

### 路径 3：专注手动模式（适合修改手动模式功能）
1. [COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md#3-手动模式详解重点) - 第 3 节
2. [COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md#4-数据模型和关联) - 第 4 节
3. [COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md#5-界面架构) - 第 5 节
4. [COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md#11-修改指南) - 第 11 节

### 路径 4：专注 API（适合修改 API 集成）
1. [COMPREHENSIVE_GUIDE.md](./COMPREHENSIVE_GUIDE.md#4-api-架构重点) - 第 4 节
2. [COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md#6-api-架构) - 第 6 节

---

## 📝 文档版本

- **COMPLETE_TECHNICAL_DOCUMENTATION.md**: v3.0 (2026-01-19)
- **ARCHITECTURE.md**: v2.0
- **COMPREHENSIVE_GUIDE.md**: v2.0

---

## 🚀 快速开始

如果您是第一次接触这个项目，建议：

1. **先读这个索引文件**（5 分钟）- 了解文档结构
2. **阅读 [COMPLETE_TECHNICAL_DOCUMENTATION.md](./COMPLETE_TECHNICAL_DOCUMENTATION.md) 的前 3 节**（45 分钟）- 理解核心概念
3. **根据需要查阅其他章节**

---

**祝您阅读愉快！如有疑问，请优先查阅 COMPLETE_TECHNICAL_DOCUMENTATION.md** 📚
