import 'dart:io';
import 'api_manager.dart';

/// Sora API 服务（兼容层）
/// 
/// 此类现在作为 ApiManager 的兼容层，保持旧代码的接口不变
/// 内部实现已迁移到 ApiManager 和供应商模式
/// 
/// @deprecated 建议直接使用 ApiManager 以获得更好的灵活性
/// 
/// 使用示例：
/// ```dart
/// // 旧代码（仍然支持）
/// final service = SoraApiService(baseUrl: '...', apiKey: '...');
/// await service.uploadVideoToOss(file);
/// 
/// // 推荐新代码
/// ApiManager().uploadVideoToOss(file);
/// ```
class SoraApiService {
  final String baseUrl;
  final String apiKey;
  
  // API 管理器实例
  final ApiManager _apiManager = ApiManager();
  
  SoraApiService({
    required this.baseUrl,
    required this.apiKey,
  }) {
    // 如果 ApiManager 未初始化，使用提供的配置初始化它
    // 如果已初始化，则继续使用现有配置（由 App 在启动时设置）
    if (!_apiManager.isInitialized) {
      print('⚠️ [SoraApiService] ApiManager 未初始化，使用提供的配置进行初始化');
      _apiManager.initializeProvider(
        providerName: 'geeknow',
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
    } else {
      print('ℹ️ [SoraApiService] ApiManager 已初始化，使用现有配置（供应商: ${_apiManager.currentProviderName}）');
    }
  }
  
  /// 上传视频文件到 Supabase Storage
  /// 
  /// [videoFile] 要上传的视频文件
  /// 返回上传后的公网 URL
  Future<String> uploadVideoToOss(File videoFile) async {
    print('🔄 [SoraApiService] 代理调用 ApiManager.uploadVideoToOss()');
    return await _apiManager.uploadVideoToOss(videoFile);
  }
  
  /// 创建角色
  /// 
  /// [videoUrl] 视频的 URL（Supabase Storage 公网地址）
  /// 返回角色创建响应数据
  Future<Map<String, dynamic>> createCharacter(String videoUrl) async {
    print('🔄 [SoraApiService] 代理调用 ApiManager.createCharacter()');
    return await _apiManager.createCharacter(videoUrl);
  }
}
