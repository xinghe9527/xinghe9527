import 'dart:io';
import 'providers/base_provider.dart';
import 'providers/geeknow_provider.dart';

/// API 管理器 - 单例模式（混合服务商模式）
/// 
/// 负责管理多个 API 供应商，支持为 LLM、图片、视频分别配置不同的供应商
/// 这种 Mix & Match 模式提供最大的灵活性
/// 
/// 使用示例：
/// ```dart
/// // 设置不同的供应商
/// ApiManager().setLlmProvider('geeknow', baseUrl: '...', apiKey: '...');
/// ApiManager().setImageProvider('stabilityai', baseUrl: '...', apiKey: '...');
/// ApiManager().setVideoProvider('geeknow', baseUrl: '...', apiKey: '...');
/// 
/// // 调用服务
/// final result = await ApiManager().chatCompletion(...);
/// ```
class ApiManager {
  // 单例实例
  static final ApiManager _instance = ApiManager._internal();
  
  factory ApiManager() => _instance;
  
  ApiManager._internal();

  // ==========================================
  // Provider 实例存储（混合服务商模式）
  // ==========================================
  
  /// LLM 服务供应商（聊天补全）
  BaseApiProvider? _llmProvider;
  
  /// 图片生成服务供应商
  BaseApiProvider? _imageProvider;
  
  /// 视频生成服务供应商
  BaseApiProvider? _videoProvider;
  
  /// Provider 实例缓存
  /// 
  /// Key 格式: "providerName:baseUrl:apiKey"
  /// 避免为相同配置重复创建 Provider 实例
  final Map<String, BaseApiProvider> _providersCache = {};

  // ==========================================
  // Getters - 检查初始化状态
  // ==========================================
  
  /// 检查 LLM Provider 是否已初始化
  bool get isLlmInitialized => _llmProvider != null;
  
  /// 检查图片 Provider 是否已初始化
  bool get isImageInitialized => _imageProvider != null;
  
  /// 检查视频 Provider 是否已初始化
  bool get isVideoInitialized => _videoProvider != null;
  
  /// 检查是否所有 Provider 都已初始化
  bool get isFullyInitialized => isLlmInitialized && isImageInitialized && isVideoInitialized;
  
  /// 获取 LLM Provider 名称
  String? get llmProviderName => _llmProvider?.providerName;
  
  /// 获取图片 Provider 名称
  String? get imageProviderName => _imageProvider?.providerName;
  
  /// 获取视频 Provider 名称
  String? get videoProviderName => _videoProvider?.providerName;
  
  // 向后兼容的属性（支持旧代码）
  @Deprecated('请使用 isLlmInitialized, isImageInitialized, isVideoInitialized')
  bool get isInitialized => isVideoInitialized; // 默认检查视频 Provider（最常用）
  
  @Deprecated('请使用 llmProviderName, imageProviderName, videoProviderName')
  String? get currentProviderName => videoProviderName;

  // ==========================================
  // Provider 创建工厂方法
  // ==========================================
  
  /// 创建或获取 Provider 实例（使用缓存）
  /// 
  /// [providerName] 供应商名称
  /// [baseUrl] API 基础 URL
  /// [apiKey] API 密钥
  BaseApiProvider _getOrCreateProvider({
    required String providerName,
    required String baseUrl,
    required String apiKey,
  }) {
    // 生成缓存 Key
    final cacheKey = '$providerName:$baseUrl:$apiKey';
    
    // 从缓存中获取
    if (_providersCache.containsKey(cacheKey)) {
      print('♻️ [ApiManager] 从缓存中获取 Provider: $providerName');
      return _providersCache[cacheKey]!;
    }
    
    // 创建新的 Provider
    print('🔧 [ApiManager] 创建新的 Provider: $providerName');
    print('🔧 [ApiManager] BaseUrl: $baseUrl');
    
    BaseApiProvider provider;
    
    switch (providerName.toLowerCase()) {
      case 'geeknow':
        provider = GeeknowProvider(
          baseUrl: baseUrl,
          apiKey: apiKey,
        );
        break;
      // TODO: 添加其他供应商支持
      // case 'openai':
      //   provider = OpenAIProvider(baseUrl: baseUrl, apiKey: apiKey);
      //   break;
      // case 'stabilityai':
      //   provider = StabilityAIProvider(baseUrl: baseUrl, apiKey: apiKey);
      //   break;
      default:
        throw Exception('❌ 不支持的供应商: $providerName\n目前支持: geeknow');
    }
    
    // 存入缓存
    _providersCache[cacheKey] = provider;
    print('✅ [ApiManager] Provider 创建完成并缓存: ${provider.providerName}');
    
    return provider;
  }

