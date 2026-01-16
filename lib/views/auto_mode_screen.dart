import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../logic/auto_mode_provider.dart';
import '../models/scene_model.dart';
import '../models/scene_status.dart';
import '../models/auto_mode_project.dart';
import '../models/auto_mode_step.dart';
import '../models/character_model.dart';
import 'prompt_config_view.dart';
import '../services/ffmpeg_service.dart';

/// Auto Mode 屏幕 - 使用 AutoModeProvider 管理状态
class AutoModeScreen extends StatefulWidget {
  final Map<String, dynamic>? projectData;
  const AutoModeScreen({super.key, this.projectData});

  @override
  State<AutoModeScreen> createState() => _AutoModeScreenState();
}

class _AutoModeScreenState extends State<AutoModeScreen> with SingleTickerProviderStateMixin {
  final AutoModeProvider _provider = AutoModeProvider();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _fadeController;
  String? _projectId;
  
  // 场景编辑控制器映射：sceneIndex -> {script: controller, imagePrompt: controller}
  final Map<int, Map<String, TextEditingController>> _sceneControllers = {};
  final Map<int, Timer> _sceneDebounceTimers = {};

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );
    
    // CRITICAL: 从 projectData 获取项目 ID
    // 如果 projectData 没有 ID，不自动生成，只显示空状态
    _projectId = widget.projectData?['id'] as String?;
    
    // 清理项目 ID（移除可能的 'project_' 前缀）
    if (_projectId != null && _projectId!.isNotEmpty) {
      if (_projectId!.startsWith('project_')) {
        _projectId = _projectId!.substring(8);
        print('[AutoModeScreen] 清理项目 ID 前缀: ${widget.projectData?['id']} -> $_projectId');
      }
      print('[AutoModeScreen] 正在打开已有项目: $_projectId');
      
      // 初始化 Provider 并加载项目（仅当有 ID 时）
      _provider.initialize().then((_) async {
        if (_projectId != null && mounted) {
          try {
            // CRITICAL: initializeProject 只加载，不创建
            await _provider.initializeProject(_projectId!);
            if (mounted) {
              setState(() {});
            }
          } catch (e) {
            print('[AutoModeScreen] 加载项目失败: $e');
            // 如果加载失败，显示错误状态
            if (mounted) {
              setState(() {
                _projectId = null; // 重置为未选择状态
              });
            }
          }
        }
      });
    } else {
      // 如果没有项目 ID，只初始化 Provider，不创建新项目
      print('[AutoModeScreen] 未提供项目 ID，显示空状态');
      _provider.initialize();
    }
    
    _provider.addListener(_onProviderChanged);
  }
  
  /// 创建新项目（仅当用户明确点击创建按钮时调用）
  Future<void> _createNewProject() async {
    if (!mounted) return;
    
    try {
      // CRITICAL: 使用专门的 createNewProject 方法
      await _provider.initialize();
      final newProjectId = await _provider.createNewProject(
        title: widget.projectData?['title'] as String? ?? '新项目',
      );
      
      _projectId = newProjectId;
      print('[AutoModeScreen] ✓ 用户创建新项目: $_projectId');
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('[AutoModeScreen] ✗ 创建项目失败: $e');
      // 显示错误提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('创建项目失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 显示删除所有自动模式项目确认对话框
  Future<void> _showDeleteAllProjectsDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text(
              '确认清空',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          '确定要删除所有自动模式项目吗？\n\n此操作将：\n• 删除所有自动模式项目数据\n• 清空内存缓存\n• 无法恢复\n\n此操作不可撤销！',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 15,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              '取消',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text('确定清空'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        // 显示加载指示器
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Center(
            child: Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Color(0xFF1a1a2e),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.red),
                  SizedBox(height: 16),
                  Text(
                    '正在清空数据...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        );

        // 执行删除所有自动模式项目
        await _provider.forceClearAllData();

        // 关闭加载指示器
        if (mounted) {
          Navigator.of(context).pop();
        }

        // 显示成功提示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ 所有自动模式项目已删除'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );

          // 重置项目 ID，显示空状态
          setState(() {
            _projectId = null;
          });
        }
      } catch (e) {
        // 关闭加载指示器
        if (mounted) {
          Navigator.of(context).pop();
        }

        // 显示错误提示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('清空失败: $e'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    // CRITICAL: 生命周期安全 - 按正确顺序清理
    
    // 1. 首先取消所有定时器（如果有）
    for (final timer in _sceneDebounceTimers.values) {
      timer.cancel();
    }
    _sceneDebounceTimers.clear();
    
    // 2. 清理场景控制器（只清理 imagePrompt）
    for (final controllers in _sceneControllers.values) {
      controllers['imagePrompt']?.dispose();
    }
    _sceneControllers.clear();
    
    // 3. 移除监听器（防止在保存过程中触发更新）
    _provider.removeListener(_onProviderChanged);
    
    // 3. 立即保存项目（确保数据不丢失）
    if (_projectId != null && mounted) {
      // 使用 unawaited 因为 dispose 不能是 async
      _provider.saveImmediately(_projectId!).catchError((e) {
        print('[AutoModeScreen] 保存项目失败: $e');
      });
    }
    
    // 4. 清理所有控制器（在保存之后）
    _inputController.dispose();
    _scrollController.dispose();
    _fadeController.dispose();
    
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) {
      setState(() {});
      // 移除自动滚动，让用户保持在当前位置
      // _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleInput(String input) async {
    if (input.trim().isEmpty || _projectId == null || !mounted) return;
    
    final project = _provider.getProjectById(_projectId!);
    if (project == null || project.isProcessing) return;
    
    _inputController.clear();
    await _provider.processInput(_projectId!, input);
    
    // CRITICAL: 检查 mounted 状态
    if (!mounted) return;
  }

  Color _getStepColor(AutoModeStep step) {
    switch (step) {
      case AutoModeStep.script:
        return Color(0xFF00D4FF);
      case AutoModeStep.character:
        return Color(0xFFFF9800);
      case AutoModeStep.layout:
        return Color(0xFF6C5CE7);
      case AutoModeStep.image:
        return Color(0xFFFF6B9D);
      case AutoModeStep.video:
        return Color(0xFFFFB74D);
      case AutoModeStep.finalize:
        return Color(0xFF00E676);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 如果没有项目 ID，显示空状态（不自动创建）
    if (_projectId == null || _projectId!.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text('自动模式'),
          backgroundColor: Colors.transparent,
          actions: [
            // 删除所有按钮 - 强制显示在 AppBar 中
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
              tooltip: '清空所有自动模式数据',
              onPressed: () => _showDeleteAllProjectsDialog(context),
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_open_outlined, size: 64, color: Colors.white38),
              SizedBox(height: 16),
              Text(
                '未选择项目',
                style: TextStyle(fontSize: 18, color: Colors.white70),
              ),
              SizedBox(height: 8),
              Text(
                '请从项目列表中选择一个项目',
                style: TextStyle(fontSize: 14, color: Colors.white38),
              ),
              SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _createNewProject,
                icon: Icon(Icons.add),
                label: Text('创建新项目'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 直接获取项目（通过监听器更新）
    final project = _provider.getProjectById(_projectId!);
    
    if (project == null) {
      return Scaffold(
        body: Center(
          child: Text('项目不存在'),
        ),
      );
    }
    
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        
        // CRITICAL: 原子性返回按钮 - 确保保存完成后再返回
        if (_projectId != null && mounted) {
          try {
            print('[AutoModeScreen] 返回前保存项目: $_projectId');
            await _provider.saveImmediately(_projectId!);
            print('[AutoModeScreen] 项目已保存，允许返回');
          } catch (e) {
            print('[AutoModeScreen] 保存项目失败: $e');
          }
        }
        
        // 确保保存完成后再返回
        if (mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A0A14), Color(0xFF0f0f1e), Color(0xFF1a1a2e)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(project),
              _buildStepIndicator(project),
              Expanded(
                child: _buildContentArea(project),
              ),
              // CRITICAL: 在 script、layout 和 image 步骤都显示输入框，允许用户与 agent 交流
              if (project.currentStep == AutoModeStep.script || 
                  project.currentStep == AutoModeStep.layout ||
                  project.currentStep == AutoModeStep.image)
                _buildInputArea(project),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildSaveStatusIndicator(AutoModeProject project) {
    if (project.isSaving) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
              ),
            ),
            SizedBox(width: 6),
            Text(
              '保存中...',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    } else if (!project.hasUnsavedChanges && project.lastModified != null) {
      // 显示保存成功图标（短暂显示后淡出）
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.0, end: 0.0),
        duration: Duration(seconds: 2),
        builder: (context, opacity, child) {
          return Opacity(
            opacity: opacity,
            child: Container(
              padding: EdgeInsets.all(6),
              child: Icon(
                Icons.cloud_done,
                color: Color(0xFF00E676),
                size: 18,
              ),
            ),
          );
        },
      );
    }
    return SizedBox.shrink();
  }

  Widget _buildTopBar(AutoModeProject project) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 18),
            ),
          ),
          SizedBox(width: 16),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF6C5CE7), Color(0xFFFF6B9D)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.auto_stories_outlined, color: Colors.white, size: 22),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'AI 智能创作工作流',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
          // 保存状态指示器
          _buildSaveStatusIndicator(project),
          SizedBox(width: 8),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PromptConfigView()),
              );
            },
            icon: Icon(Icons.auto_awesome_motion, color: Colors.white70),
            tooltip: '提示词模板',
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(AutoModeProject project) {
    final steps = [
      AutoModeStep.script,
      AutoModeStep.character,
      AutoModeStep.layout,
      AutoModeStep.image,
      AutoModeStep.video,
      AutoModeStep.finalize,
    ];

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: steps.asMap().entries.map((entry) {
          final step = entry.value;
          final index = entry.key;
          final isActive = project.currentStep == step;
          final isCompleted = steps.indexOf(project.currentStep) > index;
          final color = _getStepColor(step);

          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isActive || isCompleted
                        ? color
                        : Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isActive ? color : Colors.white.withOpacity(0.2),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: isCompleted
                        ? Icon(Icons.check, color: Colors.white, size: 18)
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                if (index < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? color
                            : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildContentArea(AutoModeProject project) {
    return AnimatedSwitcher(
      duration: Duration(milliseconds: 400),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0.1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            )),
            child: child,
          ),
        );
      },
      child: _buildStepContent(project),
      key: ValueKey(project.currentStep),
    );
  }

  Widget _buildStepContent(AutoModeProject project) {
    switch (project.currentStep) {
      case AutoModeStep.script:
      case AutoModeStep.character:
      case AutoModeStep.layout:
        return _buildChatView(project);
      case AutoModeStep.image:
        return _buildImageStep(project);
      case AutoModeStep.video:
        // CRITICAL: 视频步骤直接显示场景列表，不显示项目级别的"处理中"界面
        // 每个场景卡片会显示自己的生成状态，左侧图片区域始终保留
        return _buildVideoStep(project);
      case AutoModeStep.finalize:
        return _buildFinalizeView(project);
    }
  }

  Widget _buildChatView(AutoModeProject project) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (project.currentStep == AutoModeStep.script && project.currentScript.isEmpty)
            _buildWelcomeMessage(),
          if (project.currentScript.isNotEmpty)
            _buildContentBubble(
              project.currentScript,
              '剧本',
              _getStepColor(AutoModeStep.script),
            ),
          // 角色生成步骤：显示角色列表
          if (project.currentStep == AutoModeStep.character)
            _buildCharacterStep(project),
          // 分镜生成步骤：如果 scenes 已生成，显示可编辑的文本框列表
          if (project.currentStep == AutoModeStep.layout && project.scenes.isNotEmpty)
            _buildLayoutStep(project),
          // 如果只有 currentLayout 文本但没有 scenes，显示原始文本
          if (project.currentStep == AutoModeStep.layout && 
              project.currentLayout.isNotEmpty && 
              project.scenes.isEmpty)
            _buildContentBubble(
              project.currentLayout,
              '分镜生成',
              _getStepColor(AutoModeStep.layout),
            ),
          // CRITICAL: 在图片生成步骤，显示图片生成完成提示
          if (project.currentStep == AutoModeStep.image && project.scenes.isNotEmpty)
            _buildImageGenerationStatus(project),
          if (project.errorMessage != null)
            _buildErrorBubble(project.errorMessage!),
          if (project.isProcessing)
            _buildLoadingBubble(project),
          SizedBox(height: 20),
          // 角色生成步骤的继续按钮
          if (project.currentStep == AutoModeStep.character && 
              project.characters.isNotEmpty &&
              project.characters.every((c) => c.prompt.isNotEmpty) &&
              !project.isProcessing)
            _buildContinueButton(project),
          // 其他步骤的继续按钮
          if ((project.currentStep == AutoModeStep.script && project.currentScript.isNotEmpty) ||
              (project.currentStep == AutoModeStep.layout && project.currentLayout.isNotEmpty))
            if (!project.isProcessing)
              _buildContinueButton(project),
          // CRITICAL: 在图片生成步骤，如果所有图片已生成，显示继续按钮
          if (project.currentStep == AutoModeStep.image && 
              !project.isProcessing &&
              project.scenes.isNotEmpty &&
              project.scenes.every((s) {
                final hasImage = (s.imageUrl != null && s.imageUrl!.isNotEmpty) || 
                                (s.localImagePath != null && s.localImagePath!.isNotEmpty);
                return hasImage && !s.isGeneratingImage && s.status != SceneStatus.processing && s.status != SceneStatus.queueing;
              }))
            _buildContinueButton(project),
        ],
      ),
    );
  }
  
  /// 构建图片生成状态提示
  Widget _buildImageGenerationStatus(AutoModeProject project) {
    final totalScenes = project.scenes.length;
    final completedScenes = project.scenes.where((s) {
      final hasImage = (s.imageUrl != null && s.imageUrl!.isNotEmpty) || 
                      (s.localImagePath != null && s.localImagePath!.isNotEmpty);
      return hasImage && !s.isGeneratingImage && s.status != SceneStatus.processing && s.status != SceneStatus.queueing;
    }).length;
    final errorScenes = project.scenes.where((s) => s.status == SceneStatus.error).length;
    final generatingScenes = project.scenes.where((s) => 
      s.isGeneratingImage || s.status == SceneStatus.processing || s.status == SceneStatus.queueing
    ).length;
    
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFFFF6B9D).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFFFF6B9D).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.image_outlined, color: Color(0xFFFF6B9D), size: 20),
              SizedBox(width: 8),
              Text(
                '图片生成进度',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            '已完成: $completedScenes / $totalScenes 个场景',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (generatingScenes > 0)
            Text(
              '生成中: $generatingScenes 个场景',
              style: TextStyle(color: Color(0xFFFF6B9D), fontSize: 13),
            ),
          if (errorScenes > 0)
            Text(
              '失败: $errorScenes 个场景（请点击重新生成）',
              style: TextStyle(color: Colors.red, fontSize: 13),
            ),
          if (completedScenes == totalScenes && errorScenes == 0)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '✓ 所有图片已生成完成！可以输入"继续"进入视频生成步骤。',
                style: TextStyle(
                  color: Color(0xFF00E676),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWelcomeMessage() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Color(0xFF00D4FF), size: 24),
              SizedBox(width: 12),
              Text(
                'AI 智能创作助手',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            '只需告诉我你想要创作的故事，我会帮你完成：\n\n'
            '📝 剧本生成 → 👤 角色生成 → 🎬 分镜生成 → 🎨 图片生成 → 🎥 视频生成\n\n'
            '现在，请告诉我你想创作什么样的动漫故事？',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建角色生成步骤 UI
  Widget _buildCharacterStep(AutoModeProject project) {
    if (project.characters.isEmpty) {
      return Container(
        margin: EdgeInsets.only(bottom: 16),
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Color(0xFFFF9800).withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Color(0xFFFF9800).withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.person_outline, color: Color(0xFFFF9800), size: 20),
            SizedBox(width: 12),
            Text(
              '正在生成角色列表...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: EdgeInsets.only(bottom: 16),
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color(0xFFFF9800).withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Color(0xFFFF9800).withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.people_outline, color: Color(0xFFFF9800), size: 20),
              SizedBox(width: 8),
              Text(
                '角色生成',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        ...project.characters.asMap().entries.map((entry) {
          final index = entry.key;
          final character = entry.value;
          return _buildCharacterCard(project, character, index);
        }),
      ],
    );
  }

  /// 构建角色卡片
  Widget _buildCharacterCard(AutoModeProject project, CharacterModel character, int index) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 角色名称（左上角）
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Color(0xFFFF9800),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    character.name,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Spacer(),
                // 生成按钮
                if (character.prompt.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: character.isGeneratingImage || project.isProcessing
                        ? null
                        : () async {
                            if (_projectId != null) {
                              try {
                                await _provider.generateCharacterImage(_projectId!, index);
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('生成角色图片失败: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            }
                          },
                    icon: character.isGeneratingImage
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(Icons.image_outlined, size: 16),
                    label: Text(character.isGeneratingImage ? '生成中...' : '生成'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFFF9800),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 角色提示词和图片
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左侧：提示词
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '角色提示词',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        SizedBox(height: 8),
                        SelectableText(
                          character.prompt.isNotEmpty ? character.prompt : '等待生成...',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 12),
                // 右侧：图片
                Expanded(
                  flex: 1,
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _buildCharacterImage(character),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 构建角色图片 Widget
  Widget _buildCharacterImage(CharacterModel character) {
    // 如果有图片，显示图片
    String? imagePath = character.localImagePath ?? character.imageUrl;
    if (imagePath != null && imagePath.isNotEmpty) {
      // 使用统一的图片显示函数，支持 Base64 数据URI、HTTP URL 和本地文件
      Widget imageWidget;
      if (imagePath.startsWith('data:image/')) {
        // Base64 数据URI
        try {
          final base64Index = imagePath.indexOf('base64,');
          if (base64Index != -1) {
            final base64Data = imagePath.substring(base64Index + 7);
            final bytes = Uint8List.fromList(base64Decode(base64Data));
            imageWidget = Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: Icon(Icons.broken_image, color: Colors.white24, size: 40),
                );
              },
            );
          } else {
            imageWidget = Center(
              child: Icon(Icons.broken_image, color: Colors.white24, size: 40),
            );
          }
        } catch (e) {
          imageWidget = Center(
            child: Icon(Icons.broken_image, color: Colors.white24, size: 40),
          );
        }
      } else if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
        // HTTP URL
        imageWidget = Image.network(
          imagePath,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Icon(Icons.broken_image, color: Colors.white24, size: 40),
            );
          },
        );
      } else {
        // 本地文件路径
        imageWidget = Image.file(
          File(imagePath),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Icon(Icons.broken_image, color: Colors.white24, size: 40),
            );
          },
        );
      }
      
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: Colors.black.withOpacity(0.3),
              child: imageWidget,
            ),
            // 角色名称（左上角）
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  character.name,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    // 如果正在生成，显示加载状态
    if (character.isGeneratingImage) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              value: character.imageGenerationProgress > 0
                  ? character.imageGenerationProgress
                  : null,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9800)),
            ),
            SizedBox(height: 12),
            Text(
              character.generationStatus == 'queueing'
                  ? '队列中...'
                  : character.generationStatus == 'processing'
                      ? '处理中... ${(character.imageGenerationProgress * 100).toInt()}%'
                      : '生成中...',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );
    }
    
    // 如果有错误，显示错误信息
    if (character.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 32),
            SizedBox(height: 8),
            Text(
              '生成失败',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
            SizedBox(height: 4),
            Text(
              character.errorMessage!,
              style: TextStyle(color: Colors.white54, fontSize: 10),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }
    
    // 默认占位符
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_outline, color: Colors.white24, size: 48),
          SizedBox(height: 8),
          Text(
            '点击"生成"按钮生成角色图片',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// 构建分镜生成步骤的可编辑界面
  Widget _buildLayoutStep(AutoModeProject project) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Container(
          margin: EdgeInsets.only(bottom: 16),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _getStepColor(AutoModeStep.layout).withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _getStepColor(AutoModeStep.layout).withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.view_agenda, color: _getStepColor(AutoModeStep.layout), size: 18),
              SizedBox(width: 8),
              Text(
                '分镜生成',
                style: TextStyle(
                  color: _getStepColor(AutoModeStep.layout),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 12),
              Text(
                '共 ${project.scenes.length} 个镜头',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        // 每个场景的可编辑文本框
        ...project.scenes.asMap().entries.map((entry) {
          final index = entry.key;
          final scene = entry.value;
          return _buildSceneEditCard(project, scene, index);
        }),
      ],
    );
  }

  /// 获取图片提示词控制器（用于图片生成步骤）
  TextEditingController _getImagePromptController(int sceneIndex, String currentPrompt) {
    if (!_sceneControllers.containsKey(sceneIndex)) {
      _sceneControllers[sceneIndex] = {
        'imagePrompt': TextEditingController(text: currentPrompt),
      };
    } else {
      // 如果场景数据已更新，同步控制器文本
      final controllers = _sceneControllers[sceneIndex]!;
      if (controllers['imagePrompt']!.text != currentPrompt) {
        controllers['imagePrompt']!.text = currentPrompt;
      }
    }
    return _sceneControllers[sceneIndex]!['imagePrompt']!;
  }

  /// 构建单个场景的可编辑卡片（用于分镜生成步骤）
  Widget _buildSceneEditCard(AutoModeProject project, SceneModel scene, int sceneIndex) {
    // 获取或创建控制器（只保留 imagePrompt）
    final imagePromptController = _getImagePromptController(sceneIndex, scene.imagePrompt);
    
    void _saveChanges() {
      if (_projectId == null) return;
      
      // 取消之前的定时器
      _sceneDebounceTimers[sceneIndex]?.cancel();
      
      // 创建新的防抖定时器
      _sceneDebounceTimers[sceneIndex] = Timer(Duration(milliseconds: 500), () {
        _provider.updateScenePrompt(
          _projectId!,
          sceneIndex,
          imagePrompt: imagePromptController.text.trim(),
        );
      });
    }
    
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 镜头标题
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _getStepColor(AutoModeStep.layout).withOpacity(0.1),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getStepColor(AutoModeStep.layout),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '镜头${sceneIndex + 1}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 分镜提示词文本框（唯一文本框）
                Text(
                  '分镜提示词',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: TextField(
                    controller: imagePromptController,
                    enabled: true,
                    readOnly: false,
                    enableInteractiveSelection: true,
                    maxLines: 6,
                    minLines: 3,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '输入图片生成提示词...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(12),
                    ),
                    onChanged: (_) => _saveChanges(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentBubble(String content, String title, Color color) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          SelectableText(
            content,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBubble(String error) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              error,
              style: TextStyle(color: Colors.red[200], fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingBubble(AutoModeProject project) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(_getStepColor(project.currentStep)),
            ),
          ),
          SizedBox(width: 16),
          Text(
            '正在生成${_getStepName(project.currentStep)}...',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueButton(AutoModeProject project) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ElevatedButton.icon(
        onPressed: project.isProcessing
            ? null
            : () async {
                // 立即保存后再继续
                if (_projectId != null) {
                  await _provider.saveImmediately(_projectId!);
                  await _handleInput('继续');
                }
              },
        icon: Icon(Icons.arrow_forward, size: 18),
        label: Text('继续'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _getStepColor(project.currentStep),
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  /// 构建带角色名字的图片 Widget（用于图片生成步骤）
  Widget _buildImageWithCharacterName(AutoModeProject project, SceneModel scene) {
    // 从提示词中提取角色名字
    String? matchedCharacterName;
    for (final character in project.characters) {
      if (scene.imagePrompt.contains(character.name) || scene.script.contains(character.name)) {
        matchedCharacterName = character.name;
        break; // 只匹配第一个找到的角色
      }
    }
    
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildImageWidget(scene),
        // 角色名字（左上角）
        if (matchedCharacterName != null)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                matchedCharacterName,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 构建图片 Widget（带错误检查）
  /// CRITICAL: 图片区域应该始终显示图片（如果存在），不受视频生成状态影响
  Widget _buildImageWidget(SceneModel scene) {
    // CRITICAL: 检查是否有图片路径（优先显示图片，即使状态是错误或处理中）
    final hasImage = (scene.localImagePath != null && scene.localImagePath!.isNotEmpty) ||
                    (scene.imageUrl != null && scene.imageUrl!.isNotEmpty);
    
    // CRITICAL: 如果图片存在，无论什么状态都显示图片（包括视频生成时）
    // 只有在图片生成失败且没有图片时才显示错误图标
    if (scene.status == SceneStatus.error && !hasImage && scene.isGeneratingImage == false) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 48),
            SizedBox(height: 8),
            Text(
              '生成失败',
              style: TextStyle(color: Colors.red[200], fontSize: 12),
            ),
            if (scene.errorMessage != null)
              Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  scene.errorMessage!,
                  style: TextStyle(color: Colors.red[300], fontSize: 10),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      );
    }

    // CRITICAL: 优先检查图片路径，如果存在则直接显示图片（不受任何状态影响）
    // 这是为了确保视频生成时图片区域仍然显示图片，而不是状态信息
    String? imagePath = scene.localImagePath ?? scene.imageUrl;
    if (imagePath != null && imagePath.isNotEmpty) {
      // 图片存在，直接显示图片（无论什么状态，包括视频生成时）
      // 继续到下面的图片显示逻辑，不在这里返回
    } else if (scene.isGeneratingImage) {
      // 图片不存在但正在生成，显示加载状态
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              value: scene.imageGenerationProgress > 0 
                  ? scene.imageGenerationProgress 
                  : null,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B9D)),
            ),
            SizedBox(height: 12),
            Text(
              scene.generationStatus == 'queueing' 
                  ? '队列中...' 
                  : scene.generationStatus == 'processing'
                      ? '处理中... ${(scene.imageGenerationProgress * 100).toInt()}%'
                      : '生成中...',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );
    } else {
      // 没有图片且不在生成，显示占位符
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined, color: Colors.white24, size: 48),
            SizedBox(height: 8),
            Text(
              '暂无图片',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      );
    }

    // 显示图片（本地优先）
    if (scene.localImagePath != null && scene.localImagePath!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        child: Container(
          color: Colors.black.withOpacity(0.3),
          child: Image.file(
            File(scene.localImagePath!),
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) {
              // 如果本地文件加载失败，尝试网络 URL
              if (scene.imageUrl != null && scene.imageUrl!.isNotEmpty) {
                return Image.network(
                  scene.imageUrl!,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Icon(Icons.broken_image, color: Colors.white24, size: 48),
                    );
                  },
                );
              }
              return Center(
                child: Icon(Icons.broken_image, color: Colors.white24, size: 48),
              );
            },
          ),
        ),
      );
    }

    // 使用网络 URL
    if (scene.imageUrl != null && scene.imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        child: Container(
          color: Colors.black.withOpacity(0.3),
          child: Image.network(
            scene.imageUrl!,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  Icon(Icons.broken_image, color: Colors.white24, size: 48),
                  SizedBox(height: 8),
                  Text(
                    '图片加载失败',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    }

    // 默认占位符
    return Center(
      child: Icon(Icons.image_outlined, color: Colors.white24, size: 48),
    );
  }

  Widget _buildImageStep(AutoModeProject project) {
    final scenes = project.scenes;
    
    if (scenes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined, size: 64, color: Colors.white24),
            SizedBox(height: 16),
            Text(
              '暂无场景',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ],
        ),
      );
    }

    // CRITICAL: 检查所有图片是否已生成
    final allImagesCompleted = scenes.every((s) {
      final hasImage = (s.imageUrl != null && s.imageUrl!.isNotEmpty) || 
                      (s.localImagePath != null && s.localImagePath!.isNotEmpty);
      return hasImage && !s.isGeneratingImage && s.status != SceneStatus.processing && s.status != SceneStatus.queueing;
    });
    final errorScenes = scenes.where((s) => s.status == SceneStatus.error).length;
    final completedCount = scenes.where((s) {
      final hasImage = (s.imageUrl != null && s.imageUrl!.isNotEmpty) || 
                      (s.localImagePath != null && s.localImagePath!.isNotEmpty);
      return hasImage && !s.isGeneratingImage && s.status != SceneStatus.processing && s.status != SceneStatus.queueing;
    }).length;

    return Column(
      children: [
        // CRITICAL: 显示图片生成状态提示
        if (allImagesCompleted && errorScenes == 0)
          Container(
            margin: EdgeInsets.all(20),
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(0xFF00E676).withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Color(0xFF00E676).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF00E676), size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '✓ 所有图片已生成完成！可以输入"继续"进入视频生成步骤。',
                    style: TextStyle(
                      color: Color(0xFF00E676),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (errorScenes > 0)
          Container(
            margin: EdgeInsets.all(20),
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '有 $errorScenes 个场景图片生成失败，请先点击"重新生成"按钮修复失败的场景。',
                    style: TextStyle(
                      color: Colors.red[200],
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            margin: EdgeInsets.all(20),
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(0xFFFF6B9D).withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Color(0xFFFF6B9D).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.image_outlined, color: Color(0xFFFF6B9D), size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '图片生成进度: $completedCount / ${scenes.length} 已完成',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // 场景列表
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 20),
            itemCount: scenes.length,
            itemBuilder: (context, index) {
              return _buildSceneImageCard(project, scenes[index], index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSceneImageCard(AutoModeProject project, SceneModel scene, int index) {
    return Container(
      margin: EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：提示词
          Expanded(
            flex: 2,
            child: Container(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Color(0xFFFF6B9D).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '场景 ${scene.index + 1}',
                          style: TextStyle(
                            color: Color(0xFFFF6B9D),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text(
                    scene.script,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: 12),
                  // 图片提示词（可编辑）
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '图片提示词',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 6),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: TextField(
                          // 获取或创建控制器
                          controller: _getImagePromptController(index, scene.imagePrompt),
                          enabled: true,
                          readOnly: false,
                          enableInteractiveSelection: true,
                          maxLines: 4,
                          minLines: 2,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            height: 1.4,
                          ),
                          decoration: InputDecoration(
                            hintText: '输入图片生成提示词...',
                            hintStyle: TextStyle(color: Colors.white38, fontSize: 11),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(12),
                          ),
                          onChanged: (_) {
                            // 保存修改的防抖
                            _sceneDebounceTimers[index]?.cancel();
                            _sceneDebounceTimers[index] = Timer(Duration(milliseconds: 500), () {
                              if (_projectId != null) {
                                final controller = _getImagePromptController(index, scene.imagePrompt);
                                _provider.updateScenePrompt(
                                  _projectId!,
                                  index,
                                  imagePrompt: controller.text.trim(),
                                );
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: (scene.isGeneratingImage || _projectId == null || project.isProcessing)
                        ? null
                        : () async {
                            // CRITICAL: 重新生成前，先保存当前修改的提示词
                            if (_projectId != null) {
                              try {
                                // 取消防抖定时器，立即保存
                                _sceneDebounceTimers[index]?.cancel();
                                final controller = _getImagePromptController(index, scene.imagePrompt);
                                final currentPrompt = controller.text.trim();
                                
                                // 先更新提示词
                                await _provider.updateScenePrompt(
                                  _projectId!,
                                  index,
                                  imagePrompt: currentPrompt,
                                );
                                
                                // 然后重新生成图片
                                await _provider.regenerateImage(_projectId!, index);
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('重新生成失败: $e'),
                                      backgroundColor: Colors.red,
                                      duration: Duration(seconds: 3),
                                    ),
                                  );
                                }
                              }
                            }
                          },
                    icon: scene.isGeneratingImage
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(Icons.refresh, size: 16),
                    label: Text(scene.isGeneratingImage ? '生成中...' : '重新生成'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFFF6B9D),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 右侧：图片（带角色名字显示）
          Expanded(
            flex: 1,
            child: Container(
              height: 300,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: _buildImageWithCharacterName(project, scene),
            ),
          ),
        ],
      ),
    );
  }

  String _getStepName(AutoModeStep step) {
    switch (step) {
      case AutoModeStep.script:
        return '剧本生成';
      case AutoModeStep.character:
        return '角色生成';
      case AutoModeStep.layout:
        return '分镜生成';
      case AutoModeStep.image:
        return '图片生成';
      case AutoModeStep.video:
        return '视频生成';
      case AutoModeStep.finalize:
        return '最终合并';
    }
  }


  Widget _buildVideoStep(AutoModeProject project) {
    final scenes = project.scenes;
    
    if (scenes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library_outlined, size: 64, color: Colors.white24),
            SizedBox(height: 16),
            Text(
              '暂无场景',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ],
        ),
      );
    }

    // CRITICAL: 视频步骤不显示项目级别的"处理中"界面
    // 直接显示场景列表，每个场景卡片会显示自己的状态
    // 左侧图片区域始终保留，不会被覆盖

    // CRITICAL: 检查所有视频是否已生成
    final allVideosCompleted = scenes.every((s) {
      final hasVideo = (s.videoUrl != null && s.videoUrl!.isNotEmpty) || 
                      (s.localVideoPath != null && s.localVideoPath!.isNotEmpty);
      return hasVideo && !s.isGeneratingVideo && s.status != SceneStatus.processing && s.status != SceneStatus.queueing;
    });
    final errorScenes = scenes.where((s) => s.status == SceneStatus.error).length;
    final completedCount = scenes.where((s) {
      final hasVideo = (s.videoUrl != null && s.videoUrl!.isNotEmpty) || 
                      (s.localVideoPath != null && s.localVideoPath!.isNotEmpty);
      return hasVideo && !s.isGeneratingVideo && s.status != SceneStatus.processing && s.status != SceneStatus.queueing;
    }).length;

    return Column(
      children: [
        // CRITICAL: 显示视频生成状态提示
        if (allVideosCompleted && errorScenes == 0)
          Container(
            margin: EdgeInsets.all(20),
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(0xFF00E676).withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Color(0xFF00E676).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF00E676), size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '✓ 所有视频已生成完成！可以输入"继续"进入最终合并步骤。',
                    style: TextStyle(
                      color: Color(0xFF00E676),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (errorScenes > 0)
          Container(
            margin: EdgeInsets.all(20),
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '有 $errorScenes 个场景视频生成失败，请先点击"重新生成"按钮修复失败的场景。',
                    style: TextStyle(
                      color: Colors.red[200],
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            margin: EdgeInsets.all(20),
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(0xFFFFB74D).withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Color(0xFFFFB74D).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.video_library_outlined, color: Color(0xFFFFB74D), size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '视频生成进度: $completedCount / ${scenes.length} 已完成',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // 场景列表
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 20),
            itemCount: scenes.length,
            itemBuilder: (context, index) {
              return _buildSceneVideoCard(project, scenes[index], scenes[index].index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSceneVideoCard(AutoModeProject project, SceneModel scene, int index) {
    final hasVideo = (scene.videoUrl != null && scene.videoUrl!.isNotEmpty) ||
                    (scene.localVideoPath != null && scene.localVideoPath!.isNotEmpty);
    final isError = scene.status == SceneStatus.error;
    final isGenerating = scene.isGeneratingVideo || 
                        scene.status == SceneStatus.processing || 
                        scene.status == SceneStatus.queueing;
    
    return Container(
      margin: EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isError 
            ? Colors.red.withOpacity(0.5) 
            : Colors.white.withOpacity(0.1),
          width: isError ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：视频提示词（可编辑）
          Expanded(
            flex: 1,
            child: Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Color(0xFFFFB74D).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '场景 ${scene.index + 1}',
                          style: TextStyle(
                            color: Color(0xFFFFB74D),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // 重新生成按钮（始终可点击，始终显示"重新生成"，不改变文字）
                      ElevatedButton.icon(
                        onPressed: () async {
                            // CRITICAL: 重新生成前，先保存当前修改的提示词
                            if (_projectId != null) {
                              try {
                                // 取消防抖定时器，立即保存
                                _sceneDebounceTimers[index]?.cancel();
                                final controller = _getImagePromptController(index, scene.imagePrompt);
                                final currentPrompt = controller.text.trim();
                                
                                // 先更新提示词
                                await _provider.updateScenePrompt(
                                  _projectId!,
                                  index,
                                  imagePrompt: currentPrompt,
                                );
                                
                                // 然后重新生成视频（即使正在生成中也可以点击重新生成）
                                await _provider.regenerateVideo(_projectId!, index);
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('重新生成失败: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            }
                          },
                        icon: Icon(Icons.refresh, size: 16), // 始终显示刷新图标
                        label: Text('重新生成'), // 始终显示"重新生成"，不改变
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFFFB74D),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  // 视频提示词文本框（可编辑）
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: TextField(
                      // 获取或创建控制器
                      controller: _getImagePromptController(index, scene.imagePrompt),
                      enabled: true,
                      readOnly: false,
                      enableInteractiveSelection: true,
                      maxLines: 6,
                      minLines: 3,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.4,
                      ),
                      decoration: InputDecoration(
                        hintText: '输入视频生成提示词...',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 11),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(12),
                      ),
                      onChanged: (_) {
                        // 保存修改的防抖
                        _sceneDebounceTimers[index]?.cancel();
                        _sceneDebounceTimers[index] = Timer(Duration(milliseconds: 500), () {
                          if (_projectId != null) {
                            final controller = _getImagePromptController(index, scene.imagePrompt);
                            _provider.updateScenePrompt(
                              _projectId!,
                              index,
                              imagePrompt: controller.text.trim(),
                            );
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 中间：生成的图片
          Expanded(
            flex: 1,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
              ),
              child: (scene.localImagePath != null && scene.localImagePath!.isNotEmpty) ||
                      (scene.imageUrl != null && scene.imageUrl!.isNotEmpty)
                  ? ClipRRect(
                      child: _buildImageWidget(scene),
                    )
                  : Center(
                      child: Icon(Icons.image_outlined, size: 32, color: Colors.white24),
                    ),
            ),
          ),
          // 右侧：视频播放器
          Expanded(
            flex: 1,
            child: Container(
              height: 200,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              // CRITICAL: 参考视频空间的实现，直接根据API返回的进度显示
              // 只有在明确失败且不在处理中时才显示失败
              // 如果有进度信息（generationStatus == 'processing'），就显示进度，不显示失败
              child: hasVideo
                ? _buildVideoPlayer(project, scene, index)
                : (isError && !isGenerating && scene.generationStatus != 'processing' && scene.generationStatus != 'queueing')
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 32, color: Colors.red,),
                          SizedBox(height: 8),
                          Text(
                            '生成失败',
                            style: TextStyle(color: Colors.red[200], fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          if (scene.errorMessage != null && scene.errorMessage!.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 8, left: 8, right: 8),
                              child: Text(
                                scene.errorMessage!,
                                style: TextStyle(color: Colors.red[300], fontSize: 11),
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    )
                  : (isGenerating || scene.generationStatus == 'processing' || scene.generationStatus == 'queueing')
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // CRITICAL: 只有当有实际进度（progress > 0）或状态是processing时才显示进度条
                            // 如果只是queueing且progress是0%，只显示简单的状态文字
                            // 但如果progress > 0，即使状态是queueing，也要显示进度（因为官网可能已经开始处理）
                            if (scene.generationStatus == 'queueing' && scene.videoGenerationProgress == 0)
                              // 队列中且无进度，只显示状态文字，不显示进度条
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Color(0xFFFFB74D).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '队列中...',
                                  style: TextStyle(
                                    color: Color(0xFFFFB74D),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            else
                              // 有进度或正在处理中，显示进度条和百分比（实时同步官网进度）
                              Column(
                                children: [
                                  SizedBox(
                                    width: 60,
                                    height: 60,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        CircularProgressIndicator(
                                          value: scene.videoGenerationProgress > 0 
                                            ? scene.videoGenerationProgress 
                                            : null,
                                          strokeWidth: 4,
                                          backgroundColor: Colors.white.withOpacity(0.1),
                                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFB74D)),
                                        ),
                                        if (scene.videoGenerationProgress > 0)
                                          Text(
                                            '${(scene.videoGenerationProgress * 100).toInt()}%',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: 12),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Color(0xFFFFB74D).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      scene.generationStatus == 'processing'
                                        ? '处理中... ${(scene.videoGenerationProgress * 100).toInt()}%' // 显示实际进度
                                        : scene.generationStatus == 'queueing' && scene.videoGenerationProgress > 0
                                          ? '处理中... ${(scene.videoGenerationProgress * 100).toInt()}%' // 即使状态是queueing，有进度也显示
                                          : '生成中...',
                                      style: TextStyle(
                                        color: Color(0xFFFFB74D),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            // CRITICAL: 如果有错误信息但仍在处理中或队列中，不显示错误信息
                            // 只显示进度信息，确保实时同步官网进度
                            // 只有在明确失败且不在处理中时才显示错误
                          ],
                        ),
                      )
                    : Center(
                        // 没有视频且不在处理中，显示空状态（不显示"等待生成"等文字）
                        child: Icon(Icons.video_library_outlined, size: 32, color: Colors.white24),
                      ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建视频播放器（参考视频空间的实现）
  /// 支持点击播放、右键菜单、显示首帧
  Widget _buildVideoPlayer(AutoModeProject project, SceneModel scene, int index) {
    final videoUrl = scene.videoUrl ?? scene.localVideoPath ?? '';
    final localPath = scene.localVideoPath;
    
    return _AutoModeVideoPlayerWidget(
      videoUrl: videoUrl,
      localPath: localPath,
      onPlay: () => _playVideoInPlayer(localPath, videoUrl),
      onContextMenu: (position) => _showVideoContextMenu(context, position, localPath, videoUrl),
    );
  }
  
  /// 播放视频（参考视频空间的实现）
  Future<void> _playVideoInPlayer(String? localPath, String videoUrl) async {
    try {
      // 优先使用本地文件
      if (localPath != null && localPath.isNotEmpty) {
        final localFile = File(localPath);
        if (await localFile.exists()) {
          // Windows: 直接使用命令打开，最快速
          if (Platform.isWindows) {
            await Process.run('cmd', ['/c', 'start', '', localPath]);
            return;
          } else {
            final fileUri = Uri.file(localPath);
            if (await canLaunchUrl(fileUri)) {
              await launchUrl(fileUri, mode: LaunchMode.externalApplication);
              return;
            }
          }
        }
      }
      
      // 本地文件不存在，使用网络 URL
      if (videoUrl.isNotEmpty && videoUrl.startsWith('http')) {
        final uri = Uri.parse(videoUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }
      
      // 都失败了，提示用户
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('本地视频文件不存在，请检查自动保存设置'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('播放视频失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// 显示视频右键菜单
  void _showVideoContextMenu(BuildContext context, Offset position, String? localPath, String videoUrl) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Rect.fromLTWH(0, 0, overlay.size.width, overlay.size.height),
      ),
      items: [
        PopupMenuItem(
          child: Row(
            children: [
              Icon(Icons.play_arrow, size: 18, color: Color(0xFFFFB74D)),
              SizedBox(width: 8),
              Text('使用播放器播放'),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () => _playVideoInPlayer(localPath, videoUrl)),
        ),
        PopupMenuItem(
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 18, color: Color(0xFFFFB74D)),
              SizedBox(width: 8),
              Text('查看视频所在地址'),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () => _openVideoFolder(localPath, videoUrl)),
        ),
      ],
    );
  }
  
  /// 打开视频所在文件夹
  Future<void> _openVideoFolder(String? localPath, String videoUrl) async {
    // 优先使用本地路径
    if (localPath != null && localPath.isNotEmpty) {
      final file = File(localPath);
      if (await file.exists()) {
        try {
          if (Platform.isWindows) {
            // Windows: 使用 explorer 打开文件夹并选中文件
            await Process.run('explorer', ['/select,', localPath]);
            return;
          } else {
            // 其他系统：打开文件夹
            final directory = file.parent.path;
            final dirUri = Uri.directory(directory);
            if (await canLaunchUrl(dirUri)) {
              await launchUrl(dirUri, mode: LaunchMode.externalApplication);
              return;
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('打开文件夹失败: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }
    }
    
    // 本地文件不存在，提示用户
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('本地视频文件不存在'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  Widget _buildFinalizeView(AutoModeProject project) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 80, color: Color(0xFF00E676)),
          SizedBox(height: 24),
          Text(
            '视频合成完成！',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 12),
          if (project.finalVideoUrl != null)
            ElevatedButton.icon(
              onPressed: () {
                // 可以添加播放或下载功能
              },
              icon: Icon(Icons.play_arrow),
              label: Text('播放最终视频'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF00E676),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputArea(AutoModeProject project) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color(0xFF1a1a2e),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: TextField(
                controller: _inputController,
                enabled: true, // CRITICAL: 始终启用，允许用户输入和编辑
                readOnly: false, // CRITICAL: 允许编辑
                enableInteractiveSelection: true, // CRITICAL: 允许选择和复制粘贴
                keyboardType: TextInputType.multiline, // 支持多行输入
                textInputAction: TextInputAction.newline, // 多行时使用换行而不是提交
                style: TextStyle(color: Colors.white, fontSize: 15),
                maxLines: 3,
                minLines: 1,
                // CRITICAL: 添加键盘快捷键支持（Ctrl+V 粘贴，Ctrl+C 复制，Delete/Backspace 删除）
                keyboardAppearance: Brightness.dark,
                decoration: InputDecoration(
                  hintText: project.currentStep == AutoModeStep.script
                      ? '告诉我你想创作的故事...'
                      : project.currentStep == AutoModeStep.image
                          ? '输入修改意见或描述想要调整的内容...'
                          : '输入修改意见或回复"继续"...',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 15),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                onChanged: (value) {
                  // 空回调，确保可以输入
                },
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    _handleInput(value);
                  }
                },
              ),
            ),
          ),
          SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: project.isProcessing
                ? null
                : () {
                    final input = _inputController.text.trim();
                    if (input.isNotEmpty) {
                      _handleInput(input);
                    }
                  },
            icon: project.isProcessing
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Icon(Icons.send, size: 20),
            label: Text(project.isProcessing ? '处理中...' : '发送'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _getStepColor(project.currentStep),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 自动模式视频播放器 Widget（独立组件，管理首帧加载状态）
class _AutoModeVideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final String? localPath;
  final VoidCallback onPlay;
  final Function(Offset) onContextMenu;
  
  const _AutoModeVideoPlayerWidget({
    required this.videoUrl,
    this.localPath,
    required this.onPlay,
    required this.onContextMenu,
  });
  
  @override
  State<_AutoModeVideoPlayerWidget> createState() => _AutoModeVideoPlayerWidgetState();
}

class _AutoModeVideoPlayerWidgetState extends State<_AutoModeVideoPlayerWidget> {
  String? _thumbnailPath;
  bool _isLoadingThumbnail = false;
  
  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }
  
  Future<void> _loadThumbnail() async {
    if (widget.localPath == null || widget.localPath!.isEmpty) {
      return;
    }
    
    if (_isLoadingThumbnail || _thumbnailPath != null) {
      return;
    }
    
    setState(() {
      _isLoadingThumbnail = true;
    });
    
    try {
      final file = File(widget.localPath!);
      if (!await file.exists()) {
        if (mounted) {
          setState(() {
            _isLoadingThumbnail = false;
          });
        }
        return;
      }
      
      // 使用 FFmpeg 提取第一帧
      final ffmpegService = FFmpegService();
      final tempDir = await Directory.systemTemp.createTemp('xinghe_video_thumbnails');
      final fileName = file.uri.pathSegments.last.replaceAll(RegExp(r'\.[^.]+$'), '');
      final thumbnailPath = '${tempDir.path}${Platform.pathSeparator}${fileName}_thumb.jpg';
      
      // 提取第一帧（时间点 0.1 秒，避免黑屏）
      final result = await ffmpegService.extractFrame(
        videoPath: widget.localPath!,
        outputPath: thumbnailPath,
        timeOffset: Duration(milliseconds: 100),
      );
      
      if (mounted && result && File(thumbnailPath).existsSync()) {
        setState(() {
          _thumbnailPath = thumbnailPath;
          _isLoadingThumbnail = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _isLoadingThumbnail = false;
          });
        }
      }
    } catch (e) {
      print('[AutoModeScreen] 加载视频首帧失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingThumbnail = false;
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onPlay,
      onSecondaryTapDown: (details) => widget.onContextMenu(details.globalPosition),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 视频首帧或占位符
            if (_thumbnailPath != null && File(_thumbnailPath!).existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                  child: Image.file(
                    File(_thumbnailPath!),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.black.withOpacity(0.3),
                        child: Icon(Icons.videocam, color: Colors.white38, size: 40),
                      );
                    },
                  ),
                ),
              )
            else
              Container(
                color: Colors.black.withOpacity(0.3),
                child: Icon(Icons.videocam, color: Colors.white38, size: 40),
              ),
            // 播放按钮
            Center(
              child: Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.play_arrow, color: Colors.white, size: 32),
              ),
            ),
            // 加载首帧指示器
            if (_isLoadingThumbnail)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
