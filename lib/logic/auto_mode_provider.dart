import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pool/pool.dart';
import '../models/scene_model.dart';
import '../models/scene_status.dart';
import '../models/auto_mode_project.dart';
import '../models/auto_mode_step.dart';
import '../models/character_model.dart';
import '../models/prompt_template.dart';
import '../services/prompt_store.dart';
import '../services/api_config_manager.dart';
import '../services/ffmpeg_service.dart';
import '../services/heavy_task_runner.dart';
import '../services/api_service.dart';

// 用于启动不等待的异步任务
void unawaited(Future<void> future) {
  // 忽略 future，仅用于启动异步任务
}

/// Auto Mode 状态管理 Provider
/// 支持多个项目，每个项目有独立的 ID 和数据
/// 单例模式，确保所有实例共享数据
class AutoModeProvider extends ChangeNotifier {
  // CRITICAL: 使用独立的 Box 名称，完全隔离自动模式和手动模式的数据
  static const String _boxName = 'xinghe_auto_mode_v2';
  static Box? _projectsBox;
  
  // 单例实例
  static AutoModeProvider? _instance;
  factory AutoModeProvider() {
    _instance ??= AutoModeProvider._internal();
    return _instance!;
  }
  AutoModeProvider._internal();
  
  // 项目映射：projectId -> AutoModeProject
  final Map<String, AutoModeProject> _projects = {};
  
  // 当前活动的项目 ID（用于向后兼容）
  String? _currentProjectId;
  
  // 自动保存相关（每个项目独立）
  final Map<String, Timer> _saveTimers = {};
  bool _isInitialized = false;
  
  // 500 错误断路器 - 当检测到服务器错误时，停止所有待处理任务
  final Map<String, bool> _isAborted = {};  // projectId -> isAborted
  
  // CRITICAL: 生命周期安全标志
  bool _isDisposed = false;

  // Getters（向后兼容，使用当前项目）
  AutoModeStep get currentStep => _getCurrentProject()?.currentStep ?? AutoModeStep.script;
  String get currentScript => _getCurrentProject()?.currentScript ?? '';
  String get currentLayout => _getCurrentProject()?.currentLayout ?? '';
  List<SceneModel> get scenes => _getCurrentProject()?.scenes ?? [];
  bool get isProcessing => _getCurrentProject()?.isProcessing ?? false;
  String? get errorMessage => _getCurrentProject()?.errorMessage;
  String? get finalVideoUrl => _getCurrentProject()?.finalVideoUrl;
  DateTime? get lastModified => _getCurrentProject()?.lastModified;
  bool get isSaving => _getCurrentProject()?.isSaving ?? false;
  bool get hasUnsavedChanges => _getCurrentProject()?.hasUnsavedChanges ?? false;
  bool get isInitialized => _isInitialized;

  /// 获取当前项目（向后兼容）
  AutoModeProject? _getCurrentProject() {
    if (_currentProjectId != null) {
      return _projects[_currentProjectId];
    }
    return null;
  }

  /// 根据 ID 获取项目
  /// CRITICAL: 自动处理项目 ID 的前缀问题
  AutoModeProject? getProjectById(String projectId) {
    // 如果项目 ID 包含 'project_' 前缀，先尝试直接查找
    if (_projects.containsKey(projectId)) {
      return _projects[projectId];
    }
    // 如果不包含前缀，尝试添加前缀后查找（兼容旧数据）
    if (!projectId.startsWith('project_')) {
      final withPrefix = 'project_$projectId';
      if (_projects.containsKey(withPrefix)) {
        return _projects[withPrefix];
      }
    } else {
      // 如果包含前缀，尝试移除前缀后查找
      final withoutPrefix = projectId.substring(8);
      if (_projects.containsKey(withoutPrefix)) {
        return _projects[withoutPrefix];
      }
    }
    return null;
  }

  /// 获取所有项目
  Map<String, AutoModeProject> get allProjects => Map.unmodifiable(_projects);