  // ==========================================
  // Provider 设置方法（混合服务商模式核心）
  // ==========================================
  
  /// 设置 LLM 服务供应商
  /// 
  /// [providerName] 供应商名称（如 'geeknow', 'openai'）
  /// [baseUrl] API 基础 URL
  /// [apiKey] API 密钥
  void setLlmProvider(String providerName, {required String baseUrl, required String apiKey}) {
    print('🎯 [ApiManager] 设置 LLM Provider: $providerName');
    
    try {
      _llmProvider = _getOrCreateProvider(
        providerName: providerName,
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
      print('✅ [ApiManager] LLM Provider 设置成功: ${_llmProvider!.providerName}');
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 设置 LLM Provider 失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
      rethrow;
    }
  }
  
  /// 设置图片生成服务供应商
  /// 
  /// [providerName] 供应商名称（如 'geeknow', 'stabilityai'）
  /// [baseUrl] API 基础 URL
  /// [apiKey] API 密钥
  void setImageProvider(String providerName, {required String baseUrl, required String apiKey}) {
    print('🎯 [ApiManager] 设置图片 Provider: $providerName');
    
    try {
      _imageProvider = _getOrCreateProvider(
        providerName: providerName,
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
      print('✅ [ApiManager] 图片 Provider 设置成功: ${_imageProvider!.providerName}');
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 设置图片 Provider 失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
      rethrow;
    }
  }
  
  /// 设置视频生成服务供应商
  /// 
  /// [providerName] 供应商名称（如 'geeknow', 'runway'）
  /// [baseUrl] API 基础 URL
  /// [apiKey] API 密钥
  void setVideoProvider(String providerName, {required String baseUrl, required String apiKey}) {
    print('🎯 [ApiManager] 设置视频 Provider: $providerName');
    
    try {
      _videoProvider = _getOrCreateProvider(
        providerName: providerName,
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
      print('✅ [ApiManager] 视频 Provider 设置成功: ${_videoProvider!.providerName}');
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 设置视频 Provider 失败');
      print('❌ [Error Details]: $e');
      print('📍 [Stack Trace]: $stackTrace');
      rethrow;
    }
  }
  
  // ==========================================
  // 向后兼容方法
  // ==========================================
  
  /// 初始化供应商（向后兼容）
  /// 
  /// 此方法将同时设置 LLM、图片、视频 Provider 为相同的供应商
  /// 
  /// @deprecated 请使用 setLlmProvider, setImageProvider, setVideoProvider 获得更好的灵活性
  @Deprecated('请使用 setLlmProvider, setImageProvider, setVideoProvider')
  void initializeProvider({
    required String providerName,
    required String baseUrl,
    required String apiKey,
  }) {
    print('⚠️ [ApiManager] 使用向后兼容方法 initializeProvider()');
    print('⚠️ [ApiManager] 建议使用 setLlmProvider, setImageProvider, setVideoProvider');
    
    // 同时设置所有三个 Provider
    setLlmProvider(providerName, baseUrl: baseUrl, apiKey: apiKey);
    setImageProvider(providerName, baseUrl: baseUrl, apiKey: apiKey);
    setVideoProvider(providerName, baseUrl: baseUrl, apiKey: apiKey);
  }

  // ==========================================
  // 代理方法 - 转发到对应的供应商
  // ==========================================

  /// LLM 聊天补全
  /// 
  /// 使用 LLM Provider 执行聊天补全
  Future<String> chatCompletion({
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    if (_llmProvider == null) {
      throw Exception('❌ 未设置 LLM 服务供应商，请先在设置中配置 LLM API');
    }
    
    print('🤖 [ApiManager] 调用 LLM Provider: ${_llmProvider!.providerName}');
    
    return await _llmProvider!.chatCompletion(
      model: model,
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  /// 生成图片
  /// 
  /// 使用图片 Provider 执行图片生成
  Future<String> generateImage({
    required String model,
    required String prompt,
    int width = 1024,
    int height = 1024,
    List<String>? referenceImages,
  }) async {
    if (_imageProvider == null) {
      throw Exception('❌ 未设置图片生成服务供应商，请先在设置中配置图片生成 API');
    }
    
    print('🎨 [ApiManager] 调用图片 Provider: ${_imageProvider!.providerName}');
    
    return await _imageProvider!.generateImage(
      model: model,
      prompt: prompt,
      width: width,
      height: height,
      referenceImages: referenceImages,
    );
  }

  /// 创建视频生成任务
  /// 
  /// 使用视频 Provider 执行视频生成
  Future<String> createVideo({
    required String model,
    required String prompt,
    String size = '720x1280',
    int? seconds,
    File? inputReference,
  }) async {
    if (_videoProvider == null) {
      throw Exception('❌ 未设置视频生成服务供应商，请先在设置中配置视频生成 API');
    }
    
    print('🎬 [ApiManager] 调用视频 Provider: ${_videoProvider!.providerName}');
    
    return await _videoProvider!.createVideo(
      model: model,
      prompt: prompt,
      size: size,
      seconds: seconds,
      inputReference: inputReference,
    );
  }

  /// 获取视频任务状态
  /// 
  /// 使用视频 Provider 查询任务状态
  Future<VideoTaskStatus> getVideoTask({
    required String taskId,
  }) async {
    if (_videoProvider == null) {
      throw Exception('❌ 未设置视频生成服务供应商，请先在设置中配置视频生成 API');
    }
    
    print('📊 [ApiManager] 查询视频任务状态 (Provider: ${_videoProvider!.providerName}): $taskId');
    
    return await _videoProvider!.getVideoTask(taskId: taskId);
  }

  /// 上传视频到 OSS
  /// 
  /// 使用视频 Provider 上传视频（通常用于角色创建）
  Future<String> uploadVideoToOss(File videoFile) async {
    if (_videoProvider == null) {
      throw Exception('❌ 未设置视频服务供应商，请先在设置中配置视频 API');
    }
    
    print('📤 [ApiManager] 上传视频到 OSS (Provider: ${_videoProvider!.providerName})');
    
    return await _videoProvider!.uploadVideoToOss(videoFile);
  }

  /// 创建角色
  /// 
  /// 使用视频 Provider 创建角色（基于上传的视频）
  Future<Map<String, dynamic>> createCharacter(String videoUrl) async {
    if (_videoProvider == null) {
      throw Exception('❌ 未设置视频服务供应商，请先在设置中配置视频 API');
    }
    
    print('👤 [ApiManager] 创建角色 (Provider: ${_videoProvider!.providerName})');
    
    return await _videoProvider!.createCharacter(videoUrl);
  }
  
  // ==========================================
  // 调试和管理方法
  // ==========================================
  
  /// 清除所有 Provider 缓存
  /// 
  /// 用于测试或强制重新初始化
  void clearCache() {
    print('🗑️ [ApiManager] 清除 Provider 缓存');
    _providersCache.clear();
  }
  
  /// 获取当前配置摘要（用于调试）
  Map<String, dynamic> getConfigSummary() {
    return {
      'llmProvider': _llmProvider != null ? {
        'name': _llmProvider!.providerName,
        'baseUrl': _llmProvider!.baseUrl,
      } : null,
      'imageProvider': _imageProvider != null ? {
        'name': _imageProvider!.providerName,
        'baseUrl': _imageProvider!.baseUrl,
      } : null,
      'videoProvider': _videoProvider != null ? {
        'name': _videoProvider!.providerName,
        'baseUrl': _videoProvider!.baseUrl,
      } : null,
      'cacheSize': _providersCache.length,
    };
  }
  
  /// 打印当前配置（用于调试）
  void printConfig() {
    print('');
    print('═══════════════════════════════════════════════════════');
    print('📋 [ApiManager] 当前配置摘要');
    print('═══════════════════════════════════════════════════════');
    print('🤖 LLM Provider: ${_llmProvider?.providerName ?? "未设置"}');
    if (_llmProvider != null) {
      print('   └─ BaseUrl: ${_llmProvider!.baseUrl}');
    }
    print('🎨 Image Provider: ${_imageProvider?.providerName ?? "未设置"}');
    if (_imageProvider != null) {
      print('   └─ BaseUrl: ${_imageProvider!.baseUrl}');
    }
    print('🎬 Video Provider: ${_videoProvider?.providerName ?? "未设置"}');
    if (_videoProvider != null) {
      print('   └─ BaseUrl: ${_videoProvider!.baseUrl}');
    }
    print('💾 缓存的 Provider 数量: ${_providersCache.length}');
    print('═══════════════════════════════════════════════════════');
    print('');
  }
}
