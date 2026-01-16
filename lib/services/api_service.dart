import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'ffmpeg_service.dart';
import 'sora_api_service.dart';

// 默认超时时间（秒）
const int kDefaultTimeout = 30;

// ==========================================
// 后台任务辅助方法
// ==========================================

/// 在后台 Isolate 中解析 JSON 字符串
/// 
/// 此函数在隔离的 Isolate 中执行，不会阻塞 UI 线程
/// 
/// [jsonString] 要解析的 JSON 字符串
/// 返回解析后的 Map
Map<String, dynamic> _parseJsonInBackground(String jsonString) {
  try {
    return jsonDecode(jsonString) as Map<String, dynamic>;
  } catch (e) {
    throw Exception('JSON 解析失败: $e\nJSON 内容: ${jsonString.substring(0, jsonString.length > 200 ? 200 : jsonString.length)}...');
  }
}

/// 在后台 Isolate 中运行重任务
/// 
/// 这是一个通用的辅助方法，用于在后台执行可能阻塞 UI 的操作
/// 
/// [task] 要执行的任务函数
/// [message] 任务的描述信息（用于日志）
/// 返回任务执行结果
Future<T> runInBackground<T>(
  Future<T> Function() task, {
  String? message,
}) async {
  if (message != null) {
    print('[BackgroundTask] 开始执行: $message');
  }
  
  try {
    // 使用 Future.microtask 确保任务在下一个事件循环中执行
    // 这允许 UI 线程先处理其他事件
    final result = await Future.microtask(task);
    
    if (message != null) {
      print('[BackgroundTask] 完成: $message');
    }
    
    return result;
  } catch (e) {
    if (message != null) {
      print('[BackgroundTask] 失败: $message - $e');
    }
    rethrow;
  }
}

// ==========================================
// API 配置模型
// ==========================================

class ApiConfig {
  String apiKey;
  String baseUrl;
  String? organization;

  ApiConfig({
    required this.apiKey,
    required this.baseUrl,
    this.organization,
  });

  Map<String, String> getHeaders() {
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };
    if (organization != null && organization!.isNotEmpty) {
      headers['OpenAI-Organization'] = organization!;
    }
    return headers;
  }

  Map<String, String> getMultipartHeaders() {
    final headers = {
      'Authorization': 'Bearer $apiKey',
    };
    return headers;
  }
}

// ==========================================
// LLM 模型配置
// ==========================================

class LlmModels {
  // 文本补全模型
  static const String gpt35TurboInstruct = 'gpt-3.5-turbo-instruct';
  
  // 聊天补全模型
  static const String gpt35Turbo = 'gpt-3.5-turbo';
  static const String gpt35Turbo1106 = 'gpt-3.5-turbo-1106';
  static const String gpt35Turbo0613 = 'gpt-3.5-turbo-0613';
  static const String gpt4Turbo = 'gpt-4-turbo';
  static const String gpt4Turbo1106 = 'gpt-4-turbo-1106';
  static const String gpt4 = 'gpt-4';
  static const String gpt40605 = 'gpt-4-0605';

  // 可选模型列表
  static List<String> get availableModels => [
        gpt35Turbo,
        gpt35Turbo1106,
        gpt35Turbo0613,
        gpt4Turbo,
        gpt4Turbo1106,
        gpt4,
        gpt40605,
        gpt35TurboInstruct,
      ];

  static String get defaultModel => gpt35Turbo;
}

// ==========================================
// 图片生成模型配置
// ==========================================

class ImageModels {
  // Gemini 图片模型 (使用 /v1beta/models/{model}:generateContent 端点)
  static const String gemini3ProImagePreview = 'gemini-3-pro-image-preview';
  static const String gemini30ProImagePreview1K = 'gemini-3.0-pro-image-preview-1K';
  
  // Flux 系列 (推荐，支持 /v1/images/generations 端点)
  static const String flux1Schnell = 'flux-1-schnell';
  static const String flux1Dev = 'flux-1-dev';
  static const String fluxPro = 'flux-pro';
  static const String fluxDev = 'flux-dev';
  static const String fluxSchnell = 'flux-schnell';
  
  // Stable Diffusion 系列
  static const String stableDiffusionXl = 'stable-diffusion-xl-1024-v1-0';
  static const String stableDiffusionV16 = 'stable-diffusion-v1-6';
  static const String sd3 = 'sd3';
  
  // Midjourney 系列
  static const String midjourney = 'midjourney';
  static const String mjChat = 'mj-chat';
  
  // 其他
  static const String ideogramV2 = 'ideogram-v2';
  static const String playgroundV25 = 'playground-v2.5';

  // 尺寸配置
  static const Map<String, List<String>> sizes = {
    gemini3ProImagePreview: ['1024x1024', '1792x1024', '1024x1792'],
    gemini30ProImagePreview1K: ['1024x1024', '1792x1024', '1024x1792'],
    flux1Schnell: ['1024x1024', '1792x1024', '1024x1792'],
    flux1Dev: ['1024x1024', '1792x1024', '1024x1792'],
    fluxPro: ['1024x1024', '1792x1024', '1024x1792'],
    fluxDev: ['1024x1024', '1792x1024', '1024x1792'],
    fluxSchnell: ['1024x1024', '1792x1024', '1024x1792'],
    stableDiffusionXl: ['1024x1024', '1792x1024', '1024x1792'],
    stableDiffusionV16: ['512x512', '768x768', '1024x1024'],
    sd3: ['1024x1024', '1536x1024', '1024x1536'],
  };

  // 质量配置
  static const List<String> qualities = ['standard', 'hd'];

  // 风格配置
  static const List<String> styles = ['vivid', 'natural'];

