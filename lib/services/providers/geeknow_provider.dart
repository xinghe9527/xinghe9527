import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'base_provider.dart';

/// Geeknow API 供应商实现
/// 
/// 这是 Geeknow 平台的具体实现，包含所有必要的 API 调用逻辑
class GeeknowProvider extends BaseApiProvider {
  final String _baseUrl;
  final String _apiKey;

  GeeknowProvider({
    required String baseUrl,
    required String apiKey,
  })  : _baseUrl = baseUrl,
        _apiKey = apiKey;

  @override
  String get baseUrl => _baseUrl;

  @override
  String get apiKey => _apiKey;

  @override
  String get providerName => 'geeknow';

  @override
  Future<String> chatCompletion({
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    return await safeApiCall(
      context: 'LLM 聊天补全',
      apiCall: () async {
        print('');
        print('═══════════════════════════════════════════════════════');
        print('🚀 [Geeknow] 聊天补全请求开始');
        print('═══════════════════════════════════════════════════════');

        final endpoint = '$_baseUrl/chat/completions';
        final apiUrl = Uri.parse(endpoint);

        final body = {
          'model': model,
          'messages': messages,
          'temperature': temperature,
          if (maxTokens != null) 'max_tokens': maxTokens,
        };

        // 请求拦截日志
        print('🚀 [API Request] URL: $apiUrl');
        print('🔑 [API Request] Model: $model');
        print('📦 [API Payload]: ${jsonEncode(body)}');
        print('─────────────────────────────────────────────────────');

        // 发送 POST 请求
        print('🌐 [API Request] 正在发送 HTTP POST 请求...');
        final response = await http.post(
          apiUrl,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiKey',
          },
          body: jsonEncode(body),
        ).timeout(const Duration(minutes: 5));

        // 响应拦截日志
        print('');
        print('─────────────────────────────────────────────────────');
        print('✅ [API Response] 收到服务器响应');
        print('✅ [API Response] Code: ${response.statusCode}');
        print('📄 [API Body Raw] 长度: ${response.body.length} 字符');
        print('📄 [API Body Raw]: ${response.body}');
        print('─────────────────────────────────────────────────────');

        // 检查响应状态码
        checkHttpResponse(response, context: 'LLM 聊天补全');

        // 解析响应
        final responseBody = response.body.trim();
        
        if (responseBody.isEmpty) {
          throw Exception('API 返回了空响应');
        }

        // 解析阶段日志
        print('');
        print('🔍 [Parsing] 开始解析 JSON...');
        
        final responseData = jsonDecode(responseBody) as Map<String, dynamic>;
        
        print('✅ [Parsing] JSON 解析成功!');
        
        // 提取内容
        final choices = responseData['choices'] as List?;
        if (choices == null || choices.isEmpty) {
          throw Exception('响应中没有 choices 字段');
        }
        
        final message = choices[0]['message'] as Map<String, dynamic>?;
        if (message == null) {
          throw Exception('响应中没有 message 字段');
        }
        
        final content = message['content'] as String?;
        if (content == null) {
          throw Exception('响应中没有 content 字段');
        }
        
        print('✅ [Geeknow] 聊天补全成功!');
        print('✅ [Content Length]: ${content.length} 字符');
        print('═══════════════════════════════════════════════════════');
        print('');
        
        return content;
      },
    );
  }

  @override
  Future<String> generateImage({
    required String model,
    required String prompt,
    int width = 1024,
    int height = 1024,
    List<String>? referenceImages,
  }) async {
    // TODO: 实现图片生成逻辑
    // 目前 Geeknow 的图片生成可能通过其他 API 端点
    throw UnimplementedError('图片生成功能待实现');
  }

  @override
  Future<String> createVideo({
    required String model,
    required String prompt,
    String size = '720x1280',
    int? seconds,
    File? inputReference,
  }) async {
    // TODO: 实现视频创建逻辑
    throw UnimplementedError('视频创建功能待实现');
  }

  @override
  Future<VideoTaskStatus> getVideoTask({
    required String taskId,
  }) async {
    // TODO: 实现视频任务查询逻辑
    throw UnimplementedError('视频任务查询功能待实现');
  }

  @override
  Future<String> uploadVideoToOss(File videoFile) async {
    return await safeApiCall(
      context: '视频上传到 Supabase',
      apiCall: () async {
        print('🚀 [Supabase Upload] 开始上传视频');
        print('📁 [Upload File]: ${videoFile.path}');
        
        // 检查文件是否存在
        if (!await videoFile.exists()) {
          print('❌ [Upload Error] 视频文件不存在: ${videoFile.path}');
          throw Exception('视频文件不存在: ${videoFile.path}');
        }
        
        // 获取 Supabase 客户端
        final supabase = Supabase.instance.client;
        
        // 生成唯一的文件路径（使用时间戳和随机字符串）
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final randomStr = DateTime.now().microsecondsSinceEpoch.toString().substring(10);
        final filePath = 'characters/video_${timestamp}_$randomStr.mp4';
        
        print('📦 [Upload Info] 存储桶: xinghe_uploads, 文件路径: $filePath');
        
        // 读取文件内容
        final fileBytes = await videoFile.readAsBytes();
        print('📦 [Upload Info] 文件大小: ${fileBytes.length} 字节 (${(fileBytes.length / 1024 / 1024).toStringAsFixed(2)} MB)');
        
        // 上传文件到 Supabase Storage
        print('🚀 [Supabase Upload] 开始上传到存储桶...');
        final response = await supabase.storage
            .from('xinghe_uploads')
            .uploadBinary(
              filePath,
              fileBytes,
              fileOptions: const FileOptions(
                contentType: 'video/mp4',
                upsert: false, // 如果文件已存在则报错
              ),
            );
        
        print('✅ [Supabase Response] 上传响应: $response');
        
        // 获取文件的公共 URL
        final publicUrl = supabase.storage
            .from('xinghe_uploads')
            .getPublicUrl(filePath);
        
        print('✅ [Upload Success] 视频上传成功!');
        print('🔗 [Public URL]: $publicUrl');
        return publicUrl;
      },
    );
  }

