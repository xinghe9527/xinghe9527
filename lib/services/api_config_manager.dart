import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'dart:async';

// 用于启动不等待的异步任务
void unawaited(Future<void> future) {
  // 忽略 future，仅用于启动异步任务
}

// ==========================================
// LLM 平台配置
// ==========================================

enum LlmPlatform {
  geeknow('GEEKNOW');

  final String displayName;
  const LlmPlatform(this.displayName);
}

// GEEKNOW 平台模型
class GeeknowModels {
  // GPT 系列模型
  static const String gpt4oMini = 'gpt-4o-mini';
  static const String gpt4o = 'gpt-4o';
  static const String gpt4Turbo = 'gpt-4-turbo';
  static const String gpt4 = 'gpt-4';
  static const String gpt35Turbo = 'gpt-3.5-turbo';
  static const String gpt35TurboInstruct = 'gpt-3.5-turbo-instruct';
  
  // Claude 系列模型
  static const String claude35Sonnet = 'claude-3-5-sonnet-20241022';
  static const String claude3Opus = 'claude-3-opus-20240229';
  static const String claude3Sonnet = 'claude-3-sonnet-20240229';
  static const String claude3Haiku = 'claude-3-haiku-20240307';
  
  // Deepseek 系列模型（文档和思考类）
  static const String deepseekChat = 'deepseek-chat';
  static const String deepseekCoder = 'deepseek-coder';
  static const String deepseekReasoner = 'deepseek-reasoner';
  
  // OpenAI 思考类模型
  static const String o1Preview = 'o1-preview';
  static const String o1Mini = 'o1-mini';
  
  // Nano Banana 系列模型 (高性能语言模型)
  static const String nanoBananaPro = 'nano-banana-pro';
  static const String nanoBananaPro4k = 'nano-banana-pro-4k';
  
  static List<String> get availableModels => [
    // GPT 系列
    gpt4oMini,
    gpt4o,
    gpt4Turbo,
    gpt4,
    gpt35Turbo,
    gpt35TurboInstruct,
    // Claude 系列
    claude35Sonnet,
    claude3Opus,
    claude3Sonnet,
    claude3Haiku,
    // Deepseek 系列（思考类）
    deepseekChat,
    deepseekCoder,
    deepseekReasoner,
    // OpenAI 思考类
    o1Preview,
    o1Mini,
    // Nano Banana 系列
    nanoBananaPro,
    nanoBananaPro4k,
  ];
  
  static String get defaultModel => gpt4oMini;
  static String get defaultBaseUrl => 'https://api.geeknow.ai/v1';
}

// ==========================================
// 图片生成平台配置
// ==========================================

enum ImagePlatform {
  geeknow('GEEKNOW');

  final String displayName;
  const ImagePlatform(this.displayName);
}

// GEEKNOW 图片模型
class GeeknowImageModels {
  // Gemini 图片模型 (使用 /v1beta/models/{model}:generateContent 端点)
  static const String gemini3ProImagePreview = 'gemini-3-pro-image-preview';
  static const String gemini3ProImagePreviewLite = 'gemini-3-pro-image-preview-lite';
  static const String gemini25FlashImagePreview = 'gemini-2.5-flash-image-preview';
  
  // 尺寸配置
  static const Map<String, List<String>> sizes = {
    gemini3ProImagePreview: ['1024x1024', '1792x1024', '1024x1792'],
    gemini3ProImagePreviewLite: ['1024x1024', '1792x1024', '1024x1792'],
    gemini25FlashImagePreview: ['1024x1024', '1792x1024', '1024x1792'],
  };
  
  // 质量配置
  static const List<String> qualities = ['standard', 'hd'];
  
  // 风格配置
  static const List<String> styles = ['vivid', 'natural'];
  
  static List<String> get availableModels => [
    gemini3ProImagePreview,
    gemini3ProImagePreviewLite,
    gemini25FlashImagePreview,
  ];
  
  // 默认使用 gemini-3-pro-image-preview
  static String get defaultModel => gemini3ProImagePreview;
  static String get defaultBaseUrl => 'https://api.geeknow.ai/v1';
  