  // 可选模型列表
  static List<String> get availableModels => [
    gemini3ProImagePreview,
    gemini30ProImagePreview1K,
    flux1Schnell,
    flux1Dev,
    fluxPro,
    fluxDev,
    fluxSchnell,
    stableDiffusionXl,
    stableDiffusionV16,
    sd3,
    midjourney,
    mjChat,
    ideogramV2,
    playgroundV25,
  ];

  // 默认使用 gemini-3-pro-image-preview
  static String get defaultModel => gemini3ProImagePreview;
}

// ==========================================
// 视频生成模型配置
// ==========================================

class VideoModels {
  // Sora 模型
  static const String sora10Turbo = 'sora-1.0-turbo';
  static const String sora2 = 'sora-2';

  // Veo 模型
  static const String veo31 = 'veo_3_1';
  static const String veo31Fast = 'veo_3_1-fast';
  static const String veo31Fl = 'veo_3_1-fl'; // 帧转视频模式
  static const String veo31FastFl = 'veo_3_1-fast-fl';
  
  // Kling 模型
  static const String klingV1 = 'kling-v1';
  static const String klingV15 = 'kling-v1-5';
  
  // Runway 模型
  static const String gen3Alpha = 'gen-3-alpha';
  
  // Pika 模型
  static const String pika10 = 'pika-1.0';
  
  // Luma 模型
  static const String dreamMachine = 'dream-machine';

  // 尺寸配置
  static const Map<String, List<String>> sizes = {
    'portrait': ['720x1280'],
    'landscape': ['1280x720'],
  };

  // 可选模型列表
  static List<String> get availableModels => [
        sora10Turbo,
        sora2,
        veo31,
        veo31Fast,
        veo31Fl,
        veo31FastFl,
        klingV1,
        klingV15,
        gen3Alpha,
        pika10,
        dreamMachine,
      ];

  // 根据模型名称获取尺寸选项
  static List<String> getSizesForModel(String model) {
    if (model.startsWith('veo') || model.startsWith('sora') || model.startsWith('kling')) {
      return ['720x1280', '1280x720'];
    }
    return ['720x1280', '1280x720'];
  }

  static String get defaultModel => veo31Fast;
}

// ==========================================
// API 响应模型
// ==========================================

// 聊天补全响应
class ChatCompletionResponse {
  final String id;
  final String object;
  final int created;
  final String model;
  final String? systemFingerprint;
  final List<Choice> choices;
  final Usage usage;

  ChatCompletionResponse({
    required this.id,
    required this.object,
    required this.created,
    required this.model,
    this.systemFingerprint,
    required this.choices,
    required this.usage,
  });

  factory ChatCompletionResponse.fromJson(Map<String, dynamic> json) {
    return ChatCompletionResponse(
      id: json['id'] ?? '',
      object: json['object'] ?? 'chat.completion',
      created: json['created'] ?? 0,
      model: json['model'] ?? '',
      systemFingerprint: json['system_fingerprint'],
      choices: (json['choices'] as List?)
              ?.map((e) => Choice.fromJson(e))
              .toList() ??
          [],
      usage: Usage.fromJson(json['usage'] ?? {}),
    );
  }
}

class Choice {
  final int index;
  final Message message;
  final String? finishReason;

  Choice({
    required this.index,
    required this.message,
    this.finishReason,
  });

  factory Choice.fromJson(Map<String, dynamic> json) {
    return Choice(
      index: json['index'] ?? 0,
      message: Message.fromJson(json['message'] ?? {}),
      finishReason: json['finish_reason'],
    );
  }
}

class Message {
  final String role;
  final String content;

  Message({required this.role, required this.content});

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      role: json['role'] ?? 'assistant',
      content: json['content'] ?? '',
    );
  }
}

class Usage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  Usage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });

  factory Usage.fromJson(Map<String, dynamic> json) {
    return Usage(
      promptTokens: json['prompt_tokens'] ?? 0,
      completionTokens: json['completion_tokens'] ?? 0,
      totalTokens: json['total_tokens'] ?? 0,
    );
  }
}

// 文本补全响应
class TextCompletionResponse {
  final String id;
  final String object;
  final int created;
  final String model;
  final String? systemFingerprint;
  final List<TextChoice> choices;
  final Usage usage;

  TextCompletionResponse({
    required this.id,
    required this.object,
    required this.created,
    required this.model,
    this.systemFingerprint,
    required this.choices,
    required this.usage,
  });

  factory TextCompletionResponse.fromJson(Map<String, dynamic> json) {
    return TextCompletionResponse(
      id: json['id'] ?? '',
      object: json['object'] ?? 'text_completion',
      created: json['created'] ?? 0,
      model: json['model'] ?? '',
      systemFingerprint: json['system_fingerprint'],
      choices: (json['choices'] as List?)
              ?.map((e) => TextChoice.fromJson(e))
              .toList() ??
          [],
      usage: Usage.fromJson(json['usage'] ?? {}),
    );
  }
}

class TextChoice {
  final String text;
  final int index;
  final String? finishReason;

  TextChoice({
    required this.text,
    required this.index,
    this.finishReason,
  });

  factory TextChoice.fromJson(Map<String, dynamic> json) {
    return TextChoice(
      text: json['text'] ?? '',
      index: json['index'] ?? 0,
      finishReason: json['finish_reason'],
    );
  }
}

// 图片生成响应
class ImageResponse {
  final int created;
  final List<ImageData> data;

  ImageResponse({required this.created, required this.data});