  /// 获取当前步骤的显示名称（向后兼容）
  String get currentStepName {
    final project = _getCurrentProject();
    if (project == null) return '剧本生成';
    
    switch (project.currentStep) {
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

  /// 初始化 Provider（加载所有项目）
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // CRITICAL: 打开独立的 Box，完全隔离自动模式数据
      _projectsBox = await Hive.openBox(_boxName);
      
      // CRITICAL: 一次性清理损坏的重复键
      await _purgeCorruptedKeys();
      
      // 加载所有项目
      await _loadAllProjects();
      
      // CRITICAL: 自动恢复最后活动的项目
      final prefs = await SharedPreferences.getInstance();
      final lastActiveProjectId = prefs.getString('last_active_project');
      if (lastActiveProjectId != null && lastActiveProjectId.isNotEmpty) {
        // 清理项目 ID（移除可能的 'project_' 前缀）
        String cleanProjectId = lastActiveProjectId;
        if (cleanProjectId.startsWith('project_')) {
          cleanProjectId = cleanProjectId.substring(8);
        }
        
        // 如果项目存在，设置为当前项目
        if (_projects.containsKey(cleanProjectId)) {
          _currentProjectId = cleanProjectId;
          print('[AutoModeProvider] 自动恢复最后活动的项目: $cleanProjectId');
        } else {
          // 如果项目不存在，清除保存的 ID
          await prefs.remove('last_active_project');
        }
      }
      
      _isInitialized = true;
      _safeNotifyListeners();
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] AutoModeProvider 初始化失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
      _isInitialized = true;
    }
  }

  /// 初始化或切换到项目（仅加载，不创建）
  /// CRITICAL: 此方法只用于加载已存在的项目，不会创建新项目
  /// 如果项目不存在，会抛出异常
  Future<void> initializeProject(String projectId) async {
    if (!_isInitialized) {
      await initialize();
    }

    // CRITICAL: 如果 projectId 为空，抛出异常
    if (projectId.isEmpty) {
      throw ArgumentError('projectId 不能为空');
    }

    // CRITICAL: 清理项目 ID（移除可能的 'project_' 前缀）
    String cleanProjectId = projectId;
    if (cleanProjectId.startsWith('project_')) {
      cleanProjectId = cleanProjectId.substring(8);
      print('[AutoModeProvider] 清理项目 ID: $projectId -> $cleanProjectId');
    }

    print('[AutoModeProvider] 加载项目: $cleanProjectId');

    // STEP 1: 检查内存中是否已存在项目
    if (_projects.containsKey(cleanProjectId)) {
      print('[AutoModeProvider] ✓ 项目已存在于内存中: $cleanProjectId');
      print('[AutoModeProvider] 项目详情: 标题=${_projects[cleanProjectId]!.title}, 剧本=${_projects[cleanProjectId]!.currentScript.isNotEmpty ? "有" : "无"}, 分镜=${_projects[cleanProjectId]!.currentLayout.isNotEmpty ? "有" : "无"}, 场景数=${_projects[cleanProjectId]!.scenes.length}');
      _currentProjectId = cleanProjectId;
      await _saveLastActiveProject(cleanProjectId);
      _safeNotifyListeners();
      return;
    }

    // STEP 2: 检查 Hive 中是否已存在项目
    if (_projectsBox != null && _projectsBox!.isOpen) {
      // CRITICAL: 使用正确的存储键格式
      final storageKey = 'project_$cleanProjectId';
      
      // 检查存储键是否存在
      if (_projectsBox!.containsKey(storageKey)) {
        final existingData = _projectsBox!.get(storageKey);
        
        if (existingData != null) {
          try {
            // 安全地转换 Map
            final data = Map<String, dynamic>.from(existingData as Map);
            final existingProject = AutoModeProject.fromJson(data);
            
            // 验证数据完整性
            print('[AutoModeProvider] ✓ 从 Hive 加载已存在的项目: $cleanProjectId');
            print('[AutoModeProvider] 项目详情: 标题=${existingProject.title}, 剧本=${existingProject.currentScript.isNotEmpty ? "有(${existingProject.currentScript.length}字符)" : "无"}, 分镜=${existingProject.currentLayout.isNotEmpty ? "有(${existingProject.currentLayout.length}字符)" : "无"}, 场景数=${existingProject.scenes.length}');
            
            // 加载已存在的项目
            _projects[cleanProjectId] = existingProject;
            _currentProjectId = cleanProjectId;
            await _saveLastActiveProject(cleanProjectId);
            _safeNotifyListeners();
            return;
          } catch (e, stackTrace) {
            print('[AutoModeProvider] ✗ 加载已存在项目失败: $e');
            print('[AutoModeProvider] 堆栈: $stackTrace');
            throw Exception('加载项目失败: $e');
          }
        } else {
          throw Exception('项目数据为空: $storageKey');
        }
      } else {
        throw Exception('项目不存在: $storageKey');
      }
    } else {
      throw Exception('存储 Box 未打开');
    }
  }
  
  /// 创建新项目（仅由 UI 的 "+" 按钮调用）
  /// CRITICAL: 这是唯一创建新项目的方法
  Future<String> createNewProject({String? title}) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    // 生成新的项目 ID（纯时间戳，不包含前缀）
    final projectId = '${DateTime.now().millisecondsSinceEpoch}';
    final projectTitle = title ?? '未命名项目';
    
    print('[AutoModeProvider] 创建新项目: $projectId, 标题: $projectTitle');
    
    // 创建新项目对象
    final newProject = AutoModeProject(
      id: projectId,
      title: projectTitle,
    );
    
    // 添加到内存
    _projects[projectId] = newProject;
    _currentProjectId = projectId;
    
    // 立即保存到磁盘
    await _saveProject(projectId);
    await _saveLastActiveProject(projectId);
    
    _safeNotifyListeners();
    
    print('[AutoModeProvider] ✓ 新项目已创建: $projectId');
    return projectId;
  }
  
  /// 保存最后活动的项目 ID
  Future<void> _saveLastActiveProject(String projectId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_active_project', projectId);
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 保存最后活动项目失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
    }
  }

  /// 加载所有项目
  /// CRITICAL: 清理重复前缀的键，标准化项目 ID
  Future<void> _loadAllProjects() async {
    try {
      if (_projectsBox == null || !_projectsBox!.isOpen) return;
      
      // 获取所有键（项目 ID）
      final keys = _projectsBox!.keys.toList();
      final keysToDelete = <String>[]; // 需要删除的混乱键
      
      print('[AutoModeProvider] 开始加载项目，发现 ${keys.length} 个存储键');
      
      for (final key in keys) {
        try {
          final keyStr = key.toString();
          
          // CRITICAL: 清理重复前缀的键
          // 如果键是 'project_project_xxx'，标记为删除
          if (keyStr.startsWith('project_project_')) {
            print('[AutoModeProvider] 发现重复前缀键，标记删除: $keyStr');
            keysToDelete.add(keyStr);
            continue;
          }
          
          final rawData = _projectsBox!.get(key);
          if (rawData == null) {
            print('[AutoModeProvider] ⚠️ 跳过空数据键: $keyStr');
            continue;
          }
          
          // CRITICAL: 使用安全的 Map 转换，避免类型转换错误
          // 修复: "type '_Map<dynamic, dynamic>' is not a subtype" 错误
          final safeMap = Map<String, dynamic>.from(rawData as Map);
          
          // CRITICAL: 尝试解析项目，如果失败则跳过该项目，不影响其他项目
          final project = AutoModeProject.fromJson(safeMap);
          
          // CRITICAL: 验证项目 ID 不为空
          if (project.id.isEmpty) {
            print('[AutoModeProvider] ⚠️ 跳过无效项目（ID为空）: $keyStr');
            keysToDelete.add(keyStr); // 标记为删除
            continue;
          }
          
          // CRITICAL: 标准化项目 ID（只保留时间戳部分）
          // 从存储键中提取干净的项目 ID
          String cleanProjectId;
          if (keyStr.startsWith('project_')) {
            cleanProjectId = keyStr.substring(8); // 移除 'project_' 前缀
          } else {
            cleanProjectId = keyStr;
          }
          
          // 如果项目 ID 与存储键不匹配，需要迁移
          if (project.id != cleanProjectId) {
            print('[AutoModeProvider] 项目 ID 不匹配: 存储键=$keyStr, 项目ID=${project.id}, 标准化为=$cleanProjectId');
            // 更新项目 ID
            final updatedProject = project.copyWith(id: cleanProjectId);
            _projects[cleanProjectId] = updatedProject;
            
            // 如果旧键与新键不同，删除旧键
            if (keyStr != 'project_$cleanProjectId') {
              keysToDelete.add(keyStr);
            }
          } else {
            _projects[cleanProjectId] = project;
          }
          
          // 健壮的初始化：检查部分完成的项目
          // 如果 currentScript 存在但 scenes 为空，说明在剧本步骤
          if (project.currentScript.isNotEmpty && project.scenes.isEmpty) {
            project.currentStep = AutoModeStep.script;
            project.isProcessing = false; // 重置处理状态，允许继续
            project.generationStatus = null;
            print('[AutoModeProvider] 检测到部分完成的项目 (剧本阶段): $cleanProjectId');
          }
          // 如果 currentLayout 存在但 scenes 为空，说明在分镜步骤
          else if (project.currentLayout.isNotEmpty && project.scenes.isEmpty) {
            project.currentStep = AutoModeStep.layout;
            project.isProcessing = false;
            project.generationStatus = null;
            print('[AutoModeProvider] 检测到部分完成的项目 (分镜阶段): $cleanProjectId');
          }
          
          // 验证本地文件是否存在
          final updatedScenes = <SceneModel>[];
          bool hasChanges = false;
          for (final scene in project.scenes) {
            SceneModel updatedScene = scene;
            
            // 检查本地图片路径
            if (scene.localImagePath != null && scene.localImagePath!.isNotEmpty) {
              final file = File(scene.localImagePath!);
              if (!await file.exists()) {
                print('[AutoModeProvider] 项目 $cleanProjectId 场景 ${scene.index} 本地图片文件不存在');
                updatedScene = updatedScene.copyWith(localImagePath: null);
                hasChanges = true;
              }
            }
            
            // 检查本地视频路径
            if (scene.localVideoPath != null && scene.localVideoPath!.isNotEmpty) {
              final file = File(scene.localVideoPath!);
              if (!await file.exists()) {
                print('[AutoModeProvider] 项目 $cleanProjectId 场景 ${scene.index} 本地视频文件不存在');
                updatedScene = updatedScene.copyWith(localVideoPath: null);
                hasChanges = true;
              }
            }
            
            updatedScenes.add(updatedScene);
          }
          
          // 如果项目 ID 被更新，需要保存到正确的存储键
          AutoModeProject finalProject = project;
          if (project.id != cleanProjectId) {
            finalProject = project.copyWith(id: cleanProjectId);
            // 保存到正确的存储键
            await _projectsBox!.put('project_$cleanProjectId', finalProject.toJson());
            // 如果旧键与新键不同，标记旧键为删除
            if (keyStr != 'project_$cleanProjectId') {
              keysToDelete.add(keyStr);
            }
          }
          
          if (hasChanges || updatedScenes.length != finalProject.scenes.length) {
            // 更新场景列表
            finalProject = finalProject.copyWith(scenes: updatedScenes);
            await _saveProject(cleanProjectId);
          }
          
          // CRITICAL: 使用清理后的项目 ID 作为键
          _projects[cleanProjectId] = finalProject;
          
          print('[AutoModeProvider] ✓ 成功恢复项目: ID=$cleanProjectId, 标题=${finalProject.title}, 场景数=${finalProject.scenes.length}, 当前步骤=${finalProject.currentStep}');
        } catch (e, stackTrace) {
          // CRITICAL: 单个项目失败不影响其他项目
          final keyStr = key.toString();
          print('[AutoModeProvider] ⚠️ 跳过损坏的项目 [$keyStr]: $e');
          print('[AutoModeProvider] 堆栈: $stackTrace');
          // 可选：自动删除损坏的数据
          // keysToDelete.add(keyStr);
        }
      }
      
      // CRITICAL: 删除所有标记为删除的混乱键
      if (keysToDelete.isNotEmpty) {
        print('[AutoModeProvider] 开始清理 ${keysToDelete.length} 个混乱的存储键...');
        for (final keyToDelete in keysToDelete) {
          try {
            await _projectsBox!.delete(keyToDelete);
            print('[AutoModeProvider] ✓ 已删除混乱键: $keyToDelete');
          } catch (e, stackTrace) {
            print('❌ [CRITICAL ERROR CAUGHT] 删除键失败: $keyToDelete');
            print('❌ [Error Details]: $e');
            print('📍 [Stack Trace]: $stackTrace');
          }
        }
        // 强制刷新到磁盘
        await _projectsBox!.flush();
        print('[AutoModeProvider] ✓ 清理完成');
      }
      
      print('[AutoModeProvider] ✓ 已加载 ${_projects.length} 个项目');
      _safeNotifyListeners();
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 加载所有项目失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
    }
  }

  /// 清理损坏的重复键（一次性清理脚本）
  Future<void> _purgeCorruptedKeys() async {
    if (_projectsBox == null || !_projectsBox!.isOpen) return;
    
    try {
      print('[AutoModeProvider] 开始清理损坏的重复键...');
      final corruptedKeys = _projectsBox!.keys
          .where((k) => k.toString().contains('project_project_'))
          .toList();
      
      if (corruptedKeys.isNotEmpty) {
        print('[AutoModeProvider] 发现 ${corruptedKeys.length} 个损坏的键');
        for (final key in corruptedKeys) {
          try {
            await _projectsBox!.delete(key);
            print('[AutoModeProvider] ✓ 已删除损坏的键: $key');
          } catch (e, stackTrace) {
            print('❌ [CRITICAL ERROR CAUGHT] 删除损坏键失败: $key');
            print('❌ [Error Details]: $e');
            print('📍 [Stack Trace]: $stackTrace');
          }
        }
        await _projectsBox!.flush();
        print('[AutoModeProvider] ✓ 清理完成');
      } else {
        print('[AutoModeProvider] ✓ 没有发现损坏的键');
      }
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 清理损坏键失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
    }
  }
  
  /// 保存到磁盘（针对特定项目）
  /// CRITICAL: 默认立即保存，不使用防抖，确保数据不丢失
  /// 如果确实需要防抖（如频繁输入），可以设置 immediate: false
  Future<void> _saveToDisk(String projectId, {bool immediate = true}) async {
    // CRITICAL: 生命周期安全检查
    if (_isDisposed) {
      print('[AutoModeProvider] 警告: Provider 已销毁，跳过保存 $projectId');
      return;
    }
    
    // 取消之前的定时器（如果有）
    _saveTimers[projectId]?.cancel();
    
    if (immediate) {
      // 立即保存，确保数据不丢失
      await _performSave(projectId);
    } else {
      // 延迟保存（仅在明确需要防抖时使用）
      _saveTimers[projectId] = Timer(Duration(milliseconds: 500), () {
        if (!_isDisposed) {
          _performSave(projectId);
        }
      });
    }
  }

  /// 立即保存（公共方法，供 UI 调用）
  Future<void> saveImmediately(String projectId) async {
    await _performSave(projectId);
  }
  
  /// 保存所有活动项目（用于应用生命周期事件）
  Future<void> saveAllProjects() async {
    print('[AutoModeProvider] 开始保存所有活动项目...');
    final futures = <Future>[];
    for (final projectId in _projects.keys) {
      futures.add(_performSave(projectId));
    }
    await Future.wait(futures);
    print('[AutoModeProvider] 已保存 ${_projects.length} 个项目');
  }

  /// 执行保存操作（保存特定项目）
  /// CRITICAL: 使用 flush() 确保数据写入物理磁盘，防止崩溃时数据丢失
  /// CRITICAL: 修复克隆 bug - 添加检查，确保 ID 不变
  Future<void> _performSave(String projectId) async {
    // CRITICAL: 生命周期安全检查 - 必须在最开始检查
    if (_isDisposed) {
      print('[AutoModeProvider] 警告: Provider 已销毁，跳过保存 $projectId');
      return;
    }
    
    // CRITICAL: 检查项目是否存在，防止克隆 bug
    if (!_projects.containsKey(projectId)) {
      print('[AutoModeProvider] ✗ 警告: 项目不存在于内存中，跳过保存: $projectId');
      return;
    }
    
    if (_projectsBox == null || !_projectsBox!.isOpen) {
      print('[AutoModeProvider] 警告: Hive Box 未打开，无法保存项目 $projectId');
      return;
    }
    
    try {
      final project = _projects[projectId]!;
      project.isSaving = true;
      project.hasUnsavedChanges = false;
      _safeNotifyListeners();
      
      // CRITICAL: 清理项目 ID（移除可能的 'project_' 前缀）
      // 但确保不改变原始项目对象的 ID
      String cleanProjectId = projectId;
      if (cleanProjectId.startsWith('project_')) {
        cleanProjectId = cleanProjectId.substring(8);
        print('[AutoModeProvider] 清理项目 ID 前缀: $projectId -> $cleanProjectId');
      }
      
      // CRITICAL: 存储键格式必须严格为 'project_$cleanProjectId'
      // 确保 ID 在保存过程中不会被改变
      final storageKey = 'project_$cleanProjectId';
      
      // CRITICAL: 验证项目 ID 是否正确保存
      // 确保 toJson() 中的 id 字段是原始的项目 ID，不会被重新生成
      final jsonData = project.toJson();
      
      // CRITICAL: 验证 ID 字段
      final savedId = jsonData['id'] as String?;
      if (savedId != cleanProjectId) {
        print('[AutoModeProvider] ⚠️ 警告: 项目 ID 不匹配! 期望: $cleanProjectId, 实际: $savedId');
        // 强制修正 ID
        jsonData['id'] = cleanProjectId;
      }
      
      // CRITICAL: 先写入 Hive
      await _projectsBox!.put(storageKey, jsonData);
      
      // CRITICAL: 立即刷新到物理磁盘，确保数据不会因崩溃而丢失
      await _projectsBox!.flush();
      
      project.lastModified = DateTime.now();
      
      print('[AutoModeProvider] ✓ 已保存项目到磁盘: $cleanProjectId (存储键: $storageKey, ID: ${jsonData['id']})');
      print('[AutoModeProvider] 项目数据大小: ${jsonData.toString().length} 字符');
    } catch (e, stackTrace) {
      print('[AutoModeProvider] ✗ 保存项目 $projectId 失败: $e');
      print('[AutoModeProvider] 堆栈: $stackTrace');
      if (_projects.containsKey(projectId)) {
        _projects[projectId]!.hasUnsavedChanges = true;
      }
    } finally {
      if (!_isDisposed && _projects.containsKey(projectId)) {
        _projects[projectId]!.isSaving = false;
      }
      _safeNotifyListeners();
    }
  }
  
  /// 安全的通知监听器（生命周期安全）
  void _safeNotifyListeners() {
    if (!_isDisposed && hasListeners) {
      // 打印当前状态信息，帮助排查 UI 不更新问题
      final project = _getCurrentProject();
      print('📢 [UI Update] Notifying listeners');
      print('📢 [UI State] Current Step: ${project?.currentStep ?? "无项目"}, isProcessing: ${project?.isProcessing ?? false}');
      print('📢 [UI State] Script length: ${project?.currentScript.length ?? 0}, Scenes: ${project?.scenes.length ?? 0}');
      print('📢 [UI State] Has listeners: $hasListeners, Is disposed: $_isDisposed');
      
      notifyListeners();
    } else {
      print('⚠️ [UI Update] Skipped notification - disposed: $_isDisposed, hasListeners: $hasListeners');
    }
  }

  /// 保存项目（内部方法）
  Future<void> _saveProject(String projectId) async {
    await _performSave(projectId);
  }

  /// 标记有未保存的更改（针对特定项目）
  /// CRITICAL: 立即保存，不使用防抖，确保数据不丢失
  void _markDirty(String projectId) {
    if (!_projects.containsKey(projectId)) return;
    
    final project = _projects[projectId]!;
    project.hasUnsavedChanges = true;
    project.lastModified = DateTime.now();
    // CRITICAL: 立即保存，不使用防抖延迟
    _saveToDisk(projectId, immediate: true);
  }

  /// 清理空项目（删除没有剧本内容的项目）
  /// 用于清理自动创建的空项目
  Future<void> cleanTrashProjects() async {
    if (_projectsBox == null || !_projectsBox!.isOpen) {
      print('[AutoModeProvider] Box 未打开，无法清理');
      return;
    }
    
    try {
      print('[AutoModeProvider] 开始清理空项目...');
      final keysToDelete = <String>[];
      
      // 遍历所有键，找出空项目
      for (final key in _projectsBox!.keys) {
        try {
          final projectData = _projectsBox!.get(key);
          if (projectData == null) {
            keysToDelete.add(key.toString());
            continue;
          }
          
          final data = Map<String, dynamic>.from(projectData as Map);
          final currentScript = data['currentScript'] as String?;
          
          // 如果剧本为空或null，标记为删除
          if (currentScript == null || currentScript.isEmpty) {
            keysToDelete.add(key.toString());
            print('[AutoModeProvider] 发现空项目: $key');
          }
        } catch (e, stackTrace) {
          print('❌ [CRITICAL ERROR CAUGHT] 检查项目失败: $key');
          print('❌ [Error Details]: $e');
          print('📍 [Stack Trace]: $stackTrace');
          // 如果解析失败，也标记为删除
          keysToDelete.add(key.toString());
        }
      }
      
      // 删除所有空项目
      if (keysToDelete.isNotEmpty) {
        print('[AutoModeProvider] 准备删除 ${keysToDelete.length} 个空项目...');
        for (final key in keysToDelete) {
          try {
            await _projectsBox!.delete(key);
            print('[AutoModeProvider] ✓ 已删除: $key');
          } catch (e, stackTrace) {
            print('❌ [CRITICAL ERROR CAUGHT] 删除空项目失败: $key');
            print('❌ [Error Details]: $e');
            print('📍 [Stack Trace]: $stackTrace');
          }
        }
        
        // 强制刷新到磁盘
        await _projectsBox!.flush();
        
        // 重新加载项目
        _projects.clear();
        await _loadAllProjects();
        
        print('[AutoModeProvider] ✓ 清理完成，已删除 ${keysToDelete.length} 个空项目');
      } else {
        print('[AutoModeProvider] ✓ 没有发现空项目');
      }
    } catch (e, stackTrace) {
      print('[AutoModeProvider] ✗ 清理失败: $e');
      print('[AutoModeProvider] 堆栈: $stackTrace');
    }
  }
  
  /// 强制清空所有数据（核清理）
  /// CRITICAL: 使用 Box.clear() 彻底删除所有数据，包括损坏的键
  /// 警告：此操作不可撤销！
  Future<void> forceClearAllData() async {
    if (_isDisposed) return;
    
    try {
      print('[AutoModeProvider] ⚠️ 开始核清理所有自动模式项目数据...');
      
      // CRITICAL: 1. 从 Hive 磁盘删除所有数据
      if (_projectsBox != null && _projectsBox!.isOpen) {
        // 使用 clear() 方法彻底清空 Box（比逐个删除更彻底）
        await _projectsBox!.clear();
        print('[AutoModeProvider] ✓ 已清空 Hive Box');
        
        // CRITICAL: 强制刷新到磁盘，确保数据真正被删除
        await _projectsBox!.flush();
        print('[AutoModeProvider] ✓ 已刷新到磁盘');
      }
      
      // CRITICAL: 2. 清空内存
      _projects.clear();
      _currentProjectId = null;
      print('[AutoModeProvider] ✓ 已清空内存');
      
      // CRITICAL: 3. 清除 SharedPreferences 中的相关数据
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_active_project');
      print('[AutoModeProvider] ✓ 已清除 SharedPreferences');
      
      // CRITICAL: 4. 重置 UI
      _safeNotifyListeners();
      
      print('[AutoModeProvider] ✓ 核清理完成，所有数据已彻底删除');
    } catch (e, stackTrace) {
      print('[AutoModeProvider] ✗ 核清理失败: $e');
      print('[AutoModeProvider] 堆栈: $stackTrace');
      rethrow; // 重新抛出异常，让 UI 可以显示错误
    }
  }
  
  /// 危险：清除所有数据（用于修复数据混乱问题）
  /// 警告：此方法会删除所有自动模式项目数据，请谨慎使用！
  /// 注意：此方法逐个删除键，forceClearAllData() 使用 clear() 更彻底
  Future<void> dangerouslyClearAllData() async {
    if (_isDisposed) return;
    
    try {
      print('[AutoModeProvider] ⚠️ 开始清除所有自动模式项目数据...');
      
      if (_projectsBox != null && _projectsBox!.isOpen) {
        // 获取所有键
        final allKeys = _projectsBox!.keys.toList();
        print('[AutoModeProvider] 发现 ${allKeys.length} 个存储键，准备删除...');
        
        // 删除所有键
        for (final key in allKeys) {
          try {
            await _projectsBox!.delete(key);
            print('[AutoModeProvider] ✓ 已删除: $key');
          } catch (e, stackTrace) {
            print('❌ [CRITICAL ERROR CAUGHT] 删除项目键失败: $key');
            print('❌ [Error Details]: $e');
            print('📍 [Stack Trace]: $stackTrace');
          }
        }
        
        // 强制刷新到磁盘
        await _projectsBox!.flush();
      }
      
      // 清空内存中的项目
      _projects.clear();
      _currentProjectId = null;
      
      // 清除最后活动的项目
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_active_project');
      
      _safeNotifyListeners();
      
      print('[AutoModeProvider] ✓ 所有数据已清除');
    } catch (e, stackTrace) {
      print('[AutoModeProvider] ✗ 清除数据失败: $e');
      print('[AutoModeProvider] 堆栈: $stackTrace');
    }
  }
  
  /// 清除项目草稿
  /// 永久删除项目（从磁盘和内存中彻底删除）
  /// CRITICAL: 确保项目不会在重启后重新出现
  Future<void> deleteProject(String projectId) async {
    if (_isDisposed) return;
    
    try {
      print('[AutoModeProvider] 开始永久删除项目: $projectId');
      
      // CRITICAL: 1. 从 Hive 磁盘删除（最重要的部分！）
      if (_projectsBox != null && _projectsBox!.isOpen) {
        // 清理项目 ID（移除可能的 'project_' 前缀）
        String cleanProjectId = projectId;
        if (cleanProjectId.startsWith('project_')) {
          cleanProjectId = cleanProjectId.substring(8);
        }
        
        // 使用正确的存储键格式
        final storageKey = 'project_$cleanProjectId';
        
        // 删除主键
        await _projectsBox!.delete(storageKey);
        print('[AutoModeProvider] ✓ 已从 Hive 删除: $storageKey');
        
        // CRITICAL: 处理可能的前缀不匹配键（以防万一）
        // 尝试删除不带前缀的键（如果存在）
        if (cleanProjectId != projectId) {
          await _projectsBox!.delete(projectId);
          print('[AutoModeProvider] ✓ 已删除备用键: $projectId');
        }
        
        // CRITICAL: 强制刷新到磁盘，确保删除操作真正写入
        await _projectsBox!.flush();
        print('[AutoModeProvider] ✓ 已刷新到磁盘');
      }
      
      // CRITICAL: 2. 从内存中删除
      _projects.remove(projectId);
      print('[AutoModeProvider] ✓ 已从内存删除');
      
      // CRITICAL: 3. 取消相关的定时器
      _saveTimers[projectId]?.cancel();
      _saveTimers.remove(projectId);
      
      // CRITICAL: 4. 如果删除的是当前活动项目，重置状态
      if (_currentProjectId == projectId) {
        _currentProjectId = null;
        print('[AutoModeProvider] ✓ 已重置当前项目');
      }
      
      // CRITICAL: 5. 清除 SharedPreferences 中的最后活动项目（如果匹配）
      final prefs = await SharedPreferences.getInstance();
      final lastActiveProjectId = prefs.getString('last_active_project');
      if (lastActiveProjectId == projectId || lastActiveProjectId == 'project_$projectId') {
        await prefs.remove('last_active_project');
        print('[AutoModeProvider] ✓ 已清除最后活动项目记录');
      }
      
      // CRITICAL: 6. 刷新 UI
      _safeNotifyListeners();
      
      print('[AutoModeProvider] ✓ 项目 $projectId 已永久删除');
    } catch (e, stackTrace) {
      print('[AutoModeProvider] ✗ 删除项目失败: $e');
      print('[AutoModeProvider] 堆栈: $stackTrace');
      rethrow; // 重新抛出异常，让 UI 可以显示错误
    }
  }
  
  /// 清除项目草稿（保留方法以向后兼容）
  @Deprecated('使用 deleteProject 代替')
  Future<void> clearProject(String projectId) async {
    await deleteProject(projectId);
  }

  /// 处理用户输入（针对特定项目）
  Future<void> processInput(String projectId, String input) async {
    if (!_projects.containsKey(projectId)) {
      throw Exception('项目不存在: $projectId');
    }

    final project = _projects[projectId]!;
    if (project.isProcessing) return;

    project.isProcessing = true;
    project.errorMessage = null;
    _safeNotifyListeners();

    try {
      // CRITICAL: 更宽松的"继续"命令识别（支持多种变体）
      final trimmedInput = input.trim().toLowerCase();
      final isContinueCommand = trimmedInput == '继续' || 
                                trimmedInput == 'continue' ||
                                trimmedInput == '下一步' ||
                                trimmedInput == 'next' ||
                                trimmedInput == '继续下一步';
      
      if (isContinueCommand) {
        // 移动到下一步
        await _moveToNextStep(projectId);
      } else {
        // 处理修改请求，重新触发当前步骤
        await _processModification(projectId, input);
      }
    } catch (e, stackTrace) {
      project.errorMessage = e.toString();
      print('❌ [CRITICAL ERROR CAUGHT] processInput 处理输入失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
    } finally {
      project.isProcessing = false;
      _safeNotifyListeners();
    }
  }

  /// 移动到下一步（针对特定项目）
  Future<void> _moveToNextStep(String projectId) async {
    final project = _projects[projectId]!;
    
    switch (project.currentStep) {
      case AutoModeStep.script:
        // 如果还没有剧本，不能继续
        if (project.currentScript.isEmpty) {
          throw Exception('请先输入故事创意');
        }
        project.currentStep = AutoModeStep.character;
        _markDirty(projectId);
        await _generateCharacters(projectId);
        break;

      case AutoModeStep.character:
        // 如果还没有角色，不能继续
        if (project.characters.isEmpty) {
          throw Exception('请先生成角色');
        }
        // 检查所有角色是否都有提示词
        final incompleteCharacters = project.characters.where((c) => c.prompt.isEmpty).toList();
        if (incompleteCharacters.isNotEmpty) {
          throw Exception('请等待所有角色提示词生成完成');
        }
        project.currentStep = AutoModeStep.layout;
        _markDirty(projectId);
        await _generateLayout(projectId);
        break;

      case AutoModeStep.layout:
        // 如果还没有分镜，不能继续
        if (project.scenes.isEmpty) {
          throw Exception('请先生成分镜设计');
        }
        project.currentStep = AutoModeStep.image;
        _markDirty(projectId);
        await _generateAllImages(projectId);
        break;

      case AutoModeStep.image:
        // CRITICAL: 检查所有图片是否已生成（考虑本地路径和错误状态）
        final incompleteScenes = project.scenes.where((s) {
          // 检查是否正在生成
          if (s.isGeneratingImage || s.status == SceneStatus.processing || s.status == SceneStatus.queueing) {
            return true;
          }
          // 检查是否有图片（网络 URL 或本地路径）
          final hasImage = (s.imageUrl != null && s.imageUrl!.isNotEmpty) || 
                          (s.localImagePath != null && s.localImagePath!.isNotEmpty);
          // 如果有错误但没有图片，也算未完成
          if (s.status == SceneStatus.error && !hasImage) {
            return true;
          }
          // 如果没有图片且不是错误状态，也算未完成
          return !hasImage;
        }).toList();
        
        if (incompleteScenes.isNotEmpty) {
          final errorScenes = incompleteScenes.where((s) => s.status == SceneStatus.error).toList();
          if (errorScenes.isNotEmpty) {
            throw Exception('有 ${errorScenes.length} 个场景图片生成失败，请先重新生成失败的图片');
          } else {
            throw Exception('请等待所有图片生成完成（还有 ${incompleteScenes.length} 个场景未完成）');
          }
        }
        
        // 所有图片已生成，进入视频生成步骤
        project.currentStep = AutoModeStep.video;
        _markDirty(projectId);
        await _generateAllVideos(projectId);
        break;

      case AutoModeStep.video:
        // 检查所有视频是否已生成
        if (project.scenes.any((s) => s.videoUrl == null || s.videoUrl!.isEmpty)) {
          throw Exception('请等待所有视频生成完成');
        }
        project.currentStep = AutoModeStep.finalize;
        _markDirty(projectId);
        await _finalizeVideo(projectId);
        break;

      case AutoModeStep.finalize:
        // 已完成，重置
        resetProject(projectId);
        break;
    }
    _safeNotifyListeners();
  }

  /// 处理修改请求（针对特定项目）
  Future<void> _processModification(String projectId, String input) async {
    final project = _projects[projectId]!;
    
    switch (project.currentStep) {
      case AutoModeStep.script:
        await _generateScript(projectId, input);
        break;

      case AutoModeStep.character:
        await _generateCharacters(projectId, modification: input);
        break;

      case AutoModeStep.layout:
        await _generateLayout(projectId, modification: input);
        break;

      case AutoModeStep.image:
        // 图片步骤的修改需要指定场景索引
        // 这里简化处理，重新生成所有图片
        await _generateAllImages(projectId);
        break;

      case AutoModeStep.video:
        // 视频步骤的修改需要指定场景索引
        // 这里简化处理，重新生成所有视频
        await _generateAllVideos(projectId);
        break;

      default:
        break;
    }
    _safeNotifyListeners();
  }

  /// 生成剧本（针对特定项目）
  /// 每次文本更新立即保存，确保零数据丢失
  Future<void> _generateScript(String projectId, String userInput) async {
    final project = _projects[projectId]!;
    
    print('');
    print('═══════════════════════════════════════════════════════');
    print('🎬 [Script] Starting generation...');
    print('📝 [Step: Script] 开始生成剧本');
    print('📝 [Step Status] projectId: $projectId, userInput length: ${userInput.length}');
    print('📝 [Step Status] 当前项目状态 - isProcessing: ${project.isProcessing}, currentScript length: ${project.currentScript.length}');
    print('═══════════════════════════════════════════════════════');
    
    final apiConfigManager = ApiConfigManager();
    if (!apiConfigManager.hasLlmConfig) {
      throw Exception('请先在设置中配置 LLM API');
    }

    final apiService = apiConfigManager.createApiService();
    
    // 获取提示词模板
    String systemPrompt = '你是一个专业的动漫剧本作家，擅长创作动漫剧本。请根据用户提供的故事创意，生成一个完整的剧本。';
    
    final templates = promptStore.getTemplates(PromptCategory.script);
    if (templates.isNotEmpty) {
      // 使用第一个模板（可以根据需要选择）
      systemPrompt = '${templates.first.content}\n\n$systemPrompt';
    }

    // 设置处理状态，立即保存
    print('🎬 [Script] Setting isProcessing = true');
    project.isProcessing = true;
    project.generationStatus = '正在生成剧本...';
    await _saveToDisk(projectId, immediate: true);
    _safeNotifyListeners();  // 通知 UI 进入加载状态
    
    print('🎬 [Script] Calling API...');
    final response = await apiService.chatCompletion(
      model: apiConfigManager.llmModel,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userInput},
      ],
      temperature: 0.7,
    );

    print('🎬 [Script] Received API result');
    final scriptContent = response.choices.first.message.content;
    print('🎬 [Script] API result length: ${scriptContent.length} characters');
    print('🎬 [Script] API result preview: ${scriptContent.substring(0, scriptContent.length > 100 ? 100 : scriptContent.length)}...');
    
    // 立即更新并保存（零数据丢失）
    print('🎬 [Script] Updating project.currentScript...');
    project.currentScript = scriptContent;
    print('🎬 [Script] State updated. Script content length: ${project.currentScript.length}');
    print('🎬 [Script] Script preview: ${project.currentScript.substring(0, project.currentScript.length > 100 ? 100 : project.currentScript.length)}...');
    
    print('🎬 [Script] Setting isProcessing = false');
    project.isProcessing = false;
    project.generationStatus = null;
    
    // CRITICAL: 立即保存到磁盘，确保数据不丢失
    print('🎬 [Script] Saving to disk...');
    await _saveToDisk(projectId, immediate: true);
    
    print('🎬 [Script] Notifying listeners...');
    _safeNotifyListeners();
    
    print('✅ [Step: Script] 剧本生成完成');
    print('✅ [Step Status] 剧本长度: ${project.currentScript.length} 字符');
    print('═══════════════════════════════════════════════════════');
    print('');
  }

  /// 生成角色（针对特定项目）
  Future<void> _generateCharacters(String projectId, {String? modification}) async {
    final project = _projects[projectId]!;
    
    print('');
    print('═══════════════════════════════════════════════════════');
    print('👤 [Step: Character] 开始生成角色');
    print('👤 [Step Status] projectId: $projectId, hasModification: ${modification != null}');
    print('═══════════════════════════════════════════════════════');
    
    final apiConfigManager = ApiConfigManager();
    if (!apiConfigManager.hasLlmConfig) {
      throw Exception('请先在设置中配置 LLM API');
    }

    final apiService = apiConfigManager.createApiService();
    
    // 获取提示词模板
    String systemPrompt = '''你是一个专业的动漫角色设计师。请根据剧本内容，提取并生成所有角色的详细描述。

要求：
1. 识别剧本中的所有主要角色
2. 为每个角色生成详细的描述，包括：
   - 角色名称
   - 外貌特征（发型、服装、体型等）
   - 性格特点
   - 角色定位
3. 生成适合图片生成的提示词，包含角色外观的详细描述
4. 确保角色描述清晰、具体，适合AI图片生成

输出格式：JSON数组，每个元素包含 name（角色名称）和 prompt（角色提示词）字段''';

    final templates = promptStore.getTemplates(PromptCategory.character);
    if (templates.isNotEmpty) {
      systemPrompt = '${templates.first.content}\n\n$systemPrompt';
    }

    // 设置处理状态，立即保存
    project.isProcessing = true;
    project.generationStatus = '正在生成角色...';
    await _saveToDisk(projectId, immediate: true);
    
    final userContent = modification ?? project.currentScript;
    final response = await apiService.chatCompletion(
      model: apiConfigManager.llmModel,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': '请根据以下剧本生成角色列表：\n\n$userContent'},
      ],
      temperature: 0.7,
    );

    try {
      final content = response.choices.first.message.content;
      // 尝试提取 JSON
      final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(content);
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0)!;
        final List<dynamic> parsed = jsonDecode(jsonStr);
        
        project.characters = parsed.map((data) {
          final charData = data as Map<String, dynamic>;
          return CharacterModel(
            name: charData['name'] as String? ?? '未命名角色',
            prompt: charData['prompt'] as String? ?? charData['description'] as String? ?? '',
          );
        }).toList();
      } else {
        // 如果没有 JSON，尝试解析文本格式
        throw Exception('无法解析角色列表，请确保返回 JSON 格式');
      }
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 解析角色列表失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
      throw Exception('解析角色列表失败: $e');
    }

    project.isProcessing = false;
    project.generationStatus = null;
    
    // CRITICAL: 立即保存到磁盘，确保数据不丢失
    await _saveToDisk(projectId, immediate: true);
    _safeNotifyListeners();
  }

  /// 生成分镜设计（针对特定项目）
  Future<void> _generateLayout(String projectId, {String? modification}) async {
    final project = _projects[projectId]!;
    
    print('');
    print('═══════════════════════════════════════════════════════');
    print('🎬 [Step: Layout] 开始生成分镜设计');
    print('🎬 [Step Status] projectId: $projectId, hasModification: ${modification != null}');
    print('═══════════════════════════════════════════════════════');
    
    final apiConfigManager = ApiConfigManager();
    if (!apiConfigManager.hasLlmConfig) {
      throw Exception('请先在设置中配置 LLM API');
    }

    final apiService = apiConfigManager.createApiService();
    
    // 获取提示词模板
    String systemPrompt = '''你是一个专业的动漫分镜设计师。请根据剧本内容，设计详细的分镜脚本。

要求：
1. 每个镜头包含：镜头类型、景别、角度、运动方式
2. 描述画面构图和视觉元素
3. 标注时长和转场方式
4. 考虑动画制作的可行性

输出格式：JSON数组，每个元素包含 index, script, imagePrompt 字段''';

    final templates = promptStore.getTemplates(PromptCategory.storyboard);
    if (templates.isNotEmpty) {
      systemPrompt = '${templates.first.content}\n\n$systemPrompt';
    }

    // 设置处理状态，立即保存
    project.isProcessing = true;
    project.generationStatus = '正在生成分镜设计...';
    await _saveToDisk(projectId, immediate: true);
    
    final userContent = modification ?? project.currentScript;
    final response = await apiService.chatCompletion(
      model: apiConfigManager.llmModel,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': '请根据以下剧本生成分镜设计：\n\n$userContent'},
      ],
      temperature: 0.7,
    );

    try {
      final content = response.choices.first.message.content;
      // 尝试提取 JSON
      final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(content);
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0)!;
        final List<dynamic> parsed = jsonDecode(jsonStr);
        
        project.scenes = parsed.asMap().entries.map((entry) {
          final data = entry.value as Map<String, dynamic>;
          return SceneModel(
            index: entry.key,
            script: data['script'] as String? ?? data['description'] as String? ?? '',
            imagePrompt: data['imagePrompt'] as String? ?? data['prompt'] as String? ?? '',
          );
        }).toList();
      } else {
        // 如果没有 JSON，尝试解析文本格式
        throw Exception('无法解析分镜设计，请确保返回 JSON 格式');
      }
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 解析分镜设计失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
      throw Exception('解析分镜设计失败: $e');
    }

    project.currentLayout = response.choices.first.message.content;
    project.isProcessing = false;
    project.generationStatus = null;
    
    // CRITICAL: 立即保存到磁盘，确保数据不丢失
    await _saveToDisk(projectId, immediate: true);
    _safeNotifyListeners();
  }

  /// 生成所有图片（使用 Pool 限制并发，Isolate 处理重操作，针对特定项目）
  /// CRITICAL: 第一行必须保存状态，标记为"处理中"，防止崩溃时数据丢失
  Future<void> _generateAllImages(String projectId) async {
    print('');
    print('═══════════════════════════════════════════════════════');
    print('🖼️  [Step: Image] 开始生成所有图片');
    print('🖼️  [Step Status] projectId: $projectId');
    print('═══════════════════════════════════════════════════════');
    
    try {
      final project = _projects[projectId]!;
      
      // CRITICAL: 第一行立即保存状态，标记为"处理中"
      project.isProcessing = true;
      project.generationStatus = '正在生成图片...';
      await _performSave(projectId);
      
      final apiConfigManager = ApiConfigManager();
      if (!apiConfigManager.hasImageConfig) {
        project.isProcessing = false;
        project.generationStatus = null;
        throw Exception('请先在设置中配置图片生成 API');
      }

      // 重置断路器状态
      _isAborted[projectId] = false;

      // 内存安全：清理图片缓存（释放内存）
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      final apiService = apiConfigManager.createApiService();
      final taskRunner = HeavyTaskRunner();
      
      // 获取提示词模板
      final templates = promptStore.getTemplates(PromptCategory.image);
      String? templateContent;
      if (templates.isNotEmpty) {
        templateContent = templates.first.content;
      }

      // 初始化所有场景为队列中状态
      for (int i = 0; i < project.scenes.length; i++) {
        project.scenes[i] = project.scenes[i].copyWith(
          isGeneratingImage: true,
          imageGenerationProgress: 0.0,
          generationStatus: 'queueing',
          status: SceneStatus.queueing,
          errorMessage: null,
        );
      }
      _safeNotifyListeners();

      // 使用 Pool 限制并发数为 2
      final pool = Pool(2, timeout: Duration(minutes: 10));
      final completer = Completer<void>();
      final completedCount = <int>[0];  // 使用列表包装以便在闭包中修改
      final totalCount = project.scenes.length;
      final errors = <String>[];

      // 为每个场景创建生成任务
      for (int i = 0; i < project.scenes.length; i++) {
        // 如果已中止（500错误），停止后续生成
        if (_isAborted[projectId] == true) {
          if (i < project.scenes.length) {
            project.scenes[i] = project.scenes[i].copyWith(
              isGeneratingImage: false,
              imageGenerationProgress: 0.0,
              status: SceneStatus.idle,
              generationStatus: null,
            );
          }
          completedCount[0]++;
          // 原子性 Completer：检查是否已完成
          if (completedCount[0] >= totalCount && !completer.isCompleted) {
            completer.complete();
          }
          continue;
        }

        final scene = project.scenes[i];
        final sceneIndex = i;

        // 合并模板和场景提示词
        String finalPrompt = scene.imagePrompt;
        if (templateContent != null && templateContent.isNotEmpty) {
          finalPrompt = '$templateContent\n\n$finalPrompt';
        }

        // 根据场景提示词匹配角色图片
        // 从提示词中提取角色名字（假设提示词中包含角色名字）
        List<String> matchedCharacterImages = [];
        for (final character in project.characters) {
          // 检查角色名字是否在提示词中（简单匹配）
          if (finalPrompt.contains(character.name) && 
              character.localImagePath != null && 
              character.localImagePath!.isNotEmpty) {
            matchedCharacterImages.add(character.localImagePath!);
          }
        }

        // 使用 Pool 资源限制并发 - 使用严格的 try-finally 模式
        // 使用 unawaited 启动异步任务，不阻塞循环
        unawaited(_processSceneWithPool(
          pool: pool,
          projectId: projectId,
          sceneIndex: sceneIndex,
          finalPrompt: finalPrompt,
          referenceImages: matchedCharacterImages.isNotEmpty ? matchedCharacterImages : null,
          apiService: apiService,
          apiConfigManager: apiConfigManager,
          taskRunner: taskRunner,
          completer: completer,
          completedCount: completedCount,
          totalCount: totalCount,
          errors: errors,
          project: project,
        ).catchError((e) {
          // Pool 资源获取失败或其他错误
          print('[AutoModeProvider] 场景 ${sceneIndex + 1} 处理失败: $e');
          completedCount[0]++;
          if (sceneIndex < project.scenes.length) {
            project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
              isGeneratingImage: false,
              imageGenerationProgress: 0.0,
              status: SceneStatus.error,
              errorMessage: '处理失败: $e',
              generationStatus: null,
            );
            errors.add('场景 ${sceneIndex + 1}: 处理失败');
            _safeNotifyListeners();
          }
          if (completedCount[0] >= totalCount && !completer.isCompleted) {
            if (errors.isNotEmpty) {
              completer.completeError(Exception('部分图片生成失败:\n${errors.join('\n')}'));
            } else {
              completer.complete();
            }
          }
        }));
      }

      // 等待所有任务完成
      await completer.future;
      
      // 数据持久化：循环完成后保存（即使有错误也保存）
      await _performSave(projectId);
    } catch (e, stackTrace) {
      print('[AutoModeProvider] 生成所有图片失败: $e');
      print('[AutoModeProvider] 堆栈: $stackTrace');
      rethrow;
    }
  }

  /// 使用严格的 try-finally 模式处理单个场景的图片生成
  /// 确保 Pool 资源只在 finally 块中释放
  Future<void> _processSceneWithPool({
    required Pool pool,
    required String projectId,
    required int sceneIndex,
    required String finalPrompt,
    List<String>? referenceImages,  // 参考图片列表（角色图片）
    required dynamic apiService,
    required ApiConfigManager apiConfigManager,
    required HeavyTaskRunner taskRunner,
    required Completer<void> completer,
    required List<int> completedCount,  // 使用列表以便在闭包中修改
    required int totalCount,
    required List<String> errors,
    required AutoModeProject project,
  }) async {
    // 获取 Pool 资源
    final resource = await pool.request();
    
    try {
      // 500 错误断路器：检查是否已中止
      if (_isAborted[projectId] == true) {
        // 已中止，直接返回，不调用 API
        if (sceneIndex < project.scenes.length) {
          project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
            isGeneratingImage: false,
            imageGenerationProgress: 0.0,
            status: SceneStatus.idle,
            generationStatus: null,
          );
        }
        return;
      }

      // 更新状态为处理中
      if (sceneIndex < project.scenes.length) {
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          generationStatus: 'processing',
          status: SceneStatus.processing,
          imageGenerationProgress: 0.1,
        );
        _safeNotifyListeners();
      }

      // 生成图片（包含错误隔离，返回 null 表示失败）
      final result = await _generateSingleImageSafe(
        projectId: projectId,
        apiService: apiService,
        apiConfigManager: apiConfigManager,
        taskRunner: taskRunner,
        prompt: finalPrompt,
        sceneIndex: sceneIndex,
        referenceImages: referenceImages,
      );

      // 检查是否失败（500错误）
      if (result == null) {
        // 生成失败，检查是否是 500 错误
        if (sceneIndex < project.scenes.length) {
          final scene = project.scenes[sceneIndex];
          final errorMsg = scene.errorMessage ?? '';
          if (errorMsg.contains('500') || errorMsg.contains('服务器错误')) {
            // 500 错误断路器：设置中止标志，停止所有待处理任务
            _isAborted[projectId] = true;
            errors.add('场景 ${sceneIndex + 1}: 服务器错误，已停止后续生成');
          } else {
            errors.add('场景 ${sceneIndex + 1}: ${errorMsg}');
          }
        }
      } else {
        // 成功，状态已在 _generateSingleImageSafe 中更新
        _markDirty(projectId);
      }
    } catch (e, stackTrace) {
      print('[AutoModeProvider] 项目 $projectId 场景 ${sceneIndex + 1} 生成失败: $e');
      print('[AutoModeProvider] 堆栈: $stackTrace');
      
      // 更新失败状态（这不应该发生，因为 _generateSingleImageSafe 已经处理了）
      if (sceneIndex < project.scenes.length) {
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          isGeneratingImage: false,
          imageGenerationProgress: 0.0,
          status: SceneStatus.error,
          errorMessage: e.toString(),
          generationStatus: null,
        );
        errors.add('场景 ${sceneIndex + 1}: $e');
        _safeNotifyListeners();
      }
    } finally {
      // 只在 finally 块中释放 Pool 资源 - 确保资源总是被释放，无论成功或失败
      // 注意：不要在其他地方调用 release()，避免双重释放
      resource.release();
      
      // 原子性 Completer：检查是否已完成，避免 "Future already completed" 错误
      completedCount[0]++;
      if (completedCount[0] >= totalCount && !completer.isCompleted) {
        if (errors.isNotEmpty && _isAborted[projectId] != true) {
          completer.completeError(Exception('部分图片生成失败:\n${errors.join('\n')}'));
        } else {
          completer.complete();
        }
      }
    }
  }

  /// 生成单个角色图片（针对特定项目）
  Future<void> generateCharacterImage(String projectId, int characterIndex) async {
    final project = _projects[projectId]!;
    
    if (characterIndex < 0 || characterIndex >= project.characters.length) {
      throw Exception('角色索引无效');
    }
    
    final character = project.characters[characterIndex];
    
    if (character.prompt.isEmpty) {
      throw Exception('角色提示词为空，无法生成图片');
    }
    
    final apiConfigManager = ApiConfigManager();
    if (!apiConfigManager.hasImageConfig) {
      throw Exception('请先在设置中配置图片生成 API');
    }
    
    final apiService = apiConfigManager.createApiService();
    
    // 更新状态
    project.characters[characterIndex] = character.copyWith(
      isGeneratingImage: true,
      imageGenerationProgress: 0.0,
      generationStatus: 'processing',
      errorMessage: null,
    );
    _safeNotifyListeners();
    
    try {
      // 调用 API 生成图片
      final response = await apiService.generateImage(
        prompt: character.prompt,
        model: apiConfigManager.imageModel,
        width: 1024,
        height: 1024,
      );
      
      // 保存图片到本地
      final imageUrl = response.imageUrl;
      if (imageUrl.isNotEmpty) {
        // 保存角色图片到本地（使用临时目录或保存设置）
        final localPath = await _saveCharacterImageToLocal(imageUrl, character.name);
        
        project.characters[characterIndex] = character.copyWith(
          imageUrl: imageUrl,
          localImagePath: localPath,
          isGeneratingImage: false,
          imageGenerationProgress: 1.0,
          generationStatus: null,
        );
      } else {
        throw Exception('图片生成失败：未返回图片 URL');
      }
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 生成角色图片失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
      project.characters[characterIndex] = character.copyWith(
        isGeneratingImage: false,
        imageGenerationProgress: 0.0,
        generationStatus: null,
        errorMessage: e.toString(),
      );
      rethrow;
    }
    
    _markDirty(projectId);
    _safeNotifyListeners();
  }

  /// 更新场景的图片提示词（场景描述保持不变）
  Future<void> updateScenePrompt(String projectId, int sceneIndex, {String? imagePrompt}) async {
    final project = _projects[projectId];
    if (project == null || sceneIndex < 0 || sceneIndex >= project.scenes.length) {
      return;
    }
    
    if (imagePrompt == null) {
      return; // 没有要更新的内容
    }
    
    final scene = project.scenes[sceneIndex];
    project.scenes[sceneIndex] = scene.copyWith(
      imagePrompt: imagePrompt,
    );
    
    _markDirty(projectId);
    await _saveToDisk(projectId, immediate: true);
    _safeNotifyListeners();
  }

  /// 生成单个图片（安全版本，包含错误隔离和 Isolate 处理，针对特定项目）
  /// 返回 null 表示失败，已更新场景状态
  /// 支持根据角色名字匹配并上传角色图片
  Future<Map<String, String?>?> _generateSingleImageSafe({
    required String projectId,
    required dynamic apiService,
    required ApiConfigManager apiConfigManager,
    required HeavyTaskRunner taskRunner,
    required String prompt,
    required int sceneIndex,
    List<String>? referenceImages,  // 参考图片列表（角色图片路径）
  }) async {
    final project = _projects[projectId]!;
    
    // 500 错误断路器：如果已中止，直接返回
    if (_isAborted[projectId] == true) {
      if (sceneIndex < project.scenes.length) {
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          isGeneratingImage: false,
          imageGenerationProgress: 0.0,
          status: SceneStatus.idle,
          errorMessage: null,
          generationStatus: null,
        );
      }
      return null;
    }
    
    try {
      // 更新进度：API 调用开始（10%）
      if (sceneIndex < project.scenes.length) {
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          imageGenerationProgress: 0.1,
          status: SceneStatus.processing,
          errorMessage: null,
        );
        _safeNotifyListeners();
      }

      // 调用 API 生成图片（如果有关联的角色图片，作为参考图上传）
      final response = await apiService.generateImage(
        prompt: prompt,
        model: apiConfigManager.imageModel,
        width: 1024,
        height: 1024,
        referenceImages: referenceImages,  // 上传角色图片作为参考
      );
      
      // 再次检查断路器（API 调用可能耗时较长）
      if (_isAborted[projectId] == true) {
        if (sceneIndex < project.scenes.length) {
          project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
            isGeneratingImage: false,
            imageGenerationProgress: 0.0,
            status: SceneStatus.idle,
            errorMessage: null,
            generationStatus: null,
          );
        }
        return null;
      }

      // 更新进度：API 调用完成（50%）
      if (sceneIndex < project.scenes.length) {
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          imageGenerationProgress: 0.5,
        );
        _safeNotifyListeners();
      }

      // 保存图片到本地（使用 Isolate 处理）
      final localImagePath = await _saveImageToLocalSafe(
        taskRunner: taskRunner,
        imageUrl: response.imageUrl,
        sceneIndex: sceneIndex,
      );

      // 更新进度：保存完成（100%）
      if (sceneIndex < project.scenes.length) {
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          imageUrl: response.imageUrl,
          localImagePath: localImagePath,
          imageGenerationProgress: 1.0,
          status: SceneStatus.success,
          errorMessage: null,
          isGeneratingImage: false,
          generationStatus: null,
        );
        _safeNotifyListeners();
      }

      return {
        'imageUrl': response.imageUrl,
        'localImagePath': localImagePath,
      };
    } catch (e, stackTrace) {
      print('[AutoModeProvider] 项目 $projectId 生成图片失败 (场景 $sceneIndex): $e');
      print('[AutoModeProvider] 堆栈: $stackTrace');
      
      // 捕获所有错误，更新场景状态，不抛出异常
      if (sceneIndex < project.scenes.length) {
        String errorMsg = e.toString();
        try {
          // 尝试获取 ApiException 的 message
          if (e.toString().contains('ApiException')) {
            final match = RegExp(r'ApiException: (.+?)(?: \(Status:|\$)').firstMatch(e.toString());
            if (match != null) {
              errorMsg = match.group(1) ?? e.toString();
            }
          }
        } catch (_) {
          // 如果解析失败，使用原始错误信息
        }
        
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          isGeneratingImage: false,
          imageGenerationProgress: 0.0,
          status: SceneStatus.error,
          errorMessage: errorMsg,
          generationStatus: null,
        );
        _safeNotifyListeners();
      }
      
      // 返回 null 表示失败
      return null;
    }
  }

  /// 重新生成指定场景的图片（使用 Pool 和 Isolate，针对特定项目）
  Future<void> regenerateImage(String projectId, int sceneIndex) async {
    if (!_projects.containsKey(projectId)) return;
    
    final project = _projects[projectId]!;
    if (sceneIndex < 0 || sceneIndex >= project.scenes.length) return;

    final scene = project.scenes[sceneIndex];
    project.scenes[sceneIndex] = scene.copyWith(
      isGeneratingImage: true,
      imageGenerationProgress: 0.0,
      generationStatus: 'queueing',
    );
    _safeNotifyListeners();

    try {
      final apiConfigManager = ApiConfigManager();
      if (!apiConfigManager.hasImageConfig) {
        throw Exception('请先在设置中配置图片生成 API');
      }

      final apiService = apiConfigManager.createApiService();
      final taskRunner = HeavyTaskRunner();
      
      final templates = promptStore.getTemplates(PromptCategory.image);
      String? templateContent;
      if (templates.isNotEmpty) {
        templateContent = templates.first.content;
      }

      String finalPrompt = scene.imagePrompt;
      if (templateContent != null && templateContent.isNotEmpty) {
        finalPrompt = '$templateContent\n\n$finalPrompt';
      }

      // 根据场景提示词匹配角色图片
      List<String> matchedCharacterImages = [];
      for (final character in project.characters) {
        // 检查角色名字是否在提示词中（简单匹配）
        if (finalPrompt.contains(character.name) && 
            character.localImagePath != null && 
            character.localImagePath!.isNotEmpty) {
          matchedCharacterImages.add(character.localImagePath!);
        }
      }

      // 使用 Pool 限制并发
      final pool = Pool(2, timeout: Duration(minutes: 10));
      final resource = await pool.request();

      try {
        // 更新状态为处理中
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          generationStatus: 'processing',
          imageGenerationProgress: 0.1,
        );
        _safeNotifyListeners();

        // 生成图片（包含错误隔离，支持角色图片参考）
        final result = await _generateSingleImageSafe(
          projectId: projectId,
          apiService: apiService,
          apiConfigManager: apiConfigManager,
          taskRunner: taskRunner,
          prompt: finalPrompt,
          sceneIndex: sceneIndex,
          referenceImages: matchedCharacterImages.isNotEmpty ? matchedCharacterImages : null,
        );

        // 如果成功，状态已在 _generateSingleImageSafe 中更新
        if (result != null) {
          _markDirty(projectId);
          _safeNotifyListeners();
        }
      } catch (e, stackTrace) {
        print('[AutoModeProvider] 项目 $projectId 重新生成图片失败: $e');
        print('[AutoModeProvider] 堆栈: $stackTrace');
        
        // CRITICAL: 在错误状态下，确保重置状态并设置错误信息
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          isGeneratingImage: false,
          imageGenerationProgress: 0.0,
          generationStatus: null,
          status: SceneStatus.error,
          errorMessage: e.toString(),
        );
        _safeNotifyListeners();
        rethrow;
      } finally {
        resource.release();
      }
    } catch (e) {
      // CRITICAL: 在错误状态下，确保重置状态并设置错误信息
      project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
        isGeneratingImage: false,
        imageGenerationProgress: 0.0,
        generationStatus: null,
        status: SceneStatus.error,
        errorMessage: e.toString(),
      );
      _safeNotifyListeners();
      rethrow;
    }
  }

  /// 重新生成单个场景的视频
  Future<void> regenerateVideo(String projectId, int sceneIndex) async {
    if (!_projects.containsKey(projectId)) return;
    
    final project = _projects[projectId]!;
    if (sceneIndex < 0 || sceneIndex >= project.scenes.length) return;

    final scene = project.scenes[sceneIndex];
    
    // 检查是否有图片
    final hasImage = (scene.imageUrl != null && scene.imageUrl!.isNotEmpty) ||
                    (scene.localImagePath != null && scene.localImagePath!.isNotEmpty);
    if (!hasImage) {
      throw Exception('场景 ${sceneIndex + 1} 没有图片，无法生成视频');
    }

    // CRITICAL: 保留所有图片相关字段，只更新视频相关字段
    // 清除所有之前的错误信息和视频URL，准备重新生成
    project.scenes[sceneIndex] = scene.copyWith(
      // 视频相关字段 - 重置为初始状态
      isGeneratingVideo: true,
      videoGenerationProgress: 0.0,
      generationStatus: 'queueing', // 初始状态为队列中
      status: SceneStatus.queueing,
      errorMessage: null, // CRITICAL: 清除之前的错误信息
      videoUrl: null, // CRITICAL: 清除之前的视频URL
      localVideoPath: null, // CRITICAL: 清除之前的本地视频路径
      // 明确保留图片相关字段（copyWith 默认会保留，但这里明确列出以确保安全）
      imageUrl: scene.imageUrl,
      localImagePath: scene.localImagePath,
      imagePrompt: scene.imagePrompt,
      script: scene.script,
      index: scene.index,
    );
    _safeNotifyListeners();

    try {
      final apiConfigManager = ApiConfigManager();
      if (!apiConfigManager.hasVideoConfig) {
        throw Exception('请先在设置中配置视频生成 API');
      }

      final apiService = apiConfigManager.createApiService();
      final taskRunner = HeavyTaskRunner();
      
      final templates = promptStore.getTemplates(PromptCategory.video);
      String? templateContent;
      if (templates.isNotEmpty) {
        templateContent = templates.first.content;
      }

      // CRITICAL: 使用当前场景的 imagePrompt（可能已被用户修改）
      final currentScene = project.scenes[sceneIndex];
      String finalPrompt = currentScene.imagePrompt;
      if (templateContent != null && templateContent.isNotEmpty) {
        finalPrompt = '$templateContent\n\n$finalPrompt';
      }

      // 使用 Pool 限制并发
      final pool = Pool(2, timeout: Duration(minutes: 10));
      final resource = await pool.request();

      try {
        // 更新状态为处理中（保留所有图片相关字段）
        project.scenes[sceneIndex] = currentScene.copyWith(
          generationStatus: 'processing',
          videoGenerationProgress: 0.1,
          // 明确保留图片相关字段
          imageUrl: currentScene.imageUrl,
          localImagePath: currentScene.localImagePath,
          imagePrompt: currentScene.imagePrompt,
          script: currentScene.script,
        );
        _safeNotifyListeners();

        // 生成视频（包含错误隔离，使用场景图片作为参考）
        final result = await _generateSingleVideoSafe(
          projectId: projectId,
          apiService: apiService,
          apiConfigManager: apiConfigManager,
          taskRunner: taskRunner,
          prompt: finalPrompt,
          sceneIndex: sceneIndex,
        );

        if (result == null) {
          // 生成失败，状态已在 _generateSingleVideoSafe 中更新
          throw Exception(project.scenes[sceneIndex].errorMessage ?? '视频生成失败');
        }
      } finally {
        resource.release();
      }
    } catch (e) {
      // CRITICAL: 在错误状态下，确保重置状态并设置错误信息
      // 但必须保留所有图片相关字段
      final currentScene = project.scenes[sceneIndex];
      project.scenes[sceneIndex] = currentScene.copyWith(
        // 视频相关字段
        isGeneratingVideo: false,
        videoGenerationProgress: 0.0,
        generationStatus: null,
        status: SceneStatus.error,
        errorMessage: e.toString(),
        // 明确保留图片相关字段，确保图片不会丢失
        imageUrl: currentScene.imageUrl,
        localImagePath: currentScene.localImagePath,
        imagePrompt: currentScene.imagePrompt,
        script: currentScene.script,
        index: currentScene.index,
      );
      _safeNotifyListeners();
      rethrow;
    }
  }

  /// 生成所有视频（针对特定项目）
  /// CRITICAL: 第一行必须保存状态，标记为"处理中"，防止崩溃时数据丢失
  /// 生成所有视频（并发生成，支持错误隔离）
  Future<void> _generateAllVideos(String projectId) async {
    print('');
    print('═══════════════════════════════════════════════════════');
    print('🎥 [Step: Video] 开始生成所有视频');
    print('🎥 [Step Status] projectId: $projectId');
    print('═══════════════════════════════════════════════════════');
    
    final project = _projects[projectId]!;
    
    // CRITICAL: 第一行立即保存状态，标记为"处理中"
    project.isProcessing = true;
    project.generationStatus = '正在生成视频...';
    await _performSave(projectId);
    
    final apiConfigManager = ApiConfigManager();
    if (!apiConfigManager.hasVideoConfig) {
      project.isProcessing = false;
      project.generationStatus = null;
      throw Exception('请先在设置中配置视频生成 API');
    }

    final apiService = apiConfigManager.createApiService();
    final taskRunner = HeavyTaskRunner();
    
    // 获取提示词模板
    final templates = promptStore.getTemplates(PromptCategory.video);
    String? templateContent;
    if (templates.isNotEmpty) {
      templateContent = templates.first.content;
    }

    // 重置中止标志
    _isAborted[projectId] = false;

    // 过滤出需要生成视频的场景（必须有图片）
    final scenesToProcess = <int>[];
    for (int i = 0; i < project.scenes.length; i++) {
      final scene = project.scenes[i];
      final hasImage = (scene.imageUrl != null && scene.imageUrl!.isNotEmpty) ||
                      (scene.localImagePath != null && scene.localImagePath!.isNotEmpty);
      if (hasImage) {
        scenesToProcess.add(i);
        // 初始化状态为队列中
        project.scenes[i] = scene.copyWith(
          isGeneratingVideo: true,
          videoGenerationProgress: 0.0,
          generationStatus: 'queueing',
          status: SceneStatus.queueing,
          errorMessage: null,
        );
      }
    }

    if (scenesToProcess.isEmpty) {
      project.isProcessing = false;
      project.generationStatus = null;
      _safeNotifyListeners();
      return;
    }

    _safeNotifyListeners();

    try {
      // 使用 Pool 限制并发（最多2个同时生成）
      final pool = Pool(2, timeout: Duration(minutes: 10));
      final completer = Completer<void>();
      final completedCount = <int>[0];
      final totalCount = scenesToProcess.length;
      final errors = <String>[];

      // 为每个场景提交并发任务
      for (final sceneIndex in scenesToProcess) {
        final scene = project.scenes[sceneIndex];
        
        // 合并模板和场景提示词
        String finalPrompt = scene.imagePrompt;
        if (templateContent != null && templateContent.isNotEmpty) {
          finalPrompt = '$templateContent\n\n$finalPrompt';
        }

        // 提交到 Pool（不等待，并发执行）
        _processSceneVideoWithPool(
          pool: pool,
          projectId: projectId,
          sceneIndex: sceneIndex,
          finalPrompt: finalPrompt,
          apiService: apiService,
          apiConfigManager: apiConfigManager,
          taskRunner: taskRunner,
          completer: completer,
          completedCount: completedCount,
          totalCount: totalCount,
          errors: errors,
          project: project,
        ).catchError((e) {
          // Pool 资源获取失败或其他错误
          print('[AutoModeProvider] 场景 ${sceneIndex + 1} 视频处理失败: $e');
          completedCount[0]++;
          if (sceneIndex < project.scenes.length) {
            project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
              isGeneratingVideo: false,
              videoGenerationProgress: 0.0,
              status: SceneStatus.error,
              errorMessage: '处理失败: $e',
              generationStatus: null,
            );
            errors.add('场景 ${sceneIndex + 1}: 处理失败');
            _safeNotifyListeners();
          }
          if (completedCount[0] >= totalCount && !completer.isCompleted) {
            if (errors.isNotEmpty) {
              completer.completeError(Exception('部分视频生成失败:\n${errors.join('\n')}'));
            } else {
              completer.complete();
            }
          }
        });
      }

      // 等待所有任务完成
      await completer.future;
      
      // 数据持久化：循环完成后保存（即使有错误也保存）
      await _performSave(projectId);
    } catch (e, stackTrace) {
      print('[AutoModeProvider] 生成所有视频失败: $e');
      print('[AutoModeProvider] 堆栈: $stackTrace');
      rethrow;
    } finally {
      project.isProcessing = false;
      project.generationStatus = null;
      _safeNotifyListeners();
      
      print('✅ [Step: Video] 所有视频生成流程完成');
      print('✅ [Step Status] 总场景数: ${project.scenes.length}');
      print('═══════════════════════════════════════════════════════');
      print('');
    }
  }

  /// 使用严格的 try-finally 模式处理单个场景的视频生成
  /// 确保 Pool 资源只在 finally 块中释放
  Future<void> _processSceneVideoWithPool({
    required Pool pool,
    required String projectId,
    required int sceneIndex,
    required String finalPrompt,
    required dynamic apiService,
    required ApiConfigManager apiConfigManager,
    required HeavyTaskRunner taskRunner,
    required Completer<void> completer,
    required List<int> completedCount,
    required int totalCount,
    required List<String> errors,
    required AutoModeProject project,
  }) async {
    // 获取 Pool 资源
    final resource = await pool.request();
    
    try {
      // 500 错误断路器：检查是否已中止
      if (_isAborted[projectId] == true) {
        if (sceneIndex < project.scenes.length) {
          project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
            isGeneratingVideo: false,
            videoGenerationProgress: 0.0,
            status: SceneStatus.idle,
            generationStatus: null,
          );
        }
        return;
      }

      // 更新状态为处理中
      if (sceneIndex < project.scenes.length) {
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          generationStatus: 'processing',
          status: SceneStatus.processing,
          videoGenerationProgress: 0.1,
        );
        _safeNotifyListeners();
      }

      // 生成视频（包含错误隔离，返回 null 表示失败）
      final result = await _generateSingleVideoSafe(
        projectId: projectId,
        apiService: apiService,
        apiConfigManager: apiConfigManager,
        taskRunner: taskRunner,
        prompt: finalPrompt,
        sceneIndex: sceneIndex,
      );

      // 检查是否失败
      if (result == null) {
        // 生成失败，检查是否是 500 错误
        if (sceneIndex < project.scenes.length) {
          final scene = project.scenes[sceneIndex];
          final errorMsg = scene.errorMessage ?? '';
          if (errorMsg.contains('500') || errorMsg.contains('服务器错误')) {
            // 500 错误断路器：设置中止标志，停止所有待处理任务
            _isAborted[projectId] = true;
            errors.add('场景 ${sceneIndex + 1}: 服务器错误，已停止后续生成');
          } else {
            errors.add('场景 ${sceneIndex + 1}: ${errorMsg}');
          }
        }
      } else {
        // 成功，状态已在 _generateSingleVideoSafe 中更新
        _markDirty(projectId);
      }
    } catch (e, stackTrace) {
      print('[AutoModeProvider] 项目 $projectId 场景 ${sceneIndex + 1} 视频生成失败: $e');
      print('[AutoModeProvider] 堆栈: $stackTrace');
      
      // 更新失败状态
      if (sceneIndex < project.scenes.length) {
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          isGeneratingVideo: false,
          videoGenerationProgress: 0.0,
          status: SceneStatus.error,
          errorMessage: e.toString(),
          generationStatus: null,
        );
        errors.add('场景 ${sceneIndex + 1}: $e');
        _safeNotifyListeners();
      }
    } finally {
      // 只在 finally 块中释放 Pool 资源
      resource.release();
      
      // 原子性 Completer：检查是否已完成
      completedCount[0]++;
      if (completedCount[0] >= totalCount && !completer.isCompleted) {
        if (errors.isNotEmpty && _isAborted[projectId] != true) {
          completer.completeError(Exception('部分视频生成失败:\n${errors.join('\n')}'));
        } else {
          completer.complete();
        }
      }
    }
  }

  /// 生成单个视频（安全版本，包含错误隔离）
  /// 返回 null 表示失败，已更新场景状态
  Future<Map<String, String?>?> _generateSingleVideoSafe({
    required String projectId,
    required dynamic apiService,
    required ApiConfigManager apiConfigManager,
    required HeavyTaskRunner taskRunner,
    required String prompt,
    required int sceneIndex,
  }) async {
    final project = _projects[projectId]!;
    
    // 500 错误断路器：如果已中止，直接返回
    if (_isAborted[projectId] == true) {
      if (sceneIndex < project.scenes.length) {
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          isGeneratingVideo: false,
          videoGenerationProgress: 0.0,
          status: SceneStatus.idle,
          errorMessage: null,
          generationStatus: null,
        );
      }
      return null;
    }
    
    try {
      // 更新进度：API 调用开始（初始0%，等待API返回真实进度）
      if (sceneIndex < project.scenes.length) {
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          videoGenerationProgress: 0.0, // 初始为0%，等待API返回真实进度
          status: SceneStatus.processing,
          errorMessage: null,
        );
        _safeNotifyListeners();
      }

      // 获取场景图片作为参考
      File? inputReferenceFile;
      final scene = project.scenes[sceneIndex];
      if (scene.localImagePath != null && scene.localImagePath!.isNotEmpty) {
        final imageFile = File(scene.localImagePath!);
        if (await imageFile.exists()) {
          inputReferenceFile = imageFile;
          print('[AutoModeProvider] 使用场景图片作为视频生成参考: ${scene.localImagePath}');
        }
      } else if (scene.imageUrl != null && scene.imageUrl!.isNotEmpty && !scene.imageUrl!.startsWith('data:')) {
        // 如果是网络URL，尝试下载（仅用于视频生成参考）
        try {
          final tempDir = await getTemporaryDirectory();
          final fileName = 'video_ref_${sceneIndex}_${DateTime.now().millisecondsSinceEpoch}.png';
          final tempFile = File('${tempDir.path}${Platform.pathSeparator}$fileName');
          final httpResponse = await http.get(Uri.parse(scene.imageUrl!));
          if (httpResponse.statusCode == 200) {
            await tempFile.writeAsBytes(httpResponse.bodyBytes);
            inputReferenceFile = tempFile;
            print('[AutoModeProvider] 已下载场景图片作为视频生成参考: ${tempFile.path}');
          }
        } catch (e, stackTrace) {
          print('❌ [CRITICAL ERROR CAUGHT] 下载场景图片失败');
          print('❌ [Error Details]: $e');
          print('📍 [Stack Trace]: $stackTrace');
          print('[AutoModeProvider] 将不使用图片参考');
        }
      }
      
      // 调用 API 创建视频任务（使用场景图片作为参考）
      final response = await apiService.createVideo(
        model: apiConfigManager.videoModel,
        prompt: prompt,
        size: apiConfigManager.videoSize,
        seconds: apiConfigManager.videoSeconds,
        inputReference: inputReferenceFile, // 传递场景图片作为参考
      );
      
      // 再次检查断路器
      if (_isAborted[projectId] == true) {
        if (sceneIndex < project.scenes.length) {
          project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
            isGeneratingVideo: false,
            videoGenerationProgress: 0.0,
            status: SceneStatus.idle,
            errorMessage: null,
            generationStatus: null,
          );
        }
        return null;
      }

      final taskId = response.id;
      
      // 更新进度：开始轮询（初始0%）
      if (sceneIndex < project.scenes.length) {
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          videoGenerationProgress: 0.0, // 初始为0%，等待API返回真实进度
        );
        _safeNotifyListeners();
      }

      // CRITICAL: 轮询获取视频 URL（最多600次，每次1秒，总共10分钟），实时同步官网进度
      // 使用API返回的progress字段来更新UI，只有在status=='failed'时才显示失败
      // 缩短轮询间隔到1秒，确保进度更新更实时
      String? videoUrl;
      int maxRetries = 600; // 10分钟超时（600次 * 1秒）
      bool hasProgressInfo = false; // 标记是否收到过进度信息
      
      for (int retry = 0; retry < maxRetries; retry++) {
        await Future.delayed(Duration(seconds: 1)); // 缩短到1秒，更实时
        
        // 检查断路器
        if (_isAborted[projectId] == true) {
          if (sceneIndex < project.scenes.length) {
            project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
              isGeneratingVideo: false,
              videoGenerationProgress: 0.0,
              status: SceneStatus.idle,
              errorMessage: null,
              generationStatus: null,
            );
            _safeNotifyListeners();
          }
          return null;
        }

        try {
          final detail = await apiService.getVideoTask(taskId: taskId);
          
          // CRITICAL: 调试日志，打印API返回的完整信息
          print('[AutoModeProvider] 场景 ${sceneIndex + 1} API返回: status=${detail.status}, progress=${detail.progress}, videoUrl=${detail.videoUrl}');
          
          // CRITICAL: 根据 API 返回的状态和进度实时更新UI
          if (detail.status == 'completed' && detail.videoUrl != null) {
            videoUrl = detail.videoUrl;
            // 立即更新状态为完成
            if (sceneIndex < project.scenes.length) {
              project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
                videoUrl: videoUrl,
                videoGenerationProgress: 1.0,
                isGeneratingVideo: false,
                status: SceneStatus.success,
                generationStatus: null,
                errorMessage: null,
              );
              _safeNotifyListeners();
            }
            break;
          } else if (detail.status == 'failed' || detail.status == 'error') {
            // CRITICAL: API明确返回failed或error状态时，立即更新UI显示失败
            final errorMsg = detail.error != null 
              ? '${detail.error!.message} (${detail.error!.code})'
              : '视频生成失败';
            
            print('[AutoModeProvider] 场景 ${sceneIndex + 1} 视频生成失败: status=${detail.status}, error=$errorMsg');
            
            // CRITICAL: 立即更新状态为失败，不要抛出异常（避免中断轮询）
            if (sceneIndex < project.scenes.length) {
              project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
                isGeneratingVideo: false,
                videoGenerationProgress: 0.0,
                status: SceneStatus.error,
                generationStatus: null,
                errorMessage: errorMsg,
              );
              _safeNotifyListeners();
            }
            
            // 抛出异常以退出轮询循环
            throw ApiException(errorMsg);
          } else if (detail.status == 'processing' || detail.status == 'pending' || detail.status == 'queued' || detail.status == 'in_progress') {
            // CRITICAL: 处理中状态，使用API返回的progress字段实时更新进度
            // 支持多种状态：processing, pending, queued, in_progress
            hasProgressInfo = true; // 标记已收到进度信息
            
            if (sceneIndex < project.scenes.length) {
              // 直接使用API返回的progress字段（0-100），转换为0.0-1.0的范围
              // 这样UI可以直接显示API的原始进度值
              final apiProgress = detail.progress.clamp(0, 100);
              final normalizedProgress = apiProgress / 100.0; // 0.0 到 1.0，直接对应API的0-100%
              
              // CRITICAL: 即使状态是queued，如果progress > 0，说明官网已经开始处理
              // 此时应该将状态更新为processing，以便UI显示进度条
              String generationStatus;
              if (detail.status == 'queued' && apiProgress == 0) {
                generationStatus = 'queueing'; // 队列中且无进度
              } else if (detail.status == 'queued' && apiProgress > 0) {
                // 状态是queued但progress > 0，说明官网已经开始处理，只是状态还没更新
                generationStatus = 'processing'; // 更新为处理中，以便显示进度
                print('[AutoModeProvider] 场景 ${sceneIndex + 1} 状态为queued但progress=${apiProgress}%，更新为processing状态');
              } else if (detail.status == 'processing' || detail.status == 'pending' || detail.status == 'in_progress') {
                generationStatus = 'processing'; // 处理中
              } else {
                generationStatus = 'processing'; // 默认
              }
              
              // CRITICAL: 即使状态是queued，如果有进度（progress > 0），也要更新进度
              // 因为官网可能已经开始了处理，只是状态还没更新
              project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
                videoGenerationProgress: normalizedProgress.clamp(0.0, 1.0),
                status: SceneStatus.processing,
                generationStatus: generationStatus, // 使用正确的状态
                errorMessage: null, // CRITICAL: 清除之前的错误信息，因为还在处理中
              );
              // CRITICAL: 每次轮询后都通知UI更新，确保实时显示官网进度
              _safeNotifyListeners();
              
              print('[AutoModeProvider] 场景 ${sceneIndex + 1} 视频生成进度: ${apiProgress}% (status: ${detail.status}, generationStatus: $generationStatus, normalizedProgress: $normalizedProgress)');
            }
          } else {
            // 其他未知状态，检查是否是失败相关的状态
            final statusLower = detail.status.toLowerCase();
            if (statusLower.contains('fail') || statusLower.contains('error') || statusLower.contains('cancel')) {
              // 可能是失败状态，更新为失败
              print('[AutoModeProvider] 场景 ${sceneIndex + 1} 检测到失败状态: ${detail.status}');
              final errorMsg = detail.error != null 
                ? '${detail.error!.message} (${detail.error!.code})'
                : '视频生成失败: ${detail.status}';
              
              if (sceneIndex < project.scenes.length) {
                project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
                  isGeneratingVideo: false,
                  videoGenerationProgress: 0.0,
                  status: SceneStatus.error,
                  generationStatus: null,
                  errorMessage: errorMsg,
                );
                _safeNotifyListeners();
              }
              
              throw ApiException(errorMsg);
            } else {
              // 其他未知状态，继续轮询但记录日志
              // CRITICAL: 即使状态未知，如果有进度信息，也要更新进度
              print('[AutoModeProvider] 场景 ${sceneIndex + 1} 视频状态未知: ${detail.status}, progress=${detail.progress}, 继续轮询...');
              if (sceneIndex < project.scenes.length) {
                final apiProgress = detail.progress.clamp(0, 100);
                final normalizedProgress = apiProgress / 100.0;
                
                project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
                  status: SceneStatus.processing,
                  generationStatus: 'processing',
                  videoGenerationProgress: normalizedProgress.clamp(0.0, 1.0), // CRITICAL: 更新进度值
                  errorMessage: null,
                );
                _safeNotifyListeners();
                print('[AutoModeProvider] 场景 ${sceneIndex + 1} 已更新进度: ${apiProgress}% (normalized: $normalizedProgress)');
              }
            }
          }
        } catch (e, stackTrace) {
          print('❌ [CRITICAL ERROR CAUGHT] API 轮询调用失败');
          print('❌ [Error Details]: $e');
          print('📍 [Stack Trace]: $stackTrace');
          // API 调用失败，检查是否是明确的失败状态
          if (e is ApiException && (e.message.contains('失败') || e.message.contains('failed') || e.message.contains('error'))) {
            // CRITICAL: 明确的失败，确保状态已更新，然后抛出异常退出轮询
            print('[AutoModeProvider] 场景 ${sceneIndex + 1} 捕获到失败异常: $e');
            
            // 确保失败状态已更新到UI
            if (sceneIndex < project.scenes.length) {
              final currentScene = project.scenes[sceneIndex];
              // 如果状态还不是error，更新为error
              if (currentScene.status != SceneStatus.error) {
                project.scenes[sceneIndex] = currentScene.copyWith(
                  isGeneratingVideo: false,
                  videoGenerationProgress: 0.0,
                  status: SceneStatus.error,
                  generationStatus: null,
                  errorMessage: e.toString(),
                );
                _safeNotifyListeners();
              }
            }
            
            // 抛出异常退出轮询
            rethrow;
          }
          
          // 网络错误等，继续重试，但更新状态显示警告
          if (sceneIndex < project.scenes.length) {
            // 如果之前收到过进度信息，说明任务还在进行，只是网络暂时有问题
            if (hasProgressInfo) {
              project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
                generationStatus: 'processing',
                errorMessage: '网络错误，正在重试...（任务仍在进行中）',
              );
            } else {
              // 如果从未收到过进度信息，可能是网络问题
              if (retry > 5) {
                project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
                  generationStatus: 'processing',
                  errorMessage: '网络错误，正在重试...',
                );
              }
            }
            _safeNotifyListeners();
          }
          
          // 网络错误不中断轮询，继续重试
          print('[AutoModeProvider] 场景 ${sceneIndex + 1} 视频查询失败（第${retry + 1}次）: $e，继续重试...');
        }
      }

      // 只有在从未收到过进度信息且超时的情况下才显示超时错误
      // 如果收到过进度信息，说明任务还在进行，不应该显示超时
      if (videoUrl == null) {
        if (hasProgressInfo) {
          // 收到过进度信息，说明任务还在进行，只是时间较长
          // 不抛出异常，而是更新状态为"处理中"，让用户可以继续等待或手动刷新
          if (sceneIndex < project.scenes.length) {
            project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
              isGeneratingVideo: false,
              status: SceneStatus.processing,
              generationStatus: 'processing',
              errorMessage: '视频生成时间较长，请稍候或点击"重新生成"检查状态',
            );
            _safeNotifyListeners();
          }
          print('[AutoModeProvider] 场景 ${sceneIndex + 1} 视频生成超时，但任务仍在进行中，建议用户继续等待或重新生成');
          return null; // 返回null但不抛出异常，让用户可以重新生成
        } else {
          // 从未收到过进度信息，可能是网络问题或任务创建失败
          throw ApiException('视频生成超时：未收到进度信息，请检查网络连接或重新生成');
        }
      }

      // 更新进度：下载视频（95%，视频生成已完成，剩余5%为下载）
      if (sceneIndex < project.scenes.length) {
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          videoGenerationProgress: 0.95, // 视频生成完成，剩余5%为下载
        );
        _safeNotifyListeners();
      }

      // 保存视频到本地并更新路径（不阻塞，异步执行）
      final savedVideoUrl = videoUrl; // 保存到局部变量供异步回调使用
      unawaited(_saveVideoToLocal(savedVideoUrl).then((savedLocalPath) {
        // CRITICAL: 保存完成后更新本地路径
        if (sceneIndex < project.scenes.length && !_isDisposed) {
          project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
            localVideoPath: savedLocalPath,
          );
          _safeNotifyListeners();
        }
      }).catchError((e) {
        print('[AutoModeProvider] 保存视频到本地失败: $e');
        // 即使保存失败，也不影响视频 URL 的使用
      }));
      
      // CRITICAL: 立即更新状态为完成（不等待本地保存）
      if (sceneIndex < project.scenes.length) {
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          videoUrl: videoUrl,
          isGeneratingVideo: false,
          videoGenerationProgress: 1.0,
          status: SceneStatus.success,
          errorMessage: null,
          generationStatus: null,
        );
        _safeNotifyListeners();
      }

      // 返回视频 URL（本地路径会在异步保存完成后更新）
      return {
        'videoUrl': videoUrl,
        'localVideoPath': null, // 异步保存，稍后更新
      };
    } catch (e, stackTrace) {
      print('[AutoModeProvider] 场景 ${sceneIndex + 1} 视频生成失败: $e');
      print('[AutoModeProvider] 堆栈: $stackTrace');
      
      // 更新失败状态
      if (sceneIndex < project.scenes.length) {
        String errorMsg = e.toString();
        if (e is ApiException) {
          errorMsg = e.message;
        }
        
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          isGeneratingVideo: false,
          videoGenerationProgress: 0.0,
          status: SceneStatus.error,
          errorMessage: errorMsg,
          generationStatus: null,
        );
        _safeNotifyListeners();
      }
      
      return null; // 返回 null 表示失败
    }
  }

  /// 最终合并视频（针对特定项目）
  Future<void> _finalizeVideo(String projectId) async {
    final project = _projects[projectId]!;
    final ffmpegService = FFmpegService();
    
    // 收集所有视频文件路径
    final videoFiles = <File>[];
    for (final scene in project.scenes) {
      if (scene.videoUrl != null && scene.videoUrl!.isNotEmpty) {
        File? videoFile;
        
        if (scene.videoUrl!.startsWith('http')) {
          // 下载网络视频
          try {
            final tempDir = await getTemporaryDirectory();
            final fileName = 'video_${scene.index}_${DateTime.now().millisecondsSinceEpoch}.mp4';
            final filePath = '${tempDir.path}/$fileName';
            final file = File(filePath);
            
            final response = await http.get(Uri.parse(scene.videoUrl!));
            if (response.statusCode == 200) {
              await file.writeAsBytes(response.bodyBytes);
              videoFile = file;
            }
          } catch (e, stackTrace) {
            print('❌ [CRITICAL ERROR CAUGHT] 下载视频失败（合并视频）');
            print('❌ [Error Details]: $e');
            print('📍 [Stack Trace]: $stackTrace');
            continue;
          }
        } else {
          // 本地文件
          final file = File(scene.videoUrl!);
          if (await file.exists()) {
            videoFile = file;
          }
        }
        
        if (videoFile != null) {
          videoFiles.add(videoFile);
        }
      }
    }

    if (videoFiles.isEmpty) {
      throw Exception('没有可合并的视频文件');
    }

    // 使用 FFmpeg 合并视频
    final mergedVideo = await ffmpegService.concatVideos(videoFiles);
    project.finalVideoUrl = mergedVideo.path;
    _markDirty(projectId);
    _safeNotifyListeners();
  }

  /// 重置项目状态
  void resetProject(String projectId) {
    if (!_projects.containsKey(projectId)) return;
    
    final project = _projects[projectId]!;
    _saveTimers[projectId]?.cancel();
    
    project.currentStep = AutoModeStep.script;
    project.currentScript = '';
    project.currentLayout = '';
    project.scenes = [];
    project.isProcessing = false;
    project.errorMessage = null;
    project.finalVideoUrl = null;
    project.lastModified = null;
    project.hasUnsavedChanges = false;
    project.generationStatus = null;
    
    _markDirty(projectId);
    _safeNotifyListeners();
  }

  /// 保存角色图片到本地
  Future<String?> _saveCharacterImageToLocal(String imageUrl, String characterName) async {
    try {
      Uint8List imageBytes;
      
      // 检查是否是 Base64 数据URI
      if (imageUrl.startsWith('data:image/')) {
        // 从 Base64 数据URI 中提取数据
        final base64Index = imageUrl.indexOf('base64,');
        if (base64Index == -1) {
          print('[AutoModeProvider] Base64 数据URI 格式无效');
          return null;
        }
        final base64Data = imageUrl.substring(base64Index + 7);
        try {
          imageBytes = Uint8List.fromList(base64Decode(base64Data));
        } catch (e, stackTrace) {
          print('❌ [CRITICAL ERROR CAUGHT] Base64 解码失败');
          print('❌ [Error Details]: $e');
          print('📍 [Stack Trace]: $stackTrace');
          return null;
        }
      } else if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
        // HTTP URL，下载图片
        final response = await http.get(Uri.parse(imageUrl));
        if (response.statusCode != 200) {
          print('[AutoModeProvider] 下载图片失败: ${response.statusCode}');
          return null;
        }
        imageBytes = response.bodyBytes;
      } else {
        // 可能是本地文件路径，直接返回
        if (await File(imageUrl).exists()) {
          return imageUrl;
        }
        print('[AutoModeProvider] 不支持的图片URL格式: $imageUrl');
        return null;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final autoSave = prefs.getBool('auto_save_images') ?? false;
      final savePath = prefs.getString('image_save_path') ?? '';

      Directory dir;
      if (!autoSave || savePath.isEmpty) {
        // 如果不自动保存，保存到临时目录
        final tempDir = await getTemporaryDirectory();
        dir = Directory('${tempDir.path}/xinghe_characters');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } else {
        // 确保目录存在
        dir = Directory(savePath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      }
      
      final fileName = 'character_${characterName}_${DateTime.now().millisecondsSinceEpoch}.png';
      final filePath = autoSave && savePath.isNotEmpty
          ? '$savePath${Platform.pathSeparator}$fileName'
          : '${dir.path}${Platform.pathSeparator}$fileName';
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);
      print('[AutoModeProvider] 角色图片已保存到本地: $filePath');
      return filePath;
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 保存角色图片失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
      return null;
    }
  }

  /// 保存图片到本地（安全版本，使用 Isolate 处理重操作）
  Future<String?> _saveImageToLocalSafe({
    required HeavyTaskRunner taskRunner,
    required String imageUrl,
    required int sceneIndex,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final autoSave = prefs.getBool('auto_save_images') ?? false;
      final savePath = prefs.getString('image_save_path') ?? '';

      if (!autoSave || savePath.isEmpty) {
        return null;
      }

      // 确保目录存在
      final dir = Directory(savePath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      Uint8List imageBytes;
      String fileExtension = 'png';
      
      // 检查是否是base64数据URI格式
      if (imageUrl.startsWith('data:image/')) {
        try {
          final base64Index = imageUrl.indexOf('base64,');
          if (base64Index == -1) {
            throw '无效的Base64数据URI';
          }
          
          final base64Data = imageUrl.substring(base64Index + 7);
          
          // 在 Isolate 中解码 Base64（避免阻塞主线程）
          imageBytes = await taskRunner.decodeBase64(base64Data);
          
          // 内存安全：立即清除 base64 字符串引用（释放内存）
          // 注意：base64Data 是局部变量，但显式设置为 null 有助于 GC
          // 由于 base64Data 是 String，Dart 会自动管理，但我们可以确保不再引用
          // 这里 base64Data 会在方法返回时自动回收
          
          // 从data URI中提取MIME类型
          final mimeMatch = RegExp(r'data:image/([^;]+)').firstMatch(imageUrl);
          if (mimeMatch != null) {
            final mimeType = mimeMatch.group(1) ?? 'png';
            if (mimeType.contains('jpeg') || mimeType.contains('jpg')) {
              fileExtension = 'jpg';
            } else if (mimeType.contains('webp')) {
              fileExtension = 'webp';
            }
          }
        } catch (e, stackTrace) {
          print('❌ [CRITICAL ERROR CAUGHT] 解析base64图片数据失败');
          print('❌ [Error Details]: $e');
          print('📍 [Stack Trace]: $stackTrace');
          return null;
        }
      } else {
        // 如果是HTTP URL，正常下载
        final response = await http.get(Uri.parse(imageUrl));
        if (response.statusCode != 200) {
          print('[AutoModeProvider] 下载图片失败: ${response.statusCode}');
          return null;
        }
        imageBytes = response.bodyBytes;
        // 从URL推断文件扩展名
        if (imageUrl.contains('.jpg') || imageUrl.contains('.jpeg')) {
          fileExtension = 'jpg';
        } else if (imageUrl.contains('.webp')) {
          fileExtension = 'webp';
        }
      }
      
      // 保存图片文件（在 Isolate 中写入，避免阻塞主线程）
      final fileName = 'auto_mode_image_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final filePath = '$savePath${Platform.pathSeparator}$fileName';
      
      // 在 Isolate 中写入文件
      final savedPath = await taskRunner.writeFile(filePath, imageBytes);
      
      // 内存安全：立即清除 imageBytes（释放大对象内存）
      // 在写入完成后立即释放，避免内存占用
      imageBytes = Uint8List(0);
      
      print('[AutoModeProvider] 图片已保存到本地: $savedPath');
      return savedPath; // 返回绝对路径
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 保存图片到本地失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
      return null;
    }
  }

  /// 保存视频到本地
  Future<String?> _saveVideoToLocal(String videoUrl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final autoSave = prefs.getBool('auto_save_videos') ?? false;
      final savePath = prefs.getString('video_save_path') ?? '';

      if (!autoSave || savePath.isEmpty) {
        return null;
      }

      // 确保目录存在
      final dir = Directory(savePath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      print('[AutoModeProvider] 开始下载视频: $videoUrl');
      final response = await http.get(Uri.parse(videoUrl));
      if (response.statusCode == 200) {
        final fileName = 'auto_mode_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final file = File('$savePath${Platform.pathSeparator}$fileName');
        await file.writeAsBytes(response.bodyBytes);
        final filePath = file.path;
        
        print('[AutoModeProvider] 视频已保存到本地: $filePath');
        return filePath; // 返回绝对路径
      } else {
        print('[AutoModeProvider] 下载视频失败: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 保存视频到本地失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
    }
    return null;
  }

  @override
  @override
  void dispose() {
    // CRITICAL: 设置销毁标志，防止后续操作
    _isDisposed = true;
    
    // 取消所有定时器
    for (final timer in _saveTimers.values) {
      timer.cancel();
    }
    _saveTimers.clear();
    
    // 确保在销毁前保存所有项目
    for (final projectId in _projects.keys) {
      final project = _projects[projectId]!;
      if (project.hasUnsavedChanges) {
        // 使用 unawaited，因为 dispose 不能是 async
        unawaited(_saveToDisk(projectId, immediate: true));
      }
    }
    
    super.dispose();
  }
}