  // 获取指定模型的尺寸列表
  static List<String> getSizesForModel(String model) {
    return sizes[model] ?? sizes[gemini3ProImagePreview]!;
  }
}

// ==========================================
// 视频生成平台配置
// ==========================================

enum VideoPlatform {
  geeknow('GEEKNOW');

  final String displayName;
  const VideoPlatform(this.displayName);
}

// GEEKNOW 视频模型
class GeeknowVideoModels {
  // Sora 模型
  static const String sora2 = 'sora-2';
  
  // Veo 模型
  static const String veo31 = 'veo_3_1';
  static const String veo31Fast = 'veo_3_1-fast';
  static const String veo31Fl = 'veo_3_1-fl'; // 帧转视频模式
  static const String veo31FastFl = 'veo_3_1-fast-fl';
  
  // 尺寸配置（所有视频模型都支持）
  static const List<String> sizes = ['720x1280', '1280x720'];
  
  static List<String> get availableModels => [
    sora2,
    veo31,
    veo31Fast,
    veo31Fl,
    veo31FastFl,
  ];
  
  static String get defaultModel => sora2;
  static String get defaultBaseUrl => 'https://api.geeknow.ai/v1';
  
  // 获取指定模型的尺寸列表
  static List<String> getSizesForModel(String model) {
    return sizes;
  }
}

// ==========================================
// API 配置管理器
// ==========================================

class ApiConfigManager extends ChangeNotifier {
  // 单例模式
  static final ApiConfigManager _instance = ApiConfigManager._internal();
  factory ApiConfigManager() => _instance;
  ApiConfigManager._internal();

  // 供应商配置（混合服务商模式 - 分别为 LLM、图片、视频配置）
  String _selectedLlmProviderId = 'geeknow';    // LLM 服务供应商
  String _selectedImageProviderId = 'geeknow';  // 图片生成服务供应商
  String _selectedVideoProviderId = 'geeknow';  // 视频生成服务供应商
  
  // 向后兼容属性（废弃）
  @Deprecated('请使用 selectedLlmProviderId, selectedImageProviderId, selectedVideoProviderId')
  String get selectedProviderId => _selectedVideoProviderId; // 默认返回视频供应商

  // LLM 配置（统一使用 GEEKNOW 中转）
  String _llmApiKey = '';
  String _llmBaseUrl = GeeknowModels.defaultBaseUrl;
  String _llmModel = GeeknowModels.defaultModel;

  // 图片生成配置（统一使用 GEEKNOW 中转）
  String _imageApiKey = '';
  String _imageBaseUrl = GeeknowImageModels.defaultBaseUrl;
  String _imageModel = GeeknowImageModels.defaultModel;
  String _imageSize = '1024x1024';
  String _imageQuality = 'standard';
  String _imageStyle = 'vivid';

  // 视频生成配置（统一使用 GEEKNOW 中转）
  String _videoApiKey = '';
  String _videoBaseUrl = GeeknowVideoModels.defaultBaseUrl;
  String _videoModel = GeeknowVideoModels.defaultModel;
  String _videoSize = '720x1280';
  int _videoSeconds = 10;

  // Getters - 供应商选择
  String get selectedLlmProviderId => _selectedLlmProviderId;
  String get selectedImageProviderId => _selectedImageProviderId;
  String get selectedVideoProviderId => _selectedVideoProviderId;
  
  // Getters - LLM 配置
  String get llmApiKey => _llmApiKey;
  String get llmBaseUrl => _llmBaseUrl;
  String get llmModel => _llmModel;

  // Getters - 图片配置
  String get imageApiKey => _imageApiKey;
  String get imageBaseUrl => _imageBaseUrl;
  String get imageModel => _imageModel;
  String get imageSize => _imageSize;
  String get imageQuality => _imageQuality;
  String get imageStyle => _imageStyle;

  // Getters - 视频配置
  String get videoApiKey => _videoApiKey;
  String get videoBaseUrl => _videoBaseUrl;
  String get videoModel => _videoModel;
  String get videoSize => _videoSize;
  int get videoSeconds => _videoSeconds;

