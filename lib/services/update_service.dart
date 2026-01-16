import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import '../main.dart'; // 导入 logService

/// 应用版本信息
class AppVersion {
  final String version;
  final int buildNumber;
  final String downloadUrl;
  final String? releaseNotes;
  final bool forceUpdate;

  AppVersion({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    this.releaseNotes,
    this.forceUpdate = false,
  });

  factory AppVersion.fromJson(Map<String, dynamic> json) {
    return AppVersion(
      version: json['version'] as String,
      buildNumber: json['build_number'] as int,
      downloadUrl: json['download_url'] as String,
      releaseNotes: json['release_notes'] as String?,
      forceUpdate: json['force_update'] as bool? ?? false,
    );
  }

  /// 比较版本号
  /// 返回 true 表示当前版本比传入版本旧
  bool isNewerThan(String currentVersion, int currentBuildNumber) {
    // 比较版本号（例如：1.0.0 vs 1.0.1）
    final currentParts = currentVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final newParts = version.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    
    // 补齐长度
    while (currentParts.length < newParts.length) currentParts.add(0);
    while (newParts.length < currentParts.length) newParts.add(0);
    
    for (int i = 0; i < currentParts.length; i++) {
      if (newParts[i] > currentParts[i]) return true;
      if (newParts[i] < currentParts[i]) return false;
    }
    
    // 版本号相同，比较构建号
    return buildNumber > currentBuildNumber;
  }
}

/// 更新服务
class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  /// 检查更新
  /// 返回最新的版本信息，如果没有新版本则返回 null
  Future<AppVersion?> checkForUpdate() async {
    try {
      logService.info('开始检查更新...');
      
      // 获取当前版本信息
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;
      
      logService.info('当前版本: $currentVersion+$currentBuildNumber');
      
      // 从 Supabase 获取最新版本
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('app_versions')
          .select()
          .order('build_number', ascending: false)
          .limit(1)
          .maybeSingle();
      
      if (response == null) {
        logService.warn('未找到版本信息');
        return null;
      }
      
      final latestVersion = AppVersion.fromJson(response);
      logService.info('最新版本: ${latestVersion.version}+${latestVersion.buildNumber}');
      
      // 检查是否有新版本
      if (latestVersion.isNewerThan(currentVersion, currentBuildNumber)) {
        logService.info('发现新版本: ${latestVersion.version}');
        return latestVersion;
      } else {
        logService.info('当前已是最新版本');
        return null;
      }
    } catch (e) {
      logService.error('检查更新失败', details: e.toString());
      return null;
    }
  }

  /// 下载并安装更新
  /// [version] 要下载的版本信息
  /// [onProgress] 下载进度回调 (0.0 - 1.0)
  Future<void> downloadAndInstall(
    AppVersion version, {
    Function(double)? onProgress,
  }) async {
    try {
      logService.info('开始下载更新: ${version.downloadUrl}');
      
      // 获取下载目录
      final directory = await getApplicationDocumentsDirectory();
      final fileName = version.downloadUrl.split('/').last;
      final filePath = '${directory.path}/$fileName';
      
      // 下载文件
      final response = await http.get(Uri.parse(version.downloadUrl));
      if (response.statusCode != 200) {
        throw Exception('下载失败: ${response.statusCode}');
      }
      
      // 保存文件
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      logService.info('下载完成: $filePath');
      
      // 根据平台打开安装程序
      if (Platform.isWindows) {
        // Windows: 直接打开 .exe 或 .msix 文件
        await launchUrl(
          Uri.file(filePath),
          mode: LaunchMode.externalApplication,
        );
      } else if (Platform.isAndroid) {
        // Android: 使用 Intent 安装 APK
        await launchUrl(
          Uri.parse('file://$filePath'),
          mode: LaunchMode.externalApplication,
        );
      } else if (Platform.isIOS) {
        // iOS: 需要特殊处理（通常通过 App Store）
        throw Exception('iOS 应用需要通过 App Store 更新');
      } else if (Platform.isMacOS) {
        // macOS: 打开 .dmg 或 .pkg 文件
        await launchUrl(
          Uri.file(filePath),
          mode: LaunchMode.externalApplication,
        );
      } else if (Platform.isLinux) {
        // Linux: 打开 .deb 或 .AppImage 文件
        await launchUrl(
          Uri.file(filePath),
          mode: LaunchMode.externalApplication,
        );
      }
      
      logService.info('已启动安装程序');
    } catch (e) {
      logService.error('下载或安装失败', details: e.toString());
      rethrow;
    }
  }
}

final updateService = UpdateService();
