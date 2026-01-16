import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/index.dart';
import 'services/update_service.dart';
import 'save_settings_panel.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'services/prompt_store.dart';
import 'views/prompt_config_view.dart';
import 'views/auto_mode_screen.dart';
import 'logic/auto_mode_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 加载环境变量
  await dotenv.load();
  
  // 初始化 Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  
  try {
    // 初始化 Hive
    await Hive.initFlutter();
    
    // 并行初始化非关键组件，提高启动速度并避免阻塞
    await Future.wait([
      apiConfigManager.loadConfig().catchError((e) {
        print('加载API配置失败: $e');
      }),
      themeManager.loadTheme().catchError((e) {
        print('加载主题失败: $e');
      }),
      generatedMediaManager.loadMedia().catchError((e) {
        print('加载媒体失败: $e');
      }),
      promptStore.initialize().catchError((e) {
        print('初始化提示词模板失败: $e');
      }),
      videoTaskManager.loadTasks().catchError((e) {
        print('加载视频任务失败: $e');
      }),
      workspaceState.loadCharacters().catchError((e) {
        print('加载角色失败: $e');
      }),
    ], eagerError: false); // 即使某个失败也继续执行
  } catch (e, stackTrace) {
    print('应用初始化失败: $e');
    print('堆栈跟踪: $stackTrace');
    // 即使初始化失败，也继续启动应用
  }
  
  // 确保应用能够启动（无论初始化是否成功）
  runApp(const AnimeApp());
  
  // 延迟检查更新（应用启动后3秒，避免阻塞启动）
  Future.delayed(Duration(seconds: 3), () async {
    try {
      final newVersion = await updateService.checkForUpdate();
      if (newVersion != null) {
        // 如果有新版本，在应用启动后显示更新提示
        // 注意：这里需要在 Widget 树构建后才能显示对话框
        // 所以实际显示会在 HomePage 中处理
      }
    } catch (e) {
      // 静默失败，不影响应用使用
      print('检查更新失败: $e');
    }
  });
}

final apiConfigManager = ApiConfigManager();

// ==================== 全局日志服务 ====================
class LogEntry {
  final DateTime timestamp;
  final String level; // INFO, WARN, ERROR, ACTION
  final String message;
  final String? details;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.details,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level,
    'message': message,
    'details': details,
  };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
    timestamp: DateTime.parse(json['timestamp']),
    level: json['level'],
    message: json['message'],
    details: json['details'],
  );
}

class LogService {
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  final List<LogEntry> _logs = [];
  final StreamController<LogEntry> _logController = StreamController<LogEntry>.broadcast();
  
  Stream<LogEntry> get logStream => _logController.stream;
  List<LogEntry> get logs => List.unmodifiable(_logs);

  void log(String level, String message, {String? details}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      details: details,
    );
    _logs.add(entry);
    _logController.add(entry);
    // 保持最多1000条日志
    if (_logs.length > 1000) {
      _logs.removeAt(0);
    }
  }

  void info(String message, {String? details}) => log('INFO', message, details: details);
  void warn(String message, {String? details}) => log('WARN', message, details: details);
  void error(String message, {String? details}) => log('ERROR', message, details: details);
  void action(String message, {String? details}) => log('ACTION', message, details: details);

  void clear() {
    _logs.clear();
  }

  Future<void> saveLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logsJson = _logs.map((e) => e.toJson()).toList();
      await prefs.setString('system_logs', jsonEncode(logsJson));
    } catch (e) {
      print('保存日志失败: $e');
    }
  }

  Future<void> loadLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logsJson = prefs.getString('system_logs');
      if (logsJson != null) {
        final List<dynamic> decoded = jsonDecode(logsJson);
        _logs.clear();
        _logs.addAll(decoded.map((e) => LogEntry.fromJson(e)));
      }
    } catch (e) {
      print('加载日志失败: $e');
    }
  }
}

final logService = LogService();

// ==================== 生成结果管理器 ====================
class GeneratedMediaManager extends ChangeNotifier {
  static final GeneratedMediaManager _instance = GeneratedMediaManager._internal();
  factory GeneratedMediaManager() => _instance;
  GeneratedMediaManager._internal();

  List<String> _generatedImages = [];
  List<Map<String, dynamic>> _generatedVideos = [];

  List<String> get generatedImages => _generatedImages;
  List<Map<String, dynamic>> get generatedVideos => _generatedVideos;

  Future<void> loadMedia() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 加载图片列表
      final imagesJson = prefs.getString('generated_images');
      if (imagesJson != null) {
        _generatedImages = List<String>.from(jsonDecode(imagesJson));
      }
      
      // 加载视频列表
      final videosJson = prefs.getString('generated_videos');
      if (videosJson != null) {
        final List<dynamic> decoded = jsonDecode(videosJson);
        _generatedVideos = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      
      notifyListeners();
    } catch (e) {
      logService.error('加载生成媒体失败', details: e.toString());
    }
  }

  Future<void> _saveMedia() async {
    try {
      // 复制列表，避免在编码过程中列表被修改
      final imagesCopy = List<String>.from(_generatedImages);
      final videosCopy = List<Map<String, dynamic>>.from(_generatedVideos);
      
      logService.info('开始保存媒体数据', details: '图片: ${imagesCopy.length}, 视频: ${videosCopy.length}');
      
      // 给 UI 线程喘息
      await Future.delayed(Duration(milliseconds: 100));
      
      // 编码图片列表
      logService.info('编码图片列表...');
      final imagesJson = jsonEncode(imagesCopy);
      logService.info('图片列表编码完成，大小: ${imagesJson.length} 字符');
      
      // 给 UI 线程喘息
      await Future.delayed(Duration(milliseconds: 100));
      
      // 编码视频列表
      final videosJson = jsonEncode(videosCopy);
      
      // 给 UI 线程喘息
      await Future.delayed(Duration(milliseconds: 100));
      
      // 保存到 SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('generated_images', imagesJson);
      await prefs.setString('generated_videos', videosJson);
      
      logService.info('媒体数据保存完成');
    } catch (e) {
      logService.error('保存生成媒体失败', details: e.toString());
    }
  }

  Future<void> addImage(String imageUrl) async {
    try {
      _generatedImages.insert(0, imageUrl);
      logService.info('添加图片到列表', details: '当前图片数: ${_generatedImages.length}');
      
      // 立即通知监听器更新UI
      notifyListeners();
      
      // 异步保存（不阻塞后续操作）
      _saveMediaAsync();
      
      // 异步自动保存到本地（不阻塞）
      _autoSaveImageAsync(imageUrl);
    } catch (e) {
      logService.error('添加图片失败', details: e.toString());
    }
  }
  
  // 异步保存媒体列表（不阻塞）
  void _saveMediaAsync() {
    // 延迟更长时间，确保UI已经更新完毕
    Future.delayed(Duration(milliseconds: 2000), () async {
      try {
        await _saveMedia();
      } catch (e) {
        logService.error('异步保存媒体列表失败', details: e.toString());
      }
    });
  }
  
  // 异步自动保存图片（不阻塞）
  void _autoSaveImageAsync(String imageUrl) {
    Future.delayed(Duration(milliseconds: 1000), () async {
      try {
        await _autoSaveImage(imageUrl);
      } catch (e) {
        logService.error('异步自动保存图片失败', details: e.toString());
      }
    });
  }

  Future<void> addVideo(Map<String, dynamic> video) async {
    // 检查是否已存在相同id的视频，防止重复添加
    final videoId = video['id'];
    if (videoId != null) {
      final existingIndex = _generatedVideos.indexWhere((v) => v['id'] == videoId);
      if (existingIndex != -1) {
        logService.warn('视频已存在，跳过添加', details: 'id: $videoId');
        return; // 已存在相同id的视频，不再添加
      }
    }
    
    _generatedVideos.insert(0, video);
    notifyListeners();
    await _saveMedia();
    
    // 自动保存到配置的路径，并将本地路径保存到video数据中
    if (video['url'] != null) {
      final localPath = await _autoSaveVideo(video['url']);
      if (localPath != null) {
        // 使用 videoId 查找更新，而不是对象引用比较
        int videoIndex = -1;
        if (videoId != null) {
          videoIndex = _generatedVideos.indexWhere((v) => v['id'] == videoId);
        } else {
          // 如果没有id，使用url匹配
          videoIndex = _generatedVideos.indexWhere((v) => v['url'] == video['url']);
        }
        
        if (videoIndex != -1) {
          _generatedVideos[videoIndex]['localPath'] = localPath;
          logService.info('视频本地路径已更新', details: localPath);
          await _saveMedia();
          notifyListeners();
        } else {
          logService.warn('无法找到视频以更新本地路径', details: 'id: $videoId');
        }
      }
    }
  }

  void removeImage(String imageUrl) {
    _generatedImages.remove(imageUrl);
    notifyListeners();
    _saveMedia();
  }

  void removeVideo(Map<String, dynamic> video) {
    _generatedVideos.remove(video);
    notifyListeners();
    _saveMedia();
  }

  void clearImages() {
    _generatedImages.clear();
    notifyListeners();
    _saveMedia();
  }

  void clearVideos() {
    _generatedVideos.clear();
    notifyListeners();
    _saveMedia();
  }

  Future<void> _autoSaveImage(String imageUrl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final autoSave = prefs.getBool('auto_save_images') ?? false;
      final savePath = prefs.getString('image_save_path') ?? '';

      if (autoSave && savePath.isNotEmpty) {
        // 使用 Future.delayed 延迟执行，避免阻塞UI
        Future.delayed(Duration(milliseconds: 100), () async {
          try {
            List<int> imageBytes;
            String fileExtension = 'png';
            
            // 检查是否是base64数据URI格式 (data:image/jpeg;base64,xxx 或 data:image/png;base64,xxx)
            if (imageUrl.startsWith('data:image/')) {
              try {
                // 直接解析 Base64（不使用 compute，避免在某些平台上卡住）
                final base64Index = imageUrl.indexOf('base64,');
                if (base64Index == -1) {
                  throw '无效的Base64数据URI';
                }
                
                final base64Data = imageUrl.substring(base64Index + 7);
                imageBytes = base64Decode(base64Data);
                
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
              } catch (e) {
                logService.error('解析base64图片数据失败', details: e.toString());
                return;
              }
            } else {
              // 如果是HTTP URL，正常下载
              final response = await http.get(Uri.parse(imageUrl));
              if (response.statusCode != 200) {
                throw '下载图片失败: ${response.statusCode}';
              }
              imageBytes = response.bodyBytes;
              // 从URL或Content-Type推断文件扩展名
              if (imageUrl.contains('.jpg') || imageUrl.contains('.jpeg')) {
                fileExtension = 'jpg';
              } else if (imageUrl.contains('.webp')) {
                fileExtension = 'webp';
              }
            }
            
            // 保存图片文件（文件I/O操作本身是异步的，不会阻塞主线程）
            final fileName = 'image_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
            final filePath = '$savePath/$fileName';
            final file = File(filePath);
            await file.writeAsBytes(imageBytes);
            logService.info('图片已自动保存', details: filePath);
          } catch (e) {
            logService.error('自动保存图片失败', details: e.toString());
          }
        });
      }
    } catch (e) {
      logService.error('自动保存图片失败', details: e.toString());
    }
  }

  Future<String?> _autoSaveVideo(String videoUrl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final autoSave = prefs.getBool('auto_save_videos') ?? false;
      final savePath = prefs.getString('video_save_path') ?? '';
      
      logService.info('检查视频自动保存设置', details: '启用: $autoSave, 路径: $savePath');

      if (!autoSave) {
        logService.warn('视频自动保存未启用', details: '请在保存设置中启用自动保存');
        return null;
      }
      
      if (savePath.isEmpty) {
        logService.warn('视频保存路径未设置', details: '请在保存设置中设置视频保存路径');
        return null;
      }
      
      // 确保目录存在
      final dir = Directory(savePath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        logService.info('创建视频保存目录', details: savePath);
      }

      logService.info('开始下载视频', details: videoUrl);
      final response = await http.get(Uri.parse(videoUrl));
      if (response.statusCode == 200) {
        final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
        // 使用 Platform.pathSeparator 或直接使用 File 的路径拼接
        final file = File('$savePath${Platform.pathSeparator}$fileName');
        await file.writeAsBytes(response.bodyBytes);
        final filePath = file.path; // 使用 file.path 确保路径格式正确
        logService.info('视频已自动保存', details: filePath);
        return filePath; // 返回保存的本地路径
      } else {
        logService.error('下载视频失败', details: '状态码: ${response.statusCode}');
      }
    } catch (e) {
      logService.error('自动保存视频失败', details: e.toString());
    }
    return null;
  }
}

final generatedMediaManager = GeneratedMediaManager();

// ==================== 视频任务管理器 ====================
// 用于全局管理视频生成任务，跨界面持久化进度
class VideoTaskManager extends ChangeNotifier {
  static final VideoTaskManager _instance = VideoTaskManager._internal();
  factory VideoTaskManager() => _instance;
  VideoTaskManager._internal();

  // 活跃任务列表
  List<Map<String, dynamic>> _activeTasks = [];
  // 失败任务列表（保留占位符，避免显示其他视频）
  List<Map<String, dynamic>> _failedTasks = [];
  bool _isPolling = false;
  
  // 指数退避轮询配置
  static const Duration _initialPollInterval = Duration(seconds: 2);
  static const Duration _maxPollInterval = Duration(seconds: 10);
  static const double _backoffMultiplier = 1.5;
  static const Duration _maxPollingDuration = Duration(minutes: 10);
  
  // 跟踪每个任务的轮询状态
  final Map<String, _TaskPollingState> _taskPollingStates = {};

  List<Map<String, dynamic>> get activeTasks => List.unmodifiable(_activeTasks);
  List<Map<String, dynamic>> get failedTasks => List.unmodifiable(_failedTasks);
  bool get hasActiveTasks => _activeTasks.isNotEmpty;
  bool get isPolling => _isPolling;

  Future<void> loadTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksJson = prefs.getString('active_video_tasks');
      if (tasksJson != null) {
        final List<dynamic> decoded = jsonDecode(tasksJson);
        _activeTasks = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        notifyListeners();
        
        // 如果有未完成的任务，恢复轮询
        if (_activeTasks.isNotEmpty) {
          _resumePolling();
        }
      }
      
      // 同时加载失败任务列表
      await loadFailedTasks();
    } catch (e) {
      logService.error('加载视频任务失败', details: e.toString());
    }
  }

  Future<void> _saveTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_video_tasks', jsonEncode(_activeTasks));
    } catch (e) {
      logService.error('保存视频任务失败', details: e.toString());
    }
  }

  void addTask(String taskId, {String? prompt, String? imagePath}) {
    // 检查是否已存在相同的任务
    if (_activeTasks.any((t) => t['id'] == taskId)) {
      return;
    }
    
    final now = DateTime.now();
    _activeTasks.add({
      'id': taskId,
      'progress': 0,
      'status': '排队中',
      'createdAt': now.toIso8601String(),
      'prompt': prompt,
      'imagePath': imagePath,
    });
    
    // 初始化任务的轮询状态
    _taskPollingStates[taskId] = _TaskPollingState(
      startTime: now,
      currentInterval: _initialPollInterval,
    );
    
    // CRITICAL: 立即通知UI更新，确保实时反馈
    notifyListeners();
    _saveTasks();
    
    // 如果还没有开始轮询，启动轮询
    if (!_isPolling) {
      startPolling();
    } else {
      // 如果已经在轮询，为新任务启动单独的轮询循环（立即执行第一次轮询）
      _startPollingForTask(taskId, isFirstPoll: true);
    }
  }
  
  /// 替换任务ID（用于将临时占位符替换为真实任务ID）
  void replaceTaskId(String oldTaskId, String newTaskId) {
    final index = _activeTasks.indexWhere((t) => t['id'] == oldTaskId);
    if (index == -1) return;
    
    // 更新任务ID
    _activeTasks[index]['id'] = newTaskId;
    
    // 更新轮询状态
    final pollingState = _taskPollingStates.remove(oldTaskId);
    if (pollingState != null) {
      _taskPollingStates[newTaskId] = pollingState;
    }
    
    // 立即通知UI更新
    notifyListeners();
    _saveTasks();
    
    // 如果轮询已启动，为新任务ID启动轮询
    if (_isPolling) {
      _startPollingForTask(newTaskId, isFirstPoll: true);
    }
  }

  void updateTaskProgress(String taskId, int progress, String status) {
    final index = _activeTasks.indexWhere((t) => t['id'] == taskId);
    if (index != -1) {
      _activeTasks[index]['progress'] = progress;
      _activeTasks[index]['status'] = status;
      notifyListeners();
      _saveTasks();
    }
  }

  void removeTask(String taskId, {bool isFailed = false}) {
    final task = _activeTasks.firstWhere((t) => t['id'] == taskId, orElse: () => {});
    _activeTasks.removeWhere((t) => t['id'] == taskId);
    _taskPollingStates.remove(taskId); // 清理轮询状态
    
    // 如果是失败的任务，添加到失败列表（保留占位符）
    if (isFailed && task.isNotEmpty) {
      _failedTasks.add({
        ...task,
        'status': '生成失败',
        'progress': 0,
        'failedAt': DateTime.now().toIso8601String(),
      });
      _saveFailedTasks();
    }
    
    notifyListeners();
    _saveTasks();
    
    // 如果没有活跃任务了，停止轮询
    if (_activeTasks.isEmpty) {
      stopPolling();
    }
  }
  
  /// 删除失败任务占位符
  void removeFailedTask(String taskId) {
    _failedTasks.removeWhere((t) => t['id'] == taskId);
    _saveFailedTasks();
    notifyListeners();
  }
  
  /// 保存失败任务列表
  Future<void> _saveFailedTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('failed_video_tasks', jsonEncode(_failedTasks));
    } catch (e) {
      logService.error('保存失败视频任务失败', details: e.toString());
    }
  }
  
  /// 加载失败任务列表
  Future<void> loadFailedTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksJson = prefs.getString('failed_video_tasks');
      if (tasksJson != null) {
        final List<dynamic> decoded = jsonDecode(tasksJson);
        _failedTasks = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        notifyListeners();
      }
    } catch (e) {
      logService.error('加载失败视频任务失败', details: e.toString());
    }
  }

  void removeAllTasks() {
    _activeTasks.clear();
    notifyListeners();
    _saveTasks();
    stopPolling();
  }
  
  /// 删除所有失败任务
  void removeAllFailedTasks() {
    _failedTasks.clear();
    _saveFailedTasks();
    notifyListeners();
  }

  int getTaskProgress(String taskId) {
    final task = _activeTasks.firstWhere((t) => t['id'] == taskId, orElse: () => {});
    return task['progress'] ?? 0;
  }

  String getTaskStatus(String taskId) {
    final task = _activeTasks.firstWhere((t) => t['id'] == taskId, orElse: () => {});
    return task['status'] ?? '未知';
  }

  void _resumePolling() {
    if (_isPolling || _activeTasks.isEmpty) return;
    
    _isPolling = true;
    notifyListeners();
    
    logService.info('恢复视频任务轮询', details: '${_activeTasks.length} 个任务');
    
    // 为所有现有任务恢复轮询状态
    for (final task in _activeTasks) {
      final taskId = task['id'] as String;
      if (!_taskPollingStates.containsKey(taskId)) {
        // 恢复任务的轮询状态（从保存的创建时间计算）
        final createdAt = DateTime.parse(task['createdAt'] as String);
        _taskPollingStates[taskId] = _TaskPollingState(
          startTime: createdAt,
          currentInterval: _initialPollInterval,
        );
      }
      _startPollingForTask(taskId, isFirstPoll: true);
    }
  }

  void startPolling() {
    if (_isPolling || _activeTasks.isEmpty) return;
    
    _isPolling = true;
    notifyListeners();
    
    logService.info('开始视频任务轮询', details: '${_activeTasks.length} 个任务');
    
    // 为所有任务启动轮询（第一次立即执行）
    for (final task in _activeTasks) {
      final taskId = task['id'] as String;
      _startPollingForTask(taskId, isFirstPoll: true);
    }
  }

  /// 为单个任务启动指数退避轮询
  /// 
  /// 使用递归 Future.delayed 方式，避免重叠请求
  /// [isFirstPoll] 是否为第一次轮询（立即执行，不等待间隔）
  void _startPollingForTask(String taskId, {bool isFirstPoll = false}) {
    // 检查任务是否仍然存在
    if (!_activeTasks.any((t) => t['id'] == taskId)) {
      return;
    }
    
    // 检查轮询状态是否存在
    final pollingState = _taskPollingStates[taskId];
    if (pollingState == null) {
      return;
    }
    
    // 检查是否超时（10分钟）
    final elapsed = DateTime.now().difference(pollingState.startTime);
      if (elapsed >= _maxPollingDuration) {
      logService.warn('视频任务轮询超时', details: '任务$taskId 已轮询超过10分钟');
      updateTaskProgress(taskId, 0, '轮询超时');
      removeTask(taskId, isFailed: true); // 超时也保留占位符
      return;
    }
    
    // 执行轮询的函数
    Future<void> executePoll() async {
      // 再次检查任务是否仍然存在
      if (!_activeTasks.any((t) => t['id'] == taskId)) {
        return;
      }
      
      // 执行轮询
      await _pollSingleTask(taskId);
      
      // 如果任务仍然存在且仍在处理中，继续轮询
      if (_activeTasks.any((t) => t['id'] == taskId)) {
        _startPollingForTask(taskId, isFirstPoll: false);
      }
    }
    
    // 如果是第一次轮询，立即执行；否则等待当前间隔
    if (isFirstPoll) {
      executePoll();
    } else {
      Future.delayed(pollingState.currentInterval, executePoll);
    }
  }

  /// 轮询单个任务
  Future<void> _pollSingleTask(String taskId) async {
    if (!apiConfigManager.hasVideoConfig) return;
    
    final pollingState = _taskPollingStates[taskId];
    if (pollingState == null) return;
    
    try {
      final apiService = apiConfigManager.createApiService();
      final detail = await apiService.getVideoTask(taskId: taskId);
      
      // CRITICAL: 实时更新进度，使用API返回的progress字段
      final statusText = _getStatusText(detail.status, detail.progress);
      updateTaskProgress(taskId, detail.progress, statusText);
      
      logService.info('视频生成进度', details: '任务$taskId: ${detail.progress}%, 状态: ${detail.status}, completedAt: ${detail.completedAt}, videoUrl: ${detail.videoUrl}');
      
      // CRITICAL: 使用更宽松的条件判断任务完成
      // 1. status 是 completed
      // 2. 或者 completedAt 不为 null（表示任务已完成）
      // 3. 或者 progress 是 100%（表示已完成）
      final statusLower = detail.status.toLowerCase();
      final isCompleted = statusLower == 'completed' || 
                          detail.completedAt != null || 
                          (detail.progress >= 100 && statusLower != 'failed' && statusLower != 'error');
      
      // CRITICAL: 检查 videoUrl，可能在 video_url 或 url 字段
      final videoUrl = detail.videoUrl;
      
      if (isCompleted && videoUrl != null && videoUrl.isNotEmpty) {
        // 视频生成完成
        await generatedMediaManager.addVideo({
          'id': taskId,
          'url': videoUrl,
          'createdAt': DateTime.now().toString(),
        });
        
        logService.info('视频生成成功', details: '任务$taskId: $videoUrl, status=${detail.status}, progress=${detail.progress}');
        removeTask(taskId);
        return; // 任务完成，停止轮询
      } else if (isCompleted && (videoUrl == null || videoUrl.isEmpty)) {
        // 任务标记为完成但没有视频URL
        // CRITICAL: 如果 completedAt 存在且已经过去一段时间（比如30秒），可能是失败
        if (detail.completedAt != null) {
          final completedTime = DateTime.fromMillisecondsSinceEpoch(detail.completedAt! * 1000);
          final timeSinceCompleted = DateTime.now().difference(completedTime);
          
          if (timeSinceCompleted.inSeconds > 30) {
            // 完成时间已过30秒但仍无URL，可能是失败
            logService.warn('任务完成超过30秒但无视频URL，可能失败', details: '任务$taskId: status=${detail.status}, progress=${detail.progress}, completedAt=${detail.completedAt}');
            removeTask(taskId, isFailed: true);
            return;
          }
        }
        
        // 否则继续轮询，等待视频URL出现
        logService.warn('任务标记为完成但无视频URL，继续轮询', details: '任务$taskId: status=${detail.status}, progress=${detail.progress}');
      }
      
      // CRITICAL: 检查失败状态（使用更宽松的条件）
      // 注意：statusLower 已经在上面定义过了，这里不需要重复定义
      final isFailed = statusLower == 'failed' || 
                       statusLower == 'error' || 
                       statusLower.contains('fail') || 
                       statusLower.contains('error') ||
                       statusLower.contains('violat') || // 违反内容政策
                       statusLower.contains('reject') || // 拒绝
                       (detail.error != null);
      
      if (isFailed) {
        // CRITICAL: 视频生成失败，保留占位符
        final errorMsg = detail.error != null 
          ? '${detail.error!.message} (${detail.error!.code})'
          : '视频生成失败: ${detail.status}';
        logService.error('视频生成失败', details: '任务$taskId: $errorMsg, status=${detail.status}, progress=${detail.progress}');
        removeTask(taskId, isFailed: true); // 保留失败占位符
        return; // 任务失败，停止轮询
      }
      
      // 任务仍在处理中
      if (detail.status == 'processing' || 
          detail.status == 'queued' || 
          detail.status == 'pending' ||
          detail.status == 'in_progress' ||
          detail.progress < 100) {
        // 任务仍在处理中，但保持较短的轮询间隔以确保实时更新
        // 如果进度接近完成（>90%），使用更短的间隔
        if (detail.progress >= 90) {
          pollingState.currentInterval = _initialPollInterval; // 接近完成时，使用最短间隔
        } else {
          // 其他情况，适度增加轮询间隔（指数退避）
          final newInterval = Duration(
            milliseconds: (pollingState.currentInterval.inMilliseconds * _backoffMultiplier).round(),
          );
          
          // 限制最大间隔为10秒
          pollingState.currentInterval = newInterval > _maxPollInterval 
              ? _maxPollInterval 
              : newInterval;
        }
        
        logService.info('调整轮询间隔', details: '任务$taskId: ${pollingState.currentInterval.inSeconds}秒, progress=${detail.progress}%');
      } else {
        // 其他未知状态，记录日志但继续轮询
        // CRITICAL: 即使状态未知，也要检查是否有完成或失败的迹象
        logService.warn('未知任务状态', details: '任务$taskId: status=${detail.status}, progress=${detail.progress}, completedAt=${detail.completedAt}, error=${detail.error}');
        
        // 如果进度是100%但没有视频URL，可能是失败
        if (detail.progress >= 100 && (detail.videoUrl == null || detail.videoUrl!.isEmpty)) {
          logService.warn('进度100%但无视频URL，可能失败', details: '任务$taskId');
          // 继续轮询一段时间，如果还是没有URL，则标记为失败
          // 这里不立即失败，给API一些时间返回URL
        }
      }
    } catch (e) {
      logService.error('查询视频状态失败', details: '任务$taskId: $e');
      
      // CRITICAL: 发生错误时，不要立即停止轮询，而是继续尝试
      // 但增加轮询间隔，避免频繁重试导致API压力过大
      final newInterval = Duration(
        milliseconds: (pollingState.currentInterval.inMilliseconds * _backoffMultiplier).round(),
      );
      pollingState.currentInterval = newInterval > _maxPollInterval 
          ? _maxPollInterval 
          : newInterval;
      
      // 即使出错，也继续轮询（除非任务已被移除）
      // 这确保网络临时故障不会导致任务丢失
    }
  }

  String _getStatusText(String status, int progress) {
    switch (status) {
      case 'queued':
        return '排队中...';
      case 'processing':
        return '生成中 $progress%';
      case 'completed':
        return '生成完成';
      case 'failed':
        return '生成失败';
      default:
        return '处理中 $progress%';
    }
  }

  void stopPolling() {
    _isPolling = false;
    _taskPollingStates.clear(); // 清理所有轮询状态
    notifyListeners();
    logService.info('停止视频任务轮询');
  }
}

/// 任务轮询状态（用于指数退避）
class _TaskPollingState {
  final DateTime startTime;
  Duration currentInterval;
  
  _TaskPollingState({
    required this.startTime,
    required this.currentInterval,
  });
}

final videoTaskManager = VideoTaskManager();

// ==================== 图片尺寸配置 ====================
class ImageSize {
  final String label;
  final int width;
  final int height;
  final String ratio;

  const ImageSize(this.label, this.width, this.height, this.ratio);

  String get display => '$label ($width×$height)';
}

const List<ImageSize> imageSizes = [
  ImageSize('1:1 方形', 1024, 1024, '1:1'),
  ImageSize('16:9 横屏', 1792, 1024, '16:9'),
  ImageSize('9:16 竖屏', 1024, 1792, '9:16'),
];

const List<String> imageQualities = ['标准', '1K', '2K', '4K'];

// ==================== 视频尺寸配置 ====================
class VideoSize {
  final String label;
  final int width;
  final int height;
  final String ratio;

  const VideoSize(this.label, this.width, this.height, this.ratio);

  String get display => '$label ($width×$height)';
}

const List<VideoSize> videoSizes = [
  VideoSize('16:9 横屏', 1280, 720, '16:9'),
  VideoSize('9:16 竖屏', 720, 1280, '9:16'),
  VideoSize('1:1 方形', 720, 720, '1:1'),
  VideoSize('4:3 标准', 960, 720, '4:3'),
  VideoSize('3:4 竖版', 720, 960, '3:4'),
];

const List<String> videoDurations = ['5秒', '10秒', '15秒'];

// ==================== 动漫风格配置 ====================
class AnimeStyle {
  final String id;
  final String name;
  final String description;
  final Color color;

  const AnimeStyle(this.id, this.name, this.description, this.color);
}

// 默认风格列表
final List<AnimeStyle> defaultAnimeStyles = [
  AnimeStyle('xianxia', '仙侠风格', '修仙玄幻仙气', Color(0xFF9C27B0)),
  AnimeStyle('dushi', '都市风格', '现代都市生活', Color(0xFF2196F3)),
  AnimeStyle('gufeng', '古风风格', '古典东方韵味', Color(0xFFFF5722)),
];

// 风格管理器
class StyleManager {
  static final StyleManager _instance = StyleManager._internal();
  factory StyleManager() => _instance;
  StyleManager._internal();

  List<AnimeStyle> _styles = [...defaultAnimeStyles];
  
  List<AnimeStyle> get styles => _styles;

  void addStyle(AnimeStyle style) {
    _styles.add(style);
    _saveStyles();
  }

  void removeStyle(String id) {
    _styles.removeWhere((s) => s.id == id);
    _saveStyles();
  }

  Future<void> loadStyles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stylesJson = prefs.getString('custom_styles');
      if (stylesJson != null) {
        final List<dynamic> decoded = jsonDecode(stylesJson);
        _styles = decoded.map((e) => AnimeStyle(
          e['id'],
          e['name'],
          e['description'],
          Color(e['color']),
        )).toList();
      }
    } catch (e) {
      _styles = [...defaultAnimeStyles];
    }
  }

  Future<void> _saveStyles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stylesJson = _styles.map((s) => {
        'id': s.id,
        'name': s.name,
        'description': s.description,
        'color': s.color.value,
      }).toList();
      await prefs.setString('custom_styles', jsonEncode(stylesJson));
    } catch (e) {
      print('保存风格失败: $e');
    }
  }
}

final styleManager = StyleManager();

// ==================== 工作区共享状态 ====================
class WorkspaceState extends ChangeNotifier {
  static final WorkspaceState _instance = WorkspaceState._internal();
  factory WorkspaceState() => _instance;
  WorkspaceState._internal();

  // 剧本内容
  String _script = '';
  String get script => _script;
  set script(String value) {
    _script = value;
    notifyListeners();
  }

  // 生成的角色
  List<Map<String, dynamic>> _characters = [];
  List<Map<String, dynamic>> get characters => _characters;
  
  void addCharacter(Map<String, dynamic> char) {
    _characters.add(char);
    notifyListeners();
    _saveCharactersAsync();
  }
  
  void updateCharacter(int index, Map<String, dynamic> char) {
    if (index >= 0 && index < _characters.length) {
      _characters[index] = char;
      notifyListeners();
      _saveCharactersAsync();
    }
  }
  
  void clearCharacters() {
    _characters.clear();
    notifyListeners();
    _saveCharactersAsync();
  }
  
  void removeCharacter(int index) {
    if (index >= 0 && index < _characters.length) {
      _characters.removeAt(index);
      notifyListeners();
      _saveCharactersAsync();
    }
  }
  
  // 加载保存的角色
  Future<void> loadCharacters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final charactersJson = prefs.getString('workspace_characters');
      if (charactersJson != null && charactersJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(charactersJson);
        _characters = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        notifyListeners();
        print('[WorkspaceState] 已加载 ${_characters.length} 个角色');
      }
    } catch (e) {
      print('[WorkspaceState] 加载角色失败: $e');
    }
  }
  
  // 异步保存角色（不阻塞UI）
  void _saveCharactersAsync() {
    Future.microtask(() async {
      try {
        final charactersCopy = List<Map<String, dynamic>>.from(_characters);
        final charactersJson = jsonEncode(charactersCopy);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('workspace_characters', charactersJson);
        print('[WorkspaceState] 已保存 ${charactersCopy.length} 个角色');
      } catch (e) {
        print('[WorkspaceState] 保存角色失败: $e');
      }
    });
  }

  // 生成的场景
  List<Map<String, dynamic>> _scenes = [];
  List<Map<String, dynamic>> get scenes => _scenes;
  void addScene(Map<String, dynamic> scene) {
    _scenes.add(scene);
    notifyListeners();
  }
  void updateScene(int index, Map<String, dynamic> scene) {
    if (index >= 0 && index < _scenes.length) {
      _scenes[index] = scene;
      notifyListeners();
    }
  }
  void clearScenes() {
    _scenes.clear();
    notifyListeners();
  }

  // 生成的物品
  List<Map<String, dynamic>> _props = [];
  List<Map<String, dynamic>> get props => _props;
  void addProp(Map<String, dynamic> prop) {
    _props.add(prop);
    notifyListeners();
  }
  void updateProp(int index, Map<String, dynamic> prop) {
    if (index >= 0 && index < _props.length) {
      _props[index] = prop;
      notifyListeners();
    }
  }
  void clearProps() {
    _props.clear();
    notifyListeners();
  }

  // 生成的分镜
  List<Map<String, dynamic>> _storyboards = [];
  List<Map<String, dynamic>> get storyboards => _storyboards;
  void addStoryboard(Map<String, dynamic> board) {
    _storyboards.add(board);
    notifyListeners();
  }
  void clearStoryboards() {
    _storyboards.clear();
    notifyListeners();
  }

  // 分镜设置
  int imageSizeIndex = 0;
  int videoSizeIndex = 0;
  int durationIndex = 1;
  int qualityIndex = 0;

  // 清空所有状态
  void clearAll() {
    _script = '';
    _characters.clear();
    _scenes.clear();
    _props.clear();
    _storyboards.clear();
    notifyListeners();
  }
}

final workspaceState = WorkspaceState();

// 二次元配色方案
// ==================== 主题管理器 ====================
class ThemeManager extends ChangeNotifier {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;
  ThemeManager._internal();

  String _currentTheme = 'default';
  String get currentTheme => _currentTheme;

  Future<void> loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentTheme = prefs.getString('app_theme') ?? 'default';
      notifyListeners();
    } catch (e) {
      print('加载主题失败: $e');
    }
  }

  Future<void> setTheme(String themeId) async {
    _currentTheme = themeId;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_theme', themeId);
    } catch (e) {
      print('保存主题失败: $e');
    }
  }

  AnimeColorScheme get colors {
    switch (_currentTheme) {
      case 'sakura':
        return AnimeColorScheme(
          primary: Color(0xFFFFB7C5),
          secondary: Color(0xFFFF69B4),
          accent: Color(0xFFFFD1DC),
          darkBg: Color(0xFF1a0f14),
          cardBg: Color(0xFF2a1a1f),
          glassBg: Color(0x1AFFB7C5),
        );
      case 'ocean':
        return AnimeColorScheme(
          primary: Color(0xFF1E90FF),
          secondary: Color(0xFF00CED1),
          accent: Color(0xFF4FC3F7),
          darkBg: Color(0xFF0a1420),
          cardBg: Color(0xFF0f1f2f),
          glassBg: Color(0x1A1E90FF),
        );
      case 'sunset':
        return AnimeColorScheme(
          primary: Color(0xFFFF8C00),
          secondary: Color(0xFFFFD700),
          accent: Color(0xFFFFB347),
          darkBg: Color(0xFF1a1008),
          cardBg: Color(0xFF2a1a10),
          glassBg: Color(0x1AFFD700),
        );
      case 'forest':
        return AnimeColorScheme(
          primary: Color(0xFF228B22),
          secondary: Color(0xFF32CD32),
          accent: Color(0xFF90EE90),
          darkBg: Color(0xFF0a140a),
          cardBg: Color(0xFF0f1f0f),
          glassBg: Color(0x1A32CD32),
        );
      case 'cyberpunk':
        return AnimeColorScheme(
          primary: Color(0xFFFF1493),
          secondary: Color(0xFF00FFFF),
          accent: Color(0xFFFF00FF),
          darkBg: Color(0xFF0d0a14),
          cardBg: Color(0xFF1a0f1f),
          glassBg: Color(0x1AFF1493),
        );
      default: // 'default'
        return AnimeColorScheme(
          primary: Color(0xFF39C5BB),
          secondary: Color(0xFF9D7FEA),
          accent: Color(0xFFFFB7C5),
          darkBg: Color(0xFF0A0A14),
          cardBg: Color(0xFF12121F),
          glassBg: Color(0x1AFFFFFF),
        );
    }
  }
}

final themeManager = ThemeManager();

class AnimeColorScheme {
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color darkBg;
  final Color cardBg;
  final Color glassBg;

  AnimeColorScheme({
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.darkBg,
    required this.cardBg,
    required this.glassBg,
  });
}

// 保留旧的 AnimeColors 以兼容现有代码
class AnimeColors {
  static Color get miku => themeManager.colors.primary;
  static Color get sakura => themeManager.colors.accent;
  static Color get purple => themeManager.colors.secondary;
  static const blue = Color(0xFF667eea); // 天空蓝
  static const orangeAccent = Color(0xFFFF9800); // 橙色
  static Color get darkBg => themeManager.colors.darkBg;
  static Color get cardBg => themeManager.colors.cardBg;
  static Color get glassBg => themeManager.colors.glassBg;
}

// ==================== 图片显示辅助函数 ====================
// 支持base64数据URI和HTTP URL的图片显示
// 缓存已解码的 Base64 图片数据，避免重复解码
final Map<int, Uint8List> _base64ImageCache = {};

Widget buildImageWidget({
  required String imageUrl,
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
  Widget Function(BuildContext, Object?, StackTrace?)? errorBuilder,
  Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder,
}) {
  final defaultErrorWidget = Container(
    color: AnimeColors.cardBg,
    child: Center(child: Icon(Icons.broken_image, color: Colors.white38, size: 40)),
  );
  
  // 检查是否是base64数据URI
  if (imageUrl.startsWith('data:image/')) {
    // 使用 hashCode 作为缓存键
    final cacheKey = imageUrl.hashCode;
    
    // 检查缓存
    if (_base64ImageCache.containsKey(cacheKey)) {
      return Image.memory(
        _base64ImageCache[cacheKey]!,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: errorBuilder ?? (_, __, ___) => defaultErrorWidget,
        gaplessPlayback: true,
      );
    }
    
    // 同步解码 Base64（对于已缓存的图片会直接返回）
    try {
      final base64Index = imageUrl.indexOf('base64,');
      if (base64Index != -1) {
        final base64Data = imageUrl.substring(base64Index + 7);
        final bytes = Uint8List.fromList(base64Decode(base64Data));
        
        // 缓存解码后的数据
        _base64ImageCache[cacheKey] = bytes;
        
        return Image.memory(
          bytes,
          fit: fit,
          width: width,
          height: height,
          errorBuilder: errorBuilder ?? (_, __, ___) => defaultErrorWidget,
          gaplessPlayback: true,
        );
      }
    } catch (e) {
      logService.error('解析base64图片失败', details: e.toString());
      return defaultErrorWidget;
    }
  }
  
  // 如果不是base64格式，使用Image.network
  return Image.network(
    imageUrl,
    fit: fit,
    width: width,
    height: height,
    errorBuilder: errorBuilder ?? (_, __, ___) => defaultErrorWidget,
    loadingBuilder: loadingBuilder,
  );
}

// ==================== 图片查看器 ====================
void showImageViewer(BuildContext context, {String? imagePath, String? imageUrl}) {
  showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(20),
      child: Stack(
        children: [
          // 图片
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: imagePath != null
                  ? Image.file(
                      File(imagePath),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Container(
                        padding: EdgeInsets.all(40),
                        decoration: BoxDecoration(
                          color: AnimeColors.cardBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.broken_image, color: Colors.white38, size: 60),
                      ),
                    )
                  : imageUrl != null
                      ? buildImageWidget(
                          imageUrl: imageUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Container(
                            padding: EdgeInsets.all(40),
                            decoration: BoxDecoration(
                              color: AnimeColors.cardBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.broken_image, color: Colors.white38, size: 60),
                          ),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              padding: EdgeInsets.all(40),
                              child: CircularProgressIndicator(color: AnimeColors.miku),
                            );
                          },
                        )
                      : Container(
                          padding: EdgeInsets.all(40),
                          child: Icon(Icons.image_not_supported, color: Colors.white38, size: 60),
                        ),
            ),
          ),
          // 关闭按钮
          Positioned(
            top: 0,
            right: 0,
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close, color: Colors.white, size: 24),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class AnimeApp extends StatefulWidget {
  const AnimeApp({super.key});

  @override
  State<AnimeApp> createState() => _AnimeAppState();
}

class _AnimeAppState extends State<AnimeApp> with WidgetsBindingObserver {
  AppLifecycleListener? _lifecycleListener;
  final AutoModeProvider _autoModeProvider = AutoModeProvider(); // 单例实例

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // 初始化 AutoModeProvider（单例，只初始化一次）
    _autoModeProvider.initialize();
    
    // 设置应用生命周期监听器
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _handleAppLifecycleChange,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycleListener?.dispose();
    super.dispose();
  }

  void _handleAppLifecycleChange(AppLifecycleState state) {
    // 当应用进入后台、暂停或分离状态时，立即保存所有项目
    // AutoModeProvider 是单例，所有 AutoModeScreen 共享同一个实例
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive || 
        state == AppLifecycleState.detached) {
      print('[AnimeApp] 应用生命周期变化: $state，开始保存所有项目...');
      _autoModeProvider.saveAllProjects().catchError((e) {
        print('[AnimeApp] 保存所有项目失败: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeManager,
      builder: (context, child) {
        return MaterialApp(
          title: '星橙AI动漫制作',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: AnimeColors.darkBg,
            primarySwatch: Colors.purple,
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AnimeColors.purple,
              brightness: Brightness.dark,
              primary: AnimeColors.purple,
              secondary: AnimeColors.miku,
            ),
          ),
          home: HomePage(),
        );
      },
    );
  }
}

// ==========================================
// 响应式布局系统
// ==========================================

/// 屏幕类型枚举
enum ScreenType {
  mobile,   // < 600px
  tablet,   // 600px - 1100px
  desktop,  // > 1100px
}

/// 响应式布局工具类
class ResponsiveLayout {
  /// 根据屏幕宽度确定屏幕类型
  static ScreenType getScreenType(double width) {
    if (width < 600) {
      return ScreenType.mobile;
    } else if (width < 1100) {
      return ScreenType.tablet;
    } else {
      return ScreenType.desktop;
    }
  }

  /// 是否为移动设备
  static bool isMobile(BuildContext context) {
    return getScreenType(MediaQuery.of(context).size.width) == ScreenType.mobile;
  }

  /// 是否为平板设备
  static bool isTablet(BuildContext context) {
    return getScreenType(MediaQuery.of(context).size.width) == ScreenType.tablet;
  }

  /// 是否为桌面设备
  static bool isDesktop(BuildContext context) {
    return getScreenType(MediaQuery.of(context).size.width) == ScreenType.desktop;
  }

  /// 获取当前屏幕类型
  static ScreenType currentScreenType(BuildContext context) {
    return getScreenType(MediaQuery.of(context).size.width);
  }
}

/// 响应式布局包装器
/// 根据屏幕大小自动调整布局
class ResponsiveLayoutWrapper extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const ResponsiveLayoutWrapper({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveLayout.currentScreenType(context);

    switch (screenType) {
      case ScreenType.mobile:
        return mobile;
      case ScreenType.tablet:
        return tablet ?? mobile;
      case ScreenType.desktop:
        return desktop ?? tablet ?? mobile;
    }
  }
}

/// 响应式输入区域包装器
/// 在桌面端限制最大宽度并居中
class ResponsiveInputWrapper extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsiveInputWrapper({
    super.key,
    required this.child,
    this.maxWidth = 1600, // 增加最大宽度以容纳左右两栏布局
  });

  @override
  Widget build(BuildContext context) {
    if (ResponsiveLayout.isDesktop(context)) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
    }
    return child;
  }
}

// 首页
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Interval(0.0, 0.6, curve: Curves.easeOut)),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Interval(0.0, 0.6, curve: Curves.easeOut)),
    );
    _animController.forward();
    
    // 记录启动日志
    logService.info('星橙AI动漫制作 启动成功');
    logService.info('加载用户配置完成');
    _checkApiConfig();
    
    // 延迟检查更新（应用启动后3秒，避免阻塞启动）
    Future.delayed(Duration(seconds: 3), () {
      if (mounted) {
        _checkForUpdate();
      }
    });
  }
  
  /// 检查更新
  Future<void> _checkForUpdate() async {
    try {
      final newVersion = await updateService.checkForUpdate();
      if (newVersion != null && mounted) {
        _showUpdateDialog(newVersion);
      }
    } catch (e) {
      // 静默失败，不影响应用使用
      print('检查更新失败: $e');
    }
  }
  
  /// 显示更新对话框
  void _showUpdateDialog(AppVersion newVersion) {
    showDialog(
      context: context,
      barrierDismissible: !newVersion.forceUpdate, // 强制更新时不能关闭
      builder: (context) => AlertDialog(
        backgroundColor: AnimeColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.system_update, color: AnimeColors.miku, size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '发现新版本',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (!newVersion.forceUpdate)
              IconButton(
                icon: Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
              ),
          ],
        ),
        content: Container(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '版本 ${newVersion.version} (Build ${newVersion.buildNumber})',
                style: TextStyle(
                  color: AnimeColors.miku,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 12),
              if (newVersion.releaseNotes != null && newVersion.releaseNotes!.isNotEmpty) ...[
                Text(
                  '更新内容：',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    newVersion.releaseNotes!,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
                SizedBox(height: 16),
              ],
              if (newVersion.forceUpdate)
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red[300], size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '此版本为强制更新，必须更新后才能继续使用',
                          style: TextStyle(
                            color: Colors.red[300],
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (!newVersion.forceUpdate)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('稍后更新', style: TextStyle(color: Colors.white54)),
            ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // 先关闭对话框
              try {
                // 显示下载进度对话框
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => AlertDialog(
                    backgroundColor: AnimeColors.cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AnimeColors.miku),
                        SizedBox(height: 20),
                        Text(
                          '正在下载更新...',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                );
                
                // 下载并安装
                await updateService.downloadAndInstall(newVersion);
                
                // 关闭下载对话框
                if (mounted) Navigator.pop(context);
                
                // 显示成功提示
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('更新已下载，请按照提示完成安装'),
                      backgroundColor: AnimeColors.miku,
                      duration: Duration(seconds: 5),
                    ),
                  );
                }
              } catch (e) {
                // 关闭下载对话框
                if (mounted) Navigator.pop(context);
                
                // 显示错误提示
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('更新失败: $e'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 5),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AnimeColors.miku,
              foregroundColor: Colors.white,
            ),
            child: Text('立即更新'),
          ),
        ],
      ),
    );
  }
  
  void _checkApiConfig() {
    if (!apiConfigManager.hasLlmConfig) {
      logService.warn('LLM API 未配置');
    } else {
      logService.info('LLM API 已配置', details: '模型: ${apiConfigManager.llmModel}');
    }
    if (!apiConfigManager.hasImageConfig) {
      logService.warn('图片 API 未配置');
    } else {
      logService.info('图片 API 已配置', details: '模型: ${apiConfigManager.imageModel}');
    }
    if (!apiConfigManager.hasVideoConfig) {
      logService.warn('视频 API 未配置');
    } else {
      logService.info('视频 API 已配置', details: '模型: ${apiConfigManager.videoModel}');
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AnimeColors.darkBg,
              Color(0xFF0f0f1e),
              Color(0xFF1a1a2e),
            ],
          ),
        ),
        child: Stack(
          children: [
            // 装饰背景
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [AnimeColors.purple.withOpacity(0.15), Colors.transparent],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -150,
              left: -150,
              child: Container(
                width: 500,
                height: 500,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [AnimeColors.miku.withOpacity(0.1), Colors.transparent],
                  ),
                ),
              ),
            ),
            // 主体内容
            SafeArea(
              child: AnimatedBuilder(
                animation: _animController,
                builder: (context, child) => Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: child,
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 根据屏幕高度自适应间距
                    final isCompact = constraints.maxHeight < 750;
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: isCompact ? 20 : 40),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Logo
                                Container(
                                  width: isCompact ? 100 : 140,
                                  height: isCompact ? 100 : 140,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [AnimeColors.miku, AnimeColors.purple, AnimeColors.sakura],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AnimeColors.miku.withOpacity(0.4),
                                        blurRadius: 50,
                                        spreadRadius: 10,
                                      ),
                                      BoxShadow(
                                        color: AnimeColors.purple.withOpacity(0.3),
                                        blurRadius: 80,
                                        spreadRadius: 20,
                                      ),
                                    ],
                                  ),
                                  child: Icon(Icons.auto_awesome, size: isCompact ? 50 : 70, color: Colors.white),
                                ),
                                SizedBox(height: isCompact ? 24 : 40),
                                // 标题
                                ShaderMask(
                                  shaderCallback: (bounds) => LinearGradient(
                                    colors: [Colors.white, AnimeColors.miku, AnimeColors.purple],
                                  ).createShader(bounds),
                                  child: Text(
                                    '星橙AI动漫制作',
                                    style: TextStyle(
                                      fontSize: isCompact ? 32 : 42,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 3,
                                    ),
                                  ),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'AI 驱动的动漫视频创作平台',
                                  style: TextStyle(
                                    fontSize: isCompact ? 14 : 18,
                                    color: Colors.white.withOpacity(0.6),
                                    letterSpacing: 2,
                                  ),
                                ),
                                SizedBox(height: isCompact ? 40 : 60),
                                // 开始按钮
                                _buildMainButton(
                                  context,
                                  '进入创作空间',
                                  Icons.rocket_launch_rounded,
                                  () => _navigateToGallery(),
                                  isCompact: isCompact,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToGallery() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const ProjectGalleryPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: Duration(milliseconds: 400),
      ),
    );
  }

  Widget _buildMainButton(BuildContext context, String text, IconData icon, VoidCallback onTap, {bool isCompact = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: isCompact ? 32 : 48, vertical: isCompact ? 16 : 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [AnimeColors.miku, AnimeColors.purple],
          ),
          boxShadow: [
            BoxShadow(
              color: AnimeColors.miku.withOpacity(0.4),
              blurRadius: 30,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: isCompact ? 22 : 26),
            SizedBox(width: isCompact ? 10 : 14),
            Text(
              text,
              style: TextStyle(
                fontSize: isCompact ? 15 : 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 作品模式枚举
enum ProjectMode {
  autonomous,
  script;

  String get label {
    switch (this) {
      case ProjectMode.autonomous:
        return '手动模式';
      case ProjectMode.script:
        return '自动模式';
    }
  }

  IconData get icon {
    switch (this) {
      case ProjectMode.autonomous:
        return Icons.brush_outlined;
      case ProjectMode.script:
        return Icons.auto_stories_outlined;
    }
  }

  Color get color {
    switch (this) {
      case ProjectMode.autonomous:
        return AnimeColors.miku;
      case ProjectMode.script:
        return AnimeColors.purple;
    }
  }
}

// 侧边栏菜单项
enum SidebarMenu {
  projects('创作空间', Icons.auto_awesome_outlined),
  drawing('绘图空间', Icons.palette_outlined),
  video('视频空间', Icons.movie_creation_outlined),
  materials('素材库', Icons.perm_media_outlined),
  logs('系统日志', Icons.terminal_outlined);

  final String label;
  final IconData icon;
  const SidebarMenu(this.label, this.icon);
}

// 作品区域页面
class ProjectGalleryPage extends StatefulWidget {
  const ProjectGalleryPage({super.key});

  @override
  State<ProjectGalleryPage> createState() => _ProjectGalleryPageState();
}

class _ProjectGalleryPageState extends State<ProjectGalleryPage> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _projects = [];
  bool _isLoading = true;
  SidebarMenu _currentMenu = SidebarMenu.projects;
  String? _filterMode; // null表示全部, 'autonomous'或'script'表示筛选
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _loadProjects();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // 加载作品数据
  // CRITICAL: 同时加载自动模式和手动模式项目
  Future<void> _loadProjects() async {
    try {
      final List<Map<String, dynamic>> projectsList = [];
      
      // 1. 从 AutoModeProvider 加载自动模式项目
      try {
        final autoModeProvider = AutoModeProvider();
        await autoModeProvider.initialize();
        
        final autoModeProjects = autoModeProvider.allProjects;
        
        // 将 AutoModeProvider 的项目转换为列表格式
        final autoProjects = autoModeProjects.values.map<Map<String, dynamic>>((project) {
          return <String, dynamic>{
            'id': project.id, // CRITICAL: 包含项目 ID
            'title': project.title,
            'date': project.lastModified?.toString().substring(0, 10) ?? DateTime.now().toString().substring(0, 10),
            'thumbnail': Icons.auto_stories_outlined,
            'type': 'video',
            'mode': 'script', // 自动模式
          };
        }).toList();
        
        projectsList.addAll(autoProjects);
        print('[HomePage] 已加载 ${autoProjects.length} 个自动模式项目');
      } catch (e) {
        print('[HomePage] 加载自动模式项目失败: $e');
      }
      
      // 2. 从 SharedPreferences 加载手动模式项目（CRITICAL: 无论自动模式列表是否为空都要加载）
      try {
        final prefs = await SharedPreferences.getInstance();
        final projectsJson = prefs.getString('projects');
        if (projectsJson != null && projectsJson.isNotEmpty) {
          final List<dynamic> decoded = jsonDecode(projectsJson);
          final manualProjects = decoded.map<Map<String, dynamic>>((e) {
            return <String, dynamic>{
              'title': e['title'] as String,
              'date': e['date'] as String,
              'thumbnail': e['type'] == 'video' ? Icons.movie_outlined : Icons.image_outlined,
              'type': e['type'] as String,
              'mode': e['mode'] as String? ?? 'autonomous',
              // CRITICAL: 手动模式项目可能没有 ID，使用 title+date 作为唯一标识
              'id': e['id'] as String? ?? '${e['title']}_${e['date']}',
            };
          }).where((p) => p['mode'] == 'autonomous').toList(); // 只加载手动模式项目
          
          projectsList.addAll(manualProjects);
          print('[HomePage] 已加载 ${manualProjects.length} 个手动模式项目');
        }
      } catch (e) {
        print('[HomePage] 加载手动模式项目失败: $e');
      }
      
      setState(() {
        _projects = projectsList;
        _isLoading = false;
      });
      
      print('[HomePage] ✓ 总共加载 ${_projects.length} 个项目（自动: ${projectsList.where((p) => p['mode'] == 'script').length}, 手动: ${projectsList.where((p) => p['mode'] == 'autonomous').length}）');
    } catch (e) {
      print('[HomePage] ✗ 加载作品失败: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 保存作品数据
  // CRITICAL: 只保存手动模式项目到 SharedPreferences（自动模式项目由 AutoModeProvider 管理）
  Future<void> _saveProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // CRITICAL: 只保存手动模式项目
      final manualProjects = _projects.where((p) => p['mode'] == 'autonomous').toList();
      
      final projectsData = manualProjects.map<Map<String, dynamic>>((p) {
        return <String, dynamic>{
          'title': p['title'] as String,
          'date': p['date'] as String,
          'type': p['type'] as String,
          'mode': p['mode'] as String? ?? 'autonomous',
          'id': p['id'] as String?, // 保存 ID（如果有）
        };
      }).toList();
      
      await prefs.setString('projects', jsonEncode(projectsData));
      print('[HomePage] ✓ 已保存 ${projectsData.length} 个手动模式项目到 SharedPreferences');
    } catch (e) {
      print('[HomePage] ✗ 保存作品失败: $e');
    }
  }

  // 获取筛选后的作品
  List<Map<String, dynamic>> get _filteredProjects {
    if (_filterMode == null) return _projects;
    return _projects.where((p) => p['mode'] == _filterMode).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AnimeColors.darkBg, Color(0xFF0f0f1e), Color(0xFF1a1a2e)],
            ),
          ),
          child: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AnimeColors.miku),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AnimeColors.darkBg, Color(0xFF0f0f1e), Color(0xFF1a1a2e)],
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              // 左侧导航栏
              _buildSidebar(context),
              // 右侧主体内容
              Expanded(
                child: Column(
                  children: [
                    // 顶部栏
                    _buildTopBar(context),
                    // 主体内容
                    Expanded(
                      child: _buildMainContent(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 构建左侧导航栏
  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 140,
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.05), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Logo + 标题
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AnimeColors.miku, AnimeColors.purple],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: AnimeColors.miku.withOpacity(0.3),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(Icons.auto_awesome, color: Colors.white, size: 18),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '星橙',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Divider(color: Colors.white.withOpacity(0.1), height: 1),
          SizedBox(height: 12),
          // 菜单项（可滚动）
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: SidebarMenu.values.map((menu) => _buildSidebarItem(menu)).toList(),
              ),
            ),
          ),
          SizedBox(height: 8),
          Divider(color: Colors.white.withOpacity(0.1), height: 1),
          SizedBox(height: 10),
          // 返回首页
          _buildSidebarTextButton(
            icon: Icons.home_outlined,
            label: '首页',
            onTap: () => Navigator.pop(context),
          ),
          SizedBox(height: 6),
          // 设置
          _buildSidebarTextButton(
            icon: Icons.settings_outlined,
            label: '设置',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(SidebarMenu menu) {
    final isSelected = _currentMenu == menu;
    return InkWell(
      onTap: () {
        setState(() {
          _currentMenu = menu;
          _filterMode = null;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: isSelected
              ? LinearGradient(colors: [AnimeColors.miku.withOpacity(0.25), AnimeColors.purple.withOpacity(0.15)])
              : null,
          border: isSelected
              ? Border.all(color: AnimeColors.miku.withOpacity(0.4), width: 1)
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(
              menu.icon,
              color: isSelected ? AnimeColors.miku : Colors.white54,
              size: 18,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                menu.label,
                style: TextStyle(
                  color: isSelected ? AnimeColors.miku : Colors.white70,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarTextButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Colors.white.withOpacity(0.03),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white54, size: 18),
            SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: Colors.white60,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建主体内容
  Widget _buildMainContent(BuildContext context) {
    switch (_currentMenu) {
      case SidebarMenu.projects:
        return _buildProjectsGrid(context);
      case SidebarMenu.drawing:
        return _buildDrawingSpace();
      case SidebarMenu.video:
        return _buildVideoSpace();
      case SidebarMenu.materials:
        return _buildMaterialsLibrary();
      case SidebarMenu.logs:
        return _buildSystemLogs();
    }
  }

  // 绘图空间
  Widget _buildDrawingSpace() {
    return DrawingSpaceWidget();
  }

  // 视频空间
  Widget _buildVideoSpace() {
    return VideoSpaceWidget();
  }

  // 素材库
  Widget _buildMaterialsLibrary() {
    return MaterialsLibraryWidget();
  }

  // 系统日志
  Widget _buildSystemLogs() {
    return SystemLogsWidget();
  }

  // 作品网格（响应式）
  Widget _buildProjectsGrid(BuildContext context) {
    final projects = _filteredProjects;
    if (projects.isEmpty) {
      return _buildEmptyState(context);
    }
    return GridView.builder(
      padding: EdgeInsets.all(20),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150, // 最大宽度 150px（原300px的一半），自动适应列数
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.78, // 保持宽高比，高度会自动减半
      ),
      itemCount: projects.length,
      itemBuilder: (context, index) {
        return _buildProjectCard(context, projects[index], _projects.indexOf(projects[index]));
      },
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          // 标题
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _currentMenu.label,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 4),
              Text(
                _getSubtitle(),
                style: TextStyle(fontSize: 13, color: Colors.white54),
              ),
            ],
          ),
          Spacer(),
          // 筛选标签
          if (_currentMenu == SidebarMenu.projects)
            ...[
              _buildFilterChip('全部', null),
              SizedBox(width: 8),
              _buildFilterChip('手动模式', 'autonomous'),
              SizedBox(width: 8),
              _buildFilterChip('自动模式', 'script'),
              SizedBox(width: 20),
            ],
          // 创建作品按钮
          if (_currentMenu == SidebarMenu.projects)
            InkWell(
              onTap: () => _showCreateProjectDialog(context),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [AnimeColors.miku, AnimeColors.purple],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AnimeColors.miku.withOpacity(0.35),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 8),
                    Text(
                      '创建作品',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getSubtitle() {
    switch (_currentMenu) {
      case SidebarMenu.projects:
        return '管理你的所有创作项目';
      case SidebarMenu.drawing:
        return 'AI 智能绘图工具';
      case SidebarMenu.video:
        return 'AI 视频生成与编辑';
      case SidebarMenu.materials:
        return '角色、场景、道具素材管理';
      case SidebarMenu.logs:
        return '查看系统运行状态';
    }
  }

  Widget _buildFilterChip(String label, String? mode) {
    final isSelected = _filterMode == mode;
    return InkWell(
      onTap: () => setState(() => _filterMode = mode),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isSelected ? AnimeColors.miku.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          border: Border.all(
            color: isSelected ? AnimeColors.miku : Colors.white.withOpacity(0.1),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AnimeColors.miku : Colors.white60,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.folder_open_outlined, size: 50, color: Colors.white24),
          ),
          SizedBox(height: 24),
          Text(
            '还没有作品',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white70),
          ),
          SizedBox(height: 12),
          Text(
            '点击上方按钮创建你的第一个作品',
            style: TextStyle(fontSize: 14, color: Colors.white38),
          ),
          SizedBox(height: 32),
          InkWell(
            onTap: () => _showCreateProjectDialog(context),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(colors: [AnimeColors.miku, AnimeColors.purple]),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, color: Colors.white),
                  SizedBox(width: 8),
                  Text('开始创作', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectCard(BuildContext context, Map<String, dynamic> project, int index) {
    final mode = project['mode'] as String? ?? 'autonomous';
    final isAutonomous = mode == 'autonomous';
    final modeColor = isAutonomous ? AnimeColors.miku : AnimeColors.purple;
    final modeIcon = isAutonomous ? Icons.brush_outlined : Icons.auto_stories_outlined;
    final modeLabel = isAutonomous ? '手动' : '自动';

    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据卡片宽度计算字体大小
        final cardWidth = constraints.maxWidth;
        final isSmall = cardWidth < 150;
        final titleFontSize = isSmall ? 11.0 : 14.0;
        final dateFontSize = isSmall ? 9.0 : 11.0;
        final iconSize = isSmall ? 32.0 : 48.0;
        final padding = isSmall ? 8.0 : 14.0;
        final labelFontSize = isSmall ? 8.0 : 10.0;
        final labelIconSize = isSmall ? 10.0 : 12.0;
        final labelPadding = isSmall ? EdgeInsets.symmetric(horizontal: 6, vertical: 3) : EdgeInsets.symmetric(horizontal: 10, vertical: 5);
        
        return InkWell(
          onTap: () {
            // CRITICAL: 确保传递正确的项目 ID
            final projectId = project['id'] as String?;
            final projectTitle = project['title'] as String? ?? '未命名项目';
            
            // 根据模式打开不同的工作区
            if (isAutonomous) {
              // CRITICAL: 手动模式 - 返回后重新加载项目列表
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WorkspaceShell(projectData: project),
                ),
              ).then((_) {
                // 从 WorkspaceShell 返回后，重新加载项目列表
                if (mounted) {
                  _loadProjects();
                  print('[HomePage] 从手动模式返回，已重新加载项目列表');
                }
              });
            } else {
              // CRITICAL: 自动模式 - 传递包含 ID 的 projectData
              print('[HomePage] 正在打开已有项目: $projectId, 标题: $projectTitle');
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AutoModeScreen(
                    projectData: {
                      'id': projectId, // CRITICAL: 确保传递 ID
                      'title': projectTitle,
                    },
                  ),
                ),
              ).then((_) {
                // 从 AutoModeScreen 返回后，重新加载项目列表
                if (mounted) {
                  _loadProjects();
                  print('[HomePage] 从自动模式返回，已重新加载项目列表');
                }
              });
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: AnimeColors.glassBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                ),
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 缩略图
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  modeColor.withOpacity(0.25),
                                  AnimeColors.purple.withOpacity(0.15),
                                ],
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                project['thumbnail'] as IconData,
                                size: iconSize,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                        ),
                        // 信息
                        Padding(
                          padding: EdgeInsets.all(padding),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                project['title'],
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: titleFontSize,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 4),
                              Text(
                                project['date'],
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: dateFontSize,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // 模式标签
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: labelPadding,
                        decoration: BoxDecoration(
                          color: modeColor.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: modeColor.withOpacity(0.4),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(modeIcon, color: Colors.white, size: labelIconSize),
                            SizedBox(width: 3),
                            Text(
                              modeLabel,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: labelFontSize,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 删除按钮
                    Positioned(
                      top: 6,
                      right: 6,
                      child: InkWell(
                        onTap: () => _deleteProject(context, index),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: EdgeInsets.all(isSmall ? 4 : 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            color: Colors.white,
                            size: isSmall ? 12 : 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // 显示创建作品对话框
  void _showCreateProjectDialog(BuildContext context) {
    final TextEditingController nameController = TextEditingController();
    String selectedMode = 'autonomous';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: 480,
                decoration: BoxDecoration(
                  color: AnimeColors.cardBg.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标题栏
                    Container(
                      padding: EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [AnimeColors.miku, AnimeColors.purple]),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(Icons.add_rounded, color: Colors.white, size: 26),
                          ),
                          SizedBox(width: 16),
                          Text(
                            '创建新作品',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: Icon(Icons.close, color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                    // 内容区
                    Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 作品名称
                          Text(
                            '作品名称',
                            style: TextStyle(color: AnimeColors.miku, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 12),
                          TextField(
                            controller: nameController,
                            autofocus: true,
                            enabled: true,
                            readOnly: false,
                            enableInteractiveSelection: true,
                            style: TextStyle(color: Colors.white, fontSize: 15),
                            decoration: InputDecoration(
                              hintText: '例如：我的第一部动漫作品',
                              hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.white10),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.white10),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: AnimeColors.miku, width: 2),
                              ),
                              filled: true,
                              fillColor: AnimeColors.darkBg,
                              contentPadding: EdgeInsets.all(16),
                              prefixIcon: Icon(Icons.edit_outlined, color: Colors.white38, size: 20),
                            ),
                          ),
                          SizedBox(height: 28),
                          // 创作模式
                          Text(
                            '创作模式',
                            style: TextStyle(color: AnimeColors.miku, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildModeOption(
                                  mode: 'autonomous',
                                  icon: Icons.brush_outlined,
                                  label: '手动模式',
                                  description: '自由创作，精细控制每一帧',
                                  color: AnimeColors.miku,
                                  isSelected: selectedMode == 'autonomous',
                                  onTap: () => setDialogState(() => selectedMode = 'autonomous'),
                                ),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: _buildModeOption(
                                  mode: 'script',
                                  icon: Icons.auto_stories_outlined,
                                  label: '自动模式',
                                  description: '一句话生成完整视频',
                                  color: AnimeColors.purple,
                                  isSelected: selectedMode == 'script',
                                  onTap: () => setDialogState(() => selectedMode = 'script'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // 操作按钮
                    Padding(
                      padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: Text('取消', style: TextStyle(color: Colors.white54, fontSize: 15)),
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: InkWell(
                              onTap: () async {
                                if (nameController.text.isNotEmpty) {
                                  await _createProject(nameController.text, selectedMode);
                                  Navigator.pop(dialogContext);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('作品创建成功！'),
                                      backgroundColor: AnimeColors.miku,
                                    ),
                                  );
                                }
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [AnimeColors.miku, AnimeColors.purple]),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Center(
                                  child: Text(
                                    '创建作品',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ).then((_) => nameController.dispose());
  }

  Widget _buildModeOption({
    required String mode,
    required IconData icon,
    required String label,
    required String description,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isSelected ? color.withOpacity(0.15) : Colors.white.withOpacity(0.03),
          border: Border.all(
            color: isSelected ? color : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: isSelected ? LinearGradient(colors: [color, color.withOpacity(0.7)]) : null,
                color: isSelected ? null : Colors.white.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: isSelected ? Colors.white : Colors.white54, size: 26),
            ),
            SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 6),
            Text(
              description,
              style: TextStyle(color: Colors.white38, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // 创建新作品
  Future<void> _createProject(String name, String mode) async {
    logService.action('创建新作品', details: '名称: $name, 模式: $mode');
    
    // CRITICAL: 如果是自动模式，使用 AutoModeProvider 创建项目
    if (mode == 'script') {
      final autoModeProvider = AutoModeProvider();
      await autoModeProvider.initialize();
      
      // CRITICAL: 使用 createNewProject 方法创建新项目
      await autoModeProvider.initialize();
      final projectId = await autoModeProvider.createNewProject(title: name);
      
      // 添加到本地列表
      setState(() {
        _projects.add(<String, dynamic>{
          'id': projectId, // CRITICAL: 包含项目 ID
          'title': name,
          'date': DateTime.now().toString().substring(0, 10),
          'thumbnail': Icons.auto_stories_outlined,
          'type': 'video',
          'mode': mode,
        });
      });
      
      print('[HomePage] 创建自动模式项目: $projectId, 标题: $name');
    } else {
      // 手动模式，保存到 SharedPreferences
      final now = DateTime.now();
      final dateStr = now.toString().substring(0, 10);
      
      setState(() {
        _projects.add(<String, dynamic>{
          'title': name,
          'date': dateStr,
          'thumbnail': Icons.movie_outlined,
          'type': 'video',
          'mode': mode,
          // CRITICAL: 为手动模式项目生成唯一 ID
          'id': '${name}_$dateStr',
        });
      });
      
      // CRITICAL: 立即保存到 SharedPreferences，确保数据持久化
      await _saveProjects();
      print('[HomePage] ✓ 手动模式项目已保存到 SharedPreferences: $name');
    }
    
    logService.info('作品创建成功', details: name);
  }

  // 删除作品
  void _deleteProject(BuildContext context, int index) {
    final project = _projects[index];
    final projectId = project['id'] as String?;
    final projectMode = project['mode'] as String? ?? 'autonomous';
    final isAutoMode = projectMode == 'script';
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AnimeColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AnimeColors.sakura),
            SizedBox(width: 8),
            Text(
              '确认删除',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(
          '确认彻底删除该作品吗？此操作不可恢复。\n\n作品名称: "${project['title']}"',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              
              try {
                final projectName = project['title'] as String;
                logService.action('删除作品', details: projectName);
                
                // CRITICAL: 根据模式选择删除方式
                if (isAutoMode && projectId != null) {
                  // 自动模式：使用 AutoModeProvider 删除（从 Hive 磁盘删除）
                  final autoModeProvider = AutoModeProvider();
                  await autoModeProvider.initialize();
                  await autoModeProvider.deleteProject(projectId);
                  print('[HomePage] ✓ 已从 AutoModeProvider 删除项目: $projectId');
                } else {
                  // 手动模式：从 SharedPreferences 删除
                  // 手动模式项目存储在 SharedPreferences 的 'projects' 键中
                  // 删除操作已经在 _saveProjects() 中处理（通过更新列表）
                }
                
                // 从本地列表删除
                setState(() {
                  _projects.removeAt(index);
                });
                
                // CRITICAL: 保存更新后的列表（手动模式需要，自动模式列表会从 Provider 重新加载）
                await _saveProjects();
                
                // CRITICAL: 如果是自动模式，重新加载项目列表以确保 UI 同步
                if (isAutoMode) {
                  await _loadProjects();
                }
                
                logService.info('作品已删除', details: projectName);
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✓ 作品已永久删除'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                print('[HomePage] ✗ 删除项目失败: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('删除失败: $e'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AnimeColors.sakura,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('确认删除'),
          ),
        ],
      ),
    );
  }
}

// 自动模式工作空间 - 类似市面上AI视频生成软件的对话式界面
class ScriptModeWorkspace extends StatefulWidget {
  final Map<String, dynamic>? projectData;
  const ScriptModeWorkspace({super.key, this.projectData});

  @override
  State<ScriptModeWorkspace> createState() => _ScriptModeWorkspaceState();
}

class _ScriptModeWorkspaceState extends State<ScriptModeWorkspace> {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isGenerating = false;
  int _currentStep = 0; // 0: 初始, 1: 故事生成, 2: 分镜生成, 3: 图片生成, 4: 视频生成

  final List<String> _steps = ['故事创意', '剧本生成', '分镜设计', '图片生成', '视频合成'];

  @override
  void initState() {
    super.initState();
    _addWelcomeMessage();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _addWelcomeMessage() {
    _messages.add({
      'role': 'assistant',
      'content': '你好！我是你的 AI 动漫导演助手 ✨\n\n只需告诉我你想要创作的故事，我会帮你完成：\n\n🎭 故事创意 → 📝 剧本生成 → 🎬 分镜设计 → 🎨 图片生成 → 🎥 视频合成\n\n现在，请告诉我你想创作什么样的动漫故事？',
      'timestamp': DateTime.now(),
    });
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

  Future<void> _sendMessage() async {
    if (_chatController.text.trim().isEmpty || _isGenerating) return;

    final userMessage = _chatController.text.trim();
    _chatController.clear();

    setState(() {
      _messages.add({
        'role': 'user',
        'content': userMessage,
        'timestamp': DateTime.now(),
      });
      _isGenerating = true;
    });
    _scrollToBottom();

    try {
      // 根据当前步骤生成不同内容
      await _processUserInput(userMessage);
    } catch (e) {
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': '抱歉，处理请求时出现错误：$e\n\n请检查 API 配置后重试。',
          'timestamp': DateTime.now(),
          'isError': true,
        });
      });
    } finally {
      setState(() => _isGenerating = false);
      _scrollToBottom();
    }
  }

  Future<void> _processUserInput(String input) async {
    if (!apiConfigManager.hasLlmConfig) {
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': '⚠️ 请先在设置中配置 LLM API，才能开始创作之旅！',
          'timestamp': DateTime.now(),
          'isError': true,
        });
      });
      return;
    }

    final apiService = apiConfigManager.createApiService();

    // 第一步：生成故事大纲
    setState(() {
      _currentStep = 1;
      _messages.add({
        'role': 'assistant',
        'content': '正在为你构思故事... 🎭',
        'timestamp': DateTime.now(),
        'isLoading': true,
      });
    });
    _scrollToBottom();

    try {
      final storyResponse = await apiService.chatCompletion(
        model: apiConfigManager.llmModel,
        messages: [
          {
            'role': 'system',
            'content': '你是一个专业的动漫故事创作者。请根据用户的创意，创作一个简洁有趣的动漫故事大纲。故事要有明确的开头、发展、高潮和结尾。请用300字以内概括。'
          },
          {'role': 'user', 'content': input},
        ],
        temperature: 0.8,
      );

      final story = storyResponse.choices.first.message.content;

      // 更新消息，替换loading状态
      setState(() {
        _messages.removeLast();
        _messages.add({
          'role': 'assistant',
          'content': '📖 **故事大纲已生成！**\n\n$story\n\n---\n\n要继续生成详细剧本吗？回复 "继续" 或提出修改意见。',
          'timestamp': DateTime.now(),
          'step': 1,
          'data': story,
        });
        _currentStep = 1;
      });
    } catch (e) {
      setState(() {
        _messages.removeLast();
        _messages.add({
          'role': 'assistant',
          'content': '❌ 生成失败：$e',
          'timestamp': DateTime.now(),
          'isError': true,
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AnimeColors.darkBg, Color(0xFF0f0f1e), Color(0xFF1a1a2e)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 顶部栏
              _buildTopBar(),
              // 步骤指示器
              _buildStepIndicator(),
              // 聊天区域
              Expanded(
                child: _buildChatArea(),
              ),
              // 输入区域
              _buildInputArea(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
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
              gradient: LinearGradient(colors: [AnimeColors.purple, AnimeColors.sakura]),
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
                  widget.projectData?['title'] ?? '自动模式',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '一句话生成完整动漫视频',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
          // 快捷操作按钮
          _buildQuickAction(Icons.refresh_rounded, '重新开始', () {
            setState(() {
              _messages.clear();
              _currentStep = 0;
              _addWelcomeMessage();
            });
          }),
          SizedBox(width: 8),
          _buildQuickAction(Icons.auto_awesome_motion, '提示词模板', () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PromptConfigView()),
            );
          }),
          SizedBox(width: 8),
          _buildQuickAction(Icons.settings_outlined, '设置', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
          }),
        ],
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white54, size: 18),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: List.generate(_steps.length, (index) {
          final isCompleted = index < _currentStep;
          final isActive = index == _currentStep;
          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isCompleted || isActive
                        ? LinearGradient(colors: [AnimeColors.miku, AnimeColors.purple])
                        : null,
                    color: isCompleted || isActive ? null : Colors.white.withOpacity(0.1),
                    border: isActive
                        ? Border.all(color: AnimeColors.miku, width: 2)
                        : null,
                  ),
                  child: Center(
                    child: isCompleted
                        ? Icon(Icons.check, color: Colors.white, size: 16)
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.white38,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _steps[index],
                    style: TextStyle(
                      color: isCompleted || isActive ? Colors.white : Colors.white38,
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (index < _steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: isCompleted ? AnimeColors.miku : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildChatArea() {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.all(20),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isUser = message['role'] == 'user';
        final isLoading = message['isLoading'] == true;
        final isError = message['isError'] == true;

        return Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [AnimeColors.purple, AnimeColors.miku]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.smart_toy_outlined, color: Colors.white, size: 20),
                ),
                SizedBox(width: 12),
              ],
              Flexible(
                child: Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isUser
                        ? AnimeColors.miku.withOpacity(0.2)
                        : isError
                            ? AnimeColors.sakura.withOpacity(0.1)
                            : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isUser
                          ? AnimeColors.miku.withOpacity(0.3)
                          : isError
                              ? AnimeColors.sakura.withOpacity(0.3)
                              : Colors.white.withOpacity(0.08),
                    ),
                  ),
                  child: isLoading
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(AnimeColors.miku),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              message['content'],
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ],
                        )
                      : SelectableText(
                          message['content'],
                          style: TextStyle(
                            color: isError ? AnimeColors.sakura : Colors.white.withOpacity(0.85),
                            fontSize: 14,
                            height: 1.6,
                          ),
                        ),
                ),
              ),
              if (isUser) ...[
                SizedBox(width: 12),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [AnimeColors.miku, AnimeColors.blue]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.person_rounded, color: Colors.white, size: 20),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Row(
        children: [
          // 快捷指令
          _buildQuickCommand('✨ 生成故事', '帮我创作一个关于冒险的动漫故事'),
          SizedBox(width: 8),
          _buildQuickCommand('🎬 继续', '继续'),
          SizedBox(width: 16),
          // 输入框（响应式包装）
          Expanded(
            child: ResponsiveInputWrapper(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: TextField(
                  controller: _chatController,
                  enabled: true,
                  readOnly: false,
                  enableInteractiveSelection: true,
                  style: TextStyle(color: Colors.white, fontSize: 15),
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: '告诉我你想创作的故事...',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 15),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
          ),
          SizedBox(width: 12),
          // 发送按钮
          InkWell(
            onTap: _isGenerating ? null : _sendMessage,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: _isGenerating
                    ? null
                    : LinearGradient(colors: [AnimeColors.miku, AnimeColors.purple]),
                color: _isGenerating ? Colors.white.withOpacity(0.1) : null,
                borderRadius: BorderRadius.circular(16),
              ),
              child: _isGenerating
                  ? Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white54),
                        ),
                      ),
                    )
                  : Icon(Icons.send_rounded, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickCommand(String label, String command) {
    return InkWell(
      onTap: () {
        _chatController.text = command;
        _sendMessage();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Text(
          label,
          style: TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ),
    );
  }
}

// 星橙工坊（创作界面）
class WorkspaceShell extends StatefulWidget {
  final Map<String, dynamic>? projectData;
  const WorkspaceShell({super.key, this.projectData});

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  int _currentTab = 0;
  
  /// 显示删除所有手动模式项目确认对话框
  Future<void> _showDeleteAllManualProjectsDialog(BuildContext context) async {
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
              '确认删除',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          '确定要删除所有手动模式项目吗？\n\n此操作将：\n• 删除所有手动模式项目数据\n• 无法恢复\n\n此操作不可撤销！',
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
            child: Text('确定删除'),
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
                    '正在删除项目...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        );

        // 执行删除所有手动模式项目
        await _deleteAllManualProjects();

        // 关闭加载指示器
        if (mounted) {
          Navigator.of(context).pop();
        }

        // 显示成功提示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ 所有手动模式项目已删除'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
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
              content: Text('删除失败: $e'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }
  
  /// 删除所有手动模式项目
  Future<void> _deleteAllManualProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final projectsJson = prefs.getString('projects');
      
      if (projectsJson != null) {
        final List<dynamic> decoded = jsonDecode(projectsJson);
        // 只保留非手动模式的项目（即自动模式项目）
        final filteredProjects = decoded.where((p) {
          final mode = p['mode'] as String? ?? 'autonomous';
          return mode != 'autonomous'; // 删除手动模式，保留其他模式
        }).toList();
        
        // 保存过滤后的项目列表
        await prefs.setString('projects', jsonEncode(filteredProjects));
        print('[WorkspaceShell] ✓ 已删除所有手动模式项目');
      }
    } catch (e) {
      print('[WorkspaceShell] ✗ 删除手动模式项目失败: $e');
      rethrow;
    }
  }

  List<Widget> get _pages => const [
        StoryGenerationPanel(),
        ScriptGenerationPanel(),
        StoryboardGenerationPanel(),
        CharacterGenerationPanel(),
        SceneGenerationPanel(),
        PropGenerationPanel(),
      ];

  final List<(IconData, String)> _navItems = [
    (Icons.auto_stories_outlined, '故事生成'),
    (Icons.description_outlined, '剧本生成'),
    (Icons.view_agenda_outlined, '分镜生成'),
    (Icons.person_outline, '角色生成'),
    (Icons.landscape_outlined, '场景生成'),
    (Icons.inventory_2_outlined, '物品生成'),
  ];

  @override
  Widget build(BuildContext context) {
    final screenType = ResponsiveLayout.currentScreenType(context);
    final isMobile = screenType == ScreenType.mobile;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AnimeColors.darkBg, Color(0xFF0f0f1e)],
          ),
        ),
        child: SafeArea(
          child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
        ),
      ),
      bottomNavigationBar: isMobile ? _buildBottomNavigationBar() : null,
    );
  }

  /// 构建桌面/平板布局（使用 NavigationRail）
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // 左侧导航栏
        _buildNavigationRail(),
        // 右侧主体
        Expanded(
          child: Column(
            children: [
              _buildTopBar(context),
              Expanded(
                child: AnimatedSwitcher(
                  duration: Duration(milliseconds: 300),
                  child: Container(
                    key: ValueKey(_currentTab),
                    padding: EdgeInsets.all(20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AnimeColors.glassBg,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                          ),
                          child: _currentTab < _pages.length ? _pages[_currentTab] : SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建移动端布局
  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildTopBar(context),
        Expanded(
          child: AnimatedSwitcher(
            duration: Duration(milliseconds: 300),
            child: Container(
              key: ValueKey(_currentTab),
              padding: EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AnimeColors.glassBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                    ),
                    child: _currentTab < _pages.length ? _pages[_currentTab] : SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建桌面端导航栏（NavigationRail）
  Widget _buildNavigationRail() {
    return Container(
      width: 220,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 返回按钮
          InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white.withOpacity(0.05),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  Icon(Icons.arrow_back_ios_new_rounded, color: AnimeColors.miku, size: 18),
                  SizedBox(width: 8),
                  Text(
                    '返回作品区',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 24),
          // 导航项
          Expanded(
            child: ListView.builder(
              itemCount: _navItems.length,
              itemBuilder: (context, index) {
                final isSelected = _currentTab == index;
                final (icon, label) = _navItems[index];
                return Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () => setState(() => _currentTab = index),
                    borderRadius: BorderRadius.circular(16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: isSelected ? AnimeColors.glassBg : Colors.transparent,
                            border: Border.all(
                              color: isSelected ? AnimeColors.miku.withOpacity(0.5) : Colors.white.withOpacity(0.1),
                              width: isSelected ? 2 : 1,
                            ),
                            gradient: isSelected
                                ? LinearGradient(
                                    colors: [
                                      AnimeColors.miku.withOpacity(0.2),
                                      AnimeColors.purple.withOpacity(0.2),
                                    ],
                                  )
                                : null,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                icon,
                                size: 20,
                                color: isSelected ? AnimeColors.miku : Colors.white60,
                              ),
                              SizedBox(width: 12),
                              Text(
                                label,
                                style: TextStyle(
                                  color: isSelected ? AnimeColors.miku : Colors.white70,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 构建移动端底部导航栏
  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: SafeArea(
        child: Container(
          height: 70,
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_navItems.length, (index) {
              final isSelected = _currentTab == index;
              final (icon, label) = _navItems[index];
              return Expanded(
                child: InkWell(
                  onTap: () => setState(() => _currentTab = index),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: isSelected ? AnimeColors.miku.withOpacity(0.2) : Colors.transparent,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 24,
                          color: isSelected ? AnimeColors.miku : Colors.white60,
                        ),
                        SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            color: isSelected ? AnimeColors.miku : Colors.white60,
                            fontSize: 10,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Row(
        children: [
          Text(
            '自主创作，我的漫剧我做主！',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          Spacer(),
          // 设置按钮
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
            icon: Icon(Icons.settings_outlined, color: Colors.white70),
            tooltip: 'API 设置',
          ),
        ],
      ),
    );
  }
}

// 故事生成面板（保留原有逻辑，只更新样式）
class StoryGenerationPanel extends StatefulWidget {
  const StoryGenerationPanel({super.key});

  @override
  State<StoryGenerationPanel> createState() => _StoryGenerationPanelState();
}

class _StoryGenerationPanelState extends State<StoryGenerationPanel> {
  final TextEditingController _storyController = TextEditingController();
  bool _isLoading = false;
  String? _generatedStory;
  String? _selectedTemplate; // 选中的提示词模板名称
  Map<String, String> _promptTemplates = {}; // 提示词模板列表（合并所有类别）

  @override
  void initState() {
    super.initState();
    _loadPromptTemplates();
    _loadSelectedTemplate();
    _loadSavedContent(); // 加载保存的内容
  }

  @override
  void dispose() {
    _saveTimer?.cancel(); // CRITICAL: 取消定时器，防止内存泄漏
    _storyController.dispose();
    super.dispose();
  }

  // 加载保存的内容
  Future<void> _loadSavedContent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedInput = prefs.getString('story_input');
      final savedOutput = prefs.getString('story_output');
      if (mounted) {
        setState(() {
          if (savedInput != null && savedInput.isNotEmpty) {
            _storyController.text = savedInput;
          }
          if (savedOutput != null && savedOutput.isNotEmpty) {
            _generatedStory = savedOutput;
          }
        });
      }
    } catch (e) {
      logService.error('加载故事内容失败', details: e.toString());
    }
  }

  // 保存内容（使用防抖，避免频繁写入）
  Timer? _saveTimer;
  Future<void> _saveContent() async {
    // 取消之前的定时器
    _saveTimer?.cancel();
    // 设置新的定时器，500ms 后保存（防抖）
    _saveTimer = Timer(Duration(milliseconds: 500), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('story_input', _storyController.text);
        if (_generatedStory != null) {
          await prefs.setString('story_output', _generatedStory!);
        }
        print('[StoryGenerationPanel] ✓ 已保存输入内容');
      } catch (e) {
        logService.error('保存故事内容失败', details: e.toString());
      }
    });
  }

  // 加载提示词模板（从所有类别加载，优先使用图片提示词）
  Future<void> _loadPromptTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final promptsJson = prefs.getString('prompts');
      if (promptsJson != null) {
        final decoded = jsonDecode(promptsJson) as Map<String, dynamic>;
        // 合并所有类别的提示词，优先使用图片提示词
        final allPrompts = <String, String>{};
        // 按优先级顺序加载：image > character > scene > video > prop
        final categories = ['image', 'character', 'scene', 'video', 'prop'];
        for (final category in categories) {
          final categoryPrompts = Map<String, String>.from(decoded[category] ?? {});
          categoryPrompts.forEach((key, value) {
            if (!allPrompts.containsKey(key)) {
              allPrompts[key] = value;
            }
          });
        }
        setState(() {
          _promptTemplates = allPrompts;
        });
      }
    } catch (e) {
      logService.error('加载提示词模板失败', details: e.toString());
    }
  }

  // 加载保存的模板选择
  Future<void> _loadSelectedTemplate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTemplate = prefs.getString('story_selected_template');
      if (savedTemplate != null && savedTemplate.isNotEmpty) {
        setState(() {
          _selectedTemplate = savedTemplate;
        });
      }
    } catch (e) {
      logService.error('加载保存的模板选择失败', details: e.toString());
    }
  }


  // 保存模板选择
  Future<void> _saveSelectedTemplate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_selectedTemplate != null) {
        await prefs.setString('story_selected_template', _selectedTemplate!);
      } else {
        await prefs.remove('story_selected_template');
      }
      logService.info('保存模板选择', details: _selectedTemplate ?? '不使用模板');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('模板选择已保存'),
            backgroundColor: AnimeColors.miku,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      logService.error('保存模板选择失败', details: e.toString());
    }
  }

  // 显示模板选择对话框
  void _showTemplateSelector() {
    showDialog(
      context: context,
      builder: (context) => _PromptTemplateManagerDialog(
        category: 'story',
        selectedTemplate: _selectedTemplate,
        accentColor: AnimeColors.miku,
        onSelect: (template) {
          setState(() {
            _selectedTemplate = template;
          });
          if (template != null) {
            _saveSelectedTemplate();
          }
        },
        onSave: () {
          _loadPromptTemplates();
        },
      ),
    );
  }

  Future<void> _generateStory() async {
    if (_storyController.text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先输入一句话生成剧本')),
      );
      return;
    }
    if (!apiConfigManager.hasLlmConfig) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在设置中配置 LLM API')),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final apiService = apiConfigManager.createApiService();
      
      // 构建系统提示词
      String systemPrompt = '你是一个专业的剧本作家，擅长创作动漫故事。请根据用户提供的大纲，生成一个完整、生动的剧本。';
      
      // 如果选择了模板，在系统提示词后加上模板内容
      if (_selectedTemplate != null && _promptTemplates.containsKey(_selectedTemplate)) {
        final templateContent = _promptTemplates[_selectedTemplate]!;
        if (templateContent.isNotEmpty) {
          systemPrompt = '$systemPrompt\n\n$templateContent';
        }
      }
      
      // 添加重试机制（最多重试3次）
      int maxRetries = 3;
      int retryCount = 0;
      ChatCompletionResponse? response;
      
      while (retryCount < maxRetries) {
        try {
          response = await apiService.chatCompletion(
            model: apiConfigManager.llmModel,
            messages: [
              {
                'role': 'system',
                'content': systemPrompt
              },
              {
                'role': 'user',
                'content': '请根据以下大纲生成一个完整的动漫剧本：\n\n${_storyController.text}'
              },
            ],
            temperature: 0.7,
          );
          break; // 成功，退出重试循环
        } catch (e) {
          retryCount++;
          if (e is ApiException && e.statusCode == 503) {
            // 503 错误，等待后重试
            if (retryCount < maxRetries) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('服务器暂时不可用，正在重试... ($retryCount/$maxRetries)'),
                  backgroundColor: AnimeColors.orangeAccent,
                  duration: Duration(seconds: 2),
                ),
              );
              await Future.delayed(Duration(seconds: 2 * retryCount)); // 指数退避
              continue;
            }
          }
          // 其他错误或重试次数用完，抛出异常
          rethrow;
        }
      }
      
      if (response == null) {
        throw '生成失败：重试次数已用完';
      }
      
      if (!mounted) return;
      setState(() => _generatedStory = response!.choices.first.message.content);
      await _saveContent(); // 保存生成的内容
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('故事生成成功！'),
          backgroundColor: AnimeColors.miku,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      String errorMessage = '生成失败: $e';
      if (e is ApiException) {
        if (e.statusCode == 503) {
          errorMessage = '服务器暂时不可用 (503)，请稍后重试或检查网络连接';
        } else if (e.statusCode == 401) {
          errorMessage = 'API 密钥无效，请检查设置中的 API Key';
        } else if (e.statusCode == 429) {
          errorMessage = '请求过于频繁，请稍后再试';
        } else {
          errorMessage = '生成失败: ${e.message} (状态码: ${e.statusCode})';
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: AnimeColors.sakura,
          duration: Duration(seconds: 5),
        ),
      );
      logService.error('故事生成失败', details: e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildHeader('📖', '故事生成', 'AI 帮你完善剧本细节')),
              // 提示词模板选择按钮
              TextButton.icon(
                onPressed: _showTemplateSelector,
                icon: Icon(
                  Icons.text_snippet,
                  size: 16,
                  color: _selectedTemplate != null ? AnimeColors.miku : Colors.white54,
                ),
                label: Text(
                  _selectedTemplate != null ? _selectedTemplate! : '提示词模板',
                  style: TextStyle(
                    color: _selectedTemplate != null ? AnimeColors.miku : Colors.white54,
                    fontSize: 12,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              SizedBox(width: 8),
              // 保存按钮
              if (_selectedTemplate != null)
                IconButton(
                  icon: Icon(Icons.save, size: 18, color: AnimeColors.miku),
                  tooltip: '保存模板选择',
                  onPressed: () {
                    _saveSelectedTemplate();
                  },
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
            ],
          ),
          SizedBox(height: 28),
          // 左右两栏布局（响应式包装）
          Expanded(
            child: ResponsiveInputWrapper(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左侧对话框：输入区域
                  Expanded(
                    flex: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AnimeColors.glassBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          padding: EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionLabel('一句话生成剧本'),
                              SizedBox(height: 12),
                              Expanded(
                                child: TextField(
                                  controller: _storyController,
                                  enabled: true,
                                  readOnly: false,
                                  enableInteractiveSelection: true,
                                  maxLines: null,
                                  minLines: 10,
                                  textAlignVertical: TextAlignVertical.top,
                                  style: TextStyle(color: Colors.white70, fontSize: 15),
                                  decoration: _inputDecoration('描述你的故事想法：\n\n• 核心主题\n• 主要情节线\n• 人物性格\n• 情感走向...'),
                                  onChanged: (value) {
                                    // CRITICAL: 实时保存用户输入，防止数据丢失
                                    _saveContent();
                                  },
                                ),
                              ),
                              SizedBox(height: 20),
                              _buildActionButton(
                                '生成完整故事',
                                Icons.auto_awesome_outlined,
                                onPressed: _isLoading ? null : _generateStory,
                                isLoading: _isLoading,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 20),
                  // 右侧对话框：生成结果
                  Expanded(
                    flex: 1,
                    child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AnimeColors.glassBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        padding: EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildSectionLabel('生成结果'),
                                if (_generatedStory != null)
                                  IconButton(
                                    icon: Icon(Icons.copy, size: 18, color: AnimeColors.miku),
                                    tooltip: '一键复制全文',
                                    onPressed: () async {
                                      await Clipboard.setData(ClipboardData(text: _generatedStory!));
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('已复制到剪贴板'), backgroundColor: AnimeColors.miku),
                                      );
                                      logService.action('复制故事全文');
                                    },
                                    padding: EdgeInsets.zero,
                                    constraints: BoxConstraints(),
                                  ),
                              ],
                            ),
                            SizedBox(height: 12),
                            Expanded(
                              child: _generatedStory == null
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.auto_stories_outlined,
                                            size: 60,
                                            color: Colors.white24,
                                          ),
                                          SizedBox(height: 16),
                                          Text(
                                            '生成的故事将显示在这里',
                                            style: TextStyle(
                                              color: Colors.white38,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : SingleChildScrollView(
                                      child: SelectableText(
                                        _generatedStory!,
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                          height: 1.6,
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String emoji, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AnimeColors.miku, AnimeColors.purple],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Text(emoji, style: TextStyle(fontSize: 26)),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 13, color: Colors.white54),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AnimeColors.miku,
        letterSpacing: 0.5,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white10),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AnimeColors.miku, width: 2),
      ),
      filled: true,
      fillColor: AnimeColors.cardBg,
      contentPadding: EdgeInsets.all(16),
    );
  }

  Widget _buildActionButton(
    String text,
    IconData icon, {
    VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: EdgeInsets.zero,
          disabledBackgroundColor: Colors.grey.withOpacity(0.3),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: onPressed == null
                  ? [Colors.grey, Colors.grey]
                  : [AnimeColors.miku, AnimeColors.purple],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                else
                  Icon(icon, size: 20),
                SizedBox(width: 8),
                Text(
                  isLoading ? '生成中...' : text,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 剧本生成面板
class ScriptGenerationPanel extends StatefulWidget {
  const ScriptGenerationPanel({super.key});

  @override
  State<ScriptGenerationPanel> createState() => _ScriptGenerationPanelState();
}

class _ScriptGenerationPanelState extends State<ScriptGenerationPanel> {
  final TextEditingController _scriptInputController = TextEditingController();
  bool _isLoading = false;
  String? _generatedScript;
  String? _selectedTemplate; // 选中的提示词模板名称
  Map<String, String> _promptTemplates = {}; // 视频提示词模板列表

  @override
  void initState() {
    super.initState();
    _loadPromptTemplates();
    _loadSelectedTemplate();
    _loadSavedContent(); // 加载保存的内容
  }

  @override
  void dispose() {
    _saveTimer?.cancel(); // CRITICAL: 取消定时器，防止内存泄漏
    _scriptInputController.dispose();
    super.dispose();
  }

  // 加载保存的内容
  Future<void> _loadSavedContent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedInput = prefs.getString('script_input');
      final savedOutput = prefs.getString('script_output');
      if (mounted) {
        setState(() {
          if (savedInput != null && savedInput.isNotEmpty) {
            _scriptInputController.text = savedInput;
          }
          if (savedOutput != null && savedOutput.isNotEmpty) {
            _generatedScript = savedOutput;
            // 同步更新 workspaceState.script，让角色生成面板能够检测到
            workspaceState.script = savedOutput;
          }
        });
      }
    } catch (e) {
      logService.error('加载剧本内容失败', details: e.toString());
    }
  }

  // 保存内容（使用防抖，避免频繁写入）
  Timer? _saveTimer;
  Future<void> _saveContent() async {
    // 取消之前的定时器
    _saveTimer?.cancel();
    // 设置新的定时器，500ms 后保存（防抖）
    _saveTimer = Timer(Duration(milliseconds: 500), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('script_input', _scriptInputController.text);
        if (_generatedScript != null) {
          await prefs.setString('script_output', _generatedScript!);
        }
        print('[ScriptGenerationPanel] ✓ 已保存输入内容');
      } catch (e) {
        logService.error('保存剧本内容失败', details: e.toString());
      }
    });
  }

  // 加载提示词模板
  Future<void> _loadPromptTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final promptsJson = prefs.getString('prompts');
      if (promptsJson != null) {
        final decoded = jsonDecode(promptsJson) as Map<String, dynamic>;
        setState(() {
          _promptTemplates = Map<String, String>.from(decoded['video'] ?? {});
        });
      }
    } catch (e) {
      logService.error('加载提示词模板失败', details: e.toString());
    }
  }

  // 加载保存的模板选择
  Future<void> _loadSelectedTemplate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTemplate = prefs.getString('script_selected_template');
      if (savedTemplate != null && savedTemplate.isNotEmpty) {
        setState(() {
          _selectedTemplate = savedTemplate;
        });
      }
    } catch (e) {
      logService.error('加载保存的模板选择失败', details: e.toString());
    }
  }

  // 保存模板选择
  Future<void> _saveSelectedTemplate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_selectedTemplate != null) {
        await prefs.setString('script_selected_template', _selectedTemplate!);
      } else {
        await prefs.remove('script_selected_template');
      }
      logService.info('保存模板选择', details: _selectedTemplate ?? '不使用模板');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('模板选择已保存'),
            backgroundColor: AnimeColors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      logService.error('保存模板选择失败', details: e.toString());
    }
  }

  // 显示模板选择对话框
  void _showTemplateSelector() {
    showDialog(
      context: context,
      builder: (context) => _PromptTemplateManagerDialog(
        category: 'video',
        selectedTemplate: _selectedTemplate,
        accentColor: AnimeColors.blue,
        onSelect: (template) {
          setState(() {
            _selectedTemplate = template;
          });
          if (template != null) {
            _saveSelectedTemplate();
          }
        },
        onSave: () {
          _loadPromptTemplates();
        },
      ),
    );
  }

  Future<void> _generateScript() async {
    if (_scriptInputController.text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先输入故事原文')),
      );
      return;
    }
    if (!apiConfigManager.hasLlmConfig) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在设置中配置 LLM API')),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final apiService = apiConfigManager.createApiService();
      
      // 构建系统提示词
      String systemPrompt = '你是一个专业的剧本作家，擅长创作动漫剧本。请根据用户提供的故事内容，生成一个完整的剧本，包含对话、场景描述、人物动作等。';
      
      // 如果选择了模板，在系统提示词后加上模板内容
      if (_selectedTemplate != null && _promptTemplates.containsKey(_selectedTemplate)) {
        final templateContent = _promptTemplates[_selectedTemplate]!;
        if (templateContent.isNotEmpty) {
          systemPrompt = '$systemPrompt\n\n$templateContent';
        }
      }
      
      final response = await apiService.chatCompletion(
        model: apiConfigManager.llmModel,
        messages: [
          {
            'role': 'system',
            'content': systemPrompt
          },
          {
            'role': 'user',
            'content': '请根据以下内容生成一个完整的动漫剧本：\n\n${_scriptInputController.text}'
          },
        ],
        temperature: 0.7,
      );
      if (!mounted) return;
      final generatedContent = response.choices.first.message.content;
      setState(() => _generatedScript = generatedContent);
      await _saveContent(); // 保存生成的内容
      // 保存到共享状态，供其他面板使用
      workspaceState.script = generatedContent;
      logService.action('剧本生成成功');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('剧本生成成功！其他面板现在可以基于此剧本生成内容'), backgroundColor: AnimeColors.miku),
      );
    } catch (e) {
      logService.error('剧本生成失败', details: e.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成失败: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildHeader('📝', '剧本生成', '将故事转化为完整的剧本')),
              // 提示词模板选择按钮
              TextButton.icon(
                onPressed: _showTemplateSelector,
                icon: Icon(
                  Icons.text_snippet,
                  size: 16,
                  color: _selectedTemplate != null ? AnimeColors.blue : Colors.white54,
                ),
                label: Text(
                  _selectedTemplate != null ? _selectedTemplate! : '提示词模板',
                  style: TextStyle(
                    color: _selectedTemplate != null ? AnimeColors.blue : Colors.white54,
                    fontSize: 12,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              SizedBox(width: 8),
              // 保存按钮
              if (_selectedTemplate != null)
                IconButton(
                  icon: Icon(Icons.save, size: 18, color: AnimeColors.blue),
                  tooltip: '保存模板选择',
                  onPressed: () {
                    _saveSelectedTemplate();
                  },
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
            ],
          ),
          SizedBox(height: 28),
          // 左右两栏布局（响应式包装）
          Expanded(
            child: ResponsiveInputWrapper(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左侧对话框：输入区域
                  Expanded(
                    flex: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AnimeColors.glassBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          padding: EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionLabel('故事原文'),
                              SizedBox(height: 12),
                              Expanded(
                                child: TextField(
                                  controller: _scriptInputController,
                                  enabled: true,
                                  readOnly: false,
                                  enableInteractiveSelection: true,
                                  maxLines: null,
                                  minLines: 10,
                                  textAlignVertical: TextAlignVertical.top,
                                  style: TextStyle(color: Colors.white70, fontSize: 15),
                                  decoration: _inputDecoration('输入故事内容或剧本需求：\n\n• 故事梗概\n• 主要角色\n• 关键情节\n• 场景设定...'),
                                  onChanged: (value) {
                                    // CRITICAL: 实时保存用户输入，防止数据丢失
                                    _saveContent();
                                  },
                                ),
                              ),
                            SizedBox(height: 20),
                            _buildActionButton(
                              '生成完整剧本',
                              Icons.auto_awesome_outlined,
                              onPressed: _isLoading ? null : _generateScript,
                              isLoading: _isLoading,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 20),
                // 右侧对话框：生成结果
                Expanded(
                  flex: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AnimeColors.glassBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        padding: EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildSectionLabel('生成结果'),
                                if (_generatedScript != null)
                                  IconButton(
                                    icon: Icon(Icons.copy, size: 18, color: AnimeColors.miku),
                                    tooltip: '一键复制全文',
                                    onPressed: () async {
                                      await Clipboard.setData(ClipboardData(text: _generatedScript!));
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('已复制到剪贴板'), backgroundColor: AnimeColors.miku),
                                      );
                                      logService.action('复制剧本全文');
                                    },
                                    padding: EdgeInsets.zero,
                                    constraints: BoxConstraints(),
                                  ),
                              ],
                            ),
                            SizedBox(height: 12),
                            Expanded(
                              child: _generatedScript == null
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.description_outlined,
                                            size: 60,
                                            color: Colors.white24,
                                          ),
                                          SizedBox(height: 16),
                                          Text(
                                            '生成的剧本将显示在这里',
                                            style: TextStyle(
                                              color: Colors.white38,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : SingleChildScrollView(
                                      child: SelectableText(
                                        _generatedScript!,
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                          height: 1.6,
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String emoji, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AnimeColors.miku, AnimeColors.purple],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Text(emoji, style: TextStyle(fontSize: 26)),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 13, color: Colors.white54),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AnimeColors.miku,
        letterSpacing: 0.5,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white10),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AnimeColors.miku, width: 2),
      ),
      filled: true,
      fillColor: AnimeColors.cardBg,
      contentPadding: EdgeInsets.all(16),
    );
  }

  Widget _buildActionButton(
    String text,
    IconData icon, {
    VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: EdgeInsets.zero,
          disabledBackgroundColor: Colors.grey.withOpacity(0.3),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: onPressed == null
                  ? [Colors.grey, Colors.grey]
                  : [AnimeColors.miku, AnimeColors.purple],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                else
                  Icon(icon, size: 20),
                SizedBox(width: 8),
                Text(
                  isLoading ? '生成中...' : text,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 角色生成面板
class CharacterGenerationPanel extends StatefulWidget {
  const CharacterGenerationPanel({super.key});

  @override
  State<CharacterGenerationPanel> createState() => _CharacterGenerationPanelState();
}

class _CharacterGenerationPanelState extends State<CharacterGenerationPanel> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _characters = [];
  String? _selectedTemplate; // 选中的提示词模板名称
  Map<String, String> _promptTemplates = {}; // 角色提示词模板列表
  // 为每个角色的图片提示词缓存TextEditingController
  final Map<int, TextEditingController> _imagePromptControllers = {};
  // 记录每个角色是否正在生成图片
  final Map<int, bool> _generatingImages = {};
  // 记录每个角色是否正在创建角色
  final Map<int, bool> _creatingCharacters = {};
  // ImagePicker 用于右键上传图片
  final ImagePicker _imagePicker = ImagePicker();
  // 参考风格相关
  String? _referenceStyleImagePath; // 参考风格图片路径
  final TextEditingController _referenceStylePromptController = TextEditingController(text: '参考图片风格，');
  bool _showReferenceStylePanel = false; // 是否显示参考风格面板

  @override
  void initState() {
    super.initState();
    // 同步角色列表（包括从持久化存储加载的角色）
    _characters = List<Map<String, dynamic>>.from(workspaceState.characters);
    _loadPromptTemplates();
    _loadSelectedTemplate();
    _initializeControllers();
    _loadReferenceStyle(); // 加载保存的参考风格设置
    // 监听 workspaceState 的变化，以便实时更新按钮状态和角色列表
    workspaceState.addListener(_onWorkspaceStateChanged);
  }

  @override
  void dispose() {
    workspaceState.removeListener(_onWorkspaceStateChanged);
    // 清理所有Controller
    for (var controller in _imagePromptControllers.values) {
      controller.dispose();
    }
    _imagePromptControllers.clear();
    _referenceStylePromptController.dispose();
    super.dispose();
  }

  void _onWorkspaceStateChanged() {
    // 当 workspaceState 变化时（包括 script 和 characters），更新 UI
    if (mounted) {
      setState(() {
        // 同步角色列表
        _characters = workspaceState.characters;
        // 重新初始化控制器
        _initializeControllers();
      });
    }
  }

  // 初始化Controller
  void _initializeControllers() {
    for (int i = 0; i < _characters.length; i++) {
      if (!_imagePromptControllers.containsKey(i)) {
        final char = _characters[i];
        final controller = TextEditingController(
          text: char['imagePrompt'] as String? ?? '',
        );
        _imagePromptControllers[i] = controller;
      }
    }
  }

  // 获取或创建图片提示词Controller
  TextEditingController _getImagePromptController(int index) {
    if (!_imagePromptControllers.containsKey(index)) {
      final char = _characters[index];
      final controller = TextEditingController(
        text: char['imagePrompt'] as String? ?? '',
      );
      _imagePromptControllers[index] = controller;
    }
    return _imagePromptControllers[index]!;
  }

  // 加载提示词模板
  Future<void> _loadPromptTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final promptsJson = prefs.getString('prompts');
      if (promptsJson != null) {
        final decoded = jsonDecode(promptsJson) as Map<String, dynamic>;
        setState(() {
          _promptTemplates = Map<String, String>.from(decoded['character'] ?? {});
        });
      }
    } catch (e) {
      logService.error('加载提示词模板失败', details: e.toString());
    }
  }

  // 加载保存的模板选择
  Future<void> _loadSelectedTemplate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTemplate = prefs.getString('character_selected_template');
      if (savedTemplate != null && savedTemplate.isNotEmpty) {
        setState(() {
          _selectedTemplate = savedTemplate;
        });
      }
    } catch (e) {
      logService.error('加载保存的模板选择失败', details: e.toString());
    }
  }

  // 加载参考风格设置
  Future<void> _loadReferenceStyle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedImagePath = prefs.getString('character_reference_style_image');
      final savedPrompt = prefs.getString('character_reference_style_prompt');
      if (mounted) {
        setState(() {
          if (savedImagePath != null && savedImagePath.isNotEmpty) {
            // 检查文件是否存在
            final file = File(savedImagePath);
            if (file.existsSync()) {
              _referenceStyleImagePath = savedImagePath;
            }
          }
          if (savedPrompt != null && savedPrompt.isNotEmpty) {
            _referenceStylePromptController.text = savedPrompt;
          }
        });
      }
    } catch (e) {
      logService.error('加载参考风格设置失败', details: e.toString());
    }
  }

  // 保存参考风格设置
  Future<void> _saveReferenceStyle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_referenceStyleImagePath != null && _referenceStyleImagePath!.isNotEmpty) {
        await prefs.setString('character_reference_style_image', _referenceStyleImagePath!);
      } else {
        await prefs.remove('character_reference_style_image');
      }
      await prefs.setString('character_reference_style_prompt', _referenceStylePromptController.text);
    } catch (e) {
      logService.error('保存参考风格设置失败', details: e.toString());
    }
  }

  // 保存模板选择
  Future<void> _saveSelectedTemplate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_selectedTemplate != null) {
        await prefs.setString('character_selected_template', _selectedTemplate!);
      } else {
        await prefs.remove('character_selected_template');
      }
      logService.info('保存模板选择', details: _selectedTemplate ?? '不使用模板');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('模板选择已保存'),
            backgroundColor: AnimeColors.purple,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      logService.error('保存模板选择失败', details: e.toString());
    }
  }

  // 显示模板选择对话框
  void _showTemplateSelector() {
    showDialog(
      context: context,
      builder: (context) => _PromptTemplateManagerDialog(
        category: 'character',
        selectedTemplate: _selectedTemplate,
        accentColor: AnimeColors.purple,
        onSelect: (template) {
          setState(() {
            _selectedTemplate = template;
          });
          if (template != null) {
            _saveSelectedTemplate();
          }
        },
        onSave: () {
          _loadPromptTemplates();
        },
      ),
    );
  }

  Future<void> _generateCharacters() async {
    if (workspaceState.script.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在剧本生成中生成剧本'), backgroundColor: AnimeColors.sakura),
      );
      return;
    }
    if (!apiConfigManager.hasLlmConfig) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在设置中配置 LLM API'), backgroundColor: AnimeColors.sakura),
      );
      return;
    }

    setState(() => _isLoading = true);
    logService.action('开始生成角色');

    try {
      final apiService = apiConfigManager.createApiService();
      
      // 构建系统提示词
      String systemPrompt = '''你是一个专业的动漫角色设计师。请根据剧本内容分析并生成角色列表。
请以JSON格式返回，格式如下：
[{"name": "角色名", "description": "角色描述", "appearance": "外貌特征", "personality": "性格特点"}]
只返回JSON数组，不要其他内容。''';
      
      // 如果选择了模板，在系统提示词后加上模板内容
      if (_selectedTemplate != null && _promptTemplates.containsKey(_selectedTemplate)) {
        final templateContent = _promptTemplates[_selectedTemplate]!;
        if (templateContent.isNotEmpty) {
          systemPrompt = '$systemPrompt\n\n$templateContent';
        }
      }
      
      final response = await apiService.chatCompletion(
        model: apiConfigManager.llmModel,
        messages: [
          {
            'role': 'system',
            'content': systemPrompt
          },
          {
            'role': 'user',
            'content': '请根据以下剧本生成角色列表：\n\n${workspaceState.script}'
          },
        ],
        temperature: 0.7,
      );

      final content = response.choices.first.message.content;
      try {
        final List<dynamic> parsed = jsonDecode(content);
        workspaceState.clearCharacters();
        for (var char in parsed) {
          final charMap = Map<String, dynamic>.from(char);
          
          // 构建图片提示词（从角色描述信息中提取）
          final List<String> promptParts = [];
          if (charMap['description'] != null && charMap['description'].toString().isNotEmpty) {
            promptParts.add(charMap['description'].toString());
          }
          if (charMap['appearance'] != null && charMap['appearance'].toString().isNotEmpty) {
            promptParts.add(charMap['appearance'].toString());
          }
          if (charMap['personality'] != null && charMap['personality'].toString().isNotEmpty) {
            promptParts.add(charMap['personality'].toString());
          }
          
          // 将组合的提示词放入 imagePrompt
          charMap['imagePrompt'] = promptParts.join(', ');
          
          // 确保每个角色都有imageUrl和characterCode字段
          if (!charMap.containsKey('imageUrl')) {
            charMap['imageUrl'] = null;
          }
          if (!charMap.containsKey('characterCode')) {
            charMap['characterCode'] = null; // 存储 @串码
          }
          
          workspaceState.addCharacter(charMap);
        }
        setState(() {
          _characters = workspaceState.characters;
          _initializeControllers();
        });
        logService.info('角色生成成功', details: '生成了${_characters.length}个角色');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功生成${_characters.length}个角色!'), backgroundColor: AnimeColors.miku),
        );
      } catch (e) {
        // 如果JSON解析失败，尝试简单处理
        logService.warn('角色JSON解析失败，使用文本模式');
      }
    } catch (e) {
      logService.error('角色生成失败', details: e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成失败: $e'), backgroundColor: AnimeColors.sakura),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 使用 AnimatedBuilder 来监听 workspaceState 的变化，实时更新按钮状态
    return AnimatedBuilder(
      animation: workspaceState,
      builder: (context, _) {
        // 检查剧本生成结果是否有内容（去除空白字符后）
        final hasScript = workspaceState.script.isNotEmpty && workspaceState.script.trim().isNotEmpty;
        return _buildContent(hasScript);
      },
    );
  }

  Widget _buildContent(bool hasScript) {
    return Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline, color: AnimeColors.sakura, size: 28),
              SizedBox(width: 12),
              Text('角色生成', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
              Spacer(),
              // 提示词模板选择按钮
              TextButton.icon(
                onPressed: _showTemplateSelector,
                icon: Icon(
                  Icons.text_snippet,
                  size: 16,
                  color: _selectedTemplate != null ? AnimeColors.purple : Colors.white54,
                ),
                label: Text(
                  _selectedTemplate != null ? _selectedTemplate! : '提示词模板',
                  style: TextStyle(
                    color: _selectedTemplate != null ? AnimeColors.purple : Colors.white54,
                    fontSize: 12,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              SizedBox(width: 8),
              // 保存按钮
              if (_selectedTemplate != null)
                IconButton(
                  icon: Icon(Icons.save, size: 18, color: AnimeColors.purple),
                  tooltip: '保存模板选择',
                  onPressed: () {
                    _saveSelectedTemplate();
                  },
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              SizedBox(width: 8),
              // 参考风格按钮
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _showReferenceStylePanel = !_showReferenceStylePanel;
                  });
                },
                icon: Icon(
                  Icons.palette_outlined,
                  size: 16,
                  color: _referenceStyleImagePath != null ? AnimeColors.miku : Colors.white54,
                ),
                label: Text(
                  '参考风格',
                  style: TextStyle(
                    color: _referenceStyleImagePath != null ? AnimeColors.miku : Colors.white54,
                    fontSize: 12,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (!hasScript)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AnimeColors.orangeAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: AnimeColors.orangeAccent, size: 16),
                      SizedBox(width: 6),
                      Text('请先生成剧本', style: TextStyle(color: AnimeColors.orangeAccent, fontSize: 12)),
                    ],
                  ),
                ),
              SizedBox(width: 16),
              // 使用 Stack 来覆盖按钮，实现灰色状态下的点击提示
              Stack(
                children: [
                  ElevatedButton.icon(
                    onPressed: (_isLoading || !hasScript) ? null : () {
                      _generateCharacters();
                    },
                    icon: _isLoading 
                        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(Icons.auto_awesome, size: 18),
                    label: Text(_isLoading ? '生成中...' : '根据剧本生成'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasScript ? AnimeColors.sakura : Colors.grey,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                  // 如果没有剧本，添加一个透明覆盖层来捕获点击
                  if (!hasScript)
                    Positioned.fill(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _showNoScriptToast,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          // 参考风格面板
          if (_showReferenceStylePanel) ...[
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[850]?.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.palette, color: AnimeColors.miku, size: 18),
                      SizedBox(width: 8),
                      Text(
                        '参考风格',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Spacer(),
                      IconButton(
                        icon: Icon(Icons.close, size: 18, color: Colors.white54),
                        onPressed: () {
                          setState(() {
                            _showReferenceStylePanel = false;
                          });
                        },
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 图片上传区域
                      GestureDetector(
                        onTap: _pickReferenceStyleImage,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.grey[800]?.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _referenceStyleImagePath != null
                                  ? AnimeColors.miku.withOpacity(0.5)
                                  : Colors.white.withOpacity(0.1),
                              width: 2,
                            ),
                          ),
                          child: _referenceStyleImagePath != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(_referenceStyleImagePath!),
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Center(
                                        child: Icon(Icons.broken_image, color: Colors.white38, size: 32),
                                      );
                                    },
                                  ),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_photo_alternate, color: Colors.white38, size: 32),
                                    SizedBox(height: 8),
                                    Text(
                                      '上传图片',
                                      style: TextStyle(color: Colors.white38, fontSize: 11),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      SizedBox(width: 16),
                      // 提示词输入框
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '参考风格提示词',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 6),
                            Container(
                              height: 80,
                              decoration: BoxDecoration(
                                color: Colors.grey[800]?.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white.withOpacity(0.1)),
                              ),
                              child: TextField(
                                controller: _referenceStylePromptController,
                                enabled: true,
                                readOnly: false,
                                enableInteractiveSelection: true,
                                maxLines: null,
                                minLines: 1,
                                textAlignVertical: TextAlignVertical.top,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                                decoration: InputDecoration(
                                  hintText: '参考图片风格，',
                                  hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.all(12),
                                ),
                                onChanged: (value) {
                                  // 实时保存提示词
                                  _saveReferenceStyle();
                                },
                              ),
                            ),
                            SizedBox(height: 8),
                            if (_referenceStyleImagePath != null)
                              Row(
                                children: [
                                  Icon(Icons.check_circle, color: AnimeColors.miku, size: 16),
                                  SizedBox(width: 6),
                                  Text(
                                    '已设置参考风格，生成图片时将使用此风格',
                                    style: TextStyle(color: AnimeColors.miku, fontSize: 11),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 20),
          Expanded(
            child: _characters.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 80, color: Colors.white24),
                        SizedBox(height: 20),
                        Text(hasScript ? '点击"根据剧本生成"来创建角色' : '请先在剧本生成中生成剧本',
                            style: TextStyle(color: Colors.white38, fontSize: 14)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _characters.length,
                    itemBuilder: (context, index) => _buildCharacterCard(_characters[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCharacterCard(Map<String, dynamic> char) {
    final index = _characters.indexOf(char);
    final imagePromptController = _getImagePromptController(index);
    final isGenerating = _generatingImages[index] ?? false;
    final imageUrl = char['imageUrl'] as String?;
    final isCreating = _creatingCharacters[index] ?? false;
    final characterName = char['name'] ?? '未命名';
    // 获取角色分类标签（如果有）
    final categoryTag = char['category'] as String? ?? char['tag'] as String?;

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey[850]?.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部：角色名称、分类标签、按钮
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
              ),
            ),
            child: Row(
              children: [
                // 角色名称（蓝色）
                Text(
                  characterName,
                  style: TextStyle(
                    color: AnimeColors.blue,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                SizedBox(width: 12),
                // 分类标签（灰色按钮样式）
                if (categoryTag != null && categoryTag.isNotEmpty)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[700]?.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      categoryTag,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                Spacer(),
                // "默认"按钮
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: Colors.grey[700]?.withOpacity(0.3),
                  ),
                  child: Text(
                    '默认',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                // "详情"按钮
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    '详情',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                // 删除按钮
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.white54, size: 18),
                  tooltip: '删除角色',
                  onPressed: () => _showDeleteCharacterDialog(index),
                  padding: EdgeInsets.all(4),
                  constraints: BoxConstraints(),
                ),
              ],
            ),
          ),
          // 主体：左右布局
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左侧：提示词输入框（占据约2/3宽度）
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 200, // 固定高度，可滚动
                        decoration: BoxDecoration(
                          color: Colors.grey[800]?.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: TextField(
                          controller: imagePromptController,
                          enabled: true,
                          readOnly: false,
                          enableInteractiveSelection: true,
                          maxLines: null,
                          minLines: 1,
                          textAlignVertical: TextAlignVertical.top,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.5,
                          ),
                          decoration: InputDecoration(
                            hintText: '输入图片生成提示词...',
                            hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(12),
                          ),
                          onChanged: (value) {
                            // 实时保存提示词
                            char['imagePrompt'] = value;
                            workspaceState.updateCharacter(index, char);
                          },
                        ),
                      ),
                      SizedBox(height: 12),
                      // 图片生成按钮
                      SizedBox(
                        width: double.infinity,
                        height: 36,
                        child: ElevatedButton(
                          onPressed: isGenerating ? null : () => _generateCharacterImage(index),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: EdgeInsets.zero,
                          ),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: isGenerating
                                  ? null
                                  : LinearGradient(
                                      colors: [AnimeColors.sakura, AnimeColors.sakura.withOpacity(0.7)],
                                    ),
                              color: isGenerating ? Colors.grey.withOpacity(0.3) : null,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Container(
                              alignment: Alignment.center,
                              child: isGenerating
                                  ? Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          '生成中...',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.image, size: 16, color: Colors.white),
                                        SizedBox(width: 6),
                                        Text(
                                          '生成图片',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                // 右侧：角色图片框（占据约1/3宽度）
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 图片预览区域（支持多张图片堆叠显示）
                      GestureDetector(
                        onSecondaryTapDown: imageUrl != null && imageUrl.isNotEmpty
                            ? (details) {
                                _showImageContextMenu(context, details.globalPosition, index);
                              }
                            : null,
                        child: Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: Colors.grey[800]?.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: imageUrl != null && imageUrl.isNotEmpty
                                ? Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      // 主图片
                                      buildImageWidget(
                                        imageUrl: imageUrl,
                                        width: double.infinity,
                                        height: double.infinity,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            width: double.infinity,
                                            height: double.infinity,
                                            color: Colors.grey.withOpacity(0.2),
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.broken_image, color: Colors.white38, size: 32),
                                                SizedBox(height: 8),
                                                Text(
                                                  '加载失败',
                                                  style: TextStyle(color: Colors.white38, fontSize: 11),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return Container(
                                            width: double.infinity,
                                            height: double.infinity,
                                            color: Colors.grey.withOpacity(0.2),
                                            child: Center(
                                              child: CircularProgressIndicator(
                                                value: loadingProgress.expectedTotalBytes != null
                                                    ? loadingProgress.cumulativeBytesLoaded /
                                                        loadingProgress.expectedTotalBytes!
                                                    : null,
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      // 红色标签（左上角显示角色名称）
                                      Positioned(
                                        top: 4,
                                        left: 4,
                                        child: Container(
                                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withOpacity(0.8),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            characterName,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : Container(
                                    width: double.infinity,
                                    height: double.infinity,
                                    color: Colors.grey.withOpacity(0.1),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.image_outlined, color: Colors.white24, size: 40),
                                        SizedBox(height: 8),
                                        Text(
                                          '暂无图片',
                                          style: TextStyle(color: Colors.white38, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      SizedBox(height: 12),
                      // 显示 @串码（如果已创建角色）- 在图片下方
                      if (char['characterCode'] != null && char['characterCode'].toString().isNotEmpty) ...[
                        GestureDetector(
                          onTap: () {
                            // 点击复制串码
                            final code = '@${char['characterCode']}';
                            Clipboard.setData(ClipboardData(text: code));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('已复制: $code'),
                                duration: Duration(seconds: 2),
                                backgroundColor: AnimeColors.miku,
                              ),
                            );
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AnimeColors.miku.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AnimeColors.miku.withOpacity(0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.tag, size: 12, color: AnimeColors.miku),
                                SizedBox(width: 4),
                                Text(
                                  '@${char['characterCode']}',
                                  style: TextStyle(
                                    color: AnimeColors.miku,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(Icons.copy, size: 10, color: AnimeColors.miku.withOpacity(0.7)),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 8),
                      ],
                      // 创建角色按钮（仅在图片存在时显示）
                      if (imageUrl != null && imageUrl.isNotEmpty) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 32,
                          child: ElevatedButton(
                            onPressed: isCreating
                                ? null
                                : () {
                                    // 防止快速重复点击
                                    if (isCreating) return;
                                    _createCharacter(index);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: EdgeInsets.zero,
                            ),
                            child: Ink(
                              decoration: BoxDecoration(
                                gradient: isCreating
                                    ? null
                                    : LinearGradient(colors: [AnimeColors.blue, AnimeColors.miku]),
                                color: isCreating ? Colors.grey.withOpacity(0.3) : null,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Container(
                                alignment: Alignment.center,
                                child: isCreating
                                    ? Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            '创建中...',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.person_add, size: 14, color: Colors.white),
                                          SizedBox(width: 6),
                                          Text(
                                            '创建角色',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 显示图片右键菜单
  void _showImageContextMenu(BuildContext context, Offset position, int index) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        MediaQuery.of(context).size.width - position.dx,
        MediaQuery.of(context).size.height - position.dy,
      ),
      items: [
        PopupMenuItem(
          child: Row(
            children: [
              Icon(Icons.upload_file, color: AnimeColors.sakura, size: 18),
              SizedBox(width: 8),
              Text('上传角色图片', style: TextStyle(color: Colors.white70)),
            ],
          ),
          onTap: () async {
            // 延迟执行，等待菜单关闭
            await Future.delayed(Duration(milliseconds: 100));
            _uploadCharacterImage(index);
          },
        ),
      ],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: AnimeColors.cardBg,
    );
  }

  // 上传角色图片
  Future<void> _uploadCharacterImage(int index) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (pickedFile == null) {
        return; // 用户取消选择
      }

      final imageFile = File(pickedFile.path);
      
      // 将图片路径保存到角色数据中
      if (index < _characters.length) {
        final char = _characters[index];
        setState(() {
          // 将本地文件路径保存到 imageUrl
          char['imageUrl'] = imageFile.path;
          workspaceState.updateCharacter(index, char);
        });
        
        logService.info('角色图片已上传', details: '角色: ${char['name']}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('角色图片已上传'),
              backgroundColor: AnimeColors.miku,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      logService.error('上传角色图片失败', details: e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('上传图片失败: $e'),
            backgroundColor: AnimeColors.sakura,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 显示"请先生成剧本"提示弹窗（渐隐效果）
  void _showNoScriptToast() {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: false,
      builder: (dialogContext) {
        // 使用独立的 StatefulWidget 来控制渐隐动画
        return _NoScriptToastWidget();
      },
    );
  }

  // 上传参考风格图片
  Future<void> _pickReferenceStyleImage() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (pickedFile != null) {
        setState(() {
          _referenceStyleImagePath = pickedFile.path;
        });
        await _saveReferenceStyle(); // 保存设置
        logService.action('上传参考风格图片', details: pickedFile.path);
      }
    } catch (e) {
      logService.error('上传参考风格图片失败', details: e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('上传图片失败: $e'),
            backgroundColor: AnimeColors.sakura,
          ),
        );
      }
    }
  }

  Future<void> _generateCharacterImage(int index) async {
    if (index >= _characters.length) return;
    
    final char = _characters[index];
    final imagePrompt = _getImagePromptController(index).text.trim();
    
    if (imagePrompt.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请输入图片提示词'), backgroundColor: AnimeColors.sakura),
      );
      return;
    }

    if (!apiConfigManager.hasImageConfig) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在设置中配置图片生成 API'), backgroundColor: AnimeColors.sakura),
      );
      return;
    }

    setState(() {
      _generatingImages[index] = true;
    });

    try {
      final apiService = apiConfigManager.createApiService();
      
      // 合并提示词：参考风格提示词 + 角色卡片提示词
      String finalPrompt = imagePrompt;
      if (_referenceStyleImagePath != null && _referenceStyleImagePath!.isNotEmpty) {
        final referencePrompt = _referenceStylePromptController.text.trim();
        if (referencePrompt.isNotEmpty) {
          // 合并提示词：参考风格提示词在前，角色提示词在后
          finalPrompt = '$referencePrompt $imagePrompt';
        }
      }
      
      // 准备参考图片列表（如果有）
      List<String>? referenceImages;
      if (_referenceStyleImagePath != null && _referenceStyleImagePath!.isNotEmpty) {
        referenceImages = [_referenceStyleImagePath!];
      }
      
      // 异步调用图片生成API，不阻塞UI
      final response = await apiService.generateImage(
        prompt: finalPrompt,
        model: apiConfigManager.imageModel,
        width: 1024,
        height: 1024,
        quality: 'standard',
        referenceImages: referenceImages, // 传入参考图片
      );

      if (mounted) {
        setState(() {
          char['imageUrl'] = response.imageUrl;
          _generatingImages[index] = false;
          // 更新workspaceState
          workspaceState.updateCharacter(index, char);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片生成成功！'), backgroundColor: AnimeColors.miku),
        );
      }
    } catch (e) {
      logService.error('角色图片生成失败', details: e.toString());
      if (mounted) {
        setState(() {
          _generatingImages[index] = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片生成失败: $e'), backgroundColor: AnimeColors.sakura),
        );
      }
    }
  }

  // 显示删除角色确认对话框
  void _showDeleteCharacterDialog(int index) {
    if (index >= _characters.length) return;
    final char = _characters[index];
    final charName = char['name'] ?? '未命名';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AnimeColors.cardBg,
        title: Text(
          '确认删除',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        content: Text(
          '是否确认删除角色"$charName"？',
          style: TextStyle(color: Colors.white70),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteCharacter(index);
            },
            child: Text(
              '确认删除',
              style: TextStyle(color: AnimeColors.sakura, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // 删除角色
  void _deleteCharacter(int index) {
    if (index >= _characters.length) return;
    
    setState(() {
      _characters.removeAt(index);
      workspaceState.removeCharacter(index);
      // 清理对应的控制器
      if (_imagePromptControllers.containsKey(index)) {
        _imagePromptControllers[index]?.dispose();
        _imagePromptControllers.remove(index);
      }
      _generatingImages.remove(index);
      _creatingCharacters.remove(index);
      // 重新初始化控制器（因为索引改变了）
      _initializeControllers();
    });
    
    logService.action('删除角色', details: '索引: $index');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('角色已删除'),
        backgroundColor: AnimeColors.miku,
        duration: Duration(seconds: 2),
      ),
    );
  }

  // 创建角色（上传到 Sora API）
  Future<void> _createCharacter(int index) async {
    if (index >= _characters.length) return;
    
    // 防止重复调用 - 在方法开始就检查
    final isCurrentlyCreating = _creatingCharacters[index] ?? false;
    if (isCurrentlyCreating) {
      return;
    }
    
    // 立即设置加载状态，防止重复点击（在检查之后立即设置）
    if (mounted) {
      setState(() {
        _creatingCharacters[index] = true;
      });
    }
    
    final char = _characters[index];
    final imageUrl = char['imageUrl'] as String?;
    
    if (imageUrl == null || imageUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _creatingCharacters[index] = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('请先生成角色图片'),
            backgroundColor: AnimeColors.sakura,
          ),
        );
      }
      return;
    }

    // 检查是否已经创建过角色
    if (char['characterCode'] != null && char['characterCode'].toString().isNotEmpty) {
      if (mounted) {
        setState(() {
          _creatingCharacters[index] = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('该角色已创建，角色代码: @${char['characterCode']}'),
            backgroundColor: AnimeColors.miku,
          ),
        );
      }
      return;
    }

    if (!apiConfigManager.hasVideoConfig) {
      if (mounted) {
        setState(() {
          _creatingCharacters[index] = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('请先在设置中配置视频生成 API'),
            backgroundColor: AnimeColors.sakura,
          ),
        );
      }
      return;
    }

    try {
      logService.action('开始创建角色', details: '角色: ${char['name']}');
      
      final apiService = apiConfigManager.createApiService();
      
      // 将图片 URL 转换为 File 对象
      File imageFile;
      if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
        // 如果是网络 URL，需要先下载
        throw Exception('暂不支持网络图片，请使用本地生成的图片');
      } else if (imageUrl.startsWith('data:image/')) {
        // 如果是 base64 图片，需要先解码并保存为临时文件
        try {
          // 提取 base64 数据
          final base64Index = imageUrl.indexOf('base64,');
          if (base64Index == -1) {
            throw Exception('无效的 base64 图片格式');
          }
          
          final base64Data = imageUrl.substring(base64Index + 7);
          final imageBytes = base64Decode(base64Data);
          
          // 获取 MIME 类型
          final mimeMatch = RegExp(r'data:image/([^;]+)').firstMatch(imageUrl);
          final imageType = mimeMatch?.group(1) ?? 'png';
          final fileExtension = imageType == 'jpeg' || imageType == 'jpg' ? 'jpg' : 'png';
          
          // 保存为临时文件
          final tempDir = await getTemporaryDirectory();
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final tempImagePath = '${tempDir.path}/character_image_${timestamp}.$fileExtension';
          imageFile = File(tempImagePath);
          await imageFile.writeAsBytes(imageBytes);
          
          print('[CharacterGenerationPanel] Base64 图片已保存到临时文件: $tempImagePath');
        } catch (e) {
          throw Exception('处理 base64 图片失败: $e');
        }
      } else {
        // 本地文件路径
        imageFile = File(imageUrl);
        if (!await imageFile.exists()) {
          throw Exception('图片文件不存在: $imageUrl');
        }
      }
      
      // 调用上传角色 API
      final response = await apiService.uploadCharacter(
        imagePath: imageFile.path,
        name: char['name'] ?? '未命名',
      );
      
      // 保存角色代码
      // 清理 characterCode：去掉 @ 和 # 符号，只保留纯串码
      String cleanCode = response.characterName;
      if (cleanCode.startsWith('@')) {
        cleanCode = cleanCode.substring(1);
      }
      if (cleanCode.startsWith('#')) {
        cleanCode = cleanCode.substring(1);
      }
      // 去掉所有非字母数字字符（只保留串码本身）
      cleanCode = cleanCode.trim();
      
      setState(() {
        char['characterCode'] = cleanCode; // 保存清理后的纯串码
        workspaceState.updateCharacter(index, char);
        _creatingCharacters[index] = false;
      });
      
      logService.info('角色创建成功', details: '角色代码: @${response.characterName}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('角色创建成功！角色代码: @${response.characterName}'),
          backgroundColor: AnimeColors.miku,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      logService.error('创建角色失败', details: e.toString());
      setState(() {
        _creatingCharacters[index] = false;
      });
      
      // 提取错误信息（如果是 ApiException，使用其 message）
      String errorMessage = e.toString();
      if (e is ApiException) {
        errorMessage = e.message;
      } else if (e is Exception) {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      }
      
      // 如果错误信息太长，截取前100个字符
      if (errorMessage.length > 100) {
        errorMessage = errorMessage.substring(0, 100) + '...';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('创建角色失败: $errorMessage'),
          backgroundColor: AnimeColors.sakura,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }
}

// "请先生成剧本"提示弹窗组件（带渐隐动画）
class _NoScriptToastWidget extends StatefulWidget {
  @override
  State<_NoScriptToastWidget> createState() => _NoScriptToastWidgetState();
}

class _NoScriptToastWidgetState extends State<_NoScriptToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    );
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    // 2秒后开始渐隐
    Future.delayed(Duration(seconds: 2), () {
      if (mounted) {
        _controller.forward().then((_) {
          if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: AnimeColors.cardBg.withOpacity(0.95),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AnimeColors.orangeAccent.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline,
                  color: AnimeColors.orangeAccent,
                  size: 20,
                ),
                SizedBox(width: 12),
                Text(
                  '请先生成剧本',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 场景生成面板
class SceneGenerationPanel extends StatefulWidget {
  const SceneGenerationPanel({super.key});

  @override
  State<SceneGenerationPanel> createState() => _SceneGenerationPanelState();
}

class _SceneGenerationPanelState extends State<SceneGenerationPanel> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _scenes = [];
  String? _selectedTemplate; // 选中的提示词模板名称
  Map<String, String> _promptTemplates = {}; // 场景提示词模板列表
  // 为每个场景的图片提示词缓存TextEditingController
  final Map<int, TextEditingController> _imagePromptControllers = {};
  // 记录每个场景是否正在生成图片
  final Map<int, bool> _generatingImages = {};

  @override
  void initState() {
    super.initState();
    _scenes = workspaceState.scenes;
    _loadPromptTemplates();
    _loadSelectedTemplate();
    _initializeControllers();
  }

  @override
  void dispose() {
    // 清理所有Controller
    for (var controller in _imagePromptControllers.values) {
      controller.dispose();
    }
    _imagePromptControllers.clear();
    super.dispose();
  }

  // 初始化Controller
  void _initializeControllers() {
    for (int i = 0; i < _scenes.length; i++) {
      if (!_imagePromptControllers.containsKey(i)) {
        final scene = _scenes[i];
        final controller = TextEditingController(
          text: scene['imagePrompt'] as String? ?? '',
        );
        _imagePromptControllers[i] = controller;
      }
    }
  }

  // 获取或创建图片提示词Controller
  TextEditingController _getImagePromptController(int index) {
    if (!_imagePromptControllers.containsKey(index)) {
      final scene = _scenes[index];
      final controller = TextEditingController(
        text: scene['imagePrompt'] as String? ?? '',
      );
      _imagePromptControllers[index] = controller;
    }
    return _imagePromptControllers[index]!;
  }

  // 加载提示词模板
  Future<void> _loadPromptTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final promptsJson = prefs.getString('prompts');
      if (promptsJson != null) {
        final decoded = jsonDecode(promptsJson) as Map<String, dynamic>;
        setState(() {
          _promptTemplates = Map<String, String>.from(decoded['scene'] ?? {});
        });
      }
    } catch (e) {
      logService.error('加载提示词模板失败', details: e.toString());
    }
  }

  // 加载保存的模板选择
  Future<void> _loadSelectedTemplate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTemplate = prefs.getString('scene_selected_template');
      if (savedTemplate != null && savedTemplate.isNotEmpty) {
        setState(() {
          _selectedTemplate = savedTemplate;
        });
      }
    } catch (e) {
      logService.error('加载保存的模板选择失败', details: e.toString());
    }
  }

  // 保存模板选择
  Future<void> _saveSelectedTemplate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_selectedTemplate != null) {
        await prefs.setString('scene_selected_template', _selectedTemplate!);
      } else {
        await prefs.remove('scene_selected_template');
      }
      logService.info('保存模板选择', details: _selectedTemplate ?? '不使用模板');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('模板选择已保存'),
            backgroundColor: AnimeColors.miku,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      logService.error('保存模板选择失败', details: e.toString());
    }
  }

  // 显示模板选择对话框
  void _showTemplateSelector() {
    showDialog(
      context: context,
      builder: (context) => _PromptTemplateManagerDialog(
        category: 'scene',
        selectedTemplate: _selectedTemplate,
        accentColor: AnimeColors.miku,
        onSelect: (template) {
          setState(() {
            _selectedTemplate = template;
          });
          if (template != null) {
            _saveSelectedTemplate();
          }
        },
        onSave: () {
          _loadPromptTemplates();
        },
      ),
    );
  }

  Future<void> _generateScenes() async {
    if (workspaceState.script.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在剧本生成中生成剧本'), backgroundColor: AnimeColors.sakura),
      );
      return;
    }
    if (!apiConfigManager.hasLlmConfig) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在设置中配置 LLM API'), backgroundColor: AnimeColors.sakura),
      );
      return;
    }

    setState(() => _isLoading = true);
    logService.action('开始生成场景');

    try {
      final apiService = apiConfigManager.createApiService();
      
      // 构建系统提示词
      String systemPrompt = '''你是一个专业的动漫场景设计师。请根据剧本内容分析并生成场景列表。
请以JSON格式返回，格式如下：
[{"name": "场景名", "description": "场景描述", "atmosphere": "氛围", "time": "时间"}]
只返回JSON数组，不要其他内容。''';
      
      // 如果选择了模板，在系统提示词后加上模板内容
      if (_selectedTemplate != null && _promptTemplates.containsKey(_selectedTemplate)) {
        final templateContent = _promptTemplates[_selectedTemplate]!;
        if (templateContent.isNotEmpty) {
          systemPrompt = '$systemPrompt\n\n$templateContent';
        }
      }
      
      final response = await apiService.chatCompletion(
        model: apiConfigManager.llmModel,
        messages: [
          {
            'role': 'system',
            'content': systemPrompt
          },
          {
            'role': 'user',
            'content': '请根据以下剧本生成场景列表：\n\n${workspaceState.script}'
          },
        ],
        temperature: 0.7,
      );

      final content = response.choices.first.message.content;
      try {
        final List<dynamic> parsed = jsonDecode(content);
        workspaceState.clearScenes();
        for (var scene in parsed) {
          final sceneMap = Map<String, dynamic>.from(scene);
          // 确保每个场景都有imagePrompt和imageUrl字段
          if (!sceneMap.containsKey('imagePrompt')) {
            sceneMap['imagePrompt'] = '';
          }
          if (!sceneMap.containsKey('imageUrl')) {
            sceneMap['imageUrl'] = null;
          }
          workspaceState.addScene(sceneMap);
        }
        setState(() {
          _scenes = workspaceState.scenes;
          _initializeControllers();
        });
        logService.info('场景生成成功', details: '生成了${_scenes.length}个场景');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功生成${_scenes.length}个场景!'), backgroundColor: AnimeColors.miku),
        );
      } catch (e) {
        logService.warn('场景JSON解析失败');
      }
    } catch (e) {
      logService.error('场景生成失败', details: e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成失败: $e'), backgroundColor: AnimeColors.sakura),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasScript = workspaceState.script.isNotEmpty;

    return Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.landscape_outlined, color: AnimeColors.blue, size: 28),
              SizedBox(width: 12),
              Text('场景生成', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
              Spacer(),
              // 提示词模板选择按钮
              TextButton.icon(
                onPressed: _showTemplateSelector,
                icon: Icon(
                  Icons.text_snippet,
                  size: 16,
                  color: _selectedTemplate != null ? AnimeColors.miku : Colors.white54,
                ),
                label: Text(
                  _selectedTemplate != null ? _selectedTemplate! : '提示词模板',
                  style: TextStyle(
                    color: _selectedTemplate != null ? AnimeColors.miku : Colors.white54,
                    fontSize: 12,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              SizedBox(width: 8),
              // 保存按钮
              if (_selectedTemplate != null)
                IconButton(
                  icon: Icon(Icons.save, size: 18, color: AnimeColors.miku),
                  tooltip: '保存模板选择',
                  onPressed: () {
                    _saveSelectedTemplate();
                  },
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              if (!hasScript)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AnimeColors.orangeAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: AnimeColors.orangeAccent, size: 16),
                      SizedBox(width: 6),
                      Text('请先生成剧本', style: TextStyle(color: AnimeColors.orangeAccent, fontSize: 12)),
                    ],
                  ),
                ),
              SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _isLoading || !hasScript ? null : _generateScenes,
                icon: _isLoading 
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(Icons.auto_awesome, size: 18),
                label: Text(_isLoading ? '生成中...' : '根据剧本生成'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AnimeColors.blue,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          Expanded(
            child: _scenes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.terrain_outlined, size: 80, color: Colors.white24),
                        SizedBox(height: 20),
                        Text(hasScript ? '点击"根据剧本生成"来创建场景' : '请先在剧本生成中生成剧本',
                            style: TextStyle(color: Colors.white38, fontSize: 14)),
                      ],
                    ),
                  )
                : GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.2,
                    ),
                    itemCount: _scenes.length,
                    itemBuilder: (context, index) => _buildSceneCard(_scenes[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSceneCard(Map<String, dynamic> scene) {
    final index = _scenes.indexOf(scene);
    final imagePromptController = _getImagePromptController(index);
    final isGenerating = _generatingImages[index] ?? false;
    final imageUrl = scene['imageUrl'] as String?;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [AnimeColors.blue.withOpacity(0.15), AnimeColors.purple.withOpacity(0.1)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AnimeColors.blue.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.landscape, color: AnimeColors.blue, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(scene['name'] ?? '未命名场景', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              SizedBox(height: 10),
              // 场景信息
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(scene['description'] ?? '', style: TextStyle(color: Colors.white70, fontSize: 12), maxLines: 3, overflow: TextOverflow.ellipsis),
                      if (scene['time'] != null) ...[
                        SizedBox(height: 8),
                        Text('时间: ${scene['time']}', style: TextStyle(color: AnimeColors.blue, fontSize: 11)),
                      ],
                      SizedBox(height: 12),
                      // 图片提示词输入框
                      Text('图片提示词', style: TextStyle(color: AnimeColors.blue, fontSize: 11, fontWeight: FontWeight.w600)),
                      SizedBox(height: 6),
                      Container(
                        height: 80,
                        decoration: BoxDecoration(
                          color: AnimeColors.cardBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: TextField(
                          controller: imagePromptController,
                          enabled: true,
                          readOnly: false,
                          enableInteractiveSelection: true,
                          maxLines: null,
                          minLines: 2,
                          textAlignVertical: TextAlignVertical.top,
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                          decoration: InputDecoration(
                            hintText: '输入图片生成提示词...',
                            hintStyle: TextStyle(color: Colors.white38, fontSize: 11),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(8),
                          ),
                          onChanged: (value) {
                            // 实时保存提示词
                            scene['imagePrompt'] = value;
                            workspaceState.updateScene(index, scene);
                          },
                        ),
                      ),
                      SizedBox(height: 8),
                      // 图片生成按钮
                      SizedBox(
                        width: double.infinity,
                        height: 36,
                        child: ElevatedButton(
                          onPressed: isGenerating ? null : () => _generateSceneImage(index),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: EdgeInsets.zero,
                          ),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: isGenerating
                                  ? null
                                  : LinearGradient(colors: [AnimeColors.blue, AnimeColors.blue.withOpacity(0.7)]),
                              color: isGenerating ? Colors.grey : null,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Container(
                              alignment: Alignment.center,
                              child: isGenerating
                                  ? Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        ),
                                        SizedBox(width: 8),
                                        Text('生成中...', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                      ],
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.image, size: 16, color: Colors.white),
                                        SizedBox(width: 6),
                                        Text('图片生成', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                      // 生成的图片预览
                      if (imageUrl != null && imageUrl.isNotEmpty) ...[
                        SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: buildImageWidget(
                            imageUrl: imageUrl,
                            width: double.infinity,
                            height: 120,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: double.infinity,
                                height: 120,
                                color: Colors.grey.withOpacity(0.2),
                                child: Icon(Icons.broken_image, color: Colors.white38),
                              );
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                width: double.infinity,
                                height: 120,
                                color: Colors.grey.withOpacity(0.2),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                        : null,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 生成场景图片
  Future<void> _generateSceneImage(int index) async {
    if (index >= _scenes.length) return;
    
    final scene = _scenes[index];
    final imagePrompt = _getImagePromptController(index).text.trim();
    
    if (imagePrompt.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请输入图片提示词'), backgroundColor: AnimeColors.blue),
      );
      return;
    }

    if (!apiConfigManager.hasImageConfig) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在设置中配置图片生成 API'), backgroundColor: AnimeColors.sakura),
      );
      return;
    }

    setState(() {
      _generatingImages[index] = true;
    });

    try {
      final apiService = apiConfigManager.createApiService();
      
      // 异步调用图片生成API，不阻塞UI
      final response = await apiService.generateImage(
        prompt: imagePrompt,
        model: apiConfigManager.imageModel,
        width: 1024,
        height: 1024,
        quality: 'standard',
      );

      if (mounted) {
        setState(() {
          scene['imageUrl'] = response.imageUrl;
          _generatingImages[index] = false;
          // 更新workspaceState
          workspaceState.updateScene(index, scene);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片生成成功！'), backgroundColor: AnimeColors.miku),
        );
      }
    } catch (e) {
      logService.error('场景图片生成失败', details: e.toString());
      if (mounted) {
        setState(() {
          _generatingImages[index] = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片生成失败: $e'), backgroundColor: AnimeColors.sakura),
        );
      }
    }
  }
}

// 物品生成面板
class PropGenerationPanel extends StatefulWidget {
  const PropGenerationPanel({super.key});

  @override
  State<PropGenerationPanel> createState() => _PropGenerationPanelState();
}

class _PropGenerationPanelState extends State<PropGenerationPanel> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _props = [];
  String? _selectedTemplate; // 选中的提示词模板名称
  Map<String, String> _promptTemplates = {}; // 物品提示词模板列表
  // 为每个物品的图片提示词缓存TextEditingController
  final Map<int, TextEditingController> _imagePromptControllers = {};
  // 记录每个物品是否正在生成图片
  final Map<int, bool> _generatingImages = {};

  @override
  void initState() {
    super.initState();
    _props = workspaceState.props;
    _loadPromptTemplates();
    _loadSelectedTemplate();
    _initializeControllers();
  }

  @override
  void dispose() {
    // 清理所有Controller
    for (var controller in _imagePromptControllers.values) {
      controller.dispose();
    }
    _imagePromptControllers.clear();
    super.dispose();
  }

  // 初始化Controller
  void _initializeControllers() {
    for (int i = 0; i < _props.length; i++) {
      if (!_imagePromptControllers.containsKey(i)) {
        final prop = _props[i];
        final controller = TextEditingController(
          text: prop['imagePrompt'] as String? ?? '',
        );
        _imagePromptControllers[i] = controller;
      }
    }
  }

  // 获取或创建图片提示词Controller
  TextEditingController _getImagePromptController(int index) {
    if (!_imagePromptControllers.containsKey(index)) {
      final prop = _props[index];
      final controller = TextEditingController(
        text: prop['imagePrompt'] as String? ?? '',
      );
      _imagePromptControllers[index] = controller;
    }
    return _imagePromptControllers[index]!;
  }

  // 加载提示词模板
  Future<void> _loadPromptTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final promptsJson = prefs.getString('prompts');
      if (promptsJson != null) {
        final decoded = jsonDecode(promptsJson) as Map<String, dynamic>;
        setState(() {
          _promptTemplates = Map<String, String>.from(decoded['prop'] ?? {});
        });
      }
    } catch (e) {
      logService.error('加载提示词模板失败', details: e.toString());
    }
  }

  // 加载保存的模板选择
  Future<void> _loadSelectedTemplate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTemplate = prefs.getString('prop_selected_template');
      if (savedTemplate != null && savedTemplate.isNotEmpty) {
        setState(() {
          _selectedTemplate = savedTemplate;
        });
      }
    } catch (e) {
      logService.error('加载保存的模板选择失败', details: e.toString());
    }
  }

  // 保存模板选择
  Future<void> _saveSelectedTemplate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_selectedTemplate != null) {
        await prefs.setString('prop_selected_template', _selectedTemplate!);
      } else {
        await prefs.remove('prop_selected_template');
      }
      logService.info('保存模板选择', details: _selectedTemplate ?? '不使用模板');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('模板选择已保存'),
            backgroundColor: AnimeColors.orangeAccent,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      logService.error('保存模板选择失败', details: e.toString());
    }
  }


  // 显示模板选择对话框
  void _showTemplateSelector() {
    showDialog(
      context: context,
      builder: (context) => _PromptTemplateManagerDialog(
        category: 'prop',
        selectedTemplate: _selectedTemplate,
        accentColor: AnimeColors.orangeAccent,
        onSelect: (template) {
          setState(() {
            _selectedTemplate = template;
          });
          if (template != null) {
            _saveSelectedTemplate();
          }
        },
        onSave: () {
          _loadPromptTemplates();
        },
      ),
    );
  }

  Future<void> _generateProps() async {
    if (workspaceState.script.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在剧本生成中生成剧本'), backgroundColor: AnimeColors.sakura),
      );
      return;
    }
    if (!apiConfigManager.hasLlmConfig) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在设置中配置 LLM API'), backgroundColor: AnimeColors.sakura),
      );
      return;
    }

    setState(() => _isLoading = true);
    logService.action('开始生成物品');

    try {
      final apiService = apiConfigManager.createApiService();
      
      // 构建系统提示词
      String systemPrompt = '''你是一个专业的动漫道具设计师。请根据剧本内容分析并生成重要物品列表。
请以JSON格式返回，格式如下：
[{"name": "物品名", "description": "物品描述", "significance": "剧情意义"}]
只返回JSON数组，不要其他内容。''';
      
      // 如果选择了模板，在系统提示词后加上模板内容
      if (_selectedTemplate != null && _promptTemplates.containsKey(_selectedTemplate)) {
        final templateContent = _promptTemplates[_selectedTemplate]!;
        if (templateContent.isNotEmpty) {
          systemPrompt = '$systemPrompt\n\n$templateContent';
        }
      }
      
      final response = await apiService.chatCompletion(
        model: apiConfigManager.llmModel,
        messages: [
          {
            'role': 'system',
            'content': systemPrompt
          },
          {
            'role': 'user',
            'content': '请根据以下剧本生成重要物品列表：\n\n${workspaceState.script}'
          },
        ],
        temperature: 0.7,
      );

      final content = response.choices.first.message.content;
      try {
        final List<dynamic> parsed = jsonDecode(content);
        workspaceState.clearProps();
        for (var prop in parsed) {
          final propMap = Map<String, dynamic>.from(prop);
          // 确保每个物品都有imagePrompt和imageUrl字段
          if (!propMap.containsKey('imagePrompt')) {
            propMap['imagePrompt'] = '';
          }
          if (!propMap.containsKey('imageUrl')) {
            propMap['imageUrl'] = null;
          }
          workspaceState.addProp(propMap);
        }
        setState(() {
          _props = workspaceState.props;
          _initializeControllers();
        });
        logService.info('物品生成成功', details: '生成了${_props.length}个物品');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功生成${_props.length}个物品!'), backgroundColor: AnimeColors.miku),
        );
      } catch (e) {
        logService.warn('物品JSON解析失败');
      }
    } catch (e) {
      logService.error('物品生成失败', details: e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成失败: $e'), backgroundColor: AnimeColors.sakura),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasScript = workspaceState.script.isNotEmpty;

    return Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: AnimeColors.miku, size: 28),
              SizedBox(width: 12),
              Text('物品生成', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
              Spacer(),
              // 提示词模板选择按钮
              TextButton.icon(
                onPressed: _showTemplateSelector,
                icon: Icon(
                  Icons.text_snippet,
                  size: 16,
                  color: _selectedTemplate != null ? AnimeColors.orangeAccent : Colors.white54,
                ),
                label: Text(
                  _selectedTemplate != null ? _selectedTemplate! : '提示词模板',
                  style: TextStyle(
                    color: _selectedTemplate != null ? AnimeColors.orangeAccent : Colors.white54,
                    fontSize: 12,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              SizedBox(width: 8),
              // 保存按钮
              if (_selectedTemplate != null)
                IconButton(
                  icon: Icon(Icons.save, size: 18, color: AnimeColors.orangeAccent),
                  tooltip: '保存模板选择',
                  onPressed: () {
                    _saveSelectedTemplate();
                  },
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              if (!hasScript)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AnimeColors.orangeAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: AnimeColors.orangeAccent, size: 16),
                      SizedBox(width: 6),
                      Text('请先生成剧本', style: TextStyle(color: AnimeColors.orangeAccent, fontSize: 12)),
                    ],
                  ),
                ),
              SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _isLoading || !hasScript ? null : _generateProps,
                icon: _isLoading 
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(Icons.auto_awesome, size: 18),
                label: Text(_isLoading ? '生成中...' : '根据剧本生成'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AnimeColors.miku,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          Expanded(
            child: _props.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.category_outlined, size: 80, color: Colors.white24),
                        SizedBox(height: 20),
                        Text(hasScript ? '点击"根据剧本生成"来创建物品' : '请先在剧本生成中生成剧本',
                            style: TextStyle(color: Colors.white38, fontSize: 14)),
                      ],
                    ),
                  )
                : GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.1,
                    ),
                    itemCount: _props.length,
                    itemBuilder: (context, index) => _buildPropCard(_props[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPropCard(Map<String, dynamic> prop) {
    final index = _props.indexOf(prop);
    final imagePromptController = _getImagePromptController(index);
    final isGenerating = _generatingImages[index] ?? false;
    final imageUrl = prop['imageUrl'] as String?;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AnimeColors.glassBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AnimeColors.miku.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AnimeColors.miku.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.inventory_2, color: AnimeColors.miku, size: 18),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(prop['name'] ?? '未命名', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              SizedBox(height: 8),
              // 物品信息
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (prop['description'] != null) ...[
                        Text(prop['description'], style: TextStyle(color: Colors.white70, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                        SizedBox(height: 8),
                      ],
                      // 图片提示词输入框
                      Text('图片提示词', style: TextStyle(color: AnimeColors.miku, fontSize: 10, fontWeight: FontWeight.w600)),
                      SizedBox(height: 4),
                      Container(
                        height: 60,
                        decoration: BoxDecoration(
                          color: AnimeColors.cardBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: TextField(
                          controller: imagePromptController,
                          enabled: true,
                          readOnly: false,
                          enableInteractiveSelection: true,
                          maxLines: null,
                          minLines: 2,
                          textAlignVertical: TextAlignVertical.top,
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                          decoration: InputDecoration(
                            hintText: '输入提示词...',
                            hintStyle: TextStyle(color: Colors.white38, fontSize: 10),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(6),
                          ),
                          onChanged: (value) {
                            // 实时保存提示词
                            prop['imagePrompt'] = value;
                            workspaceState.updateProp(index, prop);
                          },
                        ),
                      ),
                      SizedBox(height: 6),
                      // 图片生成按钮
                      SizedBox(
                        width: double.infinity,
                        height: 32,
                        child: ElevatedButton(
                          onPressed: isGenerating ? null : () => _generatePropImage(index),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            padding: EdgeInsets.zero,
                          ),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: isGenerating
                                  ? null
                                  : LinearGradient(colors: [AnimeColors.miku, AnimeColors.miku.withOpacity(0.7)]),
                              color: isGenerating ? Colors.grey : null,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Container(
                              alignment: Alignment.center,
                              child: isGenerating
                                  ? Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        ),
                                        SizedBox(width: 6),
                                        Text('生成中...', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                                      ],
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.image, size: 14, color: Colors.white),
                                        SizedBox(width: 4),
                                        Text('图片生成', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                      // 生成的图片预览
                      if (imageUrl != null && imageUrl.isNotEmpty) ...[
                        SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: buildImageWidget(
                            imageUrl: imageUrl,
                            width: double.infinity,
                            height: 100,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: double.infinity,
                                height: 100,
                                color: Colors.grey.withOpacity(0.2),
                                child: Icon(Icons.broken_image, color: Colors.white38, size: 20),
                              );
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                width: double.infinity,
                                height: 100,
                                color: Colors.grey.withOpacity(0.2),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                        : null,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 生成物品图片
  Future<void> _generatePropImage(int index) async {
    if (index >= _props.length) return;
    
    final prop = _props[index];
    final imagePrompt = _getImagePromptController(index).text.trim();
    
    if (imagePrompt.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请输入图片提示词'), backgroundColor: AnimeColors.miku),
      );
      return;
    }

    if (!apiConfigManager.hasImageConfig) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在设置中配置图片生成 API'), backgroundColor: AnimeColors.sakura),
      );
      return;
    }

    setState(() {
      _generatingImages[index] = true;
    });

    try {
      final apiService = apiConfigManager.createApiService();
      
      // 异步调用图片生成API，不阻塞UI
      final response = await apiService.generateImage(
        prompt: imagePrompt,
        model: apiConfigManager.imageModel,
        width: 1024,
        height: 1024,
        quality: 'standard',
      );

      if (mounted) {
        setState(() {
          prop['imageUrl'] = response.imageUrl;
          _generatingImages[index] = false;
          // 更新workspaceState
          workspaceState.updateProp(index, prop);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片生成成功！'), backgroundColor: AnimeColors.miku),
        );
      }
    } catch (e) {
      logService.error('物品图片生成失败', details: e.toString());
      if (mounted) {
        setState(() {
          _generatingImages[index] = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片生成失败: $e'), backgroundColor: AnimeColors.sakura),
        );
      }
    }
  }
}

// 分镜生成面板（直接显示分镜卡片列表）
class StoryboardGenerationPanel extends StatefulWidget {
  const StoryboardGenerationPanel({super.key});

  @override
  State<StoryboardGenerationPanel> createState() => _StoryboardGenerationPanelState();
}

class _StoryboardGenerationPanelState extends State<StoryboardGenerationPanel> {
  List<Map<String, dynamic>> _storyboards = [];
  // 为每个分镜的图片和视频提示词缓存TextEditingController
  final Map<int, TextEditingController> _imagePromptControllers = {};
  final Map<int, TextEditingController> _videoPromptControllers = {};
  String? _selectedImageTemplate; // 选中的图片提示词模板名称
  String? _selectedVideoTemplate; // 选中的视频提示词模板名称
  Map<String, String> _promptTemplates = {}; // 图片提示词模板列表（分镜生成使用image类型）
  Map<String, String> _videoPromptTemplates = {}; // 视频提示词模板列表

  @override
  void initState() {
    super.initState();
    _loadStoryboards();
    _loadPromptTemplates();
    _loadSelectedTemplate();
  }

  // 加载提示词模板
  Future<void> _loadPromptTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final promptsJson = prefs.getString('prompts');
      if (promptsJson != null) {
        final decoded = jsonDecode(promptsJson) as Map<String, dynamic>;
        setState(() {
          _promptTemplates = Map<String, String>.from(decoded['image'] ?? {});
          _videoPromptTemplates = Map<String, String>.from(decoded['video'] ?? {});
        });
      }
    } catch (e) {
      logService.error('加载提示词模板失败', details: e.toString());
    }
  }

  // 加载保存的模板选择
  Future<void> _loadSelectedTemplate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedImageTemplate = prefs.getString('storyboard_selected_image_template');
      final savedVideoTemplate = prefs.getString('storyboard_selected_video_template');
      if (mounted) {
        setState(() {
          if (savedImageTemplate != null && savedImageTemplate.isNotEmpty) {
            _selectedImageTemplate = savedImageTemplate;
          }
          if (savedVideoTemplate != null && savedVideoTemplate.isNotEmpty) {
            _selectedVideoTemplate = savedVideoTemplate;
          }
        });
      }
    } catch (e) {
      logService.error('加载保存的模板选择失败', details: e.toString());
    }
  }

  // 保存模板选择
  Future<void> _saveSelectedTemplate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_selectedImageTemplate != null) {
        await prefs.setString('storyboard_selected_image_template', _selectedImageTemplate!);
      } else {
        await prefs.remove('storyboard_selected_image_template');
      }
      if (_selectedVideoTemplate != null) {
        await prefs.setString('storyboard_selected_video_template', _selectedVideoTemplate!);
      } else {
        await prefs.remove('storyboard_selected_video_template');
      }
      logService.info('保存模板选择', details: '图片: ${_selectedImageTemplate ?? '不使用'}, 视频: ${_selectedVideoTemplate ?? '不使用'}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('模板选择已保存'),
            backgroundColor: AnimeColors.miku,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      logService.error('保存模板选择失败', details: e.toString());
    }
  }

  // 显示分镜模板选择对话框（支持生图提示词和生视频提示词）
  void _showStoryboardTemplateSelector() {
    showDialog(
      context: context,
      builder: (context) => _StoryboardTemplateManagerDialog(
        selectedImageTemplate: _selectedImageTemplate,
        selectedVideoTemplate: _selectedVideoTemplate,
        onSelect: (imageTemplate, videoTemplate) {
          setState(() {
            _selectedImageTemplate = imageTemplate;
            _selectedVideoTemplate = videoTemplate;
          });
          _saveSelectedTemplate();
        },
        onSave: () {
          _loadPromptTemplates();
        },
      ),
    );
  }


  @override
  void dispose() {
    // 清理所有Controller
    for (var controller in _imagePromptControllers.values) {
      controller.dispose();
    }
    for (var controller in _videoPromptControllers.values) {
      controller.dispose();
    }
    _imagePromptControllers.clear();
    _videoPromptControllers.clear();
    super.dispose();
  }

  // 获取或创建图片提示词Controller
  TextEditingController _getImagePromptController(int index) {
    if (!_imagePromptControllers.containsKey(index)) {
      final storyboard = _storyboards[index];
      final controller = TextEditingController(
        text: storyboard['imagePrompt'] as String? ?? '',
      );
      _imagePromptControllers[index] = controller;
    }
    return _imagePromptControllers[index]!;
  }

  // 获取或创建视频提示词Controller
  TextEditingController _getVideoPromptController(int index) {
    if (!_videoPromptControllers.containsKey(index)) {
      final storyboard = _storyboards[index];
      final controller = TextEditingController(
        text: storyboard['videoPrompt'] as String? ?? '',
      );
      _videoPromptControllers[index] = controller;
    }
    return _videoPromptControllers[index]!;
  }

  // 加载分镜数据
  Future<void> _loadStoryboards() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storyboardsJson = prefs.getString('storyboards');
      if (storyboardsJson != null) {
        final List<dynamic> decoded = jsonDecode(storyboardsJson);
        // 清理旧的Controller
        for (var controller in _imagePromptControllers.values) {
          controller.dispose();
        }
        for (var controller in _videoPromptControllers.values) {
          controller.dispose();
        }
        _imagePromptControllers.clear();
        _videoPromptControllers.clear();
        
        setState(() {
          _storyboards = decoded.map<Map<String, dynamic>>((e) {
            return {
              'title': e['title'] as String? ?? '',
              'content': e['content'] as String? ?? '',
              'imagePrompt': e['imagePrompt'] as String? ?? '',
              'videoPrompt': e['videoPrompt'] as String? ?? '',
              'imageMode': e['imageMode'] as bool? ?? true,
              'imageHeight': (e['imageHeight'] as num?)?.toDouble() ?? 200.0,
              'videoHeight': (e['videoHeight'] as num?)?.toDouble() ?? 200.0,
              'imagePreview': e['imagePreview'] as String?,
              'videoPreview': e['videoPreview'] as String?,
            };
          }).toList();
        });
      }
    } catch (e) {
      print('加载分镜数据失败: $e');
    }
  }

  // 保存分镜数据
  Future<void> _saveStoryboards() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storyboardsData = _storyboards.map((s) {
        return {
          'title': s['title'] as String,
          'content': s['content'] as String,
          'imagePrompt': s['imagePrompt'] as String,
          'videoPrompt': s['videoPrompt'] as String,
          'imageMode': s['imageMode'] as bool,
          'imageHeight': s['imageHeight'] as double,
          'videoHeight': s['videoHeight'] as double,
          'imagePreview': s['imagePreview'] as String?,
          'videoPreview': s['videoPreview'] as String?,
        };
      }).toList();
      await prefs.setString('storyboards', jsonEncode(storyboardsData));
    } catch (e) {
      print('保存分镜数据失败: $e');
    }
  }

  void _parseStoryboards(String storyboardText) {
    // 清理旧的Controller
    for (var controller in _imagePromptControllers.values) {
      controller.dispose();
    }
    for (var controller in _videoPromptControllers.values) {
      controller.dispose();
    }
    _imagePromptControllers.clear();
    _videoPromptControllers.clear();
    
    // 解析分镜文本，按【分镜N】拆分
    final lines = storyboardText.split('\n');
    final List<Map<String, dynamic>> newStoryboards = [];
    String currentTitle = '';
    final StringBuffer currentContent = StringBuffer();

    for (var line in lines) {
      final trimmedLine = line.trim();
      // 检查是否是分镜标题
      if (trimmedLine.contains('【分镜') || 
          trimmedLine.contains('[分镜') || 
          (trimmedLine.startsWith('分镜') && (trimmedLine.contains('：') || trimmedLine.contains(':') || trimmedLine.length < 20))) {
        // 保存上一个分镜
        if (currentContent.length > 0) {
          newStoryboards.add({
            'title': currentTitle.isEmpty ? '分镜 ${newStoryboards.length + 1}' : currentTitle,
            'content': currentContent.toString().trim(),
            'imagePrompt': '',
            'videoPrompt': '',
            'imageMode': true, // true=图片模式, false=视频模式
            'imageHeight': 200.0, // 输入框高度
            'videoHeight': 200.0,
            'imagePreview': null,
            'videoPreview': null,
          });
        }
        currentTitle = trimmedLine;
        currentContent.clear();
      } else {
        // 添加到当前分镜内容
        if (currentContent.length > 0) {
          currentContent.write('\n');
        }
        currentContent.write(line);
      }
    }
  
    // 添加最后一个分镜
    if (currentContent.length > 0) {
      newStoryboards.add({
        'title': currentTitle.isEmpty ? '分镜 ${newStoryboards.length + 1}' : currentTitle,
        'content': currentContent.toString().trim(),
        'imagePrompt': '',
        'videoPrompt': '',
        'imageMode': true,
        'imageHeight': 200.0,
        'videoHeight': 200.0,
        'imagePreview': null,
        'videoPreview': null,
      });
    }

    // 如果没有成功解析，将整段文本作为一个分镜
    if (newStoryboards.isEmpty && storyboardText.trim().isNotEmpty) {
      newStoryboards.add({
        'title': '分镜 1',
        'content': storyboardText.trim(),
        'imagePrompt': '',
        'videoPrompt': '',
        'imageMode': true,
        'imageHeight': 200.0,
        'videoHeight': 200.0,
        'imagePreview': null,
        'videoPreview': null,
      });
    }
    
    // 更新状态
    _storyboards = newStoryboards;
  }

  // 为单个分镜生成图片提示词
  Future<String> _generateImagePrompt(String storyboardContent) async {
    try {
      final apiService = apiConfigManager.createApiService();
      
      // 构建系统提示词
      String systemPrompt = '你是一个专业的图片提示词生成器。请根据分镜描述，生成一个简洁、准确的图片生成提示词，包含场景、人物、动作、风格等关键信息。提示词应该适合用于AI图片生成，长度控制在50-100字。';
      
      // 如果选择了图片模板，在系统提示词后加上模板内容
      if (_selectedImageTemplate != null && _promptTemplates.containsKey(_selectedImageTemplate)) {
        final templateContent = _promptTemplates[_selectedImageTemplate]!;
        if (templateContent.isNotEmpty) {
          systemPrompt = '$systemPrompt\n\n$templateContent';
        }
      }
      
      final response = await apiService.chatCompletion(
        model: apiConfigManager.llmModel,
        messages: [
          {
            'role': 'system',
            'content': systemPrompt
          },
          {
            'role': 'user',
            'content': '请为以下分镜生成图片提示词：\n\n$storyboardContent'
          },
        ],
        temperature: 0.7,
        maxTokens: 200,
      );
      return response.choices.first.message.content.trim();
    } catch (e) {
      logService.error('生成图片提示词失败', details: e.toString());
      return '';
    }
  }

  // 为单个分镜生成视频提示词
  Future<String> _generateVideoPrompt(String storyboardContent) async {
    try {
      final apiService = apiConfigManager.createApiService();
      
      // 构建系统提示词
      String systemPrompt = '你是一个专业的视频提示词生成器。请根据分镜描述，生成一个简洁、准确的视频生成提示词，重点描述动作、运动、变化等动态元素。提示词应该适合用于AI视频生成，长度控制在50-100字。';
      
      // 如果选择了视频模板，在系统提示词后加上模板内容
      if (_selectedVideoTemplate != null && _videoPromptTemplates.containsKey(_selectedVideoTemplate)) {
        final templateContent = _videoPromptTemplates[_selectedVideoTemplate]!;
        if (templateContent.isNotEmpty) {
          systemPrompt = '$systemPrompt\n\n$templateContent';
        }
      }
      
      final response = await apiService.chatCompletion(
        model: apiConfigManager.llmModel,
        messages: [
          {
            'role': 'system',
            'content': systemPrompt
          },
          {
            'role': 'user',
            'content': '请为以下分镜生成视频提示词：\n\n$storyboardContent'
          },
        ],
        temperature: 0.7,
        maxTokens: 200,
      );
      return response.choices.first.message.content.trim();
    } catch (e) {
      logService.error('生成视频提示词失败', details: e.toString());
      return '';
    }
  }

  // 异步生成完整的分镜（包括提示词）
  Future<void> _generateStoryboardsWithPrompts(String script) async {
    try {
      // 显示进度提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('正在生成分镜...'),
            backgroundColor: AnimeColors.miku,
            duration: Duration(seconds: 30),
          ),
        );
      }

      final apiService = apiConfigManager.createApiService();
      
      // 构建系统提示词
      String systemPrompt = '你是一个专业的分镜师，擅长将剧本转化为详细的分镜描述。请将剧本拆分成多个分镜，每个分镜用"【分镜N】"开头，包含场景、人物、动作等描述。';
      
      // 第一步：生成分镜描述
      final response = await apiService.chatCompletion(
        model: apiConfigManager.llmModel,
        messages: [
          {
            'role': 'system',
            'content': systemPrompt
          },
          {
            'role': 'user',
            'content': '请将以下剧本转化为分镜描述：\n\n剧本：\n$script'
          },
        ],
        temperature: 0.7,
      );
      
      final storyboardText = response.choices.first.message.content;
      
      // 第二步：解析分镜
      _parseStoryboards(storyboardText);
      
      if (!mounted) return;
      
      // 第三步：为每个分镜生成图片和视频提示词
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('正在生成提示词... (${_storyboards.length}个分镜)'),
            backgroundColor: AnimeColors.miku,
            duration: Duration(seconds: 60),
          ),
        );
      }

      // 批量生成提示词（避免阻塞）
      for (int i = 0; i < _storyboards.length; i++) {
        if (!mounted) break;
        
        final storyboard = _storyboards[i];
        final content = storyboard['content'] as String;
        
        // 并行生成图片和视频提示词
        final results = await Future.wait([
          _generateImagePrompt(content),
          _generateVideoPrompt(content),
        ]);
        
        // 更新分镜的提示词
        _storyboards[i] = {
          ...storyboard,
          'imagePrompt': results[0],
          'videoPrompt': results[1],
        };
        
        // 每生成一个分镜就更新一次UI
        if (mounted) {
          setState(() {});
        }
        
        // 添加小延迟，避免API限流
        await Future.delayed(Duration(milliseconds: 200));
      }
      
      // 保存数据
      await _saveStoryboards();
      
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('分镜生成成功！已生成 ${_storyboards.length} 个分镜及提示词'),
            backgroundColor: AnimeColors.miku,
            duration: Duration(seconds: 3),
          ),
        );
      }
      
      logService.action('分镜生成完成', details: '共${_storyboards.length}个分镜');
    } catch (e) {
      logService.error('生成分镜失败', details: e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('生成失败: $e'),
            backgroundColor: AnimeColors.sakura,
          ),
        );
      }
    }
  }

  void _showGenerateDialog() {
    final TextEditingController scriptController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.8,
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
                decoration: BoxDecoration(
                  color: AnimeColors.glassBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标题栏
                    Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AnimeColors.miku, AnimeColors.purple],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text('🎬', style: TextStyle(fontSize: 24)),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '分镜生成',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  '将剧本转化为视觉语言',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: Icon(Icons.close, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    // 内容区域
                    Flexible(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '剧本内容',
                                  style: TextStyle(
                                    color: AnimeColors.miku,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            Flexible(
                              child: Container(
                                constraints: BoxConstraints(minHeight: 200, maxHeight: 400),
                                decoration: BoxDecoration(
                                  color: AnimeColors.cardBg,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: TextField(
                                  controller: scriptController,
                                  enabled: true,
                                  readOnly: false,
                                  enableInteractiveSelection: true,
                                  maxLines: null,
                                  minLines: 8,
                                  textAlignVertical: TextAlignVertical.top,
                                  style: TextStyle(color: Colors.white70, fontSize: 15),
                                  decoration: InputDecoration(
                                    hintText: '粘贴完整剧本内容...',
                                    hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.all(16),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: () {
                                  if (scriptController.text.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('请先输入剧本内容')),
                                    );
                                    return;
                                  }
                                  if (!apiConfigManager.hasLlmConfig) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('请先在设置中配置 LLM API')),
                                    );
                                    return;
                                  }
                                  
                                  // 立即关闭对话框
                                  final script = scriptController.text;
                                  Navigator.pop(dialogContext);
                                  
                                  // 在后台异步生成分镜和提示词
                                  _generateStoryboardsWithPrompts(script);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  padding: EdgeInsets.zero,
                                ),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [AnimeColors.miku, AnimeColors.purple],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Container(
                                    alignment: Alignment.center,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.auto_awesome_outlined, size: 20),
                                        SizedBox(width: 8),
                                        Text(
                                          '生成分镜描述',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ).then((_) => scriptController.dispose());
  }

  void _addStoryboard() {
    setState(() {
      _storyboards.add({
        'title': '分镜 ${_storyboards.length + 1}',
        'content': '在这里输入新的分镜内容...',
        'imagePrompt': '',
        'videoPrompt': '',
        'imageMode': true, // true=图片模式, false=视频模式
        'imageHeight': 200.0, // 输入框高度
        'videoHeight': 200.0,
        'imagePreview': null, // 图片预览URL
        'videoPreview': null, // 视频预览URL
      });
    });
    _saveStoryboards();
  }

  void _clearAllStoryboards() {
    if (_storyboards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('没有可删除的分镜'), backgroundColor: AnimeColors.orangeAccent),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AnimeColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AnimeColors.sakura, size: 24),
            SizedBox(width: 8),
            Text('确认删除', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(
          '确定要删除所有 ${_storyboards.length} 个分镜吗？此操作不可恢复。',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              // 清理所有Controller
              for (var controller in _imagePromptControllers.values) {
                controller.dispose();
              }
              for (var controller in _videoPromptControllers.values) {
                controller.dispose();
              }
              _imagePromptControllers.clear();
              _videoPromptControllers.clear();
              
              setState(() {
                _storyboards.clear();
              });
              _saveStoryboards();
              Navigator.pop(context);
              logService.action('删除所有分镜');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已删除所有分镜'), backgroundColor: AnimeColors.miku),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AnimeColors.sakura),
            child: Text('确认删除'),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerationSettings() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AnimeColors.glassBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tune, color: AnimeColors.miku, size: 18),
                  SizedBox(width: 8),
                  Text('生成设置', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(' (生成时将使用以下参数)', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
              SizedBox(height: 16),
              Wrap(
                spacing: 24,
                runSpacing: 16,
                children: [
                  // 图片比例
                  _buildSettingGroup(
                    '图片比例',
                    Icons.aspect_ratio,
                    AnimeColors.sakura,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(imageSizes.length > 5 ? 5 : imageSizes.length, (index) {
                        final isSelected = workspaceState.imageSizeIndex == index;
                        return Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () {
                              setState(() => workspaceState.imageSizeIndex = index);
                              logService.action('设置图片比例', details: imageSizes[index].label);
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected ? AnimeColors.sakura.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: isSelected ? AnimeColors.sakura : Colors.white10),
                              ),
                              child: Text(imageSizes[index].ratio, style: TextStyle(color: isSelected ? AnimeColors.sakura : Colors.white60, fontSize: 11)),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  // 视频比例
                  _buildSettingGroup(
                    '视频比例',
                    Icons.videocam_outlined,
                    AnimeColors.blue,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(videoSizes.length, (index) {
                        final isSelected = workspaceState.videoSizeIndex == index;
                        return Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () {
                              setState(() => workspaceState.videoSizeIndex = index);
                              logService.action('设置视频比例', details: videoSizes[index].label);
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected ? AnimeColors.blue.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: isSelected ? AnimeColors.blue : Colors.white10),
                              ),
                              child: Text(videoSizes[index].ratio, style: TextStyle(color: isSelected ? AnimeColors.blue : Colors.white60, fontSize: 11)),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  // 视频时长
                  _buildSettingGroup(
                    '视频时长',
                    Icons.timer_outlined,
                    AnimeColors.purple,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(videoDurations.length, (index) {
                        final isSelected = workspaceState.durationIndex == index;
                        return Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () {
                              setState(() => workspaceState.durationIndex = index);
                              logService.action('设置视频时长', details: videoDurations[index]);
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected ? AnimeColors.purple.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: isSelected ? AnimeColors.purple : Colors.white10),
                              ),
                              child: Text(videoDurations[index], style: TextStyle(color: isSelected ? AnimeColors.purple : Colors.white60, fontSize: 11)),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  // 图片清晰度
                  _buildSettingGroup(
                    '图片清晰度',
                    Icons.hd_outlined,
                    AnimeColors.miku,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(imageQualities.length, (index) {
                        final isSelected = workspaceState.qualityIndex == index;
                        return Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () {
                              setState(() => workspaceState.qualityIndex = index);
                              logService.action('设置图片清晰度', details: imageQualities[index]);
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                gradient: isSelected ? LinearGradient(colors: [AnimeColors.miku, AnimeColors.purple]) : null,
                                color: isSelected ? null : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: isSelected ? Colors.transparent : Colors.white10),
                              ),
                              child: Text(imageQualities[index], style: TextStyle(color: isSelected ? Colors.white : Colors.white60, fontSize: 11, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400)),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingGroup(String label, IconData icon, Color color, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
        SizedBox(height: 8),
        child,
      ],
    );
  }

  void _deleteStoryboard(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AnimeColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AnimeColors.sakura),
            SizedBox(width: 8),
            Text('确认删除', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(
          '确定要删除这个分镜吗？',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                // 清理被删除分镜的Controller
                _imagePromptControllers[index]?.dispose();
                _videoPromptControllers[index]?.dispose();
                _imagePromptControllers.remove(index);
                _videoPromptControllers.remove(index);
                
                _storyboards.removeAt(index);
                
                // 重新索引Controller
                final newImageControllers = <int, TextEditingController>{};
                final newVideoControllers = <int, TextEditingController>{};
                _imagePromptControllers.forEach((key, controller) {
                  if (key < index) {
                    newImageControllers[key] = controller;
                  } else if (key > index) {
                    newImageControllers[key - 1] = controller;
                  }
                });
                _videoPromptControllers.forEach((key, controller) {
                  if (key < index) {
                    newVideoControllers[key] = controller;
                  } else if (key > index) {
                    newVideoControllers[key - 1] = controller;
                  }
                });
                _imagePromptControllers.clear();
                _videoPromptControllers.clear();
                _imagePromptControllers.addAll(newImageControllers);
                _videoPromptControllers.addAll(newVideoControllers);
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AnimeColors.sakura,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏，右上角有"分镜生成"按钮
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AnimeColors.miku, AnimeColors.purple],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text('🎬', style: TextStyle(fontSize: 26)),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '分镜生成',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '分镜列表（${_storyboards.length}个分镜）',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
              // 分镜生成按钮
              InkWell(
                onTap: _showGenerateDialog,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [AnimeColors.miku, AnimeColors.purple],
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome_outlined, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        '分镜生成',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 12),
              // 提示词模板选择按钮
              TextButton.icon(
                onPressed: () => _showStoryboardTemplateSelector(),
                icon: Icon(
                  Icons.text_snippet,
                  size: 16,
                  color: (_selectedImageTemplate != null || _selectedVideoTemplate != null) ? AnimeColors.purple : Colors.white54,
                ),
                label: Text(
                  (_selectedImageTemplate != null || _selectedVideoTemplate != null) 
                    ? '提示词模板' 
                    : '提示词模板',
                  style: TextStyle(
                    color: (_selectedImageTemplate != null || _selectedVideoTemplate != null) ? AnimeColors.purple : Colors.white54,
                    fontSize: 12,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              SizedBox(width: 8),
              // 保存按钮
              if (_selectedImageTemplate != null || _selectedVideoTemplate != null)
                IconButton(
                  icon: Icon(Icons.save, size: 18, color: AnimeColors.purple),
                  tooltip: '保存模板选择',
                  onPressed: () {
                    _saveSelectedTemplate();
                  },
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              SizedBox(width: 12),
              // 增加分镜按钮
              InkWell(
                onTap: _addStoryboard,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AnimeColors.miku.withOpacity(0.5), width: 1.5),
                    color: Colors.transparent,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.add, color: AnimeColors.miku, size: 18),
                      SizedBox(width: 8),
                      Text(
                        '增加分镜',
                        style: TextStyle(
                          color: AnimeColors.miku,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 12),
              // 删除所有分镜按钮
              InkWell(
                onTap: _clearAllStoryboards,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AnimeColors.sakura.withOpacity(0.5), width: 1.5),
                    color: Colors.transparent,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep_outlined, color: AnimeColors.sakura, size: 18),
                      SizedBox(width: 8),
                      Text(
                        '删除所有',
                        style: TextStyle(
                          color: AnimeColors.sakura,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          // 生成设置区域
          _buildGenerationSettings(),
          SizedBox(height: 20),
          // 分镜列表
          Expanded(
            child: _storyboards.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: AnimeColors.cardBg,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Icon(
                            Icons.view_agenda_outlined,
                            size: 60,
                            color: Colors.white24,
                          ),
                        ),
                        SizedBox(height: 24),
                        Text(
                          '暂无分镜',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white54,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '点击右上角"分镜生成"按钮开始生成',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _storyboards.length,
                    itemBuilder: (context, index) {
                      return _buildStoryboardCard(index);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoryboardCard(int index) {
    final storyboard = _storyboards[index];
    final imageMode = storyboard['imageMode'] as bool;
    
    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              color: AnimeColors.glassBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
            ),
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题行
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AnimeColors.miku, AnimeColors.purple],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        storyboard['title'] as String,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Spacer(),
                  ],
                ),
                SizedBox(height: 16),
                // 主要内容区域：左侧输入框 + 中间按钮 + 右侧预览
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左侧：提示词输入框（可调整大小）
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              Container(
                                height: imageMode ? (storyboard['imageHeight'] as double) : (storyboard['videoHeight'] as double),
                                decoration: BoxDecoration(
                                  color: AnimeColors.cardBg,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: TextField(
                                  controller: imageMode 
                                    ? _getImagePromptController(index)
                                    : _getVideoPromptController(index),
                                  enabled: true,
                                  readOnly: false,
                                  enableInteractiveSelection: true,
                                  maxLines: null,
                                  minLines: 3,
                                  textAlignVertical: TextAlignVertical.top,
                                  style: TextStyle(color: Colors.white70, fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: imageMode ? '图片提示词（可从分镜内容自动生成）' : '视频提示词（可从分镜内容自动生成）',
                                    hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.all(16),
                                  ),
                                  onChanged: (value) {
                                    if (imageMode) {
                                      storyboard['imagePrompt'] = value;
                                    } else {
                                      storyboard['videoPrompt'] = value;
                                    }
                                    _saveStoryboards();
                                  },
                                ),
                              ),
                              // 拖动调整高度的手柄
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: GestureDetector(
                                  onVerticalDragUpdate: (details) {
                                    setState(() {
                                      if (imageMode) {
                                        final newHeight = (storyboard['imageHeight'] as double) + details.delta.dy;
                                        storyboard['imageHeight'] = newHeight.clamp(150.0, 500.0);
                                      } else {
                                        final newHeight = (storyboard['videoHeight'] as double) + details.delta.dy;
                                        storyboard['videoHeight'] = newHeight.clamp(150.0, 500.0);
                                      }
                                    });
                                    _saveStoryboards();
                                  },
                                  child: Container(
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: Colors.transparent,
                                      borderRadius: BorderRadius.only(
                                        bottomLeft: Radius.circular(16),
                                        bottomRight: Radius.circular(16),
                                      ),
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 40,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: Colors.white30,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 12),
                    // 中间：图片/视频切换按钮
                    Column(
                      children: [
                        InkWell(
                          onTap: () {
                            setState(() {
                              storyboard['imageMode'] = true;
                            });
                            _saveStoryboards();
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: imageMode ? AnimeColors.sakura.withOpacity(0.3) : Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: imageMode ? AnimeColors.sakura : Colors.white.withOpacity(0.2),
                                width: imageMode ? 2 : 1,
                              ),
                            ),
                            child: Icon(
                              Icons.image_outlined,
                              color: imageMode ? AnimeColors.sakura : Colors.white54,
                              size: 28,
                            ),
                          ),
                        ),
                        SizedBox(height: 12),
                        InkWell(
                          onTap: () {
                            setState(() {
                              storyboard['imageMode'] = false;
                            });
                            _saveStoryboards();
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: !imageMode ? AnimeColors.miku.withOpacity(0.3) : Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: !imageMode ? AnimeColors.miku : Colors.white.withOpacity(0.2),
                                width: !imageMode ? 2 : 1,
                              ),
                            ),
                            child: Icon(
                              Icons.movie_outlined,
                              color: !imageMode ? AnimeColors.miku : Colors.white54,
                              size: 28,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(width: 12),
                    // 右侧：预览框
                    Expanded(
                      flex: 2,
                      child: Container(
                        height: imageMode ? (storyboard['imageHeight'] as double) : (storyboard['videoHeight'] as double),
                        decoration: BoxDecoration(
                          color: AnimeColors.cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: (imageMode 
                          ? (storyboard['imagePreview'] != null 
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: buildImageWidget(
                                  imageUrl: storyboard['imagePreview'] as String,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.image_not_supported, color: Colors.white24, size: 40),
                                        SizedBox(height: 8),
                                        Text('图片加载失败', style: TextStyle(color: Colors.white38, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.image_outlined, color: Colors.white24, size: 40),
                                    SizedBox(height: 8),
                                    Text('图片预览', style: TextStyle(color: Colors.white38, fontSize: 12)),
                                  ],
                                ),
                              ))
                          : (storyboard['videoPreview'] != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  color: Colors.black,
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.play_circle_outline, color: Colors.white70, size: 48),
                                        SizedBox(height: 8),
                                        Text('视频预览', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.movie_outlined, color: Colors.white24, size: 40),
                                    SizedBox(height: 8),
                                    Text('视频预览', style: TextStyle(color: Colors.white38, fontSize: 12)),
                                  ],
                                ),
                              ))),
                      ),
                    ),
                    SizedBox(width: 12),
                    // 删除按钮
                    IconButton(
                      onPressed: () => _deleteStoryboard(index),
                      icon: Icon(Icons.delete_outline, color: AnimeColors.sakura),
                      tooltip: '删除分镜',
                    ),
                  ],
                ),
                SizedBox(height: 16),
                // 生成按钮
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      if (imageMode) {
                        _generateImage(index);
                      } else {
                        _generateVideo(index);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: EdgeInsets.zero,
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: imageMode 
                            ? [AnimeColors.sakura, AnimeColors.sakura.withOpacity(0.7)]
                            : [AnimeColors.miku, AnimeColors.purple],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        child: Text(
                          imageMode ? '图片生成' : '视频生成',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 生成图片
  Future<void> _generateImage(int index) async {
    final storyboard = _storyboards[index];
    final imagePrompt = storyboard['imagePrompt'] as String? ?? '';
    final content = storyboard['content'] as String? ?? '';
    
    if (!apiConfigManager.hasImageConfig) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在设置中配置图片生成 API')),
      );
      return;
    }

    // 显示加载提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('图片生成中...')),
    );

    try {
      final apiService = apiConfigManager.createApiService();
      
      // 使用图片提示词，如果为空则使用分镜内容
      final prompt = imagePrompt.isNotEmpty ? imagePrompt : (content.isNotEmpty ? content : '一个美丽的场景');
      
      final response = await apiService.createImage(
        model: apiConfigManager.imageModel,
        prompt: prompt,
        size: apiConfigManager.imageSize,
        quality: apiConfigManager.imageQuality,
        style: apiConfigManager.imageStyle,
      );

      if (response.data.isNotEmpty && response.data.first.url != null) {
        final imageUrl = response.data.first.url!;
        setState(() {
          storyboard['imagePreview'] = imageUrl;
        });
        _saveStoryboards();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('图片生成成功！')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('图片生成失败：未返回图片URL')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片生成失败: $e')),
        );
      }
    }
  }

  // 生成视频
  Future<void> _generateVideo(int index) async {
    final storyboard = _storyboards[index];
    final videoPrompt = storyboard['videoPrompt'] as String? ?? '';
    final content = storyboard['content'] as String? ?? '';
    
    if (!apiConfigManager.hasVideoConfig) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在设置中配置视频生成 API')),
      );
      return;
    }

    // 显示加载提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('视频生成中...')),
    );

    try {
      final apiService = apiConfigManager.createApiService();
      
      // 使用视频提示词，如果为空则使用分镜内容
      final prompt = videoPrompt.isNotEmpty ? videoPrompt : (content.isNotEmpty ? content : '一个美丽的视频场景');
      
      final response = await apiService.createVideo(
        model: apiConfigManager.videoModel,
        prompt: prompt,
        size: apiConfigManager.videoSize,
        seconds: apiConfigManager.videoSeconds,
      );

      // 视频生成是异步的，返回的是任务ID
      if (response.id.isNotEmpty) {
        // 保存任务ID，后续可以查询状态
        setState(() {
          storyboard['videoTaskId'] = response.id;
          storyboard['videoStatus'] = response.status;
        });
        _saveStoryboards();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('视频生成任务已提交！任务ID: ${response.id}')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('视频生成失败：未返回任务ID')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('视频生成失败: $e')),
        );
      }
    }
  }

}

// 分镜详情页面
class StoryboardDetailPage extends StatefulWidget {
  final String storyboardText;
  const StoryboardDetailPage({super.key, required this.storyboardText});

  @override
  State<StoryboardDetailPage> createState() => _StoryboardDetailPageState();
}

class _StoryboardDetailPageState extends State<StoryboardDetailPage> {
  late List<Map<String, dynamic>> _storyboards;
  Map<int, bool> _showVideoTimeSelector = {}; // 记录每个分镜是否显示时间选择器
  Map<int, int> _videoSeconds = {}; // 记录每个分镜选择的视频时长

  @override
  void initState() {
    super.initState();
    _parseStoryboards();
  }

  void _parseStoryboards() {
    // 解析分镜文本，按【分镜N】拆分
    final lines = widget.storyboardText.split('\n');
    _storyboards = [];
    String currentTitle = '';
    String currentContent = '';

    for (var line in lines) {
      if (line.contains('【分镜') || line.contains('[分镜') || line.contains('分镜 ')) {
        if (currentContent.isNotEmpty) {
          _storyboards.add({
            'title': currentTitle.isEmpty ? '分镜 ${_storyboards.length + 1}' : currentTitle,
            'content': currentContent.trim(),
          });
        }
        currentTitle = line.trim();
        currentContent = '';
      } else {
        currentContent += line + '\n';
      }
    }
    
    // 添加最后一个分镜
    if (currentContent.isNotEmpty) {
      _storyboards.add({
        'title': currentTitle.isEmpty ? '分镜 ${_storyboards.length + 1}' : currentTitle,
        'content': currentContent.trim(),
      });
    }

    // 如果没有成功解析，将整段文本作为一个分镜
    if (_storyboards.isEmpty) {
      _storyboards.add({
        'title': '分镜 1',
        'content': widget.storyboardText,
      });
    }
    
    // 初始化时间选择器状态和默认时长
    for (int i = 0; i < _storyboards.length; i++) {
      _showVideoTimeSelector[i] = false;
      _videoSeconds[i] = apiConfigManager.videoSeconds;
    }
  }

  void _addStoryboard() {
    setState(() {
      final index = _storyboards.length;
      _storyboards.add({
        'title': '分镜 ${_storyboards.length + 1}',
        'content': '在这里输入新的分镜内容...',
      });
      _showVideoTimeSelector[index] = false;
      _videoSeconds[index] = apiConfigManager.videoSeconds;
    });
  }

  void _deleteStoryboard(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AnimeColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AnimeColors.sakura),
            SizedBox(width: 8),
            Text('确认删除', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(
          '确定要删除这个分镜吗？',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _storyboards.removeAt(index);
                _showVideoTimeSelector.remove(index);
                _videoSeconds.remove(index);
                // 重新索引
                final newSelectors = <int, bool>{};
                final newSeconds = <int, int>{};
                _showVideoTimeSelector.forEach((key, value) {
                  if (key < index) {
                    newSelectors[key] = value;
                  } else if (key > index) {
                    newSelectors[key - 1] = value;
                  }
                });
                _videoSeconds.forEach((key, value) {
                  if (key < index) {
                    newSeconds[key] = value;
                  } else if (key > index) {
                    newSeconds[key - 1] = value;
                  }
                });
                _showVideoTimeSelector = newSelectors;
                _videoSeconds = newSeconds;
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AnimeColors.sakura,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AnimeColors.darkBg, Color(0xFF0f0f1e)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 顶部栏
              Container(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    // 返回按钮
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white.withOpacity(0.05),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.arrow_back_ios_new_rounded, color: AnimeColors.miku, size: 16),
                            SizedBox(width: 6),
                            Text(
                              '返回',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Text(
                      '分镜详情（${_storyboards.length}个分镜）',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Spacer(),
                    // 添加分镜按钮
                    InkWell(
                      onTap: _addStoryboard,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: [AnimeColors.miku, AnimeColors.purple],
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.add, color: Colors.white, size: 18),
                            SizedBox(width: 6),
                            Text(
                              '添加分镜',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 分镜列表
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.all(20),
                  itemCount: _storyboards.length,
                  itemBuilder: (context, index) {
                    return _buildStoryboardCard(index);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStoryboardCard(int index) {
    final storyboard = _storyboards[index];
    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              color: AnimeColors.glassBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
            ),
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题行
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AnimeColors.miku, AnimeColors.purple],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        storyboard['title'] as String,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Spacer(),
                    // 删除按钮
                    IconButton(
                      onPressed: () => _deleteStoryboard(index),
                      icon: Icon(Icons.delete_outline, color: AnimeColors.sakura),
                      tooltip: '删除分镜',
                    ),
                  ],
                ),
                SizedBox(height: 12),
                // 分镜内容
                Text(
                  storyboard['content'] as String,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                SizedBox(height: 16),
                // 操作按钮行
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            '生成图片',
                            Icons.image_outlined,
                            AnimeColors.sakura,
                            () => _generateImage(index),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: _buildActionButton(
                            '生成视频',
                            Icons.movie_outlined,
                            AnimeColors.miku,
                            () => _generateVideo(index),
                          ),
                        ),
                      ],
                    ),
                    // 视频时长选择器（仅当点击视频生成按钮时显示）
                    if (_showVideoTimeSelector[index] == true) ...[
                      SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: AnimeColors.cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.access_time, color: AnimeColors.miku, size: 18),
                            SizedBox(width: 8),
                            Text(
                              '视频时长：',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: DropdownButton<int>(
                                value: _videoSeconds[index],
                                isExpanded: true,
                                dropdownColor: AnimeColors.cardBg,
                                style: TextStyle(color: Colors.white, fontSize: 14),
                                underline: SizedBox.shrink(),
                                items: apiConfigManager.getVideoSecondsOptions().map((seconds) {
                                  return DropdownMenuItem(
                                    value: seconds,
                                    child: Text('${seconds}秒'),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      _videoSeconds[index] = value;
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: color.withOpacity(0.15),
          border: Border.all(color: color.withOpacity(0.5), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 生成图片
  Future<void> _generateImage(int index) async {
    final storyboard = _storyboards[index];
    final content = storyboard['content'] as String;
    
    if (!apiConfigManager.hasImageConfig) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在设置中配置图片生成 API')),
      );
      return;
    }

    // 显示加载提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('图片生成中...')),
    );

    try {
      final apiService = apiConfigManager.createApiService();
      
      // 使用分镜内容作为提示词，如果没有则使用默认提示词
      final prompt = content.isNotEmpty ? content : '一个美丽的场景';
      
      final response = await apiService.createImage(
        model: apiConfigManager.imageModel,
        prompt: prompt,
        size: apiConfigManager.imageSize,
        quality: apiConfigManager.imageQuality,
        style: apiConfigManager.imageStyle,
      );

      if (response.data.isNotEmpty && response.data.first.url != null) {
        final imageUrl = response.data.first.url!;
        setState(() {
          storyboard['imageUrl'] = imageUrl;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片生成成功！')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片生成失败：未返回图片URL')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('图片生成失败: $e')),
      );
    }
  }

  // 生成视频
  Future<void> _generateVideo(int index) async {
    final storyboard = _storyboards[index];
    final content = storyboard['content'] as String;
    
    // 显示时间选择器
    setState(() {
      _showVideoTimeSelector[index] = true;
      if (!_videoSeconds.containsKey(index)) {
        _videoSeconds[index] = apiConfigManager.videoSeconds;
      }
    });

    if (!apiConfigManager.hasVideoConfig) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在设置中配置视频生成 API')),
      );
      return;
    }

    // 显示加载提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('视频生成中...')),
    );

    try {
      final apiService = apiConfigManager.createApiService();
      
      // 使用分镜内容作为提示词，如果没有则使用默认提示词
      final prompt = content.isNotEmpty ? content : '一个美丽的视频场景';
      
      final seconds = _videoSeconds[index] ?? apiConfigManager.videoSeconds;
      
      final response = await apiService.createVideo(
        model: apiConfigManager.videoModel,
        prompt: prompt,
        size: apiConfigManager.videoSize,
        seconds: seconds,
      );

      // 视频生成是异步的，返回的是任务ID
      if (response.id.isNotEmpty) {
        // 可以保存任务ID，后续查询状态
        setState(() {
          storyboard['videoTaskId'] = response.id;
          storyboard['videoStatus'] = response.status;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('视频生成任务已提交！任务ID: ${response.id}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('视频生成失败：未返回任务ID')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('视频生成失败: $e')),
      );
    }
  }
}

// 提示词详情页面
class PromptDetailPage extends StatefulWidget {
  final String promptKey;
  final String promptLabel;
  final IconData promptIcon;
  final Color promptColor;
  final Map<String, String> prompts;
  final Function(Map<String, String>) onSave;

  const PromptDetailPage({
    super.key,
    required this.promptKey,
    required this.promptLabel,
    required this.promptIcon,
    required this.promptColor,
    required this.prompts,
    required this.onSave,
  });

  @override
  State<PromptDetailPage> createState() => _PromptDetailPageState();
}

class _PromptDetailPageState extends State<PromptDetailPage> {
  late Map<String, String> _prompts;
  String? _selectedName;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _prompts = Map<String, String>.from(widget.prompts);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _addNewPrompt() {
    _nameController.clear();
    _contentController.clear();
    setState(() {
      _selectedName = null;
    });
    _showAddNameDialog();
  }

  void _showAddNameDialog() {
    final TextEditingController nameInputController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AnimeColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '新增提示词',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: nameInputController,
          autofocus: true,
          enabled: true,
          readOnly: false,
          enableInteractiveSelection: true,
          style: TextStyle(color: Colors.white70),
          decoration: InputDecoration(
            hintText: '请输入提示词名称',
            hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white10),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white10),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: widget.promptColor, width: 2),
            ),
            filled: true,
            fillColor: AnimeColors.darkBg,
            contentPadding: EdgeInsets.all(14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameInputController.text.isNotEmpty) {
                setState(() {
                  _nameController.text = nameInputController.text.trim();
                  _prompts[_nameController.text] = '';
                  _selectedName = _nameController.text;
                  _contentController.clear();
                });
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.promptColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('确定'),
          ),
        ],
      ),
    );
  }

  void _selectPrompt(String name) {
    setState(() {
      _selectedName = name;
      _nameController.text = name;
      _contentController.text = _prompts[name] ?? '';
    });
  }

  void _deletePrompt(String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AnimeColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AnimeColors.sakura),
            SizedBox(width: 8),
            Text('确认删除', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(
          '确定要删除提示词 "$name" 吗？',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _prompts.remove(name);
                if (_selectedName == name) {
                  _selectedName = null;
                  _nameController.clear();
                  _contentController.clear();
                }
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AnimeColors.sakura,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('删除'),
          ),
        ],
      ),
    );
  }

  void _savePrompts() {
    if (_selectedName != null && _nameController.text.isNotEmpty) {
      _prompts[_selectedName!] = _contentController.text;
    }
    widget.onSave(_prompts);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AnimeColors.darkBg, Color(0xFF0f0f1e), Color(0xFF1a1a2e)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 顶部栏
              Container(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                      tooltip: '返回',
                    ),
                    SizedBox(width: 12),
                    Icon(widget.promptIcon, color: widget.promptColor, size: 24),
                    SizedBox(width: 8),
                    Text(
                      widget.promptLabel,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Spacer(),
                    ElevatedButton(
                      onPressed: _savePrompts,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: EdgeInsets.zero,
                      ),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [widget.promptColor, widget.promptColor.withOpacity(0.7)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '保存',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 主体内容
              Expanded(
                child: Row(
                  children: [
                    // 左侧：名称列表
                    Container(
                      width: 280,
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                      ),
                      child: Column(
                        children: [
                          // 新增按钮
                          Padding(
                            padding: EdgeInsets.all(16),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _addNewPrompt,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: EdgeInsets.zero,
                                ),
                                child: Container(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [widget.promptColor, widget.promptColor.withOpacity(0.7)],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add, size: 20),
                                      SizedBox(width: 8),
                                      Text('新增提示词', style: TextStyle(fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Divider(color: Colors.white.withOpacity(0.1)),
                          // 名称列表
                          Expanded(
                            child: _prompts.isEmpty
                                ? Center(
                                    child: Text(
                                      '点击上方按钮新增提示词',
                                      style: TextStyle(color: Colors.white38, fontSize: 14),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: EdgeInsets.symmetric(horizontal: 12),
                                    itemCount: _prompts.length,
                                    itemBuilder: (context, index) {
                                      final name = _prompts.keys.elementAt(index);
                                      final isSelected = _selectedName == name;
                                      return InkWell(
                                        onTap: () => _selectPrompt(name),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          margin: EdgeInsets.only(bottom: 8),
                                          padding: EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? widget.promptColor.withOpacity(0.2)
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: isSelected
                                                  ? widget.promptColor
                                                  : Colors.white.withOpacity(0.1),
                                              width: isSelected ? 2 : 1,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  name,
                                                  style: TextStyle(
                                                    color: isSelected
                                                        ? widget.promptColor
                                                        : Colors.white70,
                                                    fontWeight: isSelected
                                                        ? FontWeight.w700
                                                        : FontWeight.normal,
                                                    fontSize: 14,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: () => _deletePrompt(name),
                                                icon: Icon(Icons.delete_outline,
                                                    size: 18, color: Colors.white54),
                                                padding: EdgeInsets.zero,
                                                constraints: BoxConstraints(),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                    // 右侧：内容编辑区
                    Expanded(
                      child: _selectedName == null
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(widget.promptIcon, size: 80, color: Colors.white24),
                                  SizedBox(height: 20),
                                  Text(
                                    '请选择或新增提示词',
                                    style: TextStyle(color: Colors.white54, fontSize: 16),
                                  ),
                                ],
                              ),
                            )
                          : Padding(
                              padding: EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '提示词名称',
                                    style: TextStyle(
                                      color: widget.promptColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  TextField(
                                    controller: _nameController,
                                    enabled: true,
                                    readOnly: false,
                                    enableInteractiveSelection: true,
                                    style: TextStyle(color: Colors.white70),
                                    decoration: InputDecoration(
                                      hintText: '提示词名称',
                                      hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.white10),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.white10),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: widget.promptColor, width: 2),
                                      ),
                                      filled: true,
                                      fillColor: AnimeColors.cardBg,
                                      contentPadding: EdgeInsets.all(14),
                                    ),
                                    onChanged: (value) {
                                      if (_selectedName != null && value != _selectedName) {
                                        // 如果名称改变，更新键
                                        final oldName = _selectedName!;
                                        final content = _contentController.text;
                                        setState(() {
                                          _prompts.remove(oldName);
                                          _prompts[value] = content;
                                          _selectedName = value;
                                        });
                                      }
                                    },
                                  ),
                                  SizedBox(height: 20),
                                  Text(
                                    '提示词内容',
                                    style: TextStyle(
                                      color: widget.promptColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: AnimeColors.glassBg,
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                                          ),
                                          padding: EdgeInsets.all(16),
                          child: TextField(
                            controller: _contentController,
                            enabled: true,
                            readOnly: false,
                            enableInteractiveSelection: true,
                            maxLines: null,
                            minLines: 10,
                            textAlignVertical: TextAlignVertical.top,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.6,
                            ),
                            decoration: InputDecoration(
                              hintText: '在此输入提示词内容...',
                              hintStyle: TextStyle(color: Colors.white38),
                              border: InputBorder.none,
                            ),
                                            onChanged: (value) {
                                              if (_selectedName != null) {
                                                _prompts[_selectedName!] = value;
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// API 设置页面（保留原有逻辑，更新样式）
class ApiSettingsPage extends StatefulWidget {
  const ApiSettingsPage({super.key});

  @override
  State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends State<ApiSettingsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // LLM 配置
  final TextEditingController _llmApiController = TextEditingController();
  final TextEditingController _llmUrlController = TextEditingController();
  late String _selectedLlmModel;
  LlmPlatform _selectedLlmPlatform = LlmPlatform.geeknow;

  // 图片配置
  final TextEditingController _imageApiController = TextEditingController();
  final TextEditingController _imageUrlController = TextEditingController();
  late String _selectedImageModel;
  ImagePlatform _selectedImagePlatform = ImagePlatform.geeknow;

  // 视频配置
  final TextEditingController _videoApiController = TextEditingController();
  final TextEditingController _videoUrlController = TextEditingController();
  late String _selectedVideoModel;
  VideoPlatform _selectedVideoPlatform = VideoPlatform.geeknow;
  late int _selectedVideoSeconds;

  // API KEY 显示/隐藏状态
  bool _showLlmApiKey = false;
  bool _showImageApiKey = false;
  bool _showVideoApiKey = false;

  // 自动保存定时器
  Timer? _saveTimer;

  // 提示词数据（名称 -> 内容）
  Map<String, Map<String, String>> _prompts = {
    'image': {},
    'video': {},
    'character': {},
    'prop': {},
    'scene': {},
  };
  bool _promptsLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    
    // 初始化 LLM 配置
    _llmApiController.text = apiConfigManager.llmApiKey;
    _llmUrlController.text = apiConfigManager.llmBaseUrl;
    _selectedLlmModel = apiConfigManager.llmModel;

    // 初始化图片配置
    _imageApiController.text = apiConfigManager.imageApiKey;
    _imageUrlController.text = apiConfigManager.imageBaseUrl;
    _selectedImageModel = apiConfigManager.imageModel;

    // 初始化视频配置
    _videoApiController.text = apiConfigManager.videoApiKey;
    _videoUrlController.text = apiConfigManager.videoBaseUrl;
    _selectedVideoModel = apiConfigManager.videoModel;
    _selectedVideoSeconds = apiConfigManager.videoSeconds;

    // 加载提示词
    _loadPrompts();
  }

  // 加载提示词
  Future<void> _loadPrompts() async {
    final prefs = await SharedPreferences.getInstance();
    final promptsJson = prefs.getString('prompts');
    
    if (promptsJson != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(promptsJson);
        setState(() {
          _prompts = {
            'image': Map<String, String>.from(decoded['image'] ?? {}),
            'video': Map<String, String>.from(decoded['video'] ?? {}),
            'character': Map<String, String>.from(decoded['character'] ?? {}),
            'prop': Map<String, String>.from(decoded['prop'] ?? {}),
            'scene': Map<String, String>.from(decoded['scene'] ?? {}),
          };
          _promptsLoaded = true;
        });
      } catch (e) {
        print('加载提示词失败: $e');
        setState(() {
          _promptsLoaded = true;
        });
      }
    } else {
      setState(() {
        _promptsLoaded = true;
      });
    }
  }

  // 保存提示词
  Future<void> _savePrompts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('prompts', jsonEncode(_prompts));
    } catch (e) {
      print('保存提示词失败: $e');
    }
  }


  @override
  void dispose() {
    _tabController.dispose();
    _llmApiController.dispose();
    _llmUrlController.dispose();
    _imageApiController.dispose();
    _imageUrlController.dispose();
    _videoApiController.dispose();
    _videoUrlController.dispose();
    _saveTimer?.cancel();
    super.dispose();
  }

  void _saveSettings() {
    // 立即隐藏键盘
    FocusScope.of(context).unfocus();
    
    // 更新内存中的配置（立即生效）
    apiConfigManager.setLlmConfig(
      _llmApiController.text,
      _llmUrlController.text,
      _selectedLlmModel,
    );
    apiConfigManager.setImageConfig(
      _imageApiController.text,
      _imageUrlController.text,
      model: _selectedImageModel,
    );
    apiConfigManager.setVideoConfig(
      _videoApiController.text,
      _videoUrlController.text,
      model: _selectedVideoModel,
      seconds: _selectedVideoSeconds,
    );
    
    // 立即显示成功反馈并关闭页面（不等待磁盘IO）
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('设置已保存'),
        backgroundColor: AnimeColors.miku,
        duration: Duration(seconds: 2),
      ),
    );
    Navigator.pop(context);
    
    // 后台保存到磁盘（非阻塞，已在 setLlmConfig/setImageConfig/setVideoConfig 中调用）
    // saveConfigNonBlocking 会自动在后台完成
  }

  // 自动保存API KEY配置（使用1000ms防抖）
  void _autoSaveApiKey(String type) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1000), () {
      switch (type) {
        case 'llm':
          apiConfigManager.setLlmConfig(
            _llmApiController.text,
            _llmUrlController.text,
            _selectedLlmModel,
          );
          break;
        case 'image':
          apiConfigManager.setImageConfig(
            _imageApiController.text,
            _imageUrlController.text,
            model: _selectedImageModel,
          );
          break;
        case 'video':
          apiConfigManager.setVideoConfig(
            _videoApiController.text,
            _videoUrlController.text,
            model: _selectedVideoModel,
            seconds: _selectedVideoSeconds,
          );
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AnimeColors.darkBg, Color(0xFF0f0f1e), Color(0xFF1a1a2e)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 顶部栏
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                      tooltip: '返回',
                    ),
                    SizedBox(width: 8),
                    Text(
                      '🔧 API 设置',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              // Tab 导航
              Container(
                margin: EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AnimeColors.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AnimeColors.miku, AnimeColors.purple],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                  tabs: [
                    Tab(text: '基础设置'),
                    Tab(text: '图片设置'),
                    Tab(text: '视频设置'),
                    Tab(text: '提示词设置'),
                  ],
                ),
              ),
              SizedBox(height: 16),
              // Tab 内容
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildLlmTab(),
                    _buildImageTab(),
                    _buildVideoTab(),
                    _buildPromptTab(),
                  ],
                ),
              ),
              // 保存按钮
              Padding(
                padding: EdgeInsets.all(16),
                child: _buildSaveButton(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLlmTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: _buildLlmSection(),
    );
  }

  Widget _buildImageTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: _buildImageSection(),
    );
  }

  Widget _buildVideoTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: _buildVideoSection(),
    );
  }

  Widget _buildPromptTab() {
    if (!_promptsLoaded) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(AnimeColors.miku),
        ),
      );
    }

    final promptTypes = [
      ('image', '图片提示词', Icons.image_outlined, AnimeColors.sakura),
      ('video', '视频提示词', Icons.movie_outlined, AnimeColors.miku),
      ('character', '角色提示词', Icons.person_outline, AnimeColors.purple),
      ('prop', '物品提示词', Icons.inventory_2_outlined, AnimeColors.orangeAccent),
      ('scene', '场景提示词', Icons.landscape_outlined, AnimeColors.blue),
    ];

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: promptTypes.map((type) {
          final (key, label, icon, color) = type;
          final count = _prompts[key]?.length ?? 0;
          return _buildPromptCard(key, label, icon, color, count);
        }).toList(),
      ),
    );
  }

  Widget _buildPromptCard(String key, String label, IconData icon, Color color, int count) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PromptDetailPage(
              promptKey: key,
              promptLabel: label,
              promptIcon: icon,
              promptColor: color,
              prompts: _prompts[key] ?? {},
              onSave: (Map<String, String> updatedPrompts) async {
                setState(() {
                  _prompts[key] = updatedPrompts;
                });
                await _savePrompts();
                setState(() {}); // 刷新计数
              },
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            width: 200,
            decoration: BoxDecoration(
              color: AnimeColors.glassBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
            ),
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withOpacity(0.6)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                SizedBox(height: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count 个提示词',
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLlmSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 大语言模型设置卡片
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              decoration: BoxDecoration(
                color: AnimeColors.glassBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
              ),
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AnimeColors.miku, AnimeColors.purple],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.chat_bubble_outline, color: Colors.white),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '大语言模型设置',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontSize: 17,
                              ),
                            ),
                            Text(
                              '用于故事生成和分镜生成',
                              style: TextStyle(fontSize: 12, color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),
                  // 平台选择
                  _buildLlmPlatformSelector(),
                  SizedBox(height: 16),
                  // API URL
                  _buildApiKeyField(_llmUrlController, 'API URL', 'https://api.geeknow.ai/v1'),
                  SizedBox(height: 16),
                  // API Key
                  _buildApiKeyFieldWithVisibility(
                    _llmApiController,
                    'API Key',
                    'sk-...',
                    _showLlmApiKey,
                    () => setState(() => _showLlmApiKey = !_showLlmApiKey),
                    'llm',
                  ),
                  SizedBox(height: 16),
                  // 模型选择
                  _buildModelSelector(
                    '模型选择',
                    apiConfigManager.getLlmModels(),
                    _selectedLlmModel,
                    (value) => setState(() => _selectedLlmModel = value!),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLlmPlatformSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '大语言模型平台',
          style: TextStyle(color: AnimeColors.miku, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AnimeColors.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButton<LlmPlatform>(
            value: _selectedLlmPlatform,
            isExpanded: true,
            dropdownColor: AnimeColors.cardBg,
            style: TextStyle(color: Colors.white, fontSize: 14),
            underline: SizedBox.shrink(),
            items: LlmPlatform.values.map((platform) {
              return DropdownMenuItem(
                value: platform,
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_outlined,
                      color: AnimeColors.miku,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(platform.displayName),
                  ],
                ),
              );
            }).toList(),
            onChanged: _onLlmPlatformChanged,
          ),
        ),
      ],
    );
  }

  void _onLlmPlatformChanged(LlmPlatform? platform) {
    if (platform != null) {
      setState(() {
        _selectedLlmPlatform = platform;
      });
    }
  }

  Widget _buildImageSection() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: AnimeColors.glassBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
          ),
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AnimeColors.sakura, AnimeColors.purple],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.image_outlined, color: Colors.white),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '图片生成设置',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          '用于分镜图片生成',
                          style: TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              // 平台选择
              _buildImagePlatformSelector(),
              SizedBox(height: 16),
              // API URL
              _buildApiKeyField(_imageUrlController, 'API URL', 'https://api.geeknow.ai/v1'),
              SizedBox(height: 16),
              // API Key
              _buildApiKeyFieldWithVisibility(
                _imageApiController,
                'API Key',
                'sk-...',
                _showImageApiKey,
                () => setState(() => _showImageApiKey = !_showImageApiKey),
                'image',
              ),
              SizedBox(height: 16),
              // 模型选择
              _buildModelSelector(
                '模型选择',
                apiConfigManager.getImageModels(),
                _selectedImageModel,
                (value) => setState(() => _selectedImageModel = value!),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePlatformSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '图片生成平台',
          style: TextStyle(color: AnimeColors.sakura, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AnimeColors.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButton<ImagePlatform>(
            value: _selectedImagePlatform,
            isExpanded: true,
            dropdownColor: AnimeColors.cardBg,
            style: TextStyle(color: Colors.white, fontSize: 14),
            underline: SizedBox.shrink(),
            items: ImagePlatform.values.map((platform) {
              return DropdownMenuItem(
                value: platform,
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_outlined,
                      color: AnimeColors.sakura,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(platform.displayName),
                  ],
                ),
              );
            }).toList(),
            onChanged: _onImagePlatformChanged,
          ),
        ),
      ],
    );
  }

  void _onImagePlatformChanged(ImagePlatform? platform) {
    if (platform != null) {
      setState(() {
        _selectedImagePlatform = platform;
      });
    }
  }

  Widget _buildVideoSection() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: AnimeColors.glassBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
          ),
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AnimeColors.blue, AnimeColors.miku],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.movie_outlined, color: Colors.white),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '视频生成设置',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          '用于分镜视频生成',
                          style: TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              // 平台选择
              _buildVideoPlatformSelector(),
              SizedBox(height: 16),
              // API URL
              _buildApiKeyField(_videoUrlController, 'API URL', 'https://api.geeknow.ai/v1'),
              SizedBox(height: 16),
              // API Key
              _buildApiKeyFieldWithVisibility(
                _videoApiController,
                'API Key',
                'sk-...',
                _showVideoApiKey,
                () => setState(() => _showVideoApiKey = !_showVideoApiKey),
                'video',
              ),
              SizedBox(height: 16),
              // 模型选择
              _buildModelSelector(
                '模型选择',
                apiConfigManager.getVideoModels(),
                _selectedVideoModel,
                (value) => setState(() => _selectedVideoModel = value!),
              ),
              SizedBox(height: 16),
              // 时长选择
              _buildVideoSecondsSelector(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoSecondsSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '视频时长',
          style: TextStyle(color: AnimeColors.miku, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AnimeColors.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButton<int>(
            value: _selectedVideoSeconds,
            isExpanded: true,
            dropdownColor: AnimeColors.cardBg,
            style: TextStyle(color: Colors.white, fontSize: 14),
            underline: SizedBox.shrink(),
            items: apiConfigManager.getVideoSecondsOptions().map((seconds) {
              return DropdownMenuItem(
                value: seconds,
                child: Text('${seconds}秒'),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedVideoSeconds = value;
                });
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVideoPlatformSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '视频生成平台',
          style: TextStyle(color: AnimeColors.blue, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AnimeColors.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButton<VideoPlatform>(
            value: _selectedVideoPlatform,
            isExpanded: true,
            dropdownColor: AnimeColors.cardBg,
            style: TextStyle(color: Colors.white, fontSize: 14),
            underline: SizedBox.shrink(),
            items: VideoPlatform.values.map((platform) {
              return DropdownMenuItem(
                value: platform,
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_outlined,
                      color: AnimeColors.blue,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(platform.displayName),
                  ],
                ),
              );
            }).toList(),
            onChanged: _onVideoPlatformChanged,
          ),
        ),
      ],
    );
  }

  void _onVideoPlatformChanged(VideoPlatform? platform) {
    if (platform != null) {
      setState(() {
        _selectedVideoPlatform = platform;
      });
    }
  }

  Widget _buildApiKeyField(TextEditingController controller, String label, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: AnimeColors.miku, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: true,
          readOnly: false,
          enableInteractiveSelection: true,
          style: TextStyle(color: Colors.white70, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white10),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white10),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AnimeColors.miku, width: 2),
            ),
            filled: true,
            fillColor: AnimeColors.cardBg,
            contentPadding: EdgeInsets.all(14),
          ),
        ),
      ],
    );
  }

  // 构建带密码隐藏功能的API KEY输入框
  Widget _buildApiKeyFieldWithVisibility(
    TextEditingController controller,
    String label,
    String hint,
    bool isVisible,
    VoidCallback onToggleVisibility,
    String saveType,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: AnimeColors.miku, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: true,
          readOnly: false,
          enableInteractiveSelection: true,
          obscureText: !isVisible,
          style: TextStyle(color: Colors.white70, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white10),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white10),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AnimeColors.miku, width: 2),
            ),
            filled: true,
            fillColor: AnimeColors.cardBg,
            contentPadding: EdgeInsets.only(left: 14, right: 50, top: 14, bottom: 14),
            suffixIcon: IconButton(
              icon: Icon(
                isVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: Colors.white54,
                size: 20,
              ),
              onPressed: onToggleVisibility,
            ),
          ),
          onChanged: (value) {
            _autoSaveApiKey(saveType);
          },
        ),
      ],
    );
  }

  Widget _buildModelSelector(
    String label,
    List<String> options,
    String currentValue,
    void Function(String?) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: AnimeColors.miku, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AnimeColors.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButton<String>(
            value: currentValue,
            isExpanded: true,
            dropdownColor: AnimeColors.cardBg,
            style: TextStyle(color: Colors.white, fontSize: 14),
            underline: SizedBox.shrink(),
            items: options.map((value) {
              return DropdownMenuItem(value: value, child: Text(value));
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _saveSettings,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: EdgeInsets.zero,
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AnimeColors.miku, AnimeColors.purple],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.save, size: 20),
                SizedBox(width: 8),
                Text(
                  '保存设置',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== 绘图空间 Widget ====================
class DrawingSpaceWidget extends StatefulWidget {
  const DrawingSpaceWidget({super.key});

  @override
  State<DrawingSpaceWidget> createState() => _DrawingSpaceWidgetState();
}

class _DrawingSpaceWidgetState extends State<DrawingSpaceWidget> {
  final TextEditingController _promptController = TextEditingController();
  List<String> _referenceImages = []; // Base64或文件路径
  int _selectedSizeIndex = 0;
  int _selectedQualityIndex = 0;
  bool _isGenerating = false;
  double _promptHeight = 100; // 可调整的提示词框高度
  int _batchCount = 1; // 批量生成数量
  int _generatingProgress = 0; // 批量生成进度

  // 使用全局的生成图片列表
  List<String> get _generatedImages => generatedMediaManager.generatedImages;
  
  // 防抖定时器，避免频繁的setState调用
  Timer? _mediaChangeDebounceTimer;

  @override
  void initState() {
    super.initState();
    logService.action('进入绘图空间');
    // 监听生成媒体变化
    generatedMediaManager.addListener(_onMediaChanged);
  }

  void _onMediaChanged() {
    if (!mounted) return;
    
    // 使用防抖，避免频繁的setState调用导致卡顿
    _mediaChangeDebounceTimer?.cancel();
    _mediaChangeDebounceTimer = Timer(Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _mediaChangeDebounceTimer?.cancel();
    generatedMediaManager.removeListener(_onMediaChanged);
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _pickReferenceImage() async {
    if (_referenceImages.length >= 9) {
      logService.warn('参考图已达最大数量(9张)');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('最多只能添加9张参考图'), backgroundColor: AnimeColors.sakura),
      );
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );

      if (result != null) {
        final remaining = 9 - _referenceImages.length;
        final filesToAdd = result.files.take(remaining);
        
        setState(() {
          for (var file in filesToAdd) {
            if (file.path != null) {
              _referenceImages.add(file.path!);
            }
          }
        });
        logService.action('添加参考图', details: '添加了${filesToAdd.length}张参考图');
      }
    } catch (e) {
      logService.error('选择参考图失败', details: e.toString());
    }
  }

  void _removeReferenceImage(int index) {
    setState(() {
      _referenceImages.removeAt(index);
    });
    logService.action('移除参考图');
  }

  Future<void> _generateImage() async {
    if (_promptController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请输入提示词'), backgroundColor: AnimeColors.sakura),
      );
      return;
    }

    if (!apiConfigManager.hasImageConfig) {
      logService.error('未配置图片API');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在设置中配置图片生成API'), backgroundColor: AnimeColors.sakura),
      );
      return;
    }

    // 防止重复生成
    if (_isGenerating) {
      logService.warn('图片生成正在进行中，请勿重复操作');
      return;
    }

    // 立即更新UI状态
    if (mounted) {
      setState(() {
        _isGenerating = true;
        _generatingProgress = 0;
      });
    }
    
    logService.action('开始批量生成图片', details: '数量: $_batchCount, 提示词: ${_promptController.text}');

    // 异步执行，并确保即使出错也会重置状态
    _generateImagesInBackground().catchError((error) {
      logService.error('生成图片异常', details: error.toString());
      // 确保状态重置
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _generatingProgress = 0;
        });
      }
    });
  }

  // 在后台执行生成任务
  Future<void> _generateImagesInBackground() async {
    // 保存当前的引用，避免在异步操作中使用可能已变化的值
    final apiService = apiConfigManager.createApiService();
    final selectedSize = imageSizes[_selectedSizeIndex];
    final quality = imageQualities[_selectedQualityIndex];
    final prompt = _promptController.text;
    final model = apiConfigManager.imageModel;
    final batchCount = _batchCount;
    final referenceImages = List<String>.from(_referenceImages); // 复制一份
    
    logService.info('生成参数', details: '尺寸: ${selectedSize.width}x${selectedSize.height}, 模型: $model');
    
    int successCount = 0;
    int failCount = 0;
    
    try {
      // 批量生成图片
      for (int i = 0; i < batchCount; i++) {
        // 检查组件是否已挂载
        if (!mounted) {
          logService.warn('组件已卸载，停止生成');
          break;
        }
        
        // 更新进度
        if (mounted) {
          setState(() {
            _generatingProgress = i + 1;
          });
        }
        
        try {
          logService.info('开始生成第 ${i + 1}/$batchCount 张图片');
          
          // 调用图片生成API
          final response = await apiService.generateImage(
            prompt: prompt,
            model: model,
            width: selectedSize.width,
            height: selectedSize.height,
            quality: quality == '标准' ? 'standard' : 'hd',
            referenceImages: referenceImages.isNotEmpty ? referenceImages : null,
          );

          logService.info('API返回成功，准备添加到列表');
          
          // 给 UI 线程喘息（在处理返回数据前）
          await Future.delayed(Duration(milliseconds: 200));
          
          // 添加图片到列表（不等待，避免阻塞）
          generatedMediaManager.addImage(response.imageUrl);
          
          logService.info('图片已添加到列表');
          
          successCount++;
          logService.info('图片生成成功 ${i + 1}/$batchCount', details: '尺寸: ${selectedSize.width}x${selectedSize.height}');
        } catch (e) {
          failCount++;
          logService.error('图片生成失败 ${i + 1}/$batchCount', details: e.toString());
        }
        
        // 较长延迟，确保UI有足够时间更新
        await Future.delayed(Duration(milliseconds: 500));
      }
      
      // 显示结果
      if (mounted) {
        if (failCount == 0 && successCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('全部 $successCount 张图片生成成功!'), backgroundColor: AnimeColors.miku),
          );
        } else if (successCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$successCount 张成功，$failCount 张失败'), backgroundColor: AnimeColors.orangeAccent),
          );
        } else if (failCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('全部 $failCount 张图片生成失败'), backgroundColor: AnimeColors.sakura),
          );
        }
      }
    } catch (e) {
      logService.error('批量生成图片失败', details: e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败: $e'), backgroundColor: AnimeColors.sakura),
        );
      }
    } finally {
      // 确保状态正确重置（无条件重置）
      logService.info('生成任务结束，重置状态');
      _isGenerating = false;
      _generatingProgress = 0;
      if (mounted) {
        setState(() {});
      }
      logService.info('状态已重置', details: '_isGenerating: $_isGenerating');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：参考图和提示词（固定宽度400）
          SizedBox(
            width: 400,
            child: _buildLeftPanel(),
          ),
          SizedBox(width: 20),
          // 右侧：生成结果（占据剩余空间）
          Expanded(
            child: _buildRightPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftPanel() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 参考图区域
          _buildSectionCard(
          title: '参考图',
          subtitle: '最多可添加9张 (${_referenceImages.length}/9)',
          icon: Icons.image_outlined,
          color: AnimeColors.sakura,
          child: Column(
            children: [
              // 参考图网格
              Container(
                height: 180,
                child: _referenceImages.isEmpty
                    ? _buildAddImagePlaceholder()
                    : GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: _referenceImages.length + (_referenceImages.length < 9 ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _referenceImages.length) {
                            return _buildAddImageButton();
                          }
                          return _buildReferenceImageItem(index);
                        },
                      ),
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
        // 提示词区域（可调整高度）
        _buildSectionCard(
          title: '提示词',
          subtitle: '描述你想要生成的图片（拖动底部调整大小）',
          icon: Icons.edit_outlined,
          color: AnimeColors.purple,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                  height: _promptHeight,
                  child: TextField(
                    controller: _promptController,
                    maxLines: null,
                    minLines: 3,
                    textAlignVertical: TextAlignVertical.top,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '例如：一个穿着蓝色和服的少女，站在樱花树下，阳光透过花瓣洒落...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white10),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AnimeColors.miku, width: 2),
                    ),
                    filled: true,
                    fillColor: AnimeColors.darkBg,
                    contentPadding: EdgeInsets.all(14),
                  ),
                ),
              ),
              GestureDetector(
                onVerticalDragUpdate: (details) {
                  setState(() {
                    _promptHeight = (_promptHeight + details.delta.dy).clamp(60.0, 300.0);
                  });
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: Container(
                    height: 16,
                    width: double.infinity,
                    alignment: Alignment.center,
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
        // 设置区域
        _buildSectionCard(
          title: '生成设置',
          subtitle: '选择尺寸和画质',
          icon: Icons.tune_outlined,
          color: AnimeColors.miku,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('图片比例', style: TextStyle(color: Colors.white60, fontSize: 12)),
              SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(imageSizes.length, (index) {
                    final size = imageSizes[index];
                    final isSelected = _selectedSizeIndex == index;
                    return Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: InkWell(
                        onTap: () {
                          setState(() => _selectedSizeIndex = index);
                          logService.action('选择图片尺寸', details: size.display);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? AnimeColors.miku.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? AnimeColors.miku : Colors.white10,
                            ),
                          ),
                          child: Text(
                            size.ratio,
                            style: TextStyle(
                              color: isSelected ? AnimeColors.miku : Colors.white60,
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              SizedBox(height: 16),
              Text('画质选择', style: TextStyle(color: Colors.white60, fontSize: 12)),
              SizedBox(height: 8),
              Row(
                children: List.generate(imageQualities.length, (index) {
                  final quality = imageQualities[index];
                  final isSelected = _selectedQualityIndex == index;
                  return Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () {
                        setState(() => _selectedQualityIndex = index);
                        logService.action('选择画质', details: quality);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 65, // 固定宽度，防止布局改变
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? LinearGradient(colors: [AnimeColors.miku, AnimeColors.purple])
                              : null,
                          color: isSelected ? null : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isSelected ? Colors.transparent : Colors.white10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          quality,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white60,
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              SizedBox(height: 16),
              // 批量生成数量
              Row(
                children: [
                  Text('批量生成', style: TextStyle(color: Colors.white60, fontSize: 12)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.remove_circle_outline, color: _batchCount > 1 ? AnimeColors.miku : Colors.white24),
                          onPressed: _batchCount > 1 ? () {
                            setState(() => _batchCount--);
                            logService.action('调整批量生成数量', details: '$_batchCount');
                          } : null,
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(),
                        ),
                        SizedBox(width: 8),
                        Container(
                          width: 60,
                          padding: EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: AnimeColors.miku.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AnimeColors.miku.withOpacity(0.3)),
                          ),
                          child: Text(
                            '$_batchCount',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AnimeColors.miku,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        IconButton(
                          icon: Icon(Icons.add_circle_outline, color: _batchCount < 50 ? AnimeColors.miku : Colors.white24),
                          onPressed: _batchCount < 50 ? () {
                            setState(() => _batchCount++);
                            logService.action('调整批量生成数量', details: '$_batchCount');
                          } : null,
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(),
                        ),
                        SizedBox(width: 8),
                        Text('张图片', style: TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 20),
        // 生成按钮（统一设计，与视频空间按钮样式一致）
        SizedBox(
          width: double.infinity,
          height: 52,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isGenerating ? null : _generateImage,
              borderRadius: BorderRadius.circular(26), // 更圆润的圆角（高度的一半）
              // 增强按压效果
              splashColor: Colors.white.withOpacity(0.3),
              highlightColor: Colors.white.withOpacity(0.15),
              child: Container(
                decoration: BoxDecoration(
                  gradient: _isGenerating
                      ? null
                      : LinearGradient(colors: [AnimeColors.miku, AnimeColors.purple]), // 统一渐变：左侧青蓝色，右侧淡紫色
                  color: _isGenerating ? Colors.grey : null,
                  borderRadius: BorderRadius.circular(26), // 更圆润的圆角
                  boxShadow: _isGenerating
                      ? null
                      : [
                          BoxShadow(
                            color: AnimeColors.purple.withOpacity(0.3),
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                ),
                alignment: Alignment.center,
                child: _isGenerating
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                          SizedBox(width: 12),
                          Text(
                            '生成中 $_generatingProgress/$_batchCount...',
                            style: TextStyle(
                              fontSize: 17, // 字体更明显
                              fontWeight: FontWeight.w700, // 加粗
                              color: Colors.white,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.auto_awesome, size: 22, color: Colors.white), // 统一图标样式
                          SizedBox(width: 10),
                          Text(
                            _batchCount > 1 ? '批量生成 $_batchCount 张' : '生成图片',
                            style: TextStyle(
                              fontSize: 18, // 字体更明显（从17增加到18，比生成视频更突出）
                              fontWeight: FontWeight.w700, // 加粗
                              color: Colors.white, // 明确指定白色
                              letterSpacing: 0.5, // 增加字间距，使文字更清晰
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    return _buildSectionCard(
      title: '生成结果',
      subtitle: '已生成 ${_generatedImages.length} 张图片',
      icon: Icons.photo_library_outlined,
      color: AnimeColors.blue,
      expanded: true,
      actionButton: _generatedImages.isNotEmpty
          ? IconButton(
              icon: Icon(Icons.clear_all, color: AnimeColors.sakura, size: 20),
              tooltip: '清空所有图片',
              onPressed: () {
                generatedMediaManager.clearImages();
                logService.action('清空所有生成图片');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已清空所有图片'), backgroundColor: AnimeColors.miku),
                );
              },
            )
          : null,
      child: _generatedImages.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image_outlined, size: 80, color: Colors.white24),
                  SizedBox(height: 20),
                  Text('生成的图片将显示在这里', style: TextStyle(color: Colors.white38, fontSize: 14)),
                ],
              ),
            )
          : GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _generatedImages.length,
              itemBuilder: (context, index) {
                return _buildGeneratedImageItem(_generatedImages[index]);
              },
            ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Widget child,
    bool expanded = false,
    Widget? actionButton,
  }) {
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AnimeColors.glassBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                        Text(subtitle, style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                  ),
                  if (actionButton != null) actionButton,
                ],
              ),
              SizedBox(height: 14),
              expanded ? Expanded(child: child) : child,
            ],
          ),
        ),
      ),
    );
    return expanded ? Expanded(child: content) : content;
  }

  Widget _buildAddImagePlaceholder() {
    return InkWell(
      onTap: _pickReferenceImage,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1), style: BorderStyle.solid),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_photo_alternate_outlined, size: 40, color: Colors.white38),
              SizedBox(height: 8),
              Text('点击添加参考图', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddImageButton() {
    return InkWell(
      onTap: _pickReferenceImage,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Center(
          child: Icon(Icons.add, color: Colors.white38, size: 28),
        ),
      ),
    );
  }

  Widget _buildReferenceImageItem(int index) {
    return Stack(
      children: [
        InkWell(
          onTap: () => showImageViewer(context, imagePath: _referenceImages[index]),
          borderRadius: BorderRadius.circular(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(_referenceImages[index]),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => Container(
                color: AnimeColors.cardBg,
                child: Icon(Icons.broken_image, color: Colors.white38),
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: InkWell(
            onTap: () => _removeReferenceImage(index),
            child: Container(
              padding: EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGeneratedImageItem(String imageUrl) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          InkWell(
            onTap: () => showImageViewer(context, imageUrl: imageUrl),
            child: buildImageWidget(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                        : null,
                    color: AnimeColors.miku,
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                color: AnimeColors.cardBg,
                child: Center(child: Icon(Icons.broken_image, color: Colors.white38, size: 40)),
              ),
            ),
          ),
          // 删除按钮（右上角）
          Positioned(
            top: 8,
            right: 8,
            child: InkWell(
              onTap: () {
                generatedMediaManager.removeImage(imageUrl);
                logService.action('删除生成图片', details: imageUrl);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已删除图片'), backgroundColor: AnimeColors.miku),
                );
              },
              child: Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
          // 复制按钮（右下角）
          Positioned(
            bottom: 8,
            right: 8,
            child: _buildImageActionButton(Icons.content_copy, '复制图片', () async {
              await _copyImageToClipboard(imageUrl);
            }),
          ),
        ],
      ),
    );
  }

  Future<void> _copyImageToClipboard(String imageUrl) async {
    try {
      List<int> imageBytes;
      
      // 检查是否是base64数据URI格式
      if (imageUrl.startsWith('data:image/')) {
        // 解析base64数据
        final base64Index = imageUrl.indexOf('base64,');
        if (base64Index == -1) {
          throw '无效的Base64数据URI';
        }
        final base64Data = imageUrl.substring(base64Index + 7);
        imageBytes = base64Decode(base64Data);
      } else {
        // 如果是HTTP URL，下载图片
        final response = await http.get(Uri.parse(imageUrl));
        if (response.statusCode != 200) {
          throw '下载图片失败: ${response.statusCode}';
        }
        imageBytes = response.bodyBytes;
      }
      
      // 将图片数据复制到剪贴板
      // Flutter的Clipboard只支持文本，需要使用平台特定的方法复制图片
      // 这里先将图片保存到临时文件，然后复制路径
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/temp_image_${DateTime.now().millisecondsSinceEpoch}.png');
      await tempFile.writeAsBytes(imageBytes);
      
      // 在Windows上，使用PowerShell将图片复制到剪贴板
      if (Platform.isWindows) {
        await Process.run('powershell', [
          '-command',
          'Set-Clipboard',
          '-Path',
          tempFile.path
        ]);
        logService.action('复制图片到剪贴板');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片已复制到剪贴板'), backgroundColor: AnimeColors.miku),
        );
      } else {
        // 其他平台，复制文件路径
        await Clipboard.setData(ClipboardData(text: tempFile.path));
        logService.action('复制图片路径', details: tempFile.path);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片路径已复制: ${tempFile.path}'), backgroundColor: AnimeColors.miku),
        );
      }
    } catch (e) {
      logService.error('复制图片失败', details: e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('复制失败: $e'), backgroundColor: AnimeColors.sakura),
      );
    }
  }

  Widget _buildImageActionButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      ),
    );
  }
}

// ==================== 视频空间 Widget ====================
class VideoSpaceWidget extends StatefulWidget {
  const VideoSpaceWidget({super.key});

  @override
  State<VideoSpaceWidget> createState() => _VideoSpaceWidgetState();
}

class _VideoSpaceWidgetState extends State<VideoSpaceWidget> {
  String? _selectedImagePath;
  String? _selectedMaterialName; // 保存选中的素材库图片名称
  bool _isFromMaterialLibrary = false; // 标记是否来自素材库
  int _selectedSizeIndex = 0;
  int _selectedDurationIndex = 1;
  final TextEditingController _promptController = TextEditingController();
  double _promptHeight = 100; // 可调整的提示词框高度
  int _batchCount = 1; // 批量生成数量
  
  @override
  void initState() {
    super.initState();
    logService.action('进入视频空间');
  }

  @override
  void dispose() {
    _promptController.dispose();
    // 注意：不再取消轮询定时器，让它在后台继续运行
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedImagePath = result.files.single.path;
          _selectedMaterialName = null; // 清空素材库名称
          _isFromMaterialLibrary = false; // 标记为本地文件
        });
        logService.action('选择视频起始图片');
      }
    } catch (e) {
      logService.error('选择图片失败', details: e.toString());
    }
  }

  void _showMaterialLibraryPicker() {
    logService.action('打开素材库选择');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AnimeColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.perm_media_outlined, color: AnimeColors.miku),
            SizedBox(width: 8),
            Text('选择素材', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Container(
          width: 600,
          height: 400,
          child: FutureBuilder(
            future: _loadAllMaterials(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator(color: AnimeColors.miku));
              }
              
              final allMaterials = snapshot.data ?? [];
              
              if (allMaterials.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open_outlined, size: 60, color: Colors.white24),
                      SizedBox(height: 16),
                      Text('素材库为空', style: TextStyle(color: Colors.white54)),
                      SizedBox(height: 8),
                      Text('请先在素材库中添加素材', style: TextStyle(color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                );
              }
              
              return GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemCount: allMaterials.length,
                itemBuilder: (context, index) {
                  final material = allMaterials[index];
                  final materialName = material['name'] ?? '未命名';
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedImagePath = material['path'];
                        _selectedMaterialName = materialName; // 保存素材库图片名称
                        _isFromMaterialLibrary = true; // 标记为素材库
                      });
                      logService.action('从素材库选择图片', details: materialName);
                      Navigator.pop(context);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AnimeColors.darkBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                              child: InkWell(
                                onTap: material['path'] != null 
                                    ? () => showImageViewer(context, imagePath: material['path'])
                                    : null,
                                child: material['path'] != null
                                    ? Image.file(
                                        File(material['path']!),
                                        fit: BoxFit.contain,
                                        width: double.infinity,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: AnimeColors.purple.withOpacity(0.2),
                                          child: Icon(Icons.image_outlined, color: Colors.white38, size: 32),
                                        ),
                                      )
                                    : Container(
                                        color: AnimeColors.purple.withOpacity(0.2),
                                        child: Icon(Icons.image_outlined, color: Colors.white38, size: 32),
                                      ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: SelectableText(
                                    materialName,
                                    style: TextStyle(color: Colors.white70, fontSize: 11),
                                    maxLines: 1,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Tooltip(
                                  message: '复制名称',
                                  child: InkWell(
                                    onTap: () {
                                      Clipboard.setData(ClipboardData(text: materialName));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('已复制: $materialName'),
                                          backgroundColor: AnimeColors.miku,
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    child: Icon(Icons.copy, size: 14, color: Colors.white54),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, String>>> _loadAllMaterials() async {
    final List<Map<String, String>> allMaterials = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 加载角色素材
      final charJson = prefs.getString('character_materials');
      if (charJson != null) {
        final decoded = jsonDecode(charJson) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          final materials = (value as List).map((e) => Map<String, String>.from(e)).toList();
          allMaterials.addAll(materials);
        });
      }
      
      // 加载场景素材
      final sceneJson = prefs.getString('scene_materials');
      if (sceneJson != null) {
        final materials = (jsonDecode(sceneJson) as List).map((e) => Map<String, String>.from(e)).toList();
        allMaterials.addAll(materials);
      }
      
      // 加载物品素材
      final propJson = prefs.getString('prop_materials');
      if (propJson != null) {
        final materials = (jsonDecode(propJson) as List).map((e) => Map<String, String>.from(e)).toList();
        allMaterials.addAll(materials);
      }
    } catch (e) {
      logService.error('加载素材失败', details: e.toString());
    }
    return allMaterials;
  }

  Future<void> _generateVideo() async {
    if (_selectedImagePath == null && _promptController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请上传图片或输入提示词'), backgroundColor: AnimeColors.sakura),
      );
      return;
    }

    if (!apiConfigManager.hasVideoConfig) {
      logService.error('未配置视频API');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先在设置中配置视频生成API'), backgroundColor: AnimeColors.sakura),
      );
      return;
    }
    
    logService.action('开始批量生成视频', details: '数量: $_batchCount');

    try {
      final apiService = apiConfigManager.createApiService();
      final selectedSize = videoSizes[_selectedSizeIndex];
      final durationText = videoDurations[_selectedDurationIndex];
      final seconds = int.parse(durationText.replaceAll('秒', ''));
      
      // CRITICAL: 先为所有任务创建占位符，确保UI立即反馈
      final List<String> tempTaskIds = [];
      for (int i = 0; i < _batchCount; i++) {
        final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}_$i';
        tempTaskIds.add(tempId);
        // 立即添加占位符任务，确保右边视频区域立即显示
        videoTaskManager.addTask(
          tempId,
          prompt: _promptController.text,
          imagePath: _selectedImagePath,
        );
      }
      
      // 显示成功提示（占位符已创建）
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已提交 $_batchCount 个视频生成任务，正在后台处理...'),
          backgroundColor: AnimeColors.miku,
          duration: Duration(seconds: 3),
        ),
      );
      
      // 批量生成视频（异步执行，不阻塞UI）
      int failCount = 0;
      
      for (int i = 0; i < _batchCount; i++) {
        final tempTaskId = tempTaskIds[i];
        final taskIndex = i;
        // 异步执行，不阻塞UI
        Future(() async {
          try {
            // 如果选择的是素材库图片，使用characterUrl传递图片名称
            // 否则使用inputReference传递图片文件
            String? characterUrl;
            File? inputReference;
            
            if (_selectedImagePath != null) {
              if (_isFromMaterialLibrary && _selectedMaterialName != null) {
                // 来自素材库，使用characterUrl传递名称
                characterUrl = _selectedMaterialName;
                print('[VideoSpace] 使用素材库图片名称: $characterUrl');
              } else {
                // 本地文件，使用inputReference传递文件
                inputReference = File(_selectedImagePath!);
                print('[VideoSpace] 使用本地图片文件: ${inputReference.path}');
              }
            }
            
            final response = await apiService.createVideo(
              model: apiConfigManager.videoModel,
              prompt: _promptController.text,
              size: '${selectedSize.width}x${selectedSize.height}',
              seconds: seconds,
              inputReference: inputReference,
              characterUrl: characterUrl, // 如果来自素材库，传递图片名称
            );
            
            // CRITICAL: 用真实任务ID替换临时占位符
            videoTaskManager.replaceTaskId(tempTaskId, response.id);
            
            logService.info('视频生成任务已提交 ${taskIndex + 1}/$_batchCount', details: '任务ID: ${response.id}');
          } catch (e) {
            logService.error('提交视频任务失败', details: e.toString());
            // 如果失败，移除占位符并标记为失败
            videoTaskManager.removeTask(tempTaskId, isFailed: true);
            failCount++;
            
            // 如果所有任务都失败了，显示错误提示
            if (failCount == _batchCount && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('所有视频任务提交失败'),
                  backgroundColor: AnimeColors.sakura,
                  duration: Duration(seconds: 5),
                ),
              );
            }
          }
        });
      }
      
      // 使用全局任务管理器启动轮询
      videoTaskManager.startPolling();
    } catch (e) {
      logService.error('批量生成视频失败', details: e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成失败: $e'), backgroundColor: AnimeColors.sakura),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：设置（固定宽度400）
          SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // 图片上传
                  _buildCard(
                    title: '起始图片',
                    subtitle: '上传图片或从素材库选择',
                    icon: Icons.image_outlined,
                    color: AnimeColors.blue,
                    child: Column(
                      children: [
                        InkWell(
                          onTap: _pickImage,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            height: 180,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                            ),
                                    child: _selectedImagePath != null
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                InkWell(
                                                  onTap: () => showImageViewer(context, imagePath: _selectedImagePath),
                                                  child: Image.file(
                                                    File(_selectedImagePath!),
                                                    fit: BoxFit.contain,
                                                  ),
                                                ),
                                                // 显示素材库名称（如果来自素材库）
                                                if (_isFromMaterialLibrary && _selectedMaterialName != null)
                                                  Positioned(
                                                    bottom: 8,
                                                    left: 8,
                                                    right: 8,
                                                    child: Container(
                                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.black.withOpacity(0.7),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Expanded(
                                                            child: SelectableText(
                                                              _selectedMaterialName!,
                                                              style: TextStyle(color: Colors.white, fontSize: 11),
                                                              maxLines: 1,
                                                            ),
                                                          ),
                                                          SizedBox(width: 4),
                                                          Tooltip(
                                                            message: '复制名称',
                                                            child: InkWell(
                                                              onTap: () {
                                                                Clipboard.setData(ClipboardData(text: _selectedMaterialName!));
                                                                ScaffoldMessenger.of(context).showSnackBar(
                                                                  SnackBar(
                                                                    content: Text('已复制: $_selectedMaterialName'),
                                                                    backgroundColor: AnimeColors.miku,
                                                                    duration: Duration(seconds: 2),
                                                                  ),
                                                                );
                                                              },
                                                              child: Icon(Icons.copy, size: 14, color: Colors.white70),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                Positioned(
                                                  top: 8,
                                                  right: 8,
                                                  child: InkWell(
                                                    onTap: () => setState(() {
                                                      _selectedImagePath = null;
                                                      _selectedMaterialName = null;
                                                      _isFromMaterialLibrary = false;
                                                    }),
                                                    child: Container(
                                                      padding: EdgeInsets.all(6),
                                                      decoration: BoxDecoration(
                                                        color: Colors.black54,
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: Icon(Icons.close, color: Colors.white, size: 16),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.cloud_upload_outlined, size: 48, color: Colors.white38),
                                      SizedBox(height: 12),
                                      Text('点击上传图片', style: TextStyle(color: Colors.white54, fontSize: 14)),
                                      SizedBox(height: 4),
                                      Text('或从素材库选择角色', style: TextStyle(color: Colors.white38, fontSize: 12)),
                                    ],
                                  ),
                          ),
                        ),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickImage,
                                icon: Icon(Icons.folder_open, size: 18),
                                label: Text('本地上传'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                  side: BorderSide(color: Colors.white24),
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _showMaterialLibraryPicker,
                                icon: Icon(Icons.perm_media_outlined, size: 18),
                                label: Text('素材库'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AnimeColors.miku,
                                  side: BorderSide(color: AnimeColors.miku.withOpacity(0.5)),
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  // 提示词（可调整高度）
                  _buildCard(
                    title: '视频提示词',
                    subtitle: '描述视频动作和效果（拖动底部调整大小）',
                    icon: Icons.edit_outlined,
                    color: AnimeColors.purple,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // CRITICAL: 使用SizedBox包裹，确保TextField在高度变化时不会重建
                        SizedBox(
                          height: _promptHeight,
                          child: TextField(
                            // 不使用Key，让Flutter自动管理TextField的生命周期，避免不必要的重建
                            controller: _promptController,
                            // CRITICAL: 确保文本框完全可编辑，支持删除、复制、粘贴
                            enabled: true,
                            readOnly: false,
                            enableInteractiveSelection: true, // 允许选择文本，支持复制粘贴
                            enableSuggestions: true, // 启用输入建议
                            autocorrect: true, // 启用自动更正
                            keyboardType: TextInputType.multiline, // 多行输入
                            textInputAction: TextInputAction.newline, // 换行操作
                            maxLines: null, // 不限制最大行数
                            minLines: 3, // 最小3行
                            textAlignVertical: TextAlignVertical.top, // 文本从顶部对齐
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                            // CRITICAL: 不添加任何可能影响编辑的回调（onChanged, onSubmitted, onEditingComplete等）
                            // 这样可以确保文本框始终可编辑，不会被任何逻辑阻止
                            decoration: InputDecoration(
                              hintText: '例如：人物缓缓转身，微风吹动头发...',
                              hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.white10),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.white10),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: AnimeColors.miku, width: 2),
                              ),
                              filled: true,
                              fillColor: AnimeColors.darkBg,
                              contentPadding: EdgeInsets.all(14),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onVerticalDragUpdate: (details) {
                            // CRITICAL: 拖动时只更新高度，使用更温和的更新方式，避免影响TextField的编辑状态
                            // 使用 SchedulerBinding 延迟更新，避免在拖动过程中频繁重建
                            final newHeight = (_promptHeight + details.delta.dy).clamp(60.0, 300.0);
                            if ((newHeight - _promptHeight).abs() > 1.0) { // 只在高度变化超过1像素时更新
                              setState(() {
                                _promptHeight = newHeight;
                              });
                            }
                          },
                          child: MouseRegion(
                            cursor: SystemMouseCursors.resizeUpDown,
                            child: Container(
                              height: 16,
                              width: double.infinity,
                              alignment: Alignment.center,
                              child: Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  // 时长和尺寸
                  _buildCard(
                    title: '视频设置',
                    subtitle: '选择时长和分辨率',
                    icon: Icons.tune_outlined,
                    color: AnimeColors.miku,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('视频时长', style: TextStyle(color: Colors.white60, fontSize: 12)),
                        SizedBox(height: 8),
                        Row(
                          children: List.generate(videoDurations.length, (index) {
                            final isSelected = _selectedDurationIndex == index;
                            return Padding(
                              padding: EdgeInsets.only(right: 10),
                              child: InkWell(
                                onTap: () {
                                  setState(() => _selectedDurationIndex = index);
                                  logService.action('选择视频时长', details: videoDurations[index]);
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: 70, // 固定宽度，防止布局改变
                                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    gradient: isSelected
                                        ? LinearGradient(colors: [AnimeColors.miku, AnimeColors.purple])
                                        : null,
                                    color: isSelected ? null : Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: isSelected ? Colors.transparent : Colors.white10),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    videoDurations[index],
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.white60,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                        SizedBox(height: 16),
                        Text('视频比例', style: TextStyle(color: Colors.white60, fontSize: 12)),
                        SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: List.generate(videoSizes.length, (index) {
                              final size = videoSizes[index];
                              final isSelected = _selectedSizeIndex == index;
                              return Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: InkWell(
                                  onTap: () {
                                    setState(() => _selectedSizeIndex = index);
                                    logService.action('选择视频尺寸', details: size.display);
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isSelected ? AnimeColors.miku.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: isSelected ? AnimeColors.miku : Colors.white10),
                                    ),
                                    child: Text(
                                      size.ratio,
                                      style: TextStyle(
                                        color: isSelected ? AnimeColors.miku : Colors.white60,
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                        SizedBox(height: 16),
                        // 批量生成数量
                        Row(
                          children: [
                            Text('批量生成', style: TextStyle(color: Colors.white60, fontSize: 12)),
                            SizedBox(width: 12),
                            Expanded(
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.remove_circle_outline, color: _batchCount > 1 ? AnimeColors.miku : Colors.white24),
                                    onPressed: _batchCount > 1 ? () {
                                      setState(() => _batchCount--);
                                      logService.action('调整批量生成数量', details: '$_batchCount');
                                    } : null,
                                    padding: EdgeInsets.zero,
                                    constraints: BoxConstraints(),
                                  ),
                                  SizedBox(width: 8),
                                  Container(
                                    width: 60,
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: AnimeColors.miku.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AnimeColors.miku.withOpacity(0.3)),
                                    ),
                                    child: Text(
                                      '$_batchCount',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AnimeColors.miku,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  IconButton(
                                    icon: Icon(Icons.add_circle_outline, color: _batchCount < 50 ? AnimeColors.miku : Colors.white24),
                                    onPressed: _batchCount < 50 ? () {
                                      setState(() => _batchCount++);
                                      logService.action('调整批量生成数量', details: '$_batchCount');
                                    } : null,
                                    padding: EdgeInsets.zero,
                                    constraints: BoxConstraints(),
                                  ),
                                  SizedBox(width: 8),
                                  Text('个视频', style: TextStyle(color: Colors.white60, fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  // 生成按钮（统一设计，与绘图空间按钮样式一致，增强按压效果）
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: Material(
                      color: Colors.transparent,
                      elevation: 0,
                      child: InkWell(
                        onTap: _generateVideo,
                        borderRadius: BorderRadius.circular(26), // 更圆润的圆角（高度的一半）
                        // 增强按压效果：更明显的涟漪和高亮
                        splashColor: Colors.white.withOpacity(0.4),
                        highlightColor: Colors.white.withOpacity(0.2),
                        // 增加按压时的视觉反馈
                        onTapDown: (_) {},
                        onTapUp: (_) {},
                        onTapCancel: () {},
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [AnimeColors.miku, AnimeColors.purple]), // 统一渐变：左侧青蓝色，右侧淡紫色
                            borderRadius: BorderRadius.circular(26), // 更圆润的圆角
                            boxShadow: [
                              BoxShadow(
                                color: AnimeColors.purple.withOpacity(0.3),
                                blurRadius: 8,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.movie_creation, size: 22, color: Colors.white), // 统一图标颜色
                              SizedBox(width: 10),
                              Text(
                                '生成视频',
                                style: TextStyle(
                                  fontSize: 17, // 统一字体大小（从16增加到17）
                                  fontWeight: FontWeight.w700, // 统一字体粗细（从w600增加到w700）
                                  color: Colors.white, // 明确指定白色
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: 20),
          // 右侧：结果（占据剩余空间）
          // 使用独立的 Widget，只监听 VideoTaskManager 和 GeneratedMediaManager 的变化
          Expanded(
            child: _VideoListWidget(),
          ),
        ],
      ),
    );
  }


  // 在 _VideoSpaceWidgetState 中添加 _buildCard 方法供左侧面板使用
  Widget _buildCard({
    required String title,
    required dynamic subtitle, // 可以是 String 或 Widget
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AnimeColors.glassBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                        if (subtitle is String)
                          Text(subtitle, style: TextStyle(color: Colors.white54, fontSize: 11))
                        else if (subtitle is Widget)
                          subtitle,
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }

}

/// 已完成的视频卡片 Widget（独立组件）
class _VideoCardWidget extends StatefulWidget {
  final Map<String, dynamic> video;
  
  const _VideoCardWidget({required this.video});

  @override
  State<_VideoCardWidget> createState() => _VideoCardWidgetState();
}

class _VideoCardWidgetState extends State<_VideoCardWidget> {
  String? _thumbnailPath;
  bool _isLoadingThumbnail = false;
  
  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }
  
  Future<void> _loadThumbnail() async {
    final localPath = widget.video['localPath'] as String?;
    final videoUrl = widget.video['url'] as String?;
    
    // 优先使用本地路径
    String? videoPath = localPath;
    
    // 如果本地路径不存在，尝试下载网络视频（仅用于提取首帧）
    if (videoPath == null || videoPath.isEmpty) {
      if (videoUrl != null && videoUrl.isNotEmpty) {
        // 对于网络视频，暂时不提取首帧（需要先下载，成本较高）
        // 可以后续优化为异步下载后提取
        return;
      }
      return;
    }
    
    if (_isLoadingThumbnail || _thumbnailPath != null) {
      return;
    }
    
    try {
      final file = File(videoPath);
      if (!await file.exists()) {
        return;
      }
      
      // 使用持久化目录存储缩略图（而不是临时目录）
      final appDir = await getApplicationDocumentsDirectory();
      final thumbnailDir = Directory('${appDir.path}${Platform.pathSeparator}xinghe_video_thumbnails');
      if (!await thumbnailDir.exists()) {
        await thumbnailDir.create(recursive: true);
      }
      
      // 使用视频文件路径的哈希值作为缩略图文件名，确保唯一性
      final videoPathHash = videoPath.hashCode.toString();
      final fileStat = await file.stat();
      // 使用文件修改时间作为缓存键的一部分，如果视频文件更新了，缩略图也会更新
      final cacheKey = '${videoPathHash}_${fileStat.modified.millisecondsSinceEpoch}';
      final thumbnailPath = '${thumbnailDir.path}${Platform.pathSeparator}${cacheKey}.jpg';
      
      // 检查缩略图是否已存在
      final thumbnailFile = File(thumbnailPath);
      if (await thumbnailFile.exists()) {
        // 缩略图已存在，直接使用
        if (mounted) {
          setState(() {
            _thumbnailPath = thumbnailPath;
            _isLoadingThumbnail = false;
          });
        }
        return;
      }
      
      // 缩略图不存在，需要生成
      setState(() {
        _isLoadingThumbnail = true;
      });
      
      // 使用 FFmpeg 提取第一帧
      final ffmpegService = FFmpegService();
      
      // 提取第一帧（时间点 0.1 秒，避免黑屏）
      final result = await ffmpegService.extractFrame(
        videoPath: videoPath,
        outputPath: thumbnailPath,
        timeOffset: Duration(milliseconds: 100),
      );
      
      if (mounted && result && await thumbnailFile.exists()) {
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
      print('[VideoCard] 加载视频首帧失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingThumbnail = false;
        });
      }
    }
  }
  
  void _showVideoContextMenu(BuildContext context, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(
          child: Row(
            children: [
              Icon(Icons.play_circle_outline, size: 18, color: AnimeColors.miku),
              SizedBox(width: 8),
              Text('使用播放器播放'),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () => _playVideoInPlayer(widget.video)),
        ),
        PopupMenuItem(
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 18, color: AnimeColors.blue),
              SizedBox(width: 8),
              Text('查看本地视频'),
            ],
          ),
          onTap: () => Future.delayed(Duration.zero, () => _openVideoFolder(widget.video)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showVideoContextMenu(context, details.globalPosition);
      },
      child: Container(
        decoration: BoxDecoration(
          color: AnimeColors.cardBg.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 视频首帧或占位符
            if (_thumbnailPath != null && File(_thumbnailPath!).existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
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
            // 播放按钮
            Center(
              child: InkWell(
                onTap: () => _playVideoInPlayer(widget.video),
                child: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.play_arrow, color: Colors.white, size: 32),
                ),
              ),
            ),
            // 删除按钮
            Positioned(
              top: 8,
              right: 8,
              child: InkWell(
                onTap: () {
                  generatedMediaManager.removeVideo(widget.video);
                  logService.action('删除视频');
                },
                child: Container(
                  padding: EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _playVideoInPlayer(Map<String, dynamic> video) async {
    final localPath = video['localPath'] as String?;
    
    logService.action('使用播放器播放视频');
    
    try {
      // 直接使用本地保存的文件
      if (localPath != null && localPath.isNotEmpty) {
        final localFile = File(localPath);
        if (await localFile.exists()) {
          logService.info('使用本地保存的视频文件', details: localPath);
          
          // 直接使用 Windows 命令打开，最快速
          if (Platform.isWindows) {
            await Process.run('cmd', ['/c', 'start', '', localPath]);
            logService.info('视频播放器已打开', details: localPath);
          } else {
            final fileUri = Uri.file(localPath);
            if (await canLaunchUrl(fileUri)) {
              await launchUrl(fileUri, mode: LaunchMode.externalApplication);
              logService.info('视频播放器已打开', details: localPath);
            }
          }
          return;
        }
      }
      
      // 本地文件不存在，提示用户
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('本地视频文件不存在，请检查自动保存设置'),
            backgroundColor: AnimeColors.sakura,
          ),
        );
      }
    } catch (e) {
      logService.error('打开视频失败', details: e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开视频失败: $e'), backgroundColor: AnimeColors.sakura),
        );
      }
    }
  }
  
  // 打开视频所在文件夹
  Future<void> _openVideoFolder(Map<String, dynamic> video) async {
    final localPath = video['localPath'] as String?;
    
    if (localPath == null || localPath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('本地视频文件不存在'), backgroundColor: AnimeColors.sakura),
        );
      }
      return;
    }
    
    final file = File(localPath);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('本地视频文件不存在'), backgroundColor: AnimeColors.sakura),
        );
      }
      return;
    }
    
    try {
      // 获取文件所在目录
      final directory = file.parent.path;
      
      if (Platform.isWindows) {
        // Windows: 使用 explorer 打开文件夹并选中文件
        await Process.run('explorer', ['/select,', localPath]);
        logService.info('已打开视频所在文件夹', details: directory);
      } else {
        // 其他系统：打开文件夹
        final dirUri = Uri.directory(directory);
        if (await canLaunchUrl(dirUri)) {
          await launchUrl(dirUri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      logService.error('打开文件夹失败', details: e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开文件夹失败: $e'), backgroundColor: AnimeColors.sakura),
        );
      }
    }
  }
}

/// 正在生成的视频卡片 Widget（独立组件）
/// 失败视频卡片组件
class _FailedVideoCardWidget extends StatelessWidget {
  final Map<String, dynamic> task;
  
  const _FailedVideoCardWidget({required this.task});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.5), width: 2),
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Colors.red[300],
                ),
                SizedBox(height: 12),
                Text(
                  '生成失败',
                  style: TextStyle(
                    color: Colors.red[300],
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                if (task['prompt'] != null)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      task['prompt'] as String,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: InkWell(
              onTap: () {
                videoTaskManager.removeFailedTask(task['id'] as String);
                logService.action('删除失败视频占位符', details: task['id']);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已删除失败占位符'), backgroundColor: AnimeColors.miku),
                );
              },
              child: Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GeneratingVideoCardWidget extends StatelessWidget {
  final int progress;
  final String status;
  final String taskId;
  
  const _GeneratingVideoCardWidget({
    required this.progress,
    required this.status,
    required this.taskId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AnimeColors.cardBg.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AnimeColors.miku.withOpacity(0.3)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LinearProgressIndicator(
                value: progress / 100,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(AnimeColors.miku.withOpacity(0.2)),
                minHeight: double.infinity,
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 60,
                  height: 60,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progress / 100,
                        strokeWidth: 4,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(AnimeColors.miku),
                      ),
                      Text(
                        '$progress%',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
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
                    color: AnimeColors.miku.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(color: AnimeColors.miku, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: InkWell(
              onTap: () {
                videoTaskManager.removeTask(taskId);
                logService.action('取消视频生成任务', details: taskId);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已取消任务'), backgroundColor: AnimeColors.miku),
                );
              },
              child: Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 视频列表 Widget（独立组件，只监听 VideoTaskManager 和 GeneratedMediaManager）
/// 
/// 使用 AnimatedBuilder 来只重绘这个 Widget，而不是整个页面
class _VideoListWidget extends StatelessWidget {
  const _VideoListWidget();

  @override
  Widget build(BuildContext context) {
    return _VideoListWidget._buildCard(
      title: '生成结果',
      subtitle: AnimatedBuilder(
        animation: generatedMediaManager,
        builder: (context, _) {
          return Text('已生成 ${generatedMediaManager.generatedVideos.length} 个视频');
        },
      ),
      icon: Icons.video_library_outlined,
      color: AnimeColors.orangeAccent,
      expanded: true,
      actionButton: AnimatedBuilder(
        animation: Listenable.merge([videoTaskManager, generatedMediaManager]),
        builder: (context, _) {
          final videos = generatedMediaManager.generatedVideos;
          final activeTasks = videoTaskManager.activeTasks;
          final failedTasks = videoTaskManager.failedTasks;
          
          // 如果有任何视频（已完成的、正在生成的、或失败的），显示删除按钮
          if (videos.isEmpty && activeTasks.isEmpty && failedTasks.isEmpty) {
            return SizedBox.shrink();
          }
          
          return IconButton(
            icon: Icon(Icons.clear_all, color: AnimeColors.sakura, size: 20),
            tooltip: '清空所有视频',
            onPressed: () {
              generatedMediaManager.clearVideos();
              videoTaskManager.removeAllTasks();
              videoTaskManager.removeAllFailedTasks();
              logService.action('清空所有生成视频');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已清空所有视频'), backgroundColor: AnimeColors.miku),
              );
            },
          );
        },
      ),
      child: AnimatedBuilder(
        animation: Listenable.merge([videoTaskManager, generatedMediaManager]),
        builder: (context, _) {
          final activeTasks = videoTaskManager.activeTasks;
          final failedTasks = videoTaskManager.failedTasks;
          final generatedVideos = generatedMediaManager.generatedVideos;
          
          if (generatedVideos.isEmpty && activeTasks.isEmpty && failedTasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.movie_outlined, size: 80, color: Colors.white24),
                  SizedBox(height: 20),
                  Text('生成的视频将显示在这里', style: TextStyle(color: Colors.white38, fontSize: 14)),
                ],
              ),
            );
          }
          
          return LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 800 ? 3 : 2;
              final totalItems = activeTasks.length + failedTasks.length + generatedVideos.length;
              
              return GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 16 / 9,
                ),
                itemCount: totalItems,
                itemBuilder: (context, index) {
                  // 正在生成的视频任务（显示在最前面）
                  if (index < activeTasks.length) {
                    final task = activeTasks[index];
                    final progress = task['progress'] as int? ?? 0;
                    final status = task['status'] as String? ?? '准备中';
                    final taskId = task['id'] as String;
                    return _GeneratingVideoCardWidget(
                      progress: progress,
                      status: status,
                      taskId: taskId,
                    );
                  }
                  
                  // 失败的任务（显示在中间）
                  final failedIndex = index - activeTasks.length;
                  if (failedIndex < failedTasks.length) {
                    final failedTask = failedTasks[failedIndex];
                    return _FailedVideoCardWidget(task: failedTask);
                  }
                  
                  // 已完成的视频（显示在最后）
                  final videoIndex = index - activeTasks.length - failedTasks.length;
                  if (videoIndex < generatedVideos.length) {
                    final video = generatedVideos[videoIndex];
                    return _VideoCardWidget(video: video);
                  }
                  
                  return SizedBox.shrink();
                },
              );
            },
          );
        },
      ),
    );
  }

  static Widget _buildCard({
    required String title,
    required dynamic subtitle, // 可以是 String 或 Widget
    required IconData icon,
    required Color color,
    required Widget child,
    bool expanded = false,
    Widget? actionButton,
  }) {
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AnimeColors.glassBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                        if (subtitle is String)
                          Text(subtitle, style: TextStyle(color: Colors.white54, fontSize: 11))
                        else if (subtitle is Widget)
                          subtitle,
                      ],
                    ),
                  ),
                  if (actionButton != null) actionButton,
                ],
              ),
              SizedBox(height: 14),
              expanded ? Expanded(child: child) : child,
            ],
          ),
        ),
      ),
    );
    return expanded ? Expanded(child: content) : content;
  }
}

// ==================== 素材库 Widget ====================
class MaterialsLibraryWidget extends StatefulWidget {
  const MaterialsLibraryWidget({super.key});

  @override
  State<MaterialsLibraryWidget> createState() => _MaterialsLibraryWidgetState();
}

class _MaterialsLibraryWidgetState extends State<MaterialsLibraryWidget> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedStyleIndex = 0;
  
  Map<String, List<Map<String, String>>> _characterMaterials = {};
  List<Map<String, String>> _sceneMaterials = [];
  List<Map<String, String>> _propMaterials = [];
  
  // 上传状态：使用素材的 path 作为 key 来跟踪每个素材的上传状态
  final Map<String, bool> _uploadingMaterials = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    logService.action('进入素材库');
    _loadMaterials();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMaterials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 加载角色素材
      final charJson = prefs.getString('character_materials');
      if (charJson != null) {
        final decoded = jsonDecode(charJson) as Map<String, dynamic>;
        _characterMaterials = decoded.map((key, value) => 
          MapEntry(key, (value as List).map((e) => Map<String, String>.from(e)).toList()));
      }
      
      // 加载场景素材
      final sceneJson = prefs.getString('scene_materials');
      if (sceneJson != null) {
        _sceneMaterials = (jsonDecode(sceneJson) as List).map((e) => Map<String, String>.from(e)).toList();
      }
      
      // 加载物品素材
      final propJson = prefs.getString('prop_materials');
      if (propJson != null) {
        _propMaterials = (jsonDecode(propJson) as List).map((e) => Map<String, String>.from(e)).toList();
      }
      
      setState(() {});
      logService.info('素材库加载完成');
    } catch (e) {
      logService.error('加载素材库失败', details: e.toString());
    }
  }

  Future<void> _saveMaterials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('character_materials', jsonEncode(_characterMaterials));
      await prefs.setString('scene_materials', jsonEncode(_sceneMaterials));
      await prefs.setString('prop_materials', jsonEncode(_propMaterials));
      logService.info('素材库保存成功');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('素材保存成功!'), backgroundColor: AnimeColors.miku),
      );
    } catch (e) {
      logService.error('保存素材库失败', details: e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          // Tab栏
          Container(
            decoration: BoxDecoration(
              color: AnimeColors.cardBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                gradient: LinearGradient(colors: [AnimeColors.miku, AnimeColors.purple]),
                borderRadius: BorderRadius.circular(12),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              tabs: [
                Tab(icon: Icon(Icons.person_outline, size: 20), text: '角色素材'),
                Tab(icon: Icon(Icons.landscape_outlined, size: 20), text: '场景素材'),
                Tab(icon: Icon(Icons.inventory_2_outlined, size: 20), text: '物品素材'),
              ],
            ),
          ),
          SizedBox(height: 16),
          // 内容区
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCharacterTab(),
                _buildSceneTab(),
                _buildPropTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCharacterTab() {
    final styles = styleManager.styles;
    // 确保选中索引有效
    if (_selectedStyleIndex >= styles.length) {
      _selectedStyleIndex = 0;
    }
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧风格列表
        Container(
          width: 200,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: AnimeColors.glassBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Text('风格分类', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                          Spacer(),
                          InkWell(
                            onTap: _showAddStyleDialog,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AnimeColors.miku.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.add, color: AnimeColors.miku, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        itemCount: styles.length,
                        itemBuilder: (context, index) {
                          final style = styles[index];
                          final isSelected = _selectedStyleIndex == index;
                          return InkWell(
                            onTap: () {
                              setState(() => _selectedStyleIndex = index);
                              logService.action('选择风格', details: style.name);
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              margin: EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: isSelected ? style.color.withOpacity(0.2) : null,
                                borderRadius: BorderRadius.circular(10),
                                border: isSelected ? Border.all(color: style.color.withOpacity(0.5)) : null,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: style.color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          style.name,
                                          style: TextStyle(
                                            color: isSelected ? style.color : Colors.white70,
                                            fontSize: 13,
                                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                          ),
                                        ),
                                        Text(
                                          style.description,
                                          style: TextStyle(color: Colors.white38, fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 16),
        // 右侧素材列表
        Expanded(
          child: _buildMaterialGrid(
            title: styles.isNotEmpty ? '${styles[_selectedStyleIndex].name}素材' : '素材',
            materials: styles.isNotEmpty ? (_characterMaterials[styles[_selectedStyleIndex].id] ?? []) : [],
            onAdd: () => _showAddMaterialDialog('character'),
            onSave: _saveMaterials,
          ),
        ),
      ],
    );
  }

  void _showAddStyleDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    Color selectedColor = AnimeColors.miku;
    
    final colorOptions = [
      AnimeColors.miku,
      AnimeColors.sakura,
      AnimeColors.purple,
      AnimeColors.blue,
      AnimeColors.orangeAccent,
      Color(0xFF4CAF50),
      Color(0xFFFF5722),
      Color(0xFFE91E63),
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AnimeColors.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.add_circle_outline, color: AnimeColors.miku),
              SizedBox(width: 8),
              Text('添加风格', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ],
          ),
          content: Container(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('风格名称', style: TextStyle(color: AnimeColors.miku, fontSize: 13)),
                SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  style: TextStyle(color: Colors.white70),
                  decoration: InputDecoration(
                    hintText: '例如：科幻风格',
                    hintStyle: TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: AnimeColors.darkBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                SizedBox(height: 16),
                Text('风格描述', style: TextStyle(color: AnimeColors.miku, fontSize: 13)),
                SizedBox(height: 8),
                TextField(
                  controller: descController,
                  style: TextStyle(color: Colors.white70),
                  decoration: InputDecoration(
                    hintText: '简短描述风格特点',
                    hintStyle: TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: AnimeColors.darkBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                SizedBox(height: 16),
                Text('选择颜色', style: TextStyle(color: AnimeColors.miku, fontSize: 13)),
                SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: colorOptions.map((color) {
                    final isSelected = selectedColor == color;
                    return InkWell(
                      onTap: () => setDialogState(() => selectedColor = color),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8)] : null,
                        ),
                        child: isSelected ? Icon(Icons.check, color: Colors.white, size: 18) : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('取消', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('请输入风格名称')),
                  );
                  return;
                }
                
                final newStyle = AnimeStyle(
                  nameController.text.toLowerCase().replaceAll(' ', '_'),
                  nameController.text,
                  descController.text.isEmpty ? '自定义风格' : descController.text,
                  selectedColor,
                );
                
                styleManager.addStyle(newStyle);
                logService.action('添加风格', details: nameController.text);
                setState(() {});
                Navigator.pop(context);
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('风格添加成功!'), backgroundColor: AnimeColors.miku),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: AnimeColors.miku),
              child: Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSceneTab() {
    return _buildMaterialGrid(
      title: '场景素材',
      materials: _sceneMaterials,
      onAdd: () => _showAddMaterialDialog('scene'),
      onSave: _saveMaterials,
    );
  }

  Widget _buildPropTab() {
    return _buildMaterialGrid(
      title: '物品素材',
      materials: _propMaterials,
      onAdd: () => _showAddMaterialDialog('prop'),
      onSave: _saveMaterials,
    );
  }

  Widget _buildMaterialGrid({
    required String title,
    required List<Map<String, String>> materials,
    required VoidCallback onAdd,
    required VoidCallback onSave,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: AnimeColors.glassBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            children: [
              // 标题栏
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                    Text(' (${materials.length})', style: TextStyle(color: Colors.white54, fontSize: 14)),
                    Spacer(),
                    OutlinedButton.icon(
                      onPressed: onSave,
                      icon: Icon(Icons.save_outlined, size: 16),
                      label: Text('保存'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AnimeColors.miku,
                        side: BorderSide(color: AnimeColors.miku.withOpacity(0.5)),
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                    SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: onAdd,
                      icon: Icon(Icons.add, size: 18),
                      label: Text('添加'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AnimeColors.miku,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: Colors.white.withOpacity(0.1), height: 1),
              // 素材网格
              Expanded(
                child: materials.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_open_outlined, size: 60, color: Colors.white24),
                            SizedBox(height: 16),
                            Text('暂无素材', style: TextStyle(color: Colors.white54, fontSize: 14)),
                            SizedBox(height: 8),
                            Text('点击右上角添加按钮添加素材', style: TextStyle(color: Colors.white38, fontSize: 12)),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: materials.length,
                        itemBuilder: (context, index) {
                          final material = materials[index];
                          return _buildMaterialCard(material);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMaterialCard(Map<String, String> material) {
    final isUploaded = material['characterId'] != null && material['characterId']!.isNotEmpty;
    final materialKey = material['path'] ?? material['name'] ?? '';
    final isUploading = _uploadingMaterials[materialKey] ?? false;
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AnimeColors.cardBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  InkWell(
                    onTap: material['path'] != null
                        ? () => showImageViewer(context, imagePath: material['path'])
                        : null,
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AnimeColors.purple.withOpacity(0.3), AnimeColors.miku.withOpacity(0.2)],
                        ),
                      ),
                      child: material['path'] != null
                          ? Image.file(
                              File(material['path']!),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(Icons.broken_image, size: 40, color: Colors.white38),
                            )
                          : Icon(Icons.image_outlined, size: 40, color: Colors.white38),
                    ),
                  ),
                  // 删除按钮（右上角）
                  Positioned(
                    top: 6,
                    right: 6,
                    child: InkWell(
                      onTap: () => _deleteMaterial(material),
                      child: Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close, color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                  // 已上传标记（左上角）
                  if (isUploaded)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AnimeColors.miku.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_done, color: Colors.white, size: 10),
                            SizedBox(width: 2),
                            Text('已上传', style: TextStyle(color: Colors.white, fontSize: 9)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 名称显示（可复制）
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: SelectableText(
                      material['name'] ?? '未命名',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(width: 4),
                  Tooltip(
                    message: '复制名称',
                    child: InkWell(
                      onTap: () {
                        final name = material['name'] ?? '未命名';
                        Clipboard.setData(ClipboardData(text: name));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('已复制: $name'),
                            backgroundColor: AnimeColors.miku,
                            duration: Duration(seconds: 2),
                          ),
                        );
                        logService.action('复制素材名称', details: name);
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.copy, size: 14, color: Colors.white54),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 上传按钮
            Padding(
              padding: EdgeInsets.only(left: 10, right: 10, bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (isUploaded || isUploading) ? null : () => _uploadMaterial(material),
                  icon: isUploading
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Icon(isUploaded ? Icons.check : Icons.cloud_upload, size: 14),
                  label: Text(
                    isUploading ? '上传中...' : (isUploaded ? '已上传' : '上传'),
                    style: TextStyle(fontSize: 11),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (isUploaded || isUploading) ? Colors.grey : AnimeColors.miku,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 6),
                    minimumSize: Size.zero,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 删除素材
  Future<void> _deleteMaterial(Map<String, String> material) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AnimeColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AnimeColors.sakura),
            SizedBox(width: 8),
            Text('确认删除', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          '确定要删除素材"${material['name']}"吗？\n此操作无法撤销。',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AnimeColors.sakura),
            child: Text('删除'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      setState(() {
        // 从当前风格的素材列表中删除
        final currentStyleId = styleManager.styles[_selectedStyleIndex].id;
        _characterMaterials[currentStyleId]?.remove(material);
        // 从场景素材中删除
        _sceneMaterials.remove(material);
        // 从物品素材中删除
        _propMaterials.remove(material);
      });
      
      await _saveMaterials();
      logService.action('删除素材', details: material['name'] ?? '未命名');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('素材已删除'), backgroundColor: AnimeColors.miku),
        );
      }
    }
  }
  
  // 上传素材到API
  Future<void> _uploadMaterial(Map<String, String> material) async {
    if (material['path'] == null || material['path']!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('素材文件不存在'), backgroundColor: AnimeColors.sakura),
      );
      return;
    }
    
    final materialKey = material['path'] ?? material['name'] ?? '';
    
    // 检查是否正在上传
    if (_uploadingMaterials[materialKey] == true) {
      return; // 防止重复点击
    }
    
    // 设置上传状态
    setState(() {
      _uploadingMaterials[materialKey] = true;
    });
    
    try {
      logService.action('开始上传素材', details: material['name']);
      
      final apiService = apiConfigManager.createApiService();
      
      // 开始上传流程
      final response = await apiService.uploadCharacter(
        imagePath: material['path']!,
        name: material['name'] ?? '未命名',
        model: apiConfigManager.videoModel,
      );
      
      // 更新素材信息
      // 在返回的名称前面添加 @ 符号（如果还没有）
      String characterName = response.characterName;
      if (!characterName.startsWith('@')) {
        characterName = '@$characterName';
      }
      
      setState(() {
        material['characterId'] = response.characterId;
        material['name'] = characterName; // 使用API返回的名称，前面加上@
      });
      
      await _saveMaterials();
      
      logService.info('素材上传成功', details: '角色ID: ${response.characterId}, 名称: $characterName');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('上传成功！角色名称已更新为: $characterName'),
            backgroundColor: AnimeColors.miku,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      logService.error('上传素材失败', details: e.toString());
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('上传失败: $e'),
            backgroundColor: AnimeColors.sakura,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } finally {
      // 无论成功失败，都要重置上传状态
      if (mounted) {
        setState(() {
          _uploadingMaterials[materialKey] = false;
        });
      }
    }
  }

  void _showAddMaterialDialog(String type) {
    final nameController = TextEditingController();
    String? selectedPath;
    int selectedStyleIndex = _selectedStyleIndex;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AnimeColors.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.add_circle_outline, color: AnimeColors.miku),
              SizedBox(width: 8),
              Text('添加素材', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ],
          ),
          content: Container(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (type == 'character') ...[
                  Text('选择风格', style: TextStyle(color: AnimeColors.miku, fontSize: 13)),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AnimeColors.darkBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButton<int>(
                      value: selectedStyleIndex < styleManager.styles.length ? selectedStyleIndex : 0,
                      isExpanded: true,
                      dropdownColor: AnimeColors.cardBg,
                      underline: SizedBox(),
                      items: styleManager.styles.asMap().entries.map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value.name, style: TextStyle(color: Colors.white70)),
                      )).toList(),
                      onChanged: (v) => setDialogState(() => selectedStyleIndex = v!),
                    ),
                  ),
                  SizedBox(height: 16),
                ],
                Text('素材名称', style: TextStyle(color: AnimeColors.miku, fontSize: 13)),
                SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  style: TextStyle(color: Colors.white70),
                  decoration: InputDecoration(
                    hintText: '输入素材名称',
                    hintStyle: TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: AnimeColors.darkBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                SizedBox(height: 16),
                Text('选择图片', style: TextStyle(color: AnimeColors.miku, fontSize: 13)),
                SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    try {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.image,
                        allowMultiple: false,
                      );
                      if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
                        setDialogState(() {
                          selectedPath = result.files.single.path;
                        });
                        logService.action('选择素材图片', details: selectedPath);
                      }
                    } catch (e) {
                      logService.error('选择图片失败', details: e.toString());
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('选择图片失败: ${e.toString()}'),
                          backgroundColor: AnimeColors.sakura,
                        ),
                      );
                    }
                  },
                  behavior: HitTestBehavior.opaque, // 确保整个区域都可以点击
                  child: Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: AnimeColors.darkBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: selectedPath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Stack(
                              children: [
                                Image.file(
                                  File(selectedPath!),
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                                // 半透明覆盖层，提示可以重新选择
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Icon(Icons.edit_outlined, color: Colors.white70, size: 24),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined, size: 32, color: Colors.white38),
                                SizedBox(height: 8),
                                Text('点击选择图片', style: TextStyle(color: Colors.white38, fontSize: 12)),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('取消', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isEmpty || selectedPath == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('请填写完整信息')),
                  );
                  return;
                }

                final material = {'name': nameController.text, 'path': selectedPath!};

                setState(() {
                  if (type == 'character') {
                    final styles = styleManager.styles;
                    if (styles.isNotEmpty && selectedStyleIndex < styles.length) {
                      final styleId = styles[selectedStyleIndex].id;
                      _characterMaterials[styleId] ??= [];
                      _characterMaterials[styleId]!.add(material);
                    }
                  } else if (type == 'scene') {
                    _sceneMaterials.add(material);
                  } else {
                    _propMaterials.add(material);
                  }
                });

                logService.action('添加素材', details: '${nameController.text}');
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AnimeColors.miku),
              child: Text('添加'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 系统日志 Widget ====================
class SystemLogsWidget extends StatefulWidget {
  const SystemLogsWidget({super.key});

  @override
  State<SystemLogsWidget> createState() => _SystemLogsWidgetState();
}

class _SystemLogsWidgetState extends State<SystemLogsWidget> {
  final ScrollController _scrollController = ScrollController();
  late StreamSubscription<LogEntry> _logSubscription;

  @override
  void initState() {
    super.initState();
    _logSubscription = logService.logStream.listen((_) {
      setState(() {});
      // 自动滚动到底部
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _logSubscription.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Color _getLevelColor(String level) {
    switch (level) {
      case 'INFO': return Colors.green;
      case 'WARN': return Colors.orange;
      case 'ERROR': return Colors.red;
      case 'ACTION': return AnimeColors.miku;
      default: return Colors.white54;
    }
  }

  IconData _getLevelIcon(String level) {
    switch (level) {
      case 'INFO': return Icons.info_outline;
      case 'WARN': return Icons.warning_amber_outlined;
      case 'ERROR': return Icons.error_outline;
      case 'ACTION': return Icons.touch_app_outlined;
      default: return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              color: AnimeColors.glassBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              children: [
                // 标题栏
                Padding(
                  padding: EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(Icons.terminal, color: AnimeColors.miku, size: 28),
                      SizedBox(width: 12),
                      Text('系统日志', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                      Text(' (${logService.logs.length})', style: TextStyle(fontSize: 16, color: Colors.white54)),
                      Spacer(),
                      OutlinedButton.icon(
                        onPressed: () {
                          logService.clear();
                          setState(() {});
                          logService.info('日志已清空');
                        },
                        icon: Icon(Icons.delete_outline, size: 16),
                        label: Text('清空'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AnimeColors.sakura,
                          side: BorderSide(color: AnimeColors.sakura.withOpacity(0.5)),
                        ),
                      ),
                      SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await logService.saveLogs();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('日志已保存'), backgroundColor: AnimeColors.miku),
                          );
                        },
                        icon: Icon(Icons.save_outlined, size: 16),
                        label: Text('保存'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AnimeColors.miku,
                          side: BorderSide(color: AnimeColors.miku.withOpacity(0.5)),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(color: Colors.white.withOpacity(0.1), height: 1),
                // 日志列表
                Expanded(
                  child: Container(
                    margin: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: logService.logs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.article_outlined, size: 48, color: Colors.white24),
                                SizedBox(height: 12),
                                Text('暂无日志', style: TextStyle(color: Colors.white38)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: EdgeInsets.all(12),
                            itemCount: logService.logs.length,
                            itemBuilder: (context, index) {
                              final log = logService.logs[index];
                              final color = _getLevelColor(log.level);
                              return Container(
                                padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                margin: EdgeInsets.only(bottom: 4),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(_getLevelIcon(log.level), color: color, size: 14),
                                    SizedBox(width: 8),
                                    Text(
                                      log.timestamp.toString().substring(11, 19),
                                      style: TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'monospace'),
                                    ),
                                    SizedBox(width: 8),
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        log.level,
                                        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            log.message,
                                            style: TextStyle(color: Colors.white70, fontSize: 12),
                                          ),
                                          if (log.details != null)
                                            Padding(
                                              padding: EdgeInsets.only(top: 2),
                                              child: Text(
                                                log.details!,
                                                style: TextStyle(color: Colors.white38, fontSize: 10),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== 设置主页面 ====================
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _selectedIndex = 0;

  final List<_SettingsMenuItem> _menuItems = [
    _SettingsMenuItem(
      icon: Icons.api_outlined,
      title: 'API 设置',
      subtitle: '配置模型接口',
      color: AnimeColors.miku,
    ),
    _SettingsMenuItem(
      icon: Icons.text_snippet_outlined,
      title: '提示词设置',
      subtitle: '管理生成提示词',
      color: AnimeColors.purple,
    ),
    _SettingsMenuItem(
      icon: Icons.palette_outlined,
      title: '风格设置',
      subtitle: '界面主题风格',
      color: AnimeColors.sakura,
    ),
    _SettingsMenuItem(
      icon: Icons.folder_outlined,
      title: '保存设置',
      subtitle: '自动保存路径',
      color: AnimeColors.orangeAccent,
    ),
  ];

  @override
  void initState() {
    super.initState();
    logService.action('进入设置页面');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AnimeColors.darkBg, Color(0xFF0f0f1e), Color(0xFF1a1a2e)],
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              // 左侧菜单
              Container(
                width: 240,
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 返回按钮和标题
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(Icons.arrow_back, color: Colors.white70),
                        ),
                        SizedBox(width: 8),
                        Text(
                          '设置',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 32),
                    // 菜单项
                    ...List.generate(_menuItems.length, (index) {
                      final item = _menuItems[index];
                      final isSelected = _selectedIndex == index;
                      return Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () {
                            setState(() => _selectedIndex = index);
                            logService.action('切换设置页', details: item.title);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              gradient: isSelected
                                  ? LinearGradient(colors: [item.color.withOpacity(0.3), item.color.withOpacity(0.1)])
                                  : null,
                              borderRadius: BorderRadius.circular(12),
                              border: isSelected
                                  ? Border.all(color: item.color.withOpacity(0.5))
                                  : Border.all(color: Colors.transparent),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: item.color.withOpacity(isSelected ? 0.3 : 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(item.icon, color: item.color, size: 20),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        style: TextStyle(
                                          color: isSelected ? item.color : Colors.white70,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        item.subtitle,
                                        style: TextStyle(
                                          color: Colors.white38,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              // 分割线
              Container(
                width: 1,
                color: Colors.white.withOpacity(0.1),
              ),
              // 右侧内容区
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0:
        return ApiSettingsPanel();
      case 1:
        return PromptSettingsPanel();
      case 2:
        return StyleSettingsPanel();
      case 3:
        return SaveSettingsPanel();
      default:
        return SizedBox();
    }
  }
}

class _SettingsMenuItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  _SettingsMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });
}

// ==================== API 设置面板 ====================
class ApiSettingsPanel extends StatefulWidget {
  const ApiSettingsPanel({super.key});

  @override
  State<ApiSettingsPanel> createState() => _ApiSettingsPanelState();
}

class _ApiSettingsPanelState extends State<ApiSettingsPanel> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // LLM 配置
  final TextEditingController _llmApiController = TextEditingController();
  final TextEditingController _llmUrlController = TextEditingController();
  String _selectedLlmModel = '';
  String _llmModelSearch = '';
  
  // 图片配置
  final TextEditingController _imageApiController = TextEditingController();
  final TextEditingController _imageUrlController = TextEditingController();
  String _selectedImageModel = '';
  String _imageModelSearch = '';
  
  // 视频配置
  final TextEditingController _videoApiController = TextEditingController();
  final TextEditingController _videoUrlController = TextEditingController();
  String _selectedVideoModel = '';
  String _videoModelSearch = '';
  
  // API KEY 显示状态
  bool _showLlmApiKey = false;
  bool _showImageApiKey = false;
  bool _showVideoApiKey = false;

  // 扩展的模型列表
  final List<String> _llmModels = [
    // OpenAI 系列
    'gpt-4o', 'gpt-4o-mini', 'gpt-4-turbo', 'gpt-4', 'gpt-3.5-turbo',
    // Claude 系列
    'claude-3-5-sonnet-20241022', 'claude-3-5-haiku-20241022', 'claude-3-opus-20240229',
    // DeepSeek 系列
    'deepseek-chat', 'deepseek-coder', 'deepseek-reasoner',
    // Gemini 系列
    'gemini-2.0-flash-exp', 'gemini-1.5-pro', 'gemini-1.5-flash',
    // 其他
    'qwen-plus', 'qwen-turbo', 'qwen-max', 'glm-4', 'glm-4-flash',
  ];

  final List<String> _imageModels = [
    // Gemini 图片模型
    'gemini-3-pro-image-preview',
    'gemini-3-pro-image-preview-lite',
    'gemini-2.5-flash-image-preview',
  ];

  final List<String> _videoModels = [
    // Sora 系列
    'sora-1.0-turbo', 'sora-2',
    // Veo 系列
    'veo_3_1', 'veo_3_1-fast', 'veo_3_1-fl', 'veo_3_1-fast-fl',
    // Kling 系列
    'kling-v1', 'kling-v1-5',
    // Runway 系列
    'gen-3-alpha',
    // Pika 系列
    'pika-1.0',
    // Luma 系列
    'dream-machine',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadConfig();
    // 监听配置变化，实现实时更新
    apiConfigManager.addListener(_onConfigChanged);
  }

  bool _isSaving = false; // 标记是否正在保存，防止保存时重新加载覆盖用户输入

  void _onConfigChanged() {
    if (mounted && !_isSaving) {
      // 只有在非保存状态下才重新加载配置
      _loadConfig();
      setState(() {});
    }
  }

  void _loadConfig() {
    _llmApiController.text = apiConfigManager.llmApiKey;
    _llmUrlController.text = apiConfigManager.llmBaseUrl;
    _selectedLlmModel = apiConfigManager.llmModel.isNotEmpty ? apiConfigManager.llmModel : _llmModels.first;
    
    _imageApiController.text = apiConfigManager.imageApiKey;
    _imageUrlController.text = apiConfigManager.imageBaseUrl;
    _selectedImageModel = apiConfigManager.imageModel.isNotEmpty ? apiConfigManager.imageModel : _imageModels.first;
    
    _videoApiController.text = apiConfigManager.videoApiKey;
    _videoUrlController.text = apiConfigManager.videoBaseUrl;
    _selectedVideoModel = apiConfigManager.videoModel.isNotEmpty ? apiConfigManager.videoModel : _videoModels.first;
  }

  @override
  void dispose() {
    apiConfigManager.removeListener(_onConfigChanged);
    _tabController.dispose();
    _llmApiController.dispose();
    _llmUrlController.dispose();
    _imageApiController.dispose();
    _imageUrlController.dispose();
    _videoApiController.dispose();
    _videoUrlController.dispose();
    super.dispose();
  }

  void _saveConfig() {
    // 立即关闭键盘，提供即时反馈
    FocusScope.of(context).unfocus();
    
    // 验证必填字段
    final missingFields = <String>[];
    
    if (_llmApiController.text.isEmpty) missingFields.add('LLM API Key');
    if (_llmUrlController.text.isEmpty) missingFields.add('LLM Base URL');
    if (_imageApiController.text.isEmpty) missingFields.add('图片 API Key');
    if (_imageUrlController.text.isEmpty) missingFields.add('图片 Base URL');
    if (_videoApiController.text.isEmpty) missingFields.add('视频 API Key');
    if (_videoUrlController.text.isEmpty) missingFields.add('视频 Base URL');
    
    if (missingFields.isNotEmpty) {
      logService.warn('API配置不完整', details: '缺少: ${missingFields.join(", ")}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('以下配置缺失: ${missingFields.join(", ")}'),
          backgroundColor: AnimeColors.orangeAccent,
        ),
      );
      return;
    }

    // 立即显示成功提示（不等待保存完成）
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('API 配置已保存'), backgroundColor: AnimeColors.miku),
    );
    
    // 设置保存标记，防止监听器重新加载覆盖用户输入
    _isSaving = true;
    
    // 批量更新配置，避免多次 notifyListeners() 导致 UI 重建
    apiConfigManager.updateConfigBatch(
      llmApiKey: _llmApiController.text,
      llmBaseUrl: _llmUrlController.text,
      llmModel: _selectedLlmModel,
      imageApiKey: _imageApiController.text,
      imageBaseUrl: _imageUrlController.text,
      imageModel: _selectedImageModel,
      videoApiKey: _videoApiController.text,
      videoBaseUrl: _videoUrlController.text,
      videoModel: _selectedVideoModel,
    );
    
    // 延迟通知，避免阻塞 UI（使用 microtask 确保在当前帧之后执行）
    Future.microtask(() {
      apiConfigManager.triggerNotify();
    });
    
    // 延迟重置保存标记
    Future.delayed(Duration(milliseconds: 100), () {
      if (mounted) {
        _isSaving = false;
      }
    });
    
    logService.info('API配置已保存');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Row(
            children: [
              Icon(Icons.api, color: AnimeColors.miku, size: 28),
              SizedBox(width: 12),
              Text('API 设置', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
              Spacer(),
              ElevatedButton.icon(
                onPressed: _saveConfig,
                icon: Icon(Icons.save, size: 18),
                label: Text('保存配置'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AnimeColors.miku,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
          SizedBox(height: 24),
          // Tab 栏
          Container(
            decoration: BoxDecoration(
              color: AnimeColors.cardBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                gradient: LinearGradient(colors: [AnimeColors.miku, AnimeColors.purple]),
                borderRadius: BorderRadius.circular(10),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: [
                Tab(icon: Icon(Icons.chat_outlined, size: 18), text: 'LLM 模型'),
                Tab(icon: Icon(Icons.image_outlined, size: 18), text: '图片模型'),
                Tab(icon: Icon(Icons.movie_outlined, size: 18), text: '视频模型'),
              ],
            ),
          ),
          SizedBox(height: 20),
          // 内容
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLlmPanel(),
                _buildImagePanel(),
                _buildVideoPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLlmPanel() {
    return SingleChildScrollView(
      child: _buildConfigCard(
        title: '大语言模型配置',
        icon: Icons.psychology_outlined,
        color: AnimeColors.blue,
        children: [
          _buildTextField('API Key', _llmApiController, '输入 API Key', isPassword: true, showPassword: _showLlmApiKey, onTogglePassword: () => setState(() => _showLlmApiKey = !_showLlmApiKey)),
          SizedBox(height: 16),
          _buildTextField('Base URL', _llmUrlController, 'https://api.openai.com/v1'),
          SizedBox(height: 16),
          _buildModelSelector('选择模型', _llmModels, _selectedLlmModel, _llmModelSearch, (v) => setState(() => _selectedLlmModel = v), (v) => setState(() => _llmModelSearch = v)),
        ],
      ),
    );
  }

  Widget _buildImagePanel() {
    return SingleChildScrollView(
      child: _buildConfigCard(
        title: '图片生成模型配置',
        icon: Icons.photo_camera_outlined,
        color: AnimeColors.sakura,
        children: [
          _buildTextField('API Key', _imageApiController, '输入 API Key', isPassword: true, showPassword: _showImageApiKey, onTogglePassword: () => setState(() => _showImageApiKey = !_showImageApiKey)),
          SizedBox(height: 16),
          _buildTextField('Base URL', _imageUrlController, 'https://api.openai.com/v1'),
          SizedBox(height: 16),
          _buildModelSelector('选择模型', _imageModels, _selectedImageModel, _imageModelSearch, (v) => setState(() => _selectedImageModel = v), (v) => setState(() => _imageModelSearch = v)),
        ],
      ),
    );
  }

  Widget _buildVideoPanel() {
    return SingleChildScrollView(
      child: _buildConfigCard(
        title: '视频生成模型配置',
        icon: Icons.videocam_outlined,
        color: AnimeColors.purple,
        children: [
          _buildTextField('API Key', _videoApiController, '输入 API Key', isPassword: true, showPassword: _showVideoApiKey, onTogglePassword: () => setState(() => _showVideoApiKey = !_showVideoApiKey)),
          SizedBox(height: 16),
          _buildTextField('Base URL', _videoUrlController, 'https://api.example.com/v1'),
          SizedBox(height: 16),
          _buildModelSelector('选择模型', _videoModels, _selectedVideoModel, _videoModelSearch, (v) => setState(() => _selectedVideoModel = v), (v) => setState(() => _videoModelSearch = v)),
        ],
      ),
    );
  }

  Widget _buildConfigCard({required String title, required IconData icon, required Color color, required List<Widget> children}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AnimeColors.glassBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  SizedBox(width: 12),
                  Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                ],
              ),
              SizedBox(height: 20),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, String hint, {bool isPassword = false, bool showPassword = false, VoidCallback? onTogglePassword}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AnimeColors.miku, fontSize: 13, fontWeight: FontWeight.w600)),
        SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: isPassword && !showPassword,
          style: TextStyle(color: Colors.white70, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white38),
            filled: true,
            fillColor: AnimeColors.darkBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility, color: Colors.white38, size: 20),
                    onPressed: onTogglePassword,
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildModelSelector(String label, List<String> models, String selected, String search, Function(String) onSelect, Function(String) onSearch) {
    final filteredModels = models.where((m) => m.toLowerCase().contains(search.toLowerCase())).toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AnimeColors.miku, fontSize: 13, fontWeight: FontWeight.w600)),
        SizedBox(height: 8),
        // 搜索框
        TextField(
          onChanged: onSearch,
          style: TextStyle(color: Colors.white70, fontSize: 13),
          decoration: InputDecoration(
            hintText: '搜索模型...',
            hintStyle: TextStyle(color: Colors.white38),
            prefixIcon: Icon(Icons.search, color: Colors.white38, size: 18),
            filled: true,
            fillColor: AnimeColors.darkBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        SizedBox(height: 10),
        // 模型列表
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: AnimeColors.darkBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListView.builder(
            padding: EdgeInsets.all(8),
            itemCount: filteredModels.length,
            itemBuilder: (context, index) {
              final model = filteredModels[index];
              final isSelected = model == selected;
              return InkWell(
                onTap: () => onSelect(model),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  margin: EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? AnimeColors.miku.withOpacity(0.2) : null,
                    borderRadius: BorderRadius.circular(6),
                    border: isSelected ? Border.all(color: AnimeColors.miku.withOpacity(0.5)) : null,
                  ),
                  child: Row(
                    children: [
                      Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, color: isSelected ? AnimeColors.miku : Colors.white38, size: 16),
                      SizedBox(width: 10),
                      Expanded(child: Text(model, style: TextStyle(color: isSelected ? AnimeColors.miku : Colors.white70, fontSize: 13))),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: 8),
        Text('当前选择: $selected', style: TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }
}

// ==================== 提示词设置面板 ====================
class PromptSettingsPanel extends StatefulWidget {
  const PromptSettingsPanel({super.key});

  @override
  State<PromptSettingsPanel> createState() => _PromptSettingsPanelState();
}

// 分镜模板管理对话框（支持生图提示词和生视频提示词两个类别）
class _StoryboardTemplateManagerDialog extends StatefulWidget {
  final String? selectedImageTemplate;
  final String? selectedVideoTemplate;
  final Function(String?, String?) onSelect;
  final VoidCallback? onSave;

  const _StoryboardTemplateManagerDialog({
    this.selectedImageTemplate,
    this.selectedVideoTemplate,
    required this.onSelect,
    this.onSave,
  });

  @override
  State<_StoryboardTemplateManagerDialog> createState() => _StoryboardTemplateManagerDialogState();
}

class _StoryboardTemplateManagerDialogState extends State<_StoryboardTemplateManagerDialog> {
  Map<String, String> _imageTemplates = {};
  Map<String, String> _videoTemplates = {};
  String _selectedCategory = 'image'; // 'image' 或 'video'
  String? _selectedImageTemplateName;
  String? _selectedVideoTemplateName;
  String? _selectedTemplateName; // 当前编辑的模板名称
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
    _selectedImageTemplateName = widget.selectedImageTemplate;
    _selectedVideoTemplateName = widget.selectedVideoTemplate;
    // 根据当前类别设置选中的模板
    _updateSelectedTemplate();
  }

  void _updateSelectedTemplate() {
    _selectedTemplateName = _selectedCategory == 'image' ? _selectedImageTemplateName : _selectedVideoTemplateName;
    if (_selectedTemplateName != null) {
      _nameController.text = _selectedTemplateName!;
      _contentController.text = _currentTemplates[_selectedTemplateName] ?? '';
    } else {
      _nameController.clear();
      _contentController.clear();
    }
    _isEditing = false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final promptsJson = prefs.getString('prompts');
      if (promptsJson != null && mounted) {
        final decoded = jsonDecode(promptsJson) as Map<String, dynamic>;
        setState(() {
          _imageTemplates = Map<String, String>.from(decoded['image'] ?? {});
          _videoTemplates = Map<String, String>.from(decoded['video'] ?? {});
        });
      }
    } catch (e) {
      print('加载模板失败: $e');
    }
  }

  Future<void> _saveTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final promptsJson = prefs.getString('prompts');
      Map<String, dynamic> allPrompts = {};
      if (promptsJson != null) {
        allPrompts = Map<String, dynamic>.from(jsonDecode(promptsJson));
      }
      allPrompts['image'] = _imageTemplates;
      allPrompts['video'] = _videoTemplates;
      await prefs.setString('prompts', jsonEncode(allPrompts));
      widget.onSave?.call();
    } catch (e) {
      print('保存模板失败: $e');
    }
  }

  Map<String, String> get _currentTemplates => _selectedCategory == 'image' ? _imageTemplates : _videoTemplates;

  void _selectTemplate(String name) {
    setState(() {
      _selectedTemplateName = name;
      if (_selectedCategory == 'image') {
        _selectedImageTemplateName = name;
      } else {
        _selectedVideoTemplateName = name;
      }
      _nameController.text = name;
      _contentController.text = _currentTemplates[name] ?? '';
      _isEditing = false;
    });
  }

  void _addNewTemplate() {
    setState(() {
      _selectedTemplateName = null;
      _nameController.clear();
      _contentController.clear();
      _isEditing = true;
    });
  }

  void _saveCurrentTemplate() {
    final name = _nameController.text.trim();
    final content = _contentController.text.trim();
    if (name.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请输入名称和内容'), backgroundColor: AnimeColors.sakura),
      );
      return;
    }

    setState(() {
      // 如果是编辑现有的，先删除旧的
      if (_selectedTemplateName != null && _selectedTemplateName != name) {
        if (_selectedCategory == 'image') {
          _imageTemplates.remove(_selectedTemplateName);
        } else {
          _videoTemplates.remove(_selectedTemplateName);
        }
      }
      if (_selectedCategory == 'image') {
        _imageTemplates[name] = content;
        _selectedImageTemplateName = name;
      } else {
        _videoTemplates[name] = content;
        _selectedVideoTemplateName = name;
      }
      _selectedTemplateName = name;
      _isEditing = false;
    });

    _saveTemplates();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已保存'), backgroundColor: _selectedCategory == 'image' ? AnimeColors.sakura : AnimeColors.blue),
    );
  }

  void _deleteTemplate() {
    if (_selectedTemplateName == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AnimeColors.cardBg,
        title: Text('确认删除', style: TextStyle(color: Colors.white)),
        content: Text('是否确认删除"$_selectedTemplateName"提示词模版？', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                if (_selectedCategory == 'image') {
                  _imageTemplates.remove(_selectedTemplateName);
                  if (_selectedTemplateName == _selectedImageTemplateName) {
                    _selectedImageTemplateName = null;
                  }
                } else {
                  _videoTemplates.remove(_selectedTemplateName);
                  if (_selectedTemplateName == _selectedVideoTemplateName) {
                    _selectedVideoTemplateName = null;
                  }
                }
                _updateSelectedTemplate();
              });
              _saveTemplates();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AnimeColors.sakura),
            child: Text('确认'),
          ),
        ],
      ),
    );
  }

  void _confirmSelection() {
    widget.onSelect(_selectedImageTemplateName, _selectedVideoTemplateName);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _selectedCategory == 'image' ? AnimeColors.sakura : AnimeColors.blue;
    
    return Dialog(
      backgroundColor: AnimeColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 800,
        height: 600,
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              children: [
                Icon(Icons.text_snippet, color: accentColor, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '分镜提示词模板管理',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
            SizedBox(height: 20),
            // 类别选择
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedCategory = 'image';
                        _updateSelectedTemplate();
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: _selectedCategory == 'image' ? AnimeColors.sakura.withOpacity(0.2) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _selectedCategory == 'image' ? AnimeColors.sakura : Colors.white10,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.image_outlined,
                            color: _selectedCategory == 'image' ? AnimeColors.sakura : Colors.white54,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '生图提示词',
                            style: TextStyle(
                              color: _selectedCategory == 'image' ? AnimeColors.sakura : Colors.white54,
                              fontWeight: _selectedCategory == 'image' ? FontWeight.w600 : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedCategory = 'video';
                        _updateSelectedTemplate();
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: _selectedCategory == 'video' ? AnimeColors.blue.withOpacity(0.2) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _selectedCategory == 'video' ? AnimeColors.blue : Colors.white10,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.movie_outlined,
                            color: _selectedCategory == 'video' ? AnimeColors.blue : Colors.white54,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '生视频提示词',
                            style: TextStyle(
                              color: _selectedCategory == 'video' ? AnimeColors.blue : Colors.white54,
                              fontWeight: _selectedCategory == 'video' ? FontWeight.w600 : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            // 主体内容
            Expanded(
              child: Row(
                children: [
                  // 左侧：模板列表
                  Container(
                    width: 200,
                    decoration: BoxDecoration(
                      color: AnimeColors.darkBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        // 添加按钮
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _addNewTemplate,
                              icon: Icon(Icons.add, size: 18),
                              label: Text('新增'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accentColor,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        Divider(color: Colors.white10, height: 1),
                        // 不使用模板选项
                        InkWell(
                          onTap: () {
                            setState(() {
                              if (_selectedCategory == 'image') {
                                _selectedImageTemplateName = null;
                              } else {
                                _selectedVideoTemplateName = null;
                              }
                              _updateSelectedTemplate();
                            });
                          },
                          child: Container(
                            padding: EdgeInsets.all(12),
                            color: _selectedTemplateName == null ? accentColor.withOpacity(0.2) : Colors.transparent,
                            child: Row(
                              children: [
                                Icon(
                                  _selectedTemplateName == null ? Icons.check_circle : Icons.circle_outlined,
                                  color: _selectedTemplateName == null ? accentColor : Colors.white54,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '不使用模板',
                                    style: TextStyle(
                                      color: _selectedTemplateName == null ? accentColor : Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Divider(color: Colors.white10, height: 1),
                        // 模板列表
                        Expanded(
                          child: ListView.builder(
                            itemCount: _currentTemplates.length,
                            itemBuilder: (context, index) {
                              final name = _currentTemplates.keys.elementAt(index);
                              final isSelected = name == _selectedTemplateName;
                              return InkWell(
                                onTap: () => _selectTemplate(name),
                                child: Container(
                                  padding: EdgeInsets.all(12),
                                  color: isSelected ? accentColor.withOpacity(0.2) : Colors.transparent,
                                  child: Row(
                                    children: [
                                      Icon(
                                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                                        color: isSelected ? accentColor : Colors.white54,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: TextStyle(
                                            color: isSelected ? accentColor : Colors.white70,
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  // 右侧：编辑区域
                  Expanded(
                    child: _selectedTemplateName == null && !_isEditing
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.text_snippet, size: 64, color: Colors.white24),
                                SizedBox(height: 16),
                                Text('选择或新增一个模板', style: TextStyle(color: Colors.white54)),
                              ],
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 名称输入
                              Text('名称', style: TextStyle(color: accentColor, fontSize: 13, fontWeight: FontWeight.w600)),
                              SizedBox(height: 8),
                              TextField(
                                controller: _nameController,
                                enabled: true,
                                readOnly: false,
                                enableInteractiveSelection: true,
                                style: TextStyle(color: Colors.white70, fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: '输入模板名称',
                                  hintStyle: TextStyle(color: Colors.white38),
                                  filled: true,
                                  fillColor: AnimeColors.darkBg,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                ),
                              ),
                              SizedBox(height: 16),
                              // 内容输入
                              Text('模板内容', style: TextStyle(color: accentColor, fontSize: 13, fontWeight: FontWeight.w600)),
                              SizedBox(height: 8),
                              Expanded(
                                child: TextField(
                                  controller: _contentController,
                                  enabled: true,
                                  readOnly: false,
                                  enableInteractiveSelection: true,
                                  maxLines: null,
                                  minLines: 10,
                                  style: TextStyle(color: Colors.white70, fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: '输入模板内容...',
                                    hintStyle: TextStyle(color: Colors.white38),
                                    filled: true,
                                    fillColor: AnimeColors.darkBg,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                    contentPadding: EdgeInsets.all(14),
                                  ),
                                ),
                              ),
                              SizedBox(height: 16),
                              // 操作按钮
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (_selectedTemplateName != null && !_isEditing)
                                    TextButton.icon(
                                      onPressed: _deleteTemplate,
                                      icon: Icon(Icons.delete_outline, size: 18, color: AnimeColors.sakura),
                                      label: Text('删除', style: TextStyle(color: AnimeColors.sakura)),
                                    ),
                                  if (_selectedTemplateName != null && !_isEditing)
                                    SizedBox(width: 8),
                                  if (_selectedTemplateName != null && !_isEditing)
                                    TextButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _isEditing = true;
                                        });
                                      },
                                      icon: Icon(Icons.edit, size: 18, color: accentColor),
                                      label: Text('编辑', style: TextStyle(color: accentColor)),
                                    ),
                                  if (_isEditing) ...[
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _isEditing = false;
                                          if (_selectedTemplateName != null) {
                                            _nameController.text = _selectedTemplateName!;
                                            _contentController.text = _currentTemplates[_selectedTemplateName] ?? '';
                                          } else {
                                            _nameController.clear();
                                            _contentController.clear();
                                          }
                                        });
                                      },
                                      child: Text('取消', style: TextStyle(color: Colors.white54)),
                                    ),
                                    SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      onPressed: _saveCurrentTemplate,
                                      icon: Icon(Icons.save, size: 18),
                                      label: Text('保存'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: accentColor,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            // 底部按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('取消', style: TextStyle(color: Colors.white54)),
                ),
                SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _confirmSelection,
                  icon: Icon(Icons.check, size: 18),
                  label: Text('确认选择'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 提示词模板管理对话框（支持增删改查和选择）
class _PromptTemplateManagerDialog extends StatefulWidget {
  final String category; // story, video, image, character, scene, prop
  final String? selectedTemplate;
  final Color accentColor;
  final Function(String?) onSelect;
  final VoidCallback? onSave;

  const _PromptTemplateManagerDialog({
    required this.category,
    this.selectedTemplate,
    required this.accentColor,
    required this.onSelect,
    this.onSave,
  });

  @override
  State<_PromptTemplateManagerDialog> createState() => _PromptTemplateManagerDialogState();
}

class _PromptTemplateManagerDialogState extends State<_PromptTemplateManagerDialog> {
  Map<String, String> _templates = {};
  String? _selectedTemplateName;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
    _selectedTemplateName = widget.selectedTemplate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final promptsJson = prefs.getString('prompts');
      if (promptsJson != null && mounted) {
        final decoded = jsonDecode(promptsJson) as Map<String, dynamic>;
        final categoryTemplates = decoded[widget.category] as Map<String, dynamic>?;
        if (categoryTemplates != null) {
          setState(() {
            _templates = Map<String, String>.from(categoryTemplates);
          });
        }
      }
    } catch (e) {
      print('加载模板失败: $e');
    }
  }

  Future<void> _saveTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final promptsJson = prefs.getString('prompts');
      Map<String, dynamic> allPrompts = {};
      if (promptsJson != null) {
        allPrompts = Map<String, dynamic>.from(jsonDecode(promptsJson));
      }
      allPrompts[widget.category] = _templates;
      await prefs.setString('prompts', jsonEncode(allPrompts));
      widget.onSave?.call();
    } catch (e) {
      print('保存模板失败: $e');
    }
  }

  void _selectTemplate(String name) {
    setState(() {
      _selectedTemplateName = name;
      _nameController.text = name;
      _contentController.text = _templates[name] ?? '';
      _isEditing = false;
    });
  }

  void _addNewTemplate() {
    setState(() {
      _selectedTemplateName = null;
      _nameController.clear();
      _contentController.clear();
      _isEditing = true;
    });
  }

  void _saveCurrentTemplate() {
    final name = _nameController.text.trim();
    final content = _contentController.text.trim();
    if (name.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请输入名称和内容'), backgroundColor: AnimeColors.sakura),
      );
      return;
    }

    setState(() {
      // 如果是编辑现有的，先删除旧的
      if (_selectedTemplateName != null && _selectedTemplateName != name) {
        _templates.remove(_selectedTemplateName);
      }
      _templates[name] = content;
      _selectedTemplateName = name;
      _isEditing = false;
    });

    _saveTemplates();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已保存'), backgroundColor: widget.accentColor),
    );
  }

  void _deleteTemplate() {
    if (_selectedTemplateName == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AnimeColors.cardBg,
        title: Text('确认删除', style: TextStyle(color: Colors.white)),
        content: Text('是否确认删除"$_selectedTemplateName"提示词模版？', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _templates.remove(_selectedTemplateName);
                if (_selectedTemplateName == widget.selectedTemplate) {
                  _selectedTemplateName = null;
                } else {
                  _selectedTemplateName = null;
                }
                _nameController.clear();
                _contentController.clear();
              });
              _saveTemplates();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AnimeColors.sakura),
            child: Text('确认'),
          ),
        ],
      ),
    );
  }

  void _confirmSelection() {
    widget.onSelect(_selectedTemplateName);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AnimeColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 800,
        height: 600,
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              children: [
                Icon(Icons.text_snippet, color: widget.accentColor, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '提示词模板管理',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
            SizedBox(height: 20),
            // 主体内容
            Expanded(
              child: Row(
                children: [
                  // 左侧：模板列表
                  Container(
                    width: 200,
                    decoration: BoxDecoration(
                      color: AnimeColors.darkBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        // 添加按钮
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _addNewTemplate,
                              icon: Icon(Icons.add, size: 18),
                              label: Text('新增'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: widget.accentColor,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        Divider(color: Colors.white10, height: 1),
                        // 不使用模板选项
                        InkWell(
                          onTap: () {
                            setState(() {
                              _selectedTemplateName = null;
                              _nameController.clear();
                              _contentController.clear();
                              _isEditing = false;
                            });
                          },
                          child: Container(
                            padding: EdgeInsets.all(12),
                            color: _selectedTemplateName == null ? widget.accentColor.withOpacity(0.2) : Colors.transparent,
                            child: Row(
                              children: [
                                Icon(
                                  _selectedTemplateName == null ? Icons.check_circle : Icons.circle_outlined,
                                  color: _selectedTemplateName == null ? widget.accentColor : Colors.white54,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '不使用模板',
                                    style: TextStyle(
                                      color: _selectedTemplateName == null ? widget.accentColor : Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Divider(color: Colors.white10, height: 1),
                        // 模板列表
                        Expanded(
                          child: ListView.builder(
                            itemCount: _templates.length,
                            itemBuilder: (context, index) {
                              final name = _templates.keys.elementAt(index);
                              final isSelected = name == _selectedTemplateName;
                              return InkWell(
                                onTap: () => _selectTemplate(name),
                                child: Container(
                                  padding: EdgeInsets.all(12),
                                  color: isSelected ? widget.accentColor.withOpacity(0.2) : Colors.transparent,
                                  child: Row(
                                    children: [
                                      Icon(
                                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                                        color: isSelected ? widget.accentColor : Colors.white54,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: TextStyle(
                                            color: isSelected ? widget.accentColor : Colors.white70,
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  // 右侧：编辑区域
                  Expanded(
                    child: _selectedTemplateName == null && !_isEditing
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.text_snippet, size: 64, color: Colors.white24),
                                SizedBox(height: 16),
                                Text('选择或新增一个模板', style: TextStyle(color: Colors.white54)),
                              ],
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 名称输入
                              Text('名称', style: TextStyle(color: widget.accentColor, fontSize: 13, fontWeight: FontWeight.w600)),
                              SizedBox(height: 8),
                              TextField(
                                controller: _nameController,
                                enabled: true,
                                readOnly: false,
                                enableInteractiveSelection: true,
                                style: TextStyle(color: Colors.white70, fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: '输入模板名称',
                                  hintStyle: TextStyle(color: Colors.white38),
                                  filled: true,
                                  fillColor: AnimeColors.darkBg,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                ),
                              ),
                              SizedBox(height: 16),
                              // 内容输入
                              Text('模板内容', style: TextStyle(color: widget.accentColor, fontSize: 13, fontWeight: FontWeight.w600)),
                              SizedBox(height: 8),
                              Expanded(
                                child: TextField(
                                  controller: _contentController,
                                  enabled: true,
                                  readOnly: false,
                                  enableInteractiveSelection: true,
                                  maxLines: null,
                                  minLines: 10,
                                  style: TextStyle(color: Colors.white70, fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: '输入模板内容...',
                                    hintStyle: TextStyle(color: Colors.white38),
                                    filled: true,
                                    fillColor: AnimeColors.darkBg,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                    contentPadding: EdgeInsets.all(14),
                                  ),
                                ),
                              ),
                              SizedBox(height: 16),
                              // 操作按钮
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (_selectedTemplateName != null && !_isEditing)
                                    TextButton.icon(
                                      onPressed: _deleteTemplate,
                                      icon: Icon(Icons.delete_outline, size: 18, color: AnimeColors.sakura),
                                      label: Text('删除', style: TextStyle(color: AnimeColors.sakura)),
                                    ),
                                  if (_selectedTemplateName != null && !_isEditing)
                                    SizedBox(width: 8),
                                  if (_selectedTemplateName != null && !_isEditing)
                                    TextButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _isEditing = true;
                                        });
                                      },
                                      icon: Icon(Icons.edit, size: 18, color: widget.accentColor),
                                      label: Text('编辑', style: TextStyle(color: widget.accentColor)),
                                    ),
                                  if (_isEditing) ...[
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _isEditing = false;
                                          if (_selectedTemplateName != null) {
                                            _nameController.text = _selectedTemplateName!;
                                            _contentController.text = _templates[_selectedTemplateName] ?? '';
                                          } else {
                                            _nameController.clear();
                                            _contentController.clear();
                                          }
                                        });
                                      },
                                      child: Text('取消', style: TextStyle(color: Colors.white54)),
                                    ),
                                    SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      onPressed: _saveCurrentTemplate,
                                      icon: Icon(Icons.save, size: 18),
                                      label: Text('保存'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: widget.accentColor,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            // 底部按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('取消', style: TextStyle(color: Colors.white54)),
                ),
                SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _confirmSelection,
                  icon: Icon(Icons.check, size: 18),
                  label: Text('确认选择'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.accentColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 系统提示词管理对话框（通用）
class _SystemPromptManagerDialog extends StatefulWidget {
  final String category;
  final String title;

  const _SystemPromptManagerDialog({
    required this.category,
    required this.title,
  });

  @override
  State<_SystemPromptManagerDialog> createState() => _SystemPromptManagerDialogState();
}

class _SystemPromptManagerDialogState extends State<_SystemPromptManagerDialog> {
  Map<String, String> _prompts = {};
  String? _selectedPromptName;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadPrompts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadPrompts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final promptsJson = prefs.getString('system_prompts_${widget.category}');
      if (promptsJson != null && mounted) {
        final decoded = jsonDecode(promptsJson) as Map<String, dynamic>;
        setState(() {
          _prompts = Map<String, String>.from(decoded);
        });
      }
    } catch (e) {
      print('加载系统提示词失败: $e');
    }
  }

  Future<void> _savePrompts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('system_prompts_${widget.category}', jsonEncode(_prompts));
    } catch (e) {
      print('保存系统提示词失败: $e');
    }
  }

  void _selectPrompt(String name) {
    setState(() {
      _selectedPromptName = name;
      _nameController.text = name;
      _contentController.text = _prompts[name] ?? '';
      _isEditing = false;
    });
  }

  void _addNewPrompt() {
    setState(() {
      _selectedPromptName = null;
      _nameController.clear();
      _contentController.clear();
      _isEditing = true;
    });
  }

  void _saveCurrentPrompt() {
    final name = _nameController.text.trim();
    final content = _contentController.text.trim();
    if (name.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请输入名称和内容'), backgroundColor: AnimeColors.sakura),
      );
      return;
    }

    setState(() {
      // 如果是编辑现有的，先删除旧的
      if (_selectedPromptName != null && _selectedPromptName != name) {
        _prompts.remove(_selectedPromptName);
      }
      _prompts[name] = content;
      _selectedPromptName = name;
      _isEditing = false;
    });

    _savePrompts();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已保存'), backgroundColor: AnimeColors.miku),
    );
  }

  void _deletePrompt() {
    if (_selectedPromptName == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AnimeColors.cardBg,
        title: Text('确认删除', style: TextStyle(color: Colors.white)),
        content: Text('确定要删除 "$_selectedPromptName" 吗？', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _prompts.remove(_selectedPromptName);
                _selectedPromptName = null;
                _nameController.clear();
                _contentController.clear();
              });
              _savePrompts();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AnimeColors.sakura),
            child: Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AnimeColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 800,
        height: 600,
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              children: [
                Icon(Icons.edit_note, color: AnimeColors.miku, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
            SizedBox(height: 20),
            // 主体内容
            Expanded(
              child: Row(
                children: [
                  // 左侧：提示词列表
                  Container(
                    width: 200,
                    decoration: BoxDecoration(
                      color: AnimeColors.darkBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        // 添加按钮
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _addNewPrompt,
                              icon: Icon(Icons.add, size: 18),
                              label: Text('新增'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AnimeColors.miku,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        Divider(color: Colors.white10, height: 1),
                        // 提示词列表
                        Expanded(
                          child: ListView.builder(
                            itemCount: _prompts.length,
                            itemBuilder: (context, index) {
                              final name = _prompts.keys.elementAt(index);
                              final isSelected = name == _selectedPromptName;
                              return ListTile(
                                dense: true,
                                selected: isSelected,
                                selectedTileColor: AnimeColors.miku.withOpacity(0.2),
                                title: Text(
                                  name,
                                  style: TextStyle(
                                    color: isSelected ? AnimeColors.miku : Colors.white70,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => _selectPrompt(name),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  // 右侧：编辑区域
                  Expanded(
                    child: _selectedPromptName == null && !_isEditing
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.edit_note, size: 64, color: Colors.white24),
                                SizedBox(height: 16),
                                Text('选择或新增一个系统提示词', style: TextStyle(color: Colors.white54)),
                              ],
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 名称输入
                              Text('名称', style: TextStyle(color: AnimeColors.miku, fontSize: 13, fontWeight: FontWeight.w600)),
                              SizedBox(height: 8),
                              TextField(
                                controller: _nameController,
                                style: TextStyle(color: Colors.white70, fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: '输入提示词名称',
                                  hintStyle: TextStyle(color: Colors.white38),
                                  filled: true,
                                  fillColor: AnimeColors.darkBg,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                ),
                              ),
                              SizedBox(height: 16),
                              // 内容输入
                              Text('系统提示词内容', style: TextStyle(color: AnimeColors.miku, fontSize: 13, fontWeight: FontWeight.w600)),
                              SizedBox(height: 8),
                              Expanded(
                                child: TextField(
                                  controller: _contentController,
                                  maxLines: null,
                                  minLines: 10,
                                  style: TextStyle(color: Colors.white70, fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: '输入对大语言模型的角色设定...\n\n例如：你是一个专业的动漫剧本作家，擅长创作...',
                                    hintStyle: TextStyle(color: Colors.white38),
                                    filled: true,
                                    fillColor: AnimeColors.darkBg,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                    contentPadding: EdgeInsets.all(14),
                                  ),
                                ),
                              ),
                              SizedBox(height: 16),
                              // 操作按钮
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (_selectedPromptName != null)
                                    TextButton.icon(
                                      onPressed: _deletePrompt,
                                      icon: Icon(Icons.delete_outline, size: 18, color: AnimeColors.sakura),
                                      label: Text('删除', style: TextStyle(color: AnimeColors.sakura)),
                                    ),
                                  Spacer(),
                                  ElevatedButton.icon(
                                    onPressed: _saveCurrentPrompt,
                                    icon: Icon(Icons.save, size: 18),
                                    label: Text('保存'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AnimeColors.miku,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 添加提示词对话框 Widget
class _AddPromptDialog extends StatefulWidget {
  final Function(String name, String content) onSave;
  final VoidCallback onCancel;

  const _AddPromptDialog({
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_AddPromptDialog> createState() => _AddPromptDialogState();
}

class _AddPromptDialogState extends State<_AddPromptDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _contentController;
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _contentFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _contentController = TextEditingController();
    
    // 延迟聚焦，确保对话框完全显示后再聚焦
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    _nameFocusNode.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  void _handleSave() {
    final name = _nameController.text.trim();
    final content = _contentController.text.trim();
    
    if (name.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('请输入提示词名称和内容'),
          backgroundColor: AnimeColors.sakura,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    widget.onSave(name, content);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AnimeColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.add_circle_outline, color: AnimeColors.miku),
          SizedBox(width: 8),
          Text('添加提示词', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      ),
      content: Container(
        width: 500,
        constraints: BoxConstraints(maxHeight: 600),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 提示词名称输入框
              TextField(
                controller: _nameController,
                focusNode: _nameFocusNode,
                enabled: true,
                readOnly: false,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.next,
                style: TextStyle(color: Colors.white70, fontSize: 14),
                decoration: InputDecoration(
                  labelText: '提示词名称',
                  labelStyle: TextStyle(color: AnimeColors.miku),
                  filled: true,
                  fillColor: AnimeColors.darkBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AnimeColors.miku, width: 2),
                  ),
                  contentPadding: EdgeInsets.all(14),
                ),
                onSubmitted: (_) {
                  _contentFocusNode.requestFocus();
                },
              ),
              SizedBox(height: 20),
              // 提示词内容标签
              Text(
                '提示词内容',
                style: TextStyle(color: AnimeColors.miku, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              // 提示词内容输入框
              SizedBox(
                height: 300,
                child: TextField(
                  controller: _contentController,
                  focusNode: _contentFocusNode,
                  enabled: true,
                  readOnly: false,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  maxLines: null,
                  minLines: 10,
                  textAlignVertical: TextAlignVertical.top,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '在此输入提示词内容...',
                    hintStyle: TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: AnimeColors.darkBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AnimeColors.miku, width: 2),
                    ),
                    contentPadding: EdgeInsets.all(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: Text('取消', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: _handleSave,
          style: ElevatedButton.styleFrom(backgroundColor: AnimeColors.miku),
          child: Text('添加'),
        ),
      ],
    );
  }
}

class _PromptSettingsPanelState extends State<PromptSettingsPanel> {
  Map<String, Map<String, String>> _prompts = {
    'image': {},
    'video': {},
    'character': {},
    'scene': {},
    'prop': {},
  };
  
  String _selectedCategory = 'image';
  String? _selectedPromptName; // 当前选中的提示词名称
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  
  final List<Map<String, dynamic>> _categories = [
    {'key': 'image', 'name': '图片提示词', 'icon': Icons.image_outlined, 'color': AnimeColors.sakura},
    {'key': 'video', 'name': '视频提示词', 'icon': Icons.movie_outlined, 'color': AnimeColors.blue},
    {'key': 'character', 'name': '角色提示词', 'icon': Icons.person_outline, 'color': AnimeColors.purple},
    {'key': 'scene', 'name': '场景提示词', 'icon': Icons.landscape_outlined, 'color': AnimeColors.miku},
    {'key': 'prop', 'name': '物品提示词', 'icon': Icons.inventory_2_outlined, 'color': AnimeColors.orangeAccent},
  ];
  
  @override
  void dispose() {
    _contentController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadPrompts();
  }

  Future<void> _loadPrompts() async {
    final prefs = await SharedPreferences.getInstance();
    final promptsJson = prefs.getString('prompts');
    if (promptsJson != null) {
      try {
        final decoded = jsonDecode(promptsJson) as Map<String, dynamic>;
        setState(() {
          _prompts = {
            'image': Map<String, String>.from(decoded['image'] ?? {}),
            'video': Map<String, String>.from(decoded['video'] ?? {}),
            'character': Map<String, String>.from(decoded['character'] ?? {}),
            'scene': Map<String, String>.from(decoded['scene'] ?? {}),
            'prop': Map<String, String>.from(decoded['prop'] ?? {}),
          };
          // 如果有提示词，默认选中第一个
          final currentPrompts = _prompts[_selectedCategory] ?? {};
          if (currentPrompts.isNotEmpty && _selectedPromptName == null) {
            _selectedPromptName = currentPrompts.keys.first;
            _updateControllers();
          }
        });
      } catch (e) {
        logService.error('加载提示词失败', details: e.toString());
      }
    }
  }
  
  void _updateControllers() {
    if (_selectedPromptName != null) {
      final currentPrompts = _prompts[_selectedCategory] ?? {};
      _nameController.text = _selectedPromptName!;
      _contentController.text = currentPrompts[_selectedPromptName] ?? '';
    } else {
      _nameController.clear();
      _contentController.clear();
    }
  }
  
  void _selectPrompt(String name) {
    // 切换提示词时不自动保存，让用户手动保存
    setState(() {
      _selectedPromptName = name;
      _updateControllers();
    });
  }
  
  void _saveCurrentPrompt() {
    if (_selectedPromptName != null && _nameController.text.isNotEmpty) {
      final currentPrompts = _prompts[_selectedCategory] ?? {};
      // 如果名称改变了，需要更新键
      if (_selectedPromptName != _nameController.text) {
        currentPrompts.remove(_selectedPromptName);
        _selectedPromptName = _nameController.text;
      }
      currentPrompts[_nameController.text] = _contentController.text;
      _prompts[_selectedCategory] = currentPrompts;
    }
  }

  Future<void> _savePrompts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('prompts', jsonEncode(_prompts));
    logService.info('提示词已保存');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('提示词已保存'), backgroundColor: AnimeColors.miku),
    );
  }

  void _addNewPrompt() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        // 使用 StatefulWidget 来管理 Controller 的生命周期
        return _AddPromptDialog(
          onSave: (name, content) {
            final currentPrompts = _prompts[_selectedCategory] ?? {};
            currentPrompts[name] = content;
            _prompts[_selectedCategory] = currentPrompts;
            
            setState(() {
              _selectedPromptName = name;
              _updateControllers();
            });
            
            logService.action('添加提示词', details: name);
            Navigator.pop(dialogContext);
          },
          onCancel: () {
            Navigator.pop(dialogContext);
          },
        );
      },
    );
  }
  
  void _deletePrompt(String name) {
    _prompts[_selectedCategory]?.remove(name);
    
    // 如果删除的是当前选中的，需要重新选择
    if (_selectedPromptName == name) {
      final currentPrompts = _prompts[_selectedCategory] ?? {};
      if (currentPrompts.isNotEmpty) {
        // 选中第一个
        _selectedPromptName = currentPrompts.keys.first;
        _updateControllers();
      } else {
        // 没有提示词了，清空选中状态
        _selectedPromptName = null;
        _nameController.clear();
        _contentController.clear();
      }
    }
    
    setState(() {});
    logService.action('删除提示词', details: name);
  }

  @override
  Widget build(BuildContext context) {
    final currentCategory = _categories.firstWhere((c) => c['key'] == _selectedCategory);
    final currentPrompts = _prompts[_selectedCategory] ?? {};

    return Container(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Row(
            children: [
              Icon(Icons.text_snippet, color: AnimeColors.purple, size: 28),
              SizedBox(width: 12),
              Text('提示词设置', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
              Spacer(),
              ElevatedButton.icon(
                onPressed: () {
                  _saveCurrentPrompt();
                  _savePrompts();
                },
                icon: Icon(Icons.save, size: 18),
                label: Text('保存'),
                style: ElevatedButton.styleFrom(backgroundColor: AnimeColors.miku, foregroundColor: Colors.white),
              ),
            ],
          ),
          SizedBox(height: 24),
          // 分类选择
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _categories.map((cat) {
              final isSelected = _selectedCategory == cat['key'];
              return InkWell(
                onTap: () {
                  // 切换分类时不自动保存，让用户手动保存
                  setState(() {
                    _selectedCategory = cat['key'];
                    // 重置选中状态
                    final newPrompts = _prompts[_selectedCategory] ?? {};
                    _selectedPromptName = newPrompts.isNotEmpty ? newPrompts.keys.first : null;
                    _updateControllers();
                  });
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? (cat['color'] as Color).withOpacity(0.2) : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isSelected ? cat['color'] as Color : Colors.transparent),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(cat['icon'] as IconData, color: isSelected ? cat['color'] as Color : Colors.white54, size: 18),
                      SizedBox(width: 8),
                      Text(cat['name'] as String, style: TextStyle(color: isSelected ? cat['color'] as Color : Colors.white54, fontSize: 13)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          SizedBox(height: 20),
          // 左右分栏布局
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左侧：提示词名称列表
                Container(
                  width: 250,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AnimeColors.glassBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Icon(currentCategory['icon'] as IconData, color: currentCategory['color'] as Color, size: 18),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      currentCategory['name'] as String,
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                    ),
                                  ),
                                  Text(' (${currentPrompts.length})', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                ],
                              ),
                            ),
                            Divider(color: Colors.white.withOpacity(0.1), height: 1),
                            Expanded(
                              child: currentPrompts.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.text_snippet_outlined, size: 48, color: Colors.white24),
                                          SizedBox(height: 12),
                                          Text('暂无提示词', style: TextStyle(color: Colors.white38, fontSize: 13)),
                                          SizedBox(height: 8),
                                          TextButton.icon(
                                            onPressed: _addNewPrompt,
                                            icon: Icon(Icons.add, size: 16),
                                            label: Text('添加'),
                                            style: TextButton.styleFrom(foregroundColor: currentCategory['color'] as Color),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ListView.builder(
                                      padding: EdgeInsets.all(8),
                                      itemCount: currentPrompts.length,
                                      itemBuilder: (context, index) {
                                        final name = currentPrompts.keys.elementAt(index);
                                        final isSelected = _selectedPromptName == name;
                                        return InkWell(
                                          onTap: () => _selectPrompt(name),
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            margin: EdgeInsets.only(bottom: 4),
                                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: isSelected ? (currentCategory['color'] as Color).withOpacity(0.2) : Colors.transparent,
                                              borderRadius: BorderRadius.circular(8),
                                              border: isSelected ? Border.all(color: currentCategory['color'] as Color, width: 1.5) : null,
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    name,
                                                    style: TextStyle(
                                                      color: isSelected ? currentCategory['color'] as Color : Colors.white70,
                                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                                      fontSize: 13,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (isSelected)
                                                  Icon(Icons.check_circle, color: currentCategory['color'] as Color, size: 16),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                            Divider(color: Colors.white.withOpacity(0.1), height: 1),
                            Padding(
                              padding: EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _addNewPrompt,
                                      icon: Icon(Icons.add, size: 16),
                                      label: Text('添加'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: currentCategory['color'] as Color,
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.symmetric(vertical: 10),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                // 右侧：提示词内容编辑区
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AnimeColors.glassBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: _selectedPromptName == null
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.edit_note_outlined, size: 64, color: Colors.white24),
                                    SizedBox(height: 16),
                                    Text('请选择或添加提示词', style: TextStyle(color: Colors.white54, fontSize: 16)),
                                  ],
                                ),
                              )
                            : Padding(
                                padding: EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 名称编辑和删除按钮
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _nameController,
                                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                                            decoration: InputDecoration(
                                              hintText: '提示词名称',
                                              hintStyle: TextStyle(color: Colors.white38),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                borderSide: BorderSide(color: Colors.white10),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                borderSide: BorderSide(color: Colors.white10),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                borderSide: BorderSide(color: currentCategory['color'] as Color, width: 2),
                                              ),
                                              filled: true,
                                              fillColor: AnimeColors.cardBg,
                                              contentPadding: EdgeInsets.all(14),
                                            ),
                                            // 名称可以修改，但不自动保存
                                          ),
                                        ),
                                        SizedBox(width: 12),
                                        IconButton(
                                          icon: Icon(Icons.delete_outline, color: AnimeColors.sakura),
                                          onPressed: () => _deletePrompt(_selectedPromptName!),
                                          tooltip: '删除',
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 20),
                                    Row(
                                      children: [
                                        Text(
                                          '提示词内容',
                                          style: TextStyle(
                                            color: currentCategory['color'] as Color,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Spacer(),
                                        ElevatedButton.icon(
                                          onPressed: () {
                                            _saveCurrentPrompt();
                                            _savePrompts();
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('提示词已保存'),
                                                backgroundColor: AnimeColors.miku,
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          },
                                          icon: Icon(Icons.save, size: 16),
                                          label: Text('保存'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: currentCategory['color'] as Color,
                                            foregroundColor: Colors.white,
                                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 12),
                                    // 内容编辑框（可滚动）
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: AnimeColors.cardBg,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.white10),
                                        ),
                                        child: TextField(
                                          controller: _contentController,
                                          maxLines: null,
                                          minLines: 10,
                                          textAlignVertical: TextAlignVertical.top,
                                          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
                                          decoration: InputDecoration(
                                            hintText: '在此输入提示词内容...',
                                            hintStyle: TextStyle(color: Colors.white38),
                                            border: InputBorder.none,
                                            contentPadding: EdgeInsets.all(16),
                                          ),
                                          // 移除自动保存，改为手动保存
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 风格设置面板 ====================
class StyleSettingsPanel extends StatefulWidget {
  const StyleSettingsPanel({super.key});

  @override
  State<StyleSettingsPanel> createState() => _StyleSettingsPanelState();
}

class _StyleSettingsPanelState extends State<StyleSettingsPanel> {
  String _previewTheme = 'default'; // 当前预览的主题
  String _savedTheme = 'default';   // 已保存的主题

  final List<Map<String, dynamic>> _themes = [
    {
      'id': 'default',
      'name': '星橙默认',
      'description': '深色调搭配初音绿与梦幻紫',
      'preview': [AnimeColors.darkBg, AnimeColors.miku, AnimeColors.purple],
    },
    {
      'id': 'sakura',
      'name': '樱花粉韵',
      'description': '柔和粉色系温馨风格',
      'preview': [Color(0xFF1a0f14), Color(0xFFFFB7C5), Color(0xFFFF69B4)],
    },
    {
      'id': 'ocean',
      'name': '深海蔚蓝',
      'description': '冷色调海洋深邃风格',
      'preview': [Color(0xFF0a1420), Color(0xFF1E90FF), Color(0xFF00CED1)],
    },
    {
      'id': 'sunset',
      'name': '落日余晖',
      'description': '暖色调黄昏渐变风格',
      'preview': [Color(0xFF1a1008), Color(0xFFFF8C00), Color(0xFFFFD700)],
    },
    {
      'id': 'forest',
      'name': '森林秘境',
      'description': '自然绿色生机盎然',
      'preview': [Color(0xFF0a140a), Color(0xFF228B22), Color(0xFF32CD32)],
    },
    {
      'id': 'cyberpunk',
      'name': '赛博朋克',
      'description': '霓虹紫红科幻风格',
      'preview': [Color(0xFF0d0a14), Color(0xFFFF1493), Color(0xFF00FFFF)],
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    setState(() {
      _previewTheme = themeManager.currentTheme;
      _savedTheme = themeManager.currentTheme;
    });
  }

  void _selectThemePreview(String themeId) {
    setState(() {
      _previewTheme = themeId;
    });
    // 立即切换主题预览
    themeManager.setTheme(themeId);
    logService.action('预览主题', details: themeId);
  }

  Future<void> _saveTheme() async {
    setState(() => _savedTheme = _previewTheme);
    logService.action('保存主题', details: _previewTheme);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('主题已保存'), backgroundColor: AnimeColors.miku),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题和保存按钮
          Row(
            children: [
              Icon(Icons.palette, color: AnimeColors.sakura, size: 28),
              SizedBox(width: 12),
              Text('风格设置', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
              Spacer(),
              // 保存按钮
              ElevatedButton.icon(
                onPressed: _previewTheme != _savedTheme ? _saveTheme : null,
                icon: Icon(Icons.save, size: 18),
                label: Text('保存风格'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _previewTheme != _savedTheme ? AnimeColors.miku : Colors.grey,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text('选择喜欢的界面主题，打造专属创作空间', style: TextStyle(color: Colors.white54, fontSize: 14)),
          SizedBox(height: 24),
          // 主题网格
          Expanded(
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.6,
              ),
              itemCount: _themes.length,
              itemBuilder: (context, index) {
                final theme = _themes[index];
                final isSelected = _previewTheme == theme['id'];
                final isSaved = _savedTheme == theme['id'];
                final colors = theme['preview'] as List<Color>;

                return InkWell(
                  onTap: () => _selectThemePreview(theme['id']),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colors[0], colors[0].withOpacity(0.8)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? colors[1] : Colors.white.withOpacity(0.1),
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isSelected
                          ? [BoxShadow(color: colors[1].withOpacity(0.3), blurRadius: 12, spreadRadius: 2)]
                          : null,
                    ),
                    child: Stack(
                      children: [
                        // 颜色预览条
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [colors[1], colors[2]]),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(14),
                                topRight: Radius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        // 内容
                        Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Row(
                                children: [
                                  if (isSaved)
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: colors[1].withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text('已保存', style: TextStyle(color: colors[1], fontSize: 10, fontWeight: FontWeight.w600)),
                                    ),
                                  if (isSaved) SizedBox(width: 8),
                                  if (isSelected && !isSaved)
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: colors[1].withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text('预览中', style: TextStyle(color: colors[1], fontSize: 10, fontWeight: FontWeight.w600)),
                                    ),
                                  if (isSelected && !isSaved) SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      theme['name'],
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 6),
                              Text(
                                theme['description'],
                                style: TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                              SizedBox(height: 10),
                              // 颜色预览圆点
                              Row(
                                children: colors.skip(1).map((c) {
                                  return Container(
                                    margin: EdgeInsets.only(right: 6),
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white24),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 角色创建页面（Sora2 上传角色）
// ==========================================

class CharacterCreatePage extends StatefulWidget {
  const CharacterCreatePage({super.key});

  @override
  State<CharacterCreatePage> createState() => _CharacterCreatePageState();
}

class _CharacterCreatePageState extends State<CharacterCreatePage> {
  final ImagePicker _imagePicker = ImagePicker();
  final FFmpegService _ffmpegService = FFmpegService();
  bool _isLoading = false;
  List<Map<String, dynamic>> _characters = []; // 存储已创建的角色

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AnimeColors.darkBg,
              Color(0xFF0f0f1e),
              Color(0xFF1a1a2e),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 顶部标题栏
              Container(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Sora2 角色上传',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              // 上传按钮
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _uploadCharacter,
                    icon: Icon(
                      _isLoading ? Icons.hourglass_empty : Icons.cloud_upload,
                      size: 24,
                    ),
                    label: Text(
                      _isLoading ? '处理中...' : 'Sora2 上传角色',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AnimeColors.miku,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                    ),
                  ),
                ),
              ),
              // 角色列表
              Expanded(
                child: _characters.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 80,
                              color: Colors.white24,
                            ),
                            SizedBox(height: 20),
                            Text(
                              '暂无角色',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              '点击上方按钮上传角色图片',
                              style: TextStyle(
                                color: Colors.white24,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.all(20),
                        itemCount: _characters.length,
                        itemBuilder: (context, index) {
                          final character = _characters[index];
                          return _buildCharacterCard(character);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 构建角色卡片
  Widget _buildCharacterCard(Map<String, dynamic> character) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AnimeColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          // 图片
          ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              bottomLeft: Radius.circular(16),
            ),
            child: Image.file(
              File(character['imagePath'] as String),
              width: 120,
              height: 120,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 120,
                  height: 120,
                  color: Colors.grey[800],
                  child: Icon(Icons.error, color: Colors.white54),
                );
              },
            ),
          ),
          // 信息
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 角色代码
                  Row(
                    children: [
                      Icon(Icons.tag, color: AnimeColors.miku, size: 16),
                      SizedBox(width: 6),
                      Text(
                        '@${character['code'] ?? '未知'}',
                        style: TextStyle(
                          color: AnimeColors.miku,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  // 角色名称
                  if (character['name'] != null)
                    Text(
                      character['name'] as String,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 上传角色
  Future<void> _uploadCharacter() async {
    // 1. 选择图片
    final XFile? pickedFile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );

    if (pickedFile == null) {
      // 用户取消选择
      return;
    }

    final imageFile = File(pickedFile.path);

      // 2. 显示全屏 Loading
      String currentMessage = '正在构建角色模型，请稍候...';
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => WillPopScope(
          onWillPop: () async => false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                // 创建一个函数来更新消息
                final updateMessage = (String message) {
                  currentMessage = message;
                  setDialogState(() {});
                };

                // 异步执行上传流程
                Future.microtask(() async {
                  File? videoFile;
                  try {
                    // 3. 转换图片为视频
                    updateMessage('步骤 1/3: 正在转换图片为视频...');
                    videoFile = await _ffmpegService.convertImageToVideo(imageFile);

                    // 4. 创建 SoraApiService 实例（使用视频模型的 API 配置，Supabase Storage 配置已内置）
                    final soraApiService = SoraApiService(
                      baseUrl: apiConfigManager.videoBaseUrl,
                      apiKey: apiConfigManager.videoApiKey,
                    );

                    // 5. 上传视频到 Supabase Storage
                    updateMessage('步骤 2/3: 正在上传视频到 Supabase Storage...');
                    final videoUrl = await soraApiService.uploadVideoToOss(videoFile);

                    // 6. 创建角色
                    updateMessage('步骤 3/3: 正在注册角色...');
                    final characterData = await soraApiService.createCharacter(videoUrl);

                    // 7. 隐藏 Loading
                    if (mounted && Navigator.canPop(dialogContext)) {
                      Navigator.pop(dialogContext);
                    }

                    // 8. 添加到列表
                    setState(() {
                      _characters.insert(0, {
                        'code': characterData['id'] ?? characterData['username'] ?? '未知',
                        'name': characterData['username'] ?? characterData['name'] ?? '未命名',
                        'imagePath': imageFile.path,
                        'videoUrl': videoUrl,
                      });
                    });

                    // 9. 显示成功提示
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('角色创建成功！代码: @${characterData['id'] ?? '未知'}'),
                          backgroundColor: AnimeColors.miku,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }

                    logService.info(
                      '角色创建成功',
                      details: '代码: ${characterData['id']}, 名称: ${characterData['username']}',
                    );
                  } catch (e) {
                    // 隐藏 Loading
                    if (mounted && Navigator.canPop(dialogContext)) {
                      Navigator.pop(dialogContext);
                    }

                    // 显示错误提示
                    logService.error('上传角色失败', details: e.toString());
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('上传失败: ${e.toString()}'),
                          backgroundColor: AnimeColors.sakura,
                          duration: Duration(seconds: 5),
                        ),
                      );
                    }
                  } finally {
                    // 10. 清理临时视频文件
                    if (videoFile != null && await videoFile.exists()) {
                      await _ffmpegService.cleanupTempFile(videoFile);
                    }
                  }
                });

                return Container(
                  padding: EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AnimeColors.cardBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        color: AnimeColors.miku,
                        strokeWidth: 4,
                      ),
                      SizedBox(height: 24),
                      Text(
                        currentMessage,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
  }
}