  // 检查配置是否完整
  bool get hasLlmConfig =>
      _llmApiKey.isNotEmpty && _llmBaseUrl.isNotEmpty;
  bool get hasImageConfig =>
      _imageApiKey.isNotEmpty && _imageBaseUrl.isNotEmpty;
  bool get hasVideoConfig =>
      _videoApiKey.isNotEmpty && _videoBaseUrl.isNotEmpty;

  // 加载配置
  Future<void> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 加载三个独立的供应商选择（混合服务商模式）
      _selectedLlmProviderId = prefs.getString('selected_llm_provider') ?? 'geeknow';
      _selectedImageProviderId = prefs.getString('selected_image_provider') ?? 'geeknow';
      _selectedVideoProviderId = prefs.getString('selected_video_provider') ?? 'geeknow';
      
      print('📋 [ApiConfigManager] 加载供应商选择:');
      print('   - LLM: $_selectedLlmProviderId');
      print('   - Image: $_selectedImageProviderId');
      print('   - Video: $_selectedVideoProviderId');
      
      // 加载对应供应商的配置
      _llmApiKey = prefs.getString('llm_api_key') ?? '';
      _llmBaseUrl = prefs.getString('llm_base_url') ?? GeeknowModels.defaultBaseUrl;
      _llmModel = prefs.getString('llm_model') ?? GeeknowModels.defaultModel;
      
      _imageApiKey = prefs.getString('image_api_key') ?? '';
      _imageBaseUrl = prefs.getString('image_base_url') ?? GeeknowImageModels.defaultBaseUrl;
      // 检查保存的模型是否仍然可用
      final savedImageModel = prefs.getString('image_model');
      if (savedImageModel != null && GeeknowImageModels.availableModels.contains(savedImageModel)) {
        _imageModel = savedImageModel;
      } else {
        _imageModel = GeeknowImageModels.defaultModel;
      }
      _imageSize = prefs.getString('image_size') ?? '1024x1024';
      _imageQuality = prefs.getString('image_quality') ?? 'standard';
      _imageStyle = prefs.getString('image_style') ?? 'vivid';
      
      _videoApiKey = prefs.getString('video_api_key') ?? '';
      _videoBaseUrl = prefs.getString('video_base_url') ?? GeeknowVideoModels.defaultBaseUrl;
      _videoModel = prefs.getString('video_model') ?? GeeknowVideoModels.defaultModel;
      _videoSize = prefs.getString('video_size') ?? '720x1280';
      _videoSeconds = prefs.getInt('video_seconds') ?? 10;
      