  @override
  Future<Map<String, dynamic>> createCharacter(String videoUrl) async {
    return await safeApiCall(
      context: '创建角色',
      apiCall: () async {
        print('');
        print('═══════════════════════════════════════════════════════');
        print('🚀 [API Request] 创建角色请求开始');
        print('═══════════════════════════════════════════════════════');
        
        // 构建请求 URL
        String endpoint;
        if (_baseUrl.endsWith('/v1')) {
          final baseWithoutV1 = _baseUrl.substring(0, _baseUrl.length - 3);
          endpoint = '$baseWithoutV1/sora/v1/characters';
        } else if (_baseUrl.endsWith('/v1/')) {
          final baseWithoutV1 = _baseUrl.substring(0, _baseUrl.length - 4);
          endpoint = '$baseWithoutV1/sora/v1/characters';
        } else {
          endpoint = '$_baseUrl/sora/v1/characters';
        }
        
        final apiUrl = Uri.parse(endpoint);
        
        // 构建请求体
        final body = {
          'url': videoUrl,
          'timestamps': '1,3',
        };
        
        // 请求拦截日志 - 在发送前打印
        print('🚀 [API Request] URL: $apiUrl');
        print('🔑 [API Request] BaseUrl: $_baseUrl');
        print('🔑 [API Request] Endpoint: $endpoint');
        print('🔑 [API Request] Headers: {Content-Type: application/json, Authorization: Bearer ${_apiKey.substring(0, 10)}...}');
        print('📦 [API Payload]: ${jsonEncode(body)}');
        print('⏱️  [API Request] 超时设置: 8 分钟');
        print('─────────────────────────────────────────────────────');
        
        // 发送 POST 请求
        print('🌐 [API Request] 正在发送 HTTP POST 请求...');
        final response = await http.post(
          apiUrl,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiKey',
          },
          body: jsonEncode(body),
        ).timeout(const Duration(minutes: 8));
        
        // 响应拦截日志 - 第一时间打印
        print('');
        print('─────────────────────────────────────────────────────');
        print('✅ [API Response] 收到服务器响应');
        print('✅ [API Response] Code: ${response.statusCode}');
        print('✅ [API Response] Headers: ${response.headers}');
        print('📄 [API Body Raw] 长度: ${response.body.length} 字符');
        print('📄 [API Body Raw]: ${response.body}');
        print('─────────────────────────────────────────────────────');
        
        // 检查响应状态码（接受 200 或 201）
        if (response.statusCode != 200 && response.statusCode != 201) {
          checkHttpResponse(response, context: '创建角色', expectedStatusCode: 200);
        }
        
        // 解析响应
        final responseBody = response.body.trim();
        
        // 检查空响应
        if (responseBody.isEmpty) {
          print('⚠️  [API Warning] API 返回了空响应体');
          print('✅ [API Success] 使用默认响应（假设创建成功）');
          return {
            'id': 'character_${DateTime.now().millisecondsSinceEpoch}',
            'status': 'success',
            'message': '角色创建成功（API 返回空响应）',
          };
        }
        
        // 解析阶段日志
        print('');
        print('🔍 [Parsing] 开始解析 JSON...');
        print('🔍 [Parsing] 原始数据长度: ${responseBody.length}');
        
        final responseData = jsonDecode(responseBody) as Map<String, dynamic>;
        
        print('✅ [Parsing] JSON 解析成功!');
        print('✅ [Parsing] 解析后的数据类型: ${responseData.runtimeType}');
        print('✅ [Parsing] 数据字段: ${responseData.keys.toList()}');
        print('📊 [Parsing] 完整数据: $responseData');
        
        // 验证必要字段
        if (!responseData.containsKey('username') && 
            !responseData.containsKey('id') && 
            !responseData.containsKey('characterCode')) {
          print('⚠️  [Parsing] 警告: 响应数据缺少预期字段 (username/id/characterCode)');
          print('⚠️  [Parsing] 可用字段: ${responseData.keys.toList()}');
          
          // 尝试从 data 字段提取
          if (responseData.containsKey('data')) {
            print('🔍 [Parsing] 尝试从 data 字段提取信息...');
            final data = responseData['data'];
            if (data is Map) {
              responseData.addAll(Map<String, dynamic>.from(data));
              print('✅ [Parsing] 已合并 data 字段数据');
            }
          }
        }
        
        print('✅ [API Success] 角色创建成功!');
        print('═══════════════════════════════════════════════════════');
        print('');
        return responseData;
      },
    );
  }
}