  factory ImageResponse.fromJson(Map<String, dynamic> json) {
    return ImageResponse(
      created: json['created'] ?? 0,
      data: (json['data'] as List?)
              ?.map((e) => ImageData.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class ImageData {
  final String? url;
  final String? b64Json;
  final String? revisedPrompt;

  ImageData({this.url, this.b64Json, this.revisedPrompt});

  factory ImageData.fromJson(Map<String, dynamic> json) {
    return ImageData(
      url: json['url'],
      b64Json: json['b64_json'],
      revisedPrompt: json['revised_prompt'],
    );
  }
}

// 简化的图片生成响应
class ImageGenerateResponse {
  final String imageUrl;
  final String? revisedPrompt;

  ImageGenerateResponse({required this.imageUrl, this.revisedPrompt});
}

// 视频生成响应
class VideoResponse {
  final String id;
  final String object;
  final String model;
  final String status;
  final int progress;
  final int createdAt;
  final String? seconds;
  final String? size;

  VideoResponse({
    required this.id,
    required this.object,
    required this.model,
    required this.status,
    required this.progress,
    required this.createdAt,
    this.seconds,
    this.size,
  });

  factory VideoResponse.fromJson(Map<String, dynamic> json) {
    return VideoResponse(
      id: json['id'] ?? '',
      object: json['object'] ?? 'video',
      model: json['model'] ?? '',
      status: json['status'] ?? 'queued',
      progress: json['progress'] ?? 0,
      createdAt: json['created_at'] ?? json['created'] ?? 0,
      seconds: json['seconds']?.toString(),
      size: json['size'],
    );
  }
}

// 视频查询响应
class VideoDetailResponse {
  final String id;
  final String object;
  final String model;
  final String status;
  final int progress;
  final int createdAt;
  final int? completedAt;
  final int? expiresAt;
  final String? seconds;
  final String? size;
  final String? remixedFromVideoId;
  final String? videoUrl;
  final VideoError? error;

  VideoDetailResponse({
    required this.id,
    required this.object,
    required this.model,
    required this.status,
    required this.progress,
    required this.createdAt,
    this.completedAt,
    this.expiresAt,
    this.seconds,
    this.size,
    this.remixedFromVideoId,
    this.videoUrl,
    this.error,
  });

  factory VideoDetailResponse.fromJson(Map<String, dynamic> json) {
    // CRITICAL: 处理progress字段，可能是int或String类型
    int progressValue = 0;
    if (json['progress'] != null) {
      if (json['progress'] is int) {
        progressValue = json['progress'] as int;
      } else if (json['progress'] is String) {
        progressValue = int.tryParse(json['progress'] as String) ?? 0;
      } else if (json['progress'] is num) {
        progressValue = (json['progress'] as num).toInt();
      }
    }
    
    return VideoDetailResponse(
      id: json['id'] ?? '',
      object: json['object'] ?? 'video',
      model: json['model'] ?? '',
      status: json['status'] ?? 'unknown',
      progress: progressValue,
      createdAt: json['created_at'] ?? 0,
      completedAt: json['completed_at'],
      expiresAt: json['expires_at'],
      seconds: json['seconds']?.toString(),
      size: json['size'],
      remixedFromVideoId: json['remixed_from_video_id'],
      videoUrl: json['video_url'] ?? json['url'],
      error: json['error'] != null
          ? VideoError.fromJson(json['error'])
          : null,
    );
  }
}

class VideoError {
  final String message;
  final String code;

  VideoError({required this.message, required this.code});

  factory VideoError.fromJson(Map<String, dynamic> json) {
    return VideoError(
      message: json['message'] ?? '',
      code: json['code'] ?? '',
    );
  }
}

// 角色创建响应
class CharacterResponse {
  final String id;
  final String username;
  final String permalink;
  final String profilePictureUrl;
  final String? profileDesc;

  CharacterResponse({
    required this.id,
    required this.username,
    required this.permalink,
    required this.profilePictureUrl,
    this.profileDesc,
  });

  factory CharacterResponse.fromJson(Map<String, dynamic> json) {
    return CharacterResponse(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      permalink: json['permalink'] ?? '',
      profilePictureUrl: json['profile_picture_url'] ?? '',
      profileDesc: json['profile_desc'],
    );
  }
}

// 上传角色响应
class UploadCharacterResponse {
  final String characterId;
  final String characterName;

  UploadCharacterResponse({
    required this.characterId,
    required this.characterName,
  });

  factory UploadCharacterResponse.fromJson(Map<String, dynamic> json) {
    return UploadCharacterResponse(
      characterId: json['character_id'] ?? json['id'] ?? '',
      characterName: json['character_name'] ?? json['name'] ?? json['username'] ?? '',
    );
  }
}

// ==========================================
// API 服务类
// ==========================================

class ApiService {
  final ApiConfig llmConfig;
  final ApiConfig imageConfig;
  final ApiConfig videoConfig;

  ApiService({
    required this.llmConfig,
    required this.imageConfig,
    required this.videoConfig,
  });

  // ==========================================
  // LLM API 调用
  // ==========================================

  /// 聊天补全
  Future<ChatCompletionResponse> chatCompletion({
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 1.0,
    int? maxTokens,
    List<String>? stop,
  }) async {
    final url = Uri.parse('${llmConfig.baseUrl}/chat/completions');

    final body = {
      'model': model,
      'messages': messages,
      'temperature': temperature,
      if (maxTokens != null) 'max_tokens': maxTokens,
      if (stop != null && stop.isNotEmpty) 'stop': stop,
    };

    final response = await http.post(
      url,
      headers: llmConfig.getHeaders(),
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      // 使用 compute() 在后台 Isolate 中解析 JSON，避免阻塞 UI 线程
      final jsonData = await compute(_parseJsonInBackground, response.body);
      return ChatCompletionResponse.fromJson(jsonData);
    } else {
      throw ApiException(
        '聊天补全失败: ${response.statusCode}',
        response.statusCode,
        response.body,
      );
    }
  }

  /// 文本补全
  Future<TextCompletionResponse> textCompletion({
    required String model,
    required String prompt,
    double temperature = 0.7,
    int? maxTokens,
    int? n,
    List<String>? stop,
  }) async {
    final url = Uri.parse('${llmConfig.baseUrl}/completions');

    final body = {
      'model': model,
      'prompt': prompt,
      'temperature': temperature,
      if (maxTokens != null) 'max_tokens': maxTokens,
      if (n != null) 'n': n,
      if (stop != null && stop.isNotEmpty) 'stop': stop,
    };

    final response = await http.post(
      url,
      headers: llmConfig.getHeaders(),
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      // 使用 compute() 在后台 Isolate 中解析 JSON，避免阻塞 UI 线程
      final jsonData = await compute(_parseJsonInBackground, response.body);
      return TextCompletionResponse.fromJson(jsonData);
    } else {
      throw ApiException(
        '文本补全失败: ${response.statusCode}',
        response.statusCode,
        response.body,
      );
    }
  }

  // ==========================================
  // 图片生成 API 调用
  // ==========================================

  /// 创建图片生成
  Future<ImageResponse> createImage({
    required String model,
    required String prompt,
    int n = 1,
    String size = '1024x1024',
    String? quality,
    String? responseFormat,
    String? style,
    String? user,
  }) async {
    final url = Uri.parse('${imageConfig.baseUrl}/images/generations');

    final body = {
      'model': model,
      'prompt': prompt,
      'n': n,
      'size': size,
      if (quality != null) 'quality': quality,
      if (responseFormat != null) 'response_format': responseFormat,
      if (style != null) 'style': style,
      if (user != null) 'user': user,
    };

    print('=== 图片生成请求 ===');
    print('URL: $url');
    print('Model: $model');
    print('Prompt: $prompt');
    print('Size: $size');
    print('Body: ${jsonEncode(body)}');

    final response = await http.post(
      url,
      headers: imageConfig.getHeaders(),
      body: jsonEncode(body),
    );

    print('Response Status: ${response.statusCode}');
    print('Response Body: ${response.body}');

    if (response.statusCode == 200) {
      // 使用 compute() 在后台 Isolate 中解析 JSON，避免阻塞 UI 线程
      final jsonData = await compute(_parseJsonInBackground, response.body);
      return ImageResponse.fromJson(jsonData);
    } else {
      throw ApiException(
        '图片生成失败: ${response.statusCode}\n响应: ${response.body}',
        response.statusCode,
        response.body,
      );
    }
  }

  /// 创建图片编辑
  Future<ImageResponse> editImage({
    required String model,
    required File image,
    File? mask,
    required String prompt,
    int n = 1,
    String size = '1024x1024',
    String? responseFormat,
    String? user,
  }) async {
    final url = Uri.parse('${imageConfig.baseUrl}/images/edits');

    final request = http.MultipartRequest('POST', url);
    request.headers.addAll(imageConfig.getMultipartHeaders());
    request.fields['model'] = model;
    request.fields['prompt'] = prompt;
    request.fields['n'] = n.toString();
    request.fields['size'] = size;
    if (responseFormat != null) request.fields['response_format'] = responseFormat;
    if (user != null) request.fields['user'] = user;

    request.files.add(await http.MultipartFile.fromPath('image', image.path));
    if (mask != null) {
      request.files.add(await http.MultipartFile.fromPath('mask', mask.path));
    }

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      // 使用 compute() 在后台 Isolate 中解析 JSON，避免阻塞 UI 线程
      final jsonData = await compute(_parseJsonInBackground, responseBody);
      return ImageResponse.fromJson(jsonData);
    } else {
      throw ApiException(
        '图片编辑失败: ${response.statusCode}',
        response.statusCode,
        responseBody,
      );
    }
  }

  /// 创建图片变体
  Future<ImageResponse> createImageVariation({
    required String model,
    required File image,
    int n = 1,
    String size = '1024x1024',
    String? responseFormat,
    String? user,
  }) async {
    final url = Uri.parse('${imageConfig.baseUrl}/images/variations');

    final request = http.MultipartRequest('POST', url);
    request.headers.addAll(imageConfig.getMultipartHeaders());
    request.fields['model'] = model;
    request.fields['n'] = n.toString();
    request.fields['size'] = size;
    if (responseFormat != null) request.fields['response_format'] = responseFormat;
    if (user != null) request.fields['user'] = user;

    request.files.add(await http.MultipartFile.fromPath('image', image.path));

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      // 使用 compute() 在后台 Isolate 中解析 JSON，避免阻塞 UI 线程
      final jsonData = await compute(_parseJsonInBackground, responseBody);
      return ImageResponse.fromJson(jsonData);
    } else {
      throw ApiException(
        '图片变体创建失败: ${response.statusCode}',
        response.statusCode,
        responseBody,
      );
    }
  }

  /// 简化的图片生成接口 (用于绘图空间)
  Future<ImageGenerateResponse> generateImage({
    required String prompt,
    required String model,
    int width = 1024,
    int height = 1024,
    String? quality,
    String? style,
    List<String>? referenceImages, // 参考图列表（Base64数据URI或文件路径）
  }) async {
    // 检查是否是 Gemini 图片模型
    if (_isGeminiImageModel(model)) {
      return await _generateGeminiImage(
        prompt: prompt,
        model: model,
        width: width,
        height: height,
        referenceImages: referenceImages,
      );
    }
    
    // 将宽高转换为API支持的尺寸格式
    final size = '${width}x$height';
    
    final response = await createImage(
      model: model,
      prompt: prompt,
      size: size,
      quality: quality,
      style: style,
    );

    if (response.data.isNotEmpty && response.data.first.url != null) {
      return ImageGenerateResponse(
        imageUrl: response.data.first.url!,
        revisedPrompt: response.data.first.revisedPrompt,
      );
    } else if (response.data.isNotEmpty && response.data.first.b64Json != null) {
      // 如果返回的是base64，需要转换为数据URL
      return ImageGenerateResponse(
        imageUrl: 'data:image/png;base64,${response.data.first.b64Json}',
        revisedPrompt: response.data.first.revisedPrompt,
      );
    } else {
      throw ApiException('图片生成失败：未返回有效的图片数据', 500, null);
    }
  }

  /// 检查是否是 Gemini 图片模型
  bool _isGeminiImageModel(String model) {
    return model.startsWith('gemini-') && model.contains('image');
  }

  /// 获取 Gemini 模型的 API 端点
  String _getGeminiImageEndpoint(String model) {
    // 根据模型名称构建对应的端点
    // gemini-3-pro-image-preview -> /v1beta/models/gemini-3-pro-image-preview:generateContent
    // gemini-3.0-pro-image-preview-1K -> /v1beta/models/gemini-3.0-pro-image-preview-1K:generateContent
    return '/v1beta/models/$model:generateContent';
  }

  /// Gemini 图片生成
  Future<ImageGenerateResponse> _generateGeminiImage({
    required String prompt,
    required String model,
    int width = 1024,
    int height = 1024,
    List<String>? referenceImages, // 参考图列表
  }) async {
    // 构建 Gemini 专用端点
    final endpoint = _getGeminiImageEndpoint(model);
    
    // 使用 imageConfig 的 baseUrl，但替换路径为 Gemini 端点
    // 假设 baseUrl 是 https://api.geeknow.ai/v1，需要去掉 /v1 部分
    String baseUrl = imageConfig.baseUrl;
    if (baseUrl.endsWith('/v1')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 3);
    }
    
    final url = Uri.parse('$baseUrl$endpoint');

    // Gemini generateContent 请求格式
    // 需要将宽高转换为 aspect_ratio 和 image_size
    String aspectRatio = '1:1';
    String imageSize = '1K';
    
    // 根据宽高计算宽高比（优先精确匹配，然后按比例计算）
    // 1024x1024 -> 1:1
    // 1792x1024 -> 16:9 (横屏)
    // 1024x1792 -> 9:16 (竖屏)
    if (width == 1024 && height == 1024) {
      aspectRatio = '1:1';
    } else if (width == 1792 && height == 1024) {
      aspectRatio = '16:9';
    } else if (width == 1024 && height == 1792) {
      aspectRatio = '9:16';
    } else {
      // 使用比例计算
      final widthRatio = width / height;
      final heightRatio = height / width;
      
      if (width == height) {
        aspectRatio = '1:1';
      } else if (width > height) {
        // 横屏：计算 width/height
        if ((widthRatio - 16 / 9).abs() < 0.05) {
          aspectRatio = '16:9';
        } else if ((widthRatio - 3 / 2).abs() < 0.05) {
          aspectRatio = '3:2';
        } else if ((widthRatio - 4 / 3).abs() < 0.05) {
          aspectRatio = '4:3';
        } else {
          // 根据实际比例判断，不要默认16:9
          if (widthRatio > 1.5) {
            aspectRatio = '16:9';
          } else if (widthRatio > 1.3) {
            aspectRatio = '3:2';
          } else {
            aspectRatio = '4:3';
          }
        }
      } else {
        // 竖屏：计算 height/width
        if ((heightRatio - 16 / 9).abs() < 0.05) {
          aspectRatio = '9:16';
        } else if ((heightRatio - 3 / 2).abs() < 0.05) {
          aspectRatio = '2:3';
        } else if ((heightRatio - 4 / 3).abs() < 0.05) {
          aspectRatio = '3:4';
        } else {
          // 根据实际比例判断，不要默认9:16
          if (heightRatio > 1.5) {
            aspectRatio = '9:16';
          } else if (heightRatio > 1.3) {
            aspectRatio = '2:3';
          } else {
            aspectRatio = '3:4';
          }
        }
      }
    }
    
    // 根据最大尺寸确定分辨率
    final maxDimension = width > height ? width : height;
    if (maxDimension >= 3000) {
      imageSize = '4K';
    } else if (maxDimension >= 2000) {
      imageSize = '2K';
    } else {
      imageSize = '1K';
    }
    
    print('=== 尺寸转换 ===');
    print('输入: ${width}x${height}');
    print('宽高比: $aspectRatio');
    print('分辨率: $imageSize');
    print('方向: ${width > height ? "横屏" : (width < height ? "竖屏" : "正方形")}');

    // 构建 parts 数组，包含参考图和文本提示词
    // 注意：Gemini 要求图片放在文本之前
    final parts = <Map<String, dynamic>>[];
    
    // 添加参考图（如果有）- 图片必须在文本之前
    if (referenceImages != null && referenceImages.isNotEmpty) {
      print('开始处理 ${referenceImages.length} 张参考图...');
      
      final imageParts = <Map<String, dynamic>>[];
      
      for (final refImage in referenceImages) {
        try {
          Map<String, dynamic>? imagePart;
          
          if (refImage.startsWith('data:image/')) {
            // Base64 数据URI格式 - 直接提取数据
            final base64Index = refImage.indexOf('base64,');
            if (base64Index != -1) {
              final base64Data = refImage.substring(base64Index + 7);
              final mimeMatch = RegExp(r'data:image/([^;]+)').firstMatch(refImage);
              final imageType = mimeMatch?.group(1) ?? 'png';
              
              imagePart = {
                'inlineData': {
                  'mimeType': 'image/$imageType',
                  'data': base64Data,
                }
              };
            } else {
              print('跳过无效的Base64参考图');
              continue;
            }
          } else {
            // 文件路径，读取并转换为base64
            final file = File(refImage);
            if (!await file.exists()) {
              print('参考图文件不存在: $refImage');
              continue;
            }
            
            // 读取文件字节
            final bytes = await file.readAsBytes();
            print('参考图大小: ${bytes.length} bytes');
            
            // 检查文件大小，如果太大则警告（但仍然处理）
            if (bytes.length > 5 * 1024 * 1024) { // 5MB
              print('警告：参考图较大 (${(bytes.length / 1024 / 1024).toStringAsFixed(2)} MB)，可能影响性能');
            }
            
            final extension = refImage.split('.').last.toLowerCase();
            final mimeType = extension == 'jpg' || extension == 'jpeg' 
                ? 'image/jpeg' 
                : extension == 'png' 
                    ? 'image/png' 
                    : 'image/webp';
            
            // 给 UI 线程喘息的机会（在编码前）
            await Future.delayed(Duration(milliseconds: 10));
            
            // Base64编码（同步操作，但在延迟后执行）
            final base64Data = base64Encode(bytes);
            
            imagePart = {
              'inlineData': {
                'mimeType': mimeType,
                'data': base64Data,
              }
            };
          }
          
          imageParts.add(imagePart);
          print('成功添加参考图');
        } catch (e) {
          print('处理参考图失败: $e');
          // 继续处理其他参考图
        }
        
        // 给 UI 线程喘息的机会（每处理完一张图）
        await Future.delayed(Duration(milliseconds: 100));
      }
      
      // 将所有参考图添加到parts中
      parts.addAll(imageParts);
      print('参考图处理完成，共 ${imageParts.length} 张');
    }
    
    // 添加文本提示词（在图片之后）
    // 在提示词中包含尺寸和比例信息，作为 API 参数的备选
    String textPrompt = prompt;
    
    // 构建更明确的比例描述
    String orientationHint = '';
    if (aspectRatio == '9:16') {
      orientationHint = ' The image MUST be in VERTICAL/PORTRAIT orientation (9:16 aspect ratio, taller than wide, height > width).';
    } else if (aspectRatio == '16:9') {
      orientationHint = ' The image MUST be in HORIZONTAL/LANDSCAPE orientation (16:9 aspect ratio, wider than tall, width > height).';
    } else if (aspectRatio == '1:1') {
      orientationHint = ' The image MUST be SQUARE (1:1 aspect ratio, equal width and height).';
    } else {
      orientationHint = ' The image aspect ratio must be $aspectRatio.';
    }
    
    if (referenceImages != null && referenceImages.isNotEmpty) {
      textPrompt = 'Based on the reference image(s) provided above, generate an image.$orientationHint $prompt';
    } else {
      textPrompt = 'Generate an image.$orientationHint $prompt';
    }
    parts.add({'text': textPrompt});

    final body = {
      'contents': [
        {
          'parts': parts
        }
      ],
      'generationConfig': {
        'responseModalities': ['IMAGE', 'TEXT'],
        'imageGenerationConfig': {
          'aspectRatio': aspectRatio,
          'imageSize': imageSize,
          'numberOfImages': 1,
        },
      }
    };

    print('=== Gemini 图片生成请求 ===');
    print('URL: $url');
    print('Model: $model');
    print('Prompt: $prompt');
    // 不打印完整body（可能包含大量base64数据）
    print('Body parts count: ${parts.length}');

    // 给 UI 线程喘息的机会（在 JSON 编码前）
    await Future.delayed(Duration(milliseconds: 50));
    
    // JSON编码（可能很耗时，特别是有大量base64数据时）
    print('开始JSON编码请求体...');
    final bodyJson = jsonEncode(body);
    print('JSON编码完成，大小: ${bodyJson.length} 字符');
    
    // 给 UI 线程喘息的机会（在发送请求前）
    await Future.delayed(Duration(milliseconds: 50));

    // 使用带超时的请求（图片生成可能需要较长时间，设置5分钟超时）
    print('发送HTTP请求...');
    
    http.Response response;
    try {
      response = await http.post(
        url,
        headers: imageConfig.getHeaders(),
        body: bodyJson,
      ).timeout(
        Duration(minutes: 5),
        onTimeout: () {
          throw ApiException('图片生成请求超时（5分钟）', 408, '');
        },
      );
    } catch (e) {
      // 捕获网络错误、超时等
      if (e is ApiException) rethrow;
      throw ApiException(
        '图片生成请求失败: ${e.toString()}',
        0,
        null,
      );
    }

    print('收到响应: ${response.statusCode}');
    print('响应体大小: ${response.body.length} 字符');

    // 处理 500 错误和空响应
    if (response.statusCode >= 500) {
      throw ApiException(
        '服务器错误 (${response.statusCode}): ${response.body.isEmpty ? "服务器暂时不可用，请稍后重试" : response.body}',
        response.statusCode,
        response.body.isEmpty ? null : response.body,
      );
    }

    if (response.body.isEmpty) {
      throw ApiException(
        '服务器返回空响应',
        response.statusCode,
        null,
      );
    }

    if (response.statusCode == 200) {
      // 使用 compute() 在后台 Isolate 中解析 JSON，避免阻塞 UI 线程
      print('开始解析JSON响应...');
      final jsonResponse = await compute(_parseJsonInBackground, response.body);
      print('JSON解析完成');
      
      // 解析 Gemini 响应格式
      // 响应格式可能是:
      // { "candidates": [{ "content": { "parts": [{ "inlineData": { "mimeType": "image/png", "data": "base64..." } }] } }] }
      // 或者
      // { "candidates": [{ "content": { "parts": [{ "text": "..." }, { "inlineData": {...} }] } }] }
      
      try {
        final candidates = jsonResponse['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          final parts = content['parts'] as List?;
          
          if (parts != null) {
            for (final part in parts) {
              // 查找图片数据
              if (part['inlineData'] != null) {
                final inlineData = part['inlineData'];
                final mimeType = inlineData['mimeType'] ?? 'image/png';
                final base64Data = inlineData['data'];
                
                if (base64Data != null) {
                  print('Base64数据大小: ${(base64Data as String).length} 字符');
                  
                  // 给 UI 线程喘息（在构建 data URI 前）
                  await Future.delayed(Duration(milliseconds: 100));
                  
                  final dataUri = 'data:$mimeType;base64,$base64Data';
                  print('图片数据URI构建完成，总大小: ${dataUri.length} 字符');
                  
                  return ImageGenerateResponse(
                    imageUrl: dataUri,
                    revisedPrompt: null,
                  );
                }
              }
              
              // 有些响应可能直接返回 fileData 或 url
              if (part['fileData'] != null) {
                final fileData = part['fileData'];
                final fileUri = fileData['fileUri'];
                if (fileUri != null) {
                  return ImageGenerateResponse(
                    imageUrl: fileUri,
                    revisedPrompt: null,
                  );
                }
              }
            }
          }
        }
        
        // 如果响应中直接有 url 字段
        if (jsonResponse['url'] != null) {
          return ImageGenerateResponse(
            imageUrl: jsonResponse['url'],
            revisedPrompt: null,
          );
        }
        
        // 如果响应中有 data 数组（类似 OpenAI 格式）
        if (jsonResponse['data'] != null) {
          final data = jsonResponse['data'] as List?;
          if (data != null && data.isNotEmpty) {
            if (data[0]['url'] != null) {
              return ImageGenerateResponse(
                imageUrl: data[0]['url'],
                revisedPrompt: data[0]['revised_prompt'],
              );
            }
            if (data[0]['b64_json'] != null) {
              return ImageGenerateResponse(
                imageUrl: 'data:image/png;base64,${data[0]['b64_json']}',
                revisedPrompt: data[0]['revised_prompt'],
              );
            }
          }
        }
        
        throw ApiException(
          'Gemini 图片生成失败：未找到有效的图片数据\n响应: ${response.body}',
          200,
          response.body,
        );
      } catch (e) {
        if (e is ApiException) rethrow;
        throw ApiException(
          'Gemini 图片生成响应解析失败: $e\n响应: ${response.body}',
          200,
          response.body,
        );
      }
    } else {
      throw ApiException(
        'Gemini 图片生成失败: ${response.statusCode}\n响应: ${response.body}',
        response.statusCode,
        response.body,
      );
    }
  }

  // ==========================================
  // 视频生成 API 调用
  // ==========================================

  /// 创建视频生成
  Future<VideoResponse> createVideo({
    required String model,
    required String prompt,
    String size = '720x1280',
    int? seconds,
    File? inputReference,
    String? characterUrl,
    String? characterTimestamps,
  }) async {
    final url = Uri.parse('${videoConfig.baseUrl}/videos');

    print('=== 视频生成请求 ===');
    print('URL: $url');
    print('Model: $model');
    print('Prompt: $prompt');
    print('Size: $size');
    print('Seconds: $seconds');
    print('Has Input Reference: ${inputReference != null}');

    // 始终使用 multipart/form-data 格式
    final request = http.MultipartRequest('POST', url);
    request.headers.addAll(videoConfig.getMultipartHeaders());
    request.fields['model'] = model;
    request.fields['prompt'] = prompt;
    request.fields['size'] = size;
    if (seconds != null) request.fields['seconds'] = seconds.toString();
    if (characterUrl != null) request.fields['character_url'] = characterUrl;
    if (characterTimestamps != null) {
      request.fields['character_timestamps'] = characterTimestamps;
    }
    if (inputReference != null) {
      request.files.add(
        await http.MultipartFile.fromPath('input_reference', inputReference.path),
      );
    }

    print('Request Fields: ${request.fields}');

    // 发送请求并设置超时（视频生成需要更长的超时时间）
    final response = await request.send().timeout(
      const Duration(seconds: 120), // 2分钟超时，给服务器更多时间处理
      onTimeout: () {
        throw ApiException('视频生成请求超时（2分钟），请检查 API 地址和网络连接', 408, 'Request timeout');
      },
    );
    final responseBody = await response.stream.bytesToString();

    print('Response Status: ${response.statusCode}');
    print('Response Body: $responseBody');

    if (response.statusCode == 200) {
      // 使用 compute() 在后台 Isolate 中解析 JSON，避免阻塞 UI 线程
      final jsonData = await compute(_parseJsonInBackground, responseBody);
      return VideoResponse.fromJson(jsonData);
    } else {
      throw ApiException(
        '视频生成失败: ${response.statusCode}\n响应: $responseBody',
        response.statusCode,
        responseBody,
      );
    }
  }

  /// 查询视频任务状态
  Future<VideoDetailResponse> getVideoTask({
    required String taskId,
  }) async {
    final url = Uri.parse('${videoConfig.baseUrl}/videos/$taskId');

    final response = await http.get(
      url,
      headers: videoConfig.getHeaders(),
    ).timeout(
      const Duration(seconds: kDefaultTimeout),
      onTimeout: () {
        throw ApiException('视频任务查询超时', 408, 'Request timeout');
      },
    );

    if (response.statusCode == 200) {
      // CRITICAL: 调试日志，打印原始响应
      print('[ApiService] 视频任务查询响应: ${response.body}');
      
      // 使用 compute() 在后台 Isolate 中解析 JSON，避免阻塞 UI 线程
      final jsonData = await compute(_parseJsonInBackground, response.body);
      
      // CRITICAL: 调试日志，打印解析后的数据
      print('[ApiService] 解析后的数据: status=${jsonData['status']}, progress=${jsonData['progress']}');
      
      return VideoDetailResponse.fromJson(jsonData);
    } else {
      throw ApiException(
        '视频任务查询失败: ${response.statusCode}',
        response.statusCode,
        response.body,
      );
    }
  }

  /// 视频 Remix
  Future<VideoResponse> remixVideo({
    required String videoId,
    required String prompt,
    required int seconds,
  }) async {
    final url = Uri.parse('${videoConfig.baseUrl}/videos/$videoId/remix');

    final body = {
      'prompt': prompt,
      'seconds': seconds,
    };

    final response = await http.post(
      url,
      headers: videoConfig.getHeaders(),
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      // 使用 compute() 在后台 Isolate 中解析 JSON，避免阻塞 UI 线程
      final jsonData = await compute(_parseJsonInBackground, response.body);
      return VideoResponse.fromJson(jsonData);
    } else {
      throw ApiException(
        '视频 Remix 失败: ${response.statusCode}',
        response.statusCode,
        response.body,
      );
    }
  }

  /// 创建角色
  Future<CharacterResponse> createCharacter({
    String? url,
    String? timestamps,
    String? fromTask,
  }) async {
    // 构建请求 URL
    // 参考视频生成 API 的格式：${baseUrl}/videos（baseUrl 是 https://xxx/v1）
    // 角色创建 API：去掉 baseUrl 的 /v1，然后拼接 /sora/v1/characters
    final baseUrl = videoConfig.baseUrl;
    String endpoint;
    if (baseUrl.endsWith('/v1')) {
      // baseUrl 是 https://xxx/v1，去掉 /v1，然后拼接 /sora/v1/characters
      final baseWithoutV1 = baseUrl.substring(0, baseUrl.length - 3);
      endpoint = '$baseWithoutV1/sora/v1/characters';
    } else if (baseUrl.endsWith('/v1/')) {
      // baseUrl 是 https://xxx/v1/，去掉 /v1/，然后拼接 /sora/v1/characters
      final baseWithoutV1 = baseUrl.substring(0, baseUrl.length - 4);
      endpoint = '$baseWithoutV1/sora/v1/characters';
    } else {
      // baseUrl 不包含 /v1，直接拼接 /sora/v1/characters
      endpoint = '$baseUrl/sora/v1/characters';
    }
    print('[ApiService] BaseUrl: $baseUrl');
    print('[ApiService] Endpoint: $endpoint');
    final apiUrl = Uri.parse(endpoint);

    final body = {
      if (url != null) 'url': url,
      if (timestamps != null) 'timestamps': timestamps,
      if (fromTask != null) 'from_task': fromTask,
    };

    final response = await http.post(
      apiUrl,
      headers: videoConfig.getHeaders(),
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      // 使用 compute() 在后台 Isolate 中解析 JSON，避免阻塞 UI 线程
      final jsonData = await compute(_parseJsonInBackground, response.body);
      return CharacterResponse.fromJson(jsonData);
    } else {
      throw ApiException(
        '角色创建失败: ${response.statusCode}',
        response.statusCode,
        response.body,
      );
    }
  }
  
  /// 上传角色图片（使用 SoraApiService 和 Supabase Storage）
  /// 
  /// 注意：此方法现在使用 SoraApiService 来上传到 Supabase Storage 和创建角色
  Future<UploadCharacterResponse> uploadCharacter({
    required String imagePath,
    required String name,
    String? model,
  }) async {
    try {
      print('=== 开始上传角色流程（使用 Supabase Storage）===');
      print('图片路径: $imagePath');
      print('角色名称: $name');
      
      // 检查图片文件
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        throw '图片文件不存在: $imagePath';
      }
      
      // 导入 SoraApiService 和 FFmpegService
      // 注意：需要在文件顶部导入这些服务
      final ffmpegService = FFmpegService();
      final soraApiService = SoraApiService(
        baseUrl: videoConfig.baseUrl,
        apiKey: videoConfig.apiKey,
      );
      
      // 步骤1: 本地快速转换图片为视频（1-2秒）
      print('步骤1: 本地转换图片为视频...');
      final videoFile = await ffmpegService.convertImageToVideo(imageFile);
      
      try {
        // 步骤2: 上传视频到 Supabase Storage 获取 URL
        print('步骤2: 上传视频到 Supabase Storage...');
        final videoUrl = await soraApiService.uploadVideoToOss(videoFile);
        
        // 步骤3: 使用视频URL创建角色（1-2秒）
        print('步骤3: 创建角色...');
        final characterData = await soraApiService.createCharacter(videoUrl);
        
        print('角色创建成功！');
        print('角色ID: ${characterData['id']}');
        print('角色名称: ${characterData['username']}');
        
        return UploadCharacterResponse(
          characterId: characterData['id'] ?? '',
          characterName: characterData['username']?.isNotEmpty == true 
              ? characterData['username'] as String 
              : name,
        );
      } finally {
        // 确保临时文件被清理
        try {
          await ffmpegService.cleanupTempFile(videoFile);
        } catch (e) {
          print('清理临时文件失败: $e');
        }
      }
    } catch (e) {
      print('上传角色失败: $e');
      if (e is ApiException) rethrow;
      throw ApiException('上传角色失败: $e', 0, '');
    }
  }
}

// ==========================================
// API 异常类
// ==========================================

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  ApiException(this.message, [this.statusCode, this.responseBody]);

  @override
  String toString() {
    return 'ApiException: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';
  }
}