      notifyListeners();
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 加载API配置失败: $e');
      print('📍 [Stack Trace]: $stackTrace');
    }
  }

  // 保存配置（非阻塞版本，立即返回，后台写入）
  Future<void> saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 批量写入，减少等待时间
      await Future.wait([
        // 保存三个独立的供应商选择
        prefs.setString('selected_llm_provider', _selectedLlmProviderId),
        prefs.setString('selected_image_provider', _selectedImageProviderId),
        prefs.setString('selected_video_provider', _selectedVideoProviderId),
        // 保存各项配置
        prefs.setString('llm_api_key', _llmApiKey),
        prefs.setString('llm_base_url', _llmBaseUrl),
        prefs.setString('llm_model', _llmModel),
        prefs.setString('image_api_key', _imageApiKey),
        prefs.setString('image_base_url', _imageBaseUrl),
        prefs.setString('image_model', _imageModel),
        prefs.setString('image_size', _imageSize),
        prefs.setString('image_quality', _imageQuality),
        prefs.setString('image_style', _imageStyle),
        prefs.setString('video_api_key', _videoApiKey),
        prefs.setString('video_base_url', _videoBaseUrl),
        prefs.setString('video_model', _videoModel),
        prefs.setString('video_size', _videoSize),
        prefs.setInt('video_seconds', _videoSeconds),
      ]);
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 保存API配置失败: $e');
      print('📍 [Stack Trace]: $stackTrace');
    }
  }
  
  // 非阻塞保存（立即返回，后台写入）
  void saveConfigNonBlocking() {
    // 使用 unawaited 让保存操作在后台进行，不阻塞UI
    unawaited(saveConfig());
  }
  
  // 批量更新配置（不触发 notifyListeners，用于一次性更新多个配置）
  void updateConfigBatch({
    String? selectedLlmProviderId,
    String? selectedImageProviderId,
    String? selectedVideoProviderId,
    String? llmApiKey,
    String? llmBaseUrl,
    String? llmModel,
    String? imageApiKey,
    String? imageBaseUrl,
    String? imageModel,
    String? videoApiKey,
    String? videoBaseUrl,
    String? videoModel,
  }) {
    if (selectedLlmProviderId != null) _selectedLlmProviderId = selectedLlmProviderId;
    if (selectedImageProviderId != null) _selectedImageProviderId = selectedImageProviderId;
    if (selectedVideoProviderId != null) _selectedVideoProviderId = selectedVideoProviderId;
    if (llmApiKey != null) _llmApiKey = llmApiKey;
    if (llmBaseUrl != null) _llmBaseUrl = llmBaseUrl;
    if (llmModel != null) _llmModel = llmModel;
    if (imageApiKey != null) _imageApiKey = imageApiKey;
    if (imageBaseUrl != null) _imageBaseUrl = imageBaseUrl;
    if (imageModel != null) _imageModel = imageModel;
    if (videoApiKey != null) _videoApiKey = videoApiKey;
    if (videoBaseUrl != null) _videoBaseUrl = videoBaseUrl;
    if (videoModel != null) _videoModel = videoModel;
    
    // 保存但不通知（由调用者决定何时通知）
    saveConfigNonBlocking();
  }
  
  // 触发通知（公共方法，用于批量更新后统一通知）
  void triggerNotify() {
    notifyListeners();
  }

  // Setters（使用非阻塞保存）
  void setLlmConfig(String apiKey, String baseUrl, [String? model]) {
    _llmApiKey = apiKey;
    _llmBaseUrl = baseUrl;
    if (model != null) _llmModel = model;
    saveConfigNonBlocking(); // 非阻塞自动保存
    notifyListeners();
  }

  void setImageConfig(
    String apiKey,
    String baseUrl, {
    String? model,
    String? size,
    String? quality,
    String? style,
  }) {
    _imageApiKey = apiKey;
    _imageBaseUrl = baseUrl;
    if (model != null) _imageModel = model;
    if (size != null) _imageSize = size;
    if (quality != null) _imageQuality = quality;
    if (style != null) _imageStyle = style;
    saveConfigNonBlocking(); // 非阻塞自动保存
    notifyListeners();
  }

  void setVideoConfig(
    String apiKey,
    String baseUrl, {
    String? model,
    String? size,
    int? seconds,
  }) {
    _videoApiKey = apiKey;
    _videoBaseUrl = baseUrl;
    if (model != null) _videoModel = model;
    if (size != null) _videoSize = size;
    if (seconds != null) _videoSeconds = seconds;
    saveConfigNonBlocking(); // 非阻塞自动保存
    notifyListeners();
  }

  // 设置 LLM 模型
  set llmModel(String value) {
    _llmModel = value;
    notifyListeners();
  }

  // 设置图片模型
  set imageModel(String value) {
    _imageModel = value;
    // 根据模型更新默认尺寸
    final sizes = GeeknowImageModels.getSizesForModel(value);
    if (sizes.isNotEmpty && !sizes.contains(_imageSize)) {
      _imageSize = sizes.first;
    }
    notifyListeners();
  }

  // 设置图片尺寸
  set imageSize(String value) {
    _imageSize = value;
    notifyListeners();
  }

  // 设置图片质量
  set imageQuality(String value) {
    _imageQuality = value;
    notifyListeners();
  }

  // 设置图片风格
  set imageStyle(String value) {
    _imageStyle = value;
    notifyListeners();
  }

  // 设置视频模型
  set videoModel(String value) {
    _videoModel = value;
    notifyListeners();
  }

  // 设置视频尺寸
  set videoSize(String value) {
    _videoSize = value;
    notifyListeners();
  }

  // 设置视频时长
  set videoSeconds(int value) {
    _videoSeconds = value;
    notifyListeners();
  }

  // 创建 API 服务实例
  ApiService createApiService() {
    return ApiService(
      llmConfig: ApiConfig(
        apiKey: _llmApiKey,
        baseUrl: _llmBaseUrl,
      ),
      imageConfig: ApiConfig(
        apiKey: _imageApiKey,
        baseUrl: _imageBaseUrl,
      ),
      videoConfig: ApiConfig(
        apiKey: _videoApiKey,
        baseUrl: _videoBaseUrl,
      ),
    );
  }

  // 获取 LLM 模型列表（统一使用 GEEKNOW）
  List<String> getLlmModels() => GeeknowModels.availableModels;

  // 获取图片模型列表（统一使用 GEEKNOW）
  List<String> getImageModels() => GeeknowImageModels.availableModels;

  // 获取图片尺寸列表
  List<String> getImageSizes([String? model]) {
    final effectiveModel = model ?? _imageModel;
    return GeeknowImageModels.getSizesForModel(effectiveModel);
  }
  
  // 获取图片质量列表
  List<String> getImageQualities() => GeeknowImageModels.qualities;
  
  // 获取图片风格列表
  List<String> getImageStyles() => GeeknowImageModels.styles;

  // 获取视频模型列表（统一使用 GEEKNOW）
  List<String> getVideoModels() => GeeknowVideoModels.availableModels;

  // 获取视频尺寸列表
  List<String> getVideoSizes([String? model]) {
    return GeeknowVideoModels.getSizesForModel(model ?? _videoModel);
  }

  // 获取视频时长选项列表
  List<int> getVideoSecondsOptions() {
    return [5, 10, 15];
  }

  // 重置所有配置
  void reset() {
    _selectedLlmProviderId = 'geeknow';
    _selectedImageProviderId = 'geeknow';
    _selectedVideoProviderId = 'geeknow';
    
    _llmApiKey = '';
    _llmBaseUrl = GeeknowModels.defaultBaseUrl;
    _llmModel = GeeknowModels.defaultModel;

    _imageApiKey = '';
    _imageBaseUrl = GeeknowImageModels.defaultBaseUrl;
    _imageModel = GeeknowImageModels.defaultModel;
    _imageSize = '1024x1024';
    _imageQuality = 'standard';
    _imageStyle = 'vivid';

    _videoApiKey = '';
    _videoBaseUrl = GeeknowVideoModels.defaultBaseUrl;
    _videoModel = GeeknowVideoModels.defaultModel;
    _videoSize = '720x1280';
    _videoSeconds = 10;

    notifyListeners();
  }

  // 设置 LLM 供应商
  void setLlmProvider(String providerId) {
    print('🔄 [ApiConfigManager] 切换 LLM 供应商: $providerId');
    _selectedLlmProviderId = providerId;
    saveConfigNonBlocking();
    notifyListeners();
  }
  
  // 设置图片供应商
  void setImageProvider(String providerId) {
    print('🔄 [ApiConfigManager] 切换图片供应商: $providerId');
    _selectedImageProviderId = providerId;
    saveConfigNonBlocking();
    notifyListeners();
  }
  
  // 设置视频供应商
  void setVideoProvider(String providerId) {
    print('🔄 [ApiConfigManager] 切换视频供应商: $providerId');
    _selectedVideoProviderId = providerId;
    saveConfigNonBlocking();
    notifyListeners();
  }

  // 向后兼容方法（废弃）
  @Deprecated('请使用 setLlmProvider, setImageProvider, setVideoProvider')
  void setProvider(String providerId) {
    print('⚠️ [ApiConfigManager] 使用废弃的 setProvider 方法');
    print('⚠️ [ApiConfigManager] 建议使用 setLlmProvider, setImageProvider, setVideoProvider');
    // 同时设置所有三个供应商（向后兼容）
    setLlmProvider(providerId);
    setImageProvider(providerId);
    setVideoProvider(providerId);
  }

  // 获取支持的供应商列表
  List<String> getSupportedProviders() {
    return ['geeknow', 'custom'];
  }

  // 获取供应商显示名称
  String getProviderDisplayName(String providerId) {
    switch (providerId.toLowerCase()) {
      case 'geeknow':
        return 'GeekNow';
      case 'custom':
        return 'Custom/Other';
      default:
        return providerId;
    }
  }
}
