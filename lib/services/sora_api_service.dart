import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sora API 服务
/// 负责上传视频到 Supabase Storage 和创建角色
class SoraApiService {
  final String baseUrl;
  final String apiKey;
  
  // Supabase Storage 配置
  // 存储桶名称硬编码为 'xinghe_uploads'
  
  SoraApiService({
    required this.baseUrl,
    required this.apiKey,
  });
  
  /// 上传视频文件到 Supabase Storage
  /// 
  /// [videoFile] 要上传的视频文件
  /// 返回上传后的公网 URL
  Future<String> uploadVideoToOss(File videoFile) async {
    try {
      print('[SoraApiService] 开始上传视频到 Supabase Storage');
      print('[SoraApiService] 视频文件: ${videoFile.path}');
      
      // 检查文件是否存在
      if (!await videoFile.exists()) {
        throw Exception('视频文件不存在: ${videoFile.path}');
      }
      
      // 获取 Supabase 客户端
      final supabase = Supabase.instance.client;
      
      // 生成唯一的文件路径（使用时间戳和随机字符串）
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final randomStr = DateTime.now().microsecondsSinceEpoch.toString().substring(10);
      final filePath = 'characters/video_${timestamp}_$randomStr.mp4';
      
      print('[SoraApiService] 文件路径: $filePath');
      print('[SoraApiService] 存储桶: xinghe_uploads');
      
      // 读取文件内容
      final fileBytes = await videoFile.readAsBytes();
      print('[SoraApiService] 文件大小: ${fileBytes.length} 字节');
      
      // 上传文件到 Supabase Storage
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
      
      print('[SoraApiService] 上传响应: $response');
      
      // 获取文件的公共 URL
      final publicUrl = supabase.storage
          .from('xinghe_uploads')
          .getPublicUrl(filePath);
      
      print('[SoraApiService] 视频上传成功: $publicUrl');
      return publicUrl;
    } catch (e) {
      print('[SoraApiService] 上传视频到 Supabase Storage 失败: $e');
      print('[SoraApiService] 异常堆栈: ${StackTrace.current}');
      rethrow;
    }
  }
  
  /// 创建角色
  /// 
  /// [videoUrl] 视频的 URL（Supabase Storage 公网地址）
  /// 返回角色创建响应数据
  Future<Map<String, dynamic>> createCharacter(String videoUrl) async {
    try {
      print('[SoraApiService] 开始创建角色');
      print('[SoraApiService] 视频 URL: $videoUrl');
      
      // 构建请求 URL
      // 参考视频生成 API 的格式：${baseUrl}/videos（baseUrl 是 https://xxx/v1）
      // 尝试不同的路径格式：
      // 1. ${baseUrl}/sora/v1/characters -> https://xxx/v1/sora/v1/characters (可能重复)
      // 2. ${baseUrl}/sora/characters -> https://xxx/v1/sora/characters (当前尝试，返回 404)
      // 3. 去掉 baseUrl 的 /v1，然后拼接 /sora/v1/characters -> https://xxx/sora/v1/characters
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
      print('[SoraApiService] BaseUrl: $baseUrl');
      print('[SoraApiService] Endpoint: $endpoint');
      final apiUrl = Uri.parse(endpoint);
      
      // 构建请求体
      final body = {
        'url': videoUrl,
        'timestamps': '1,3',
      };
      
      print('[SoraApiService] 请求 URL: $apiUrl');
      print('[SoraApiService] 请求体: $body');
      
      // 发送 POST 请求
      // 根据 API 文档，Authorization 格式为: Bearer {token}
      // 注意：创建角色 API 可能需要较长时间（最多 8 分钟），所以设置超时为 8 分钟
      final response = await http.post(
        apiUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(body),
      ).timeout(
        const Duration(minutes: 8), // 8 分钟超时，因为创建角色可能需要较长时间
        onTimeout: () {
          throw Exception('创建角色请求超时（8分钟），请检查网络连接或稍后重试');
        },
      );
      
      print('[SoraApiService] 响应状态码: ${response.statusCode}');
      print('[SoraApiService] 响应体: ${response.body}');
      print('[SoraApiService] 响应体长度: ${response.body.length}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        // 检查响应体是否为空
        final responseBody = response.body.trim();
        if (responseBody.isEmpty) {
          // 如果响应体为空，返回一个默认的成功响应
          print('[SoraApiService] 警告: API 返回了空响应，使用默认响应');
          return {
            'id': 'character_${DateTime.now().millisecondsSinceEpoch}',
            'status': 'success',
            'message': '角色创建成功（API 返回空响应）',
          };
        }
        
        try {
          final responseData = jsonDecode(responseBody) as Map<String, dynamic>;
          print('[SoraApiService] 角色创建成功');
          print('[SoraApiService] 解析后的数据: $responseData');
          
          // 验证必要字段是否存在
          if (!responseData.containsKey('username') && !responseData.containsKey('id') && !responseData.containsKey('characterCode')) {
            print('[SoraApiService] 警告: 响应数据缺少必要字段');
            print('[SoraApiService] 可用字段: ${responseData.keys.toList()}');
            // 如果缺少必要字段，尝试从其他字段中提取
            if (responseData.containsKey('data')) {
              final data = responseData['data'];
              if (data is Map) {
                responseData.addAll(Map<String, dynamic>.from(data));
              }
            }
          }
          
          return responseData;
        } catch (e) {
          throw Exception(
            '创建角色失败: JSON 解析错误\n'
            '响应体: ${responseBody.length > 200 ? responseBody.substring(0, 200) + "..." : responseBody}\n'
            '错误: $e'
          );
        }
      } else {
        // 非成功状态码，尝试解析错误信息
        String errorMessage = '创建角色失败: ${response.statusCode}';
        if (response.body.isNotEmpty) {
          try {
            final errorData = jsonDecode(response.body);
            if (errorData is Map && errorData.containsKey('message')) {
              errorMessage += '\n错误信息: ${errorData['message']}';
            } else {
              errorMessage += '\n响应: ${response.body}';
            }
          } catch (e) {
            errorMessage += '\n响应: ${response.body}';
          }
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      print('[SoraApiService] 创建角色失败: $e');
      print('[SoraApiService] 异常堆栈: ${StackTrace.current}');
      rethrow;
    }
  }
}
