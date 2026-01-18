import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pool/pool.dart';
import '../../models/auto_mode_project.dart';
import '../../models/scene_status.dart';
import '../../models/prompt_template.dart';
import '../../services/prompt_store.dart';
import '../../services/api_config_manager.dart';
import '../../services/ffmpeg_service.dart';
import '../../services/heavy_task_runner.dart';
import '../../services/api_service.dart';

// 用于启动不等待的异步任务
void unawaited(Future<void> future) {
  // 忽略 future，仅用于启动异步任务
}

/// 媒体生成 Mixin（图片和视频）
/// 
/// 负责 Auto Mode 中图片和视频生成相关的逻辑
mixin MediaGenerationMixin on ChangeNotifier {
  // 这些属性需要在主类中定义
  Map<String, AutoModeProject> get projects;
  Map<String, bool> get isAborted;
  bool get isDisposed;
  
  // 这些方法需要在主类中实现
  Future<void> performSave(String projectId);
  void safeNotifyListeners();
  void markDirty(String projectId);
  
  /// 生成所有图片（使用 Pool 限制并发，Isolate 处理重操作，针对特定项目）
  /// CRITICAL: 第一行必须保存状态，标记为"处理中"，防止崩溃时数据丢失
  Future<void> generateAllImages(String projectId) async {
    try {
      final project = projects[projectId];
      if (project == null) {
        throw Exception('项目不存在: $projectId');
      }
      
      // CRITICAL: 第一行立即保存状态，标记为"处理中"
      project.isProcessing = true;
      project.generationStatus = '正在生成图片...';
      await performSave(projectId);
      
      final apiConfigManager = ApiConfigManager();
      if (!apiConfigManager.hasImageConfig) {
        project.isProcessing = false;
        project.generationStatus = null;
        throw Exception('请先在设置中配置图片生成 API');
      }

      // 重置断路器状态
      isAborted[projectId] = false;

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
      safeNotifyListeners();

      // 使用 Pool 限制并发数为 2
      final pool = Pool(2, timeout: Duration(minutes: 10));
      final completer = Completer<void>();
      final completedCount = <int>[0];  // 使用列表包装以便在闭包中修改
      final totalCount = project.scenes.length;
      final errors = <String>[];

      // 为每个场景创建生成任务
      for (int i = 0; i < project.scenes.length; i++) {
        // 如果已中止（500错误），停止后续生成
        if (isAborted[projectId] == true) {
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
        unawaited(processSceneWithPool(
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
          print('[MediaGenerationMixin] 场景 ${sceneIndex + 1} 处理失败: $e');
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
            safeNotifyListeners();
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
      await performSave(projectId);
    } catch (e, stackTrace) {
      print('[MediaGenerationMixin] 生成所有图片失败: $e');
      print('[MediaGenerationMixin] 堆栈: $stackTrace');
      rethrow;
    }
  }

  /// 使用严格的 try-finally 模式处理单个场景的图片生成
  /// 确保 Pool 资源只在 finally 块中释放
  Future<void> processSceneWithPool({
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
      if (isAborted[projectId] == true) {
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
        safeNotifyListeners();
      }

      // 生成图片（包含错误隔离，返回 null 表示失败）
      final result = await generateSingleImageSafe(
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
            isAborted[projectId] = true;
            errors.add('场景 ${sceneIndex + 1}: 服务器错误，已停止后续生成');
          } else {
            errors.add('场景 ${sceneIndex + 1}: ${errorMsg}');
          }
        }
      } else {
        // 成功，状态已在 generateSingleImageSafe 中更新
        markDirty(projectId);
      }
    } catch (e, stackTrace) {
      print('[MediaGenerationMixin] 项目 $projectId 场景 ${sceneIndex + 1} 生成失败: $e');
      print('[MediaGenerationMixin] 堆栈: $stackTrace');
      
      // 更新失败状态（这不应该发生，因为 generateSingleImageSafe 已经处理了）
      if (sceneIndex < project.scenes.length) {
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          isGeneratingImage: false,
          imageGenerationProgress: 0.0,
          status: SceneStatus.error,
          errorMessage: e.toString(),
          generationStatus: null,
        );
        errors.add('场景 ${sceneIndex + 1}: $e');
        safeNotifyListeners();
      }
    } finally {
      // 只在 finally 块中释放 Pool 资源 - 确保资源总是被释放，无论成功或失败
      // 注意：不要在其他地方调用 release()，避免双重释放
      resource.release();
      
      // 原子性 Completer：检查是否已完成，避免 "Future already completed" 错误
      completedCount[0]++;
      if (completedCount[0] >= totalCount && !completer.isCompleted) {
        if (errors.isNotEmpty && isAborted[projectId] != true) {
          completer.completeError(Exception('部分图片生成失败:\n${errors.join('\n')}'));
        } else {
          completer.complete();
        }
      }
    }
  }

  /// 生成单个图片（安全版本，包含错误隔离和 Isolate 处理，针对特定项目）
  /// 返回 null 表示失败，已更新场景状态
  /// 支持根据角色名字匹配并上传角色图片
  Future<Map<String, String?>?> generateSingleImageSafe({
    required String projectId,
    required dynamic apiService,
    required ApiConfigManager apiConfigManager,
    required HeavyTaskRunner taskRunner,
    required String prompt,
    required int sceneIndex,
    List<String>? referenceImages,  // 参考图片列表（角色图片路径）
  }) async {
    final project = projects[projectId];
    if (project == null) return null;
    
    // 500 错误断路器：如果已中止，直接返回
    if (isAborted[projectId] == true) {
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
        safeNotifyListeners();
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
      if (isAborted[projectId] == true) {
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
        safeNotifyListeners();
      }

      // 保存图片到本地（使用 Isolate 处理）
      final localImagePath = await saveImageToLocalSafe(
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
        safeNotifyListeners();
      }

      return {
        'imageUrl': response.imageUrl,
        'localImagePath': localImagePath,
      };
    } catch (e, stackTrace) {
      print('[MediaGenerationMixin] 项目 $projectId 生成图片失败 (场景 $sceneIndex): $e');
      print('[MediaGenerationMixin] 堆栈: $stackTrace');
      
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
        safeNotifyListeners();
      }
      
      // 返回 null 表示失败
      return null;
    }
  }

  /// 保存图片到本地（安全版本，使用 Isolate 处理重操作）
  Future<String?> saveImageToLocalSafe({
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
          print('[MediaGenerationMixin] 下载图片失败: ${response.statusCode}');
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
      imageBytes = Uint8List(0);
      
      print('[MediaGenerationMixin] 图片已保存到本地: $savedPath');
      return savedPath; // 返回绝对路径
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 保存图片到本地失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
      return null;
    }
  }

  /// 重新生成指定场景的图片（使用 Pool 和 Isolate，针对特定项目）
  Future<void> regenerateImage(String projectId, int sceneIndex) async {
    final project = projects[projectId];
    if (project == null) return;
    
    if (sceneIndex < 0 || sceneIndex >= project.scenes.length) return;

    final scene = project.scenes[sceneIndex];
    project.scenes[sceneIndex] = scene.copyWith(
      isGeneratingImage: true,
      imageGenerationProgress: 0.0,
      generationStatus: 'queueing',
    );
    safeNotifyListeners();

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
        safeNotifyListeners();

        // 生成图片（包含错误隔离，支持角色图片参考）
        final result = await generateSingleImageSafe(
          projectId: projectId,
          apiService: apiService,
          apiConfigManager: apiConfigManager,
          taskRunner: taskRunner,
          prompt: finalPrompt,
          sceneIndex: sceneIndex,
          referenceImages: matchedCharacterImages.isNotEmpty ? matchedCharacterImages : null,
        );

        // 如果成功，状态已在 generateSingleImageSafe 中更新
        if (result != null) {
          markDirty(projectId);
          safeNotifyListeners();
        }
      } catch (e, stackTrace) {
        print('[MediaGenerationMixin] 项目 $projectId 重新生成图片失败: $e');
        print('[MediaGenerationMixin] 堆栈: $stackTrace');
        
        // CRITICAL: 在错误状态下，确保重置状态并设置错误信息
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          isGeneratingImage: false,
          imageGenerationProgress: 0.0,
          generationStatus: null,
          status: SceneStatus.error,
          errorMessage: e.toString(),
        );
        safeNotifyListeners();
        rethrow;
      } finally {
        resource.release();
      }
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] regenerateImage 失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
      // CRITICAL: 在错误状态下，确保重置状态并设置错误信息
      project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
        isGeneratingImage: false,
        imageGenerationProgress: 0.0,
        generationStatus: null,
        status: SceneStatus.error,
        errorMessage: e.toString(),
      );
      safeNotifyListeners();
      rethrow;
    }
  }
  
  /// 生成所有视频（针对特定项目）
  /// CRITICAL: 第一行必须保存状态，标记为"处理中"，防止崩溃时数据丢失
  Future<void> generateAllVideos(String projectId) async {
    final project = projects[projectId];
    if (project == null) {
      throw Exception('项目不存在: $projectId');
    }
    
    // CRITICAL: 第一行立即保存状态，标记为"处理中"
    project.isProcessing = true;
    project.generationStatus = '正在生成视频...';
    await performSave(projectId);
    
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
    isAborted[projectId] = false;

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
      safeNotifyListeners();
      return;
    }

    safeNotifyListeners();

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
        processSceneVideoWithPool(
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
          print('[MediaGenerationMixin] 场景 ${sceneIndex + 1} 视频处理失败: $e');
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
            safeNotifyListeners();
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
      await performSave(projectId);
    } catch (e, stackTrace) {
      print('[MediaGenerationMixin] 生成所有视频失败: $e');
      print('[MediaGenerationMixin] 堆栈: $stackTrace');
      rethrow;
    } finally {
      project.isProcessing = false;
      project.generationStatus = null;
      safeNotifyListeners();
    }
  }

  /// 使用严格的 try-finally 模式处理单个场景的视频生成
  /// 确保 Pool 资源只在 finally 块中释放
  Future<void> processSceneVideoWithPool({
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
      if (isAborted[projectId] == true) {
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
        safeNotifyListeners();
      }

      // 生成视频（包含错误隔离，返回 null 表示失败）
      final result = await generateSingleVideoSafe(
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
            isAborted[projectId] = true;
            errors.add('场景 ${sceneIndex + 1}: 服务器错误，已停止后续生成');
          } else {
            errors.add('场景 ${sceneIndex + 1}: ${errorMsg}');
          }
        }
      } else {
        // 成功，状态已在 generateSingleVideoSafe 中更新
        markDirty(projectId);
      }
    } catch (e, stackTrace) {
      print('[MediaGenerationMixin] 项目 $projectId 场景 ${sceneIndex + 1} 视频生成失败: $e');
      print('[MediaGenerationMixin] 堆栈: $stackTrace');
      
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
        safeNotifyListeners();
      }
    } finally {
      // 只在 finally 块中释放 Pool 资源
      resource.release();
      
      // 原子性 Completer：检查是否已完成
      completedCount[0]++;
      if (completedCount[0] >= totalCount && !completer.isCompleted) {
        if (errors.isNotEmpty && isAborted[projectId] != true) {
          completer.completeError(Exception('部分视频生成失败:\n${errors.join('\n')}'));
        } else {
          completer.complete();
        }
      }
    }
  }

  /// 生成单个视频（安全版本，包含错误隔离）
  /// 返回 null 表示失败，已更新场景状态
  /// 注意：此方法包含轮询逻辑，实现实时进度同步
  Future<Map<String, String?>?> generateSingleVideoSafe({
    required String projectId,
    required dynamic apiService,
    required ApiConfigManager apiConfigManager,
    required HeavyTaskRunner taskRunner,
    required String prompt,
    required int sceneIndex,
  }) async {
    final project = projects[projectId];
    if (project == null) return null;
    
    // 500 错误断路器：如果已中止，直接返回
    if (isAborted[projectId] == true) {
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
          videoGenerationProgress: 0.0,
          status: SceneStatus.processing,
          errorMessage: null,
        );
        safeNotifyListeners();
      }

      // 获取场景图片作为参考
      File? inputReferenceFile;
      final scene = project.scenes[sceneIndex];
      if (scene.localImagePath != null && scene.localImagePath!.isNotEmpty) {
        final imageFile = File(scene.localImagePath!);
        if (await imageFile.exists()) {
          inputReferenceFile = imageFile;
          print('[MediaGenerationMixin] 使用场景图片作为视频生成参考: ${scene.localImagePath}');
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
            print('[MediaGenerationMixin] 已下载场景图片作为视频生成参考: ${tempFile.path}');
          }
        } catch (e, stackTrace) {
          print('❌ [CRITICAL ERROR CAUGHT] 下载场景图片失败');
          print('❌ [Error Details]: $e');
          print('📍 [Stack Trace]: $stackTrace');
          print('[MediaGenerationMixin] 将不使用图片参考');
        }
      }
      
      // 调用 API 创建视频任务（使用场景图片作为参考）
      final response = await apiService.createVideo(
        model: apiConfigManager.videoModel,
        prompt: prompt,
        size: apiConfigManager.videoSize,
        seconds: apiConfigManager.videoSeconds,
        inputReference: inputReferenceFile,
      );
      
      // 再次检查断路器
      if (isAborted[projectId] == true) {
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
          videoGenerationProgress: 0.0,
        );
        safeNotifyListeners();
      }

      // CRITICAL: 轮询获取视频 URL（最多600次，每次1秒，总共10分钟）
      String? videoUrl;
      int maxRetries = 600;
      bool hasProgressInfo = false;
      
      for (int retry = 0; retry < maxRetries; retry++) {
        await Future.delayed(Duration(seconds: 1));
        
        // 检查断路器
        if (isAborted[projectId] == true) {
          if (sceneIndex < project.scenes.length) {
            project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
              isGeneratingVideo: false,
              videoGenerationProgress: 0.0,
              status: SceneStatus.idle,
              errorMessage: null,
              generationStatus: null,
            );
            safeNotifyListeners();
          }
          return null;
        }

        try {
          final detail = await apiService.getVideoTask(taskId: taskId);
          
          print('[MediaGenerationMixin] 场景 ${sceneIndex + 1} API返回: status=${detail.status}, progress=${detail.progress}');
          
          // 根据 API 返回的状态和进度实时更新UI
          if (detail.status == 'completed' && detail.videoUrl != null) {
            videoUrl = detail.videoUrl;
            if (sceneIndex < project.scenes.length) {
              project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
                videoUrl: videoUrl,
                videoGenerationProgress: 1.0,
                isGeneratingVideo: false,
                status: SceneStatus.success,
                generationStatus: null,
                errorMessage: null,
              );
              safeNotifyListeners();
            }
            break;
          } else if (detail.status == 'failed' || detail.status == 'error') {
            final errorMsg = detail.error != null 
              ? '${detail.error!.message} (${detail.error!.code})'
              : '视频生成失败';
            
            if (sceneIndex < project.scenes.length) {
              project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
                isGeneratingVideo: false,
                videoGenerationProgress: 0.0,
                status: SceneStatus.error,
                generationStatus: null,
                errorMessage: errorMsg,
              );
              safeNotifyListeners();
            }
            
            throw ApiException(errorMsg);
          } else if (detail.status == 'processing' || detail.status == 'pending' || 
                     detail.status == 'queued' || detail.status == 'in_progress') {
            hasProgressInfo = true;
            
            if (sceneIndex < project.scenes.length) {
              final apiProgress = detail.progress.clamp(0, 100);
              final normalizedProgress = apiProgress / 100.0;
              
              String generationStatus;
              if (detail.status == 'queued' && apiProgress == 0) {
                generationStatus = 'queueing';
              } else if (detail.status == 'queued' && apiProgress > 0) {
                generationStatus = 'processing';
              } else {
                generationStatus = 'processing';
              }
              
              project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
                videoGenerationProgress: normalizedProgress.clamp(0.0, 1.0),
                status: SceneStatus.processing,
                generationStatus: generationStatus,
                errorMessage: null,
              );
              safeNotifyListeners();
            }
          }
        } catch (e, stackTrace) {
          print('❌ [CRITICAL ERROR CAUGHT] API 轮询失败');
          print('❌ [Error Details]: $e');
          print('📍 [Stack Trace]: $stackTrace');
          if (e is ApiException && e.message.contains('失败')) {
            if (sceneIndex < project.scenes.length) {
              final currentScene = project.scenes[sceneIndex];
              if (currentScene.status != SceneStatus.error) {
                project.scenes[sceneIndex] = currentScene.copyWith(
                  isGeneratingVideo: false,
                  videoGenerationProgress: 0.0,
                  status: SceneStatus.error,
                  generationStatus: null,
                  errorMessage: e.toString(),
                );
                safeNotifyListeners();
              }
            }
            rethrow;
          }
          
          // 网络错误，继续重试
          print('[MediaGenerationMixin] 场景 ${sceneIndex + 1} 视频查询失败（第${retry + 1}次）: $e');
        }
      }

      if (videoUrl == null) {
        if (hasProgressInfo) {
          if (sceneIndex < project.scenes.length) {
            project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
              isGeneratingVideo: false,
              status: SceneStatus.processing,
              generationStatus: 'processing',
              errorMessage: '视频生成时间较长，请稍候或点击"重新生成"检查状态',
            );
            safeNotifyListeners();
          }
          return null;
        } else {
          throw ApiException('视频生成超时：未收到进度信息');
        }
      }

      // 保存视频到本地（异步）
      final savedVideoUrl = videoUrl;
      unawaited(saveVideoToLocal(savedVideoUrl).then((savedLocalPath) {
        if (sceneIndex < project.scenes.length && !isDisposed) {
          project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
            localVideoPath: savedLocalPath,
          );
          safeNotifyListeners();
        }
      }).catchError((e) {
        print('[MediaGenerationMixin] 保存视频到本地失败: $e');
      }));
      
      // 立即更新状态为完成
      if (sceneIndex < project.scenes.length) {
        project.scenes[sceneIndex] = project.scenes[sceneIndex].copyWith(
          videoUrl: videoUrl,
          isGeneratingVideo: false,
          videoGenerationProgress: 1.0,
          status: SceneStatus.success,
          errorMessage: null,
          generationStatus: null,
        );
        safeNotifyListeners();
      }

      return {
        'videoUrl': videoUrl,
        'localVideoPath': null,
      };
    } catch (e, stackTrace) {
      print('[MediaGenerationMixin] 场景 ${sceneIndex + 1} 视频生成失败: $e');
      print('[MediaGenerationMixin] 堆栈: $stackTrace');
      
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
        safeNotifyListeners();
      }
      
      return null;
    }
  }

  /// 保存视频到本地
  Future<String?> saveVideoToLocal(String videoUrl) async {
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

      print('[MediaGenerationMixin] 开始下载视频: $videoUrl');
      final response = await http.get(Uri.parse(videoUrl));
      if (response.statusCode == 200) {
        final fileName = 'auto_mode_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final file = File('$savePath${Platform.pathSeparator}$fileName');
        await file.writeAsBytes(response.bodyBytes);
        final filePath = file.path;
        
        print('[MediaGenerationMixin] 视频已保存到本地: $filePath');
        return filePath;
      } else {
        print('[MediaGenerationMixin] 下载视频失败: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 保存视频到本地失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
    }
    return null;
  }

  /// 重新生成单个场景的视频
  Future<void> regenerateVideo(String projectId, int sceneIndex) async {
    final project = projects[projectId];
    if (project == null) return;
    
    if (sceneIndex < 0 || sceneIndex >= project.scenes.length) return;

    final scene = project.scenes[sceneIndex];
    
    // 检查是否有图片
    final hasImage = (scene.imageUrl != null && scene.imageUrl!.isNotEmpty) ||
                    (scene.localImagePath != null && scene.localImagePath!.isNotEmpty);
    if (!hasImage) {
      throw Exception('场景 ${sceneIndex + 1} 没有图片，无法生成视频');
    }

    // 清除所有之前的错误信息和视频URL，准备重新生成
    project.scenes[sceneIndex] = scene.copyWith(
      isGeneratingVideo: true,
      videoGenerationProgress: 0.0,
      generationStatus: 'queueing',
      status: SceneStatus.queueing,
      errorMessage: null,
      videoUrl: null,
      localVideoPath: null,
      // 保留图片相关字段
      imageUrl: scene.imageUrl,
      localImagePath: scene.localImagePath,
      imagePrompt: scene.imagePrompt,
      script: scene.script,
      index: scene.index,
    );
    safeNotifyListeners();

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

      final currentScene = project.scenes[sceneIndex];
      String finalPrompt = currentScene.imagePrompt;
      if (templateContent != null && templateContent.isNotEmpty) {
        finalPrompt = '$templateContent\n\n$finalPrompt';
      }

      // 使用 Pool 限制并发
      final pool = Pool(2, timeout: Duration(minutes: 10));
      final resource = await pool.request();

      try {
        project.scenes[sceneIndex] = currentScene.copyWith(
          generationStatus: 'processing',
          videoGenerationProgress: 0.1,
          imageUrl: currentScene.imageUrl,
          localImagePath: currentScene.localImagePath,
          imagePrompt: currentScene.imagePrompt,
          script: currentScene.script,
        );
        safeNotifyListeners();

        final result = await generateSingleVideoSafe(
          projectId: projectId,
          apiService: apiService,
          apiConfigManager: apiConfigManager,
          taskRunner: taskRunner,
          prompt: finalPrompt,
          sceneIndex: sceneIndex,
        );

        if (result == null) {
          throw Exception(project.scenes[sceneIndex].errorMessage ?? '视频生成失败');
        }
      } finally {
        resource.release();
      }
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] regenerateVideo 失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
      final currentScene = project.scenes[sceneIndex];
      project.scenes[sceneIndex] = currentScene.copyWith(
        isGeneratingVideo: false,
        videoGenerationProgress: 0.0,
        generationStatus: null,
        status: SceneStatus.error,
        errorMessage: e.toString(),
        imageUrl: currentScene.imageUrl,
        localImagePath: currentScene.localImagePath,
        imagePrompt: currentScene.imagePrompt,
        script: currentScene.script,
        index: currentScene.index,
      );
      safeNotifyListeners();
      rethrow;
    }
  }

  /// 最终合并视频（针对特定项目）
  Future<void> finalizeVideo(String projectId) async {
    final project = projects[projectId];
    if (project == null) {
      throw Exception('项目不存在: $projectId');
    }
    
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
            print('❌ [CRITICAL ERROR CAUGHT] 下载视频失败（合并）');
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
    markDirty(projectId);
    safeNotifyListeners();
  }
}
