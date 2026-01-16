import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:pool/pool.dart';

/// 重型任务运行器
/// 使用 Pool 限制并发数，并将所有重操作移到 Isolate 中
class HeavyTaskRunner {
  static final HeavyTaskRunner _instance = HeavyTaskRunner._internal();
  factory HeavyTaskRunner() => _instance;
  HeavyTaskRunner._internal();

  // 使用 Pool 限制并发数为 2
  final Pool _pool = Pool(2, timeout: Duration(minutes: 10));

  /// 获取 Pool 资源（用于限制并发）
  Future<PoolResource> acquire() => _pool.request();

  /// 在 Isolate 中解析 JSON
  static Map<String, dynamic> _parseJsonInIsolate(String jsonString) {
    try {
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('JSON 解析失败: $e');
    }
  }

  /// 在 Isolate 中解码 Base64
  static Uint8List _decodeBase64InIsolate(String base64String) {
    try {
      return base64Decode(base64String);
    } catch (e) {
      throw Exception('Base64 解码失败: $e');
    }
  }

  /// 在 Isolate 中写入文件
  static Future<String> _writeFileInIsolate(_WriteFileParams params) async {
    try {
      final file = File(params.filePath);
      await file.writeAsBytes(params.bytes);
      return file.path;
    } catch (e) {
      throw Exception('文件写入失败: $e');
    }
  }

  /// 解析 JSON（在 Isolate 中）
  Future<Map<String, dynamic>> parseJson(String jsonString) async {
    return await compute(_parseJsonInIsolate, jsonString);
  }

  /// 解码 Base64（在 Isolate 中）
  Future<Uint8List> decodeBase64(String base64String) async {
    return await compute(_decodeBase64InIsolate, base64String);
  }

  /// 写入文件（在 Isolate 中）
  Future<String> writeFile(String filePath, Uint8List bytes) async {
    return await compute(_writeFileInIsolate, _WriteFileParams(
      filePath: filePath,
      bytes: bytes,
    ));
  }

  /// 清理图片缓存
  void clearImageCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}

/// 文件写入参数（用于传递给 Isolate）
class _WriteFileParams {
  final String filePath;
  final Uint8List bytes;

  _WriteFileParams({
    required this.filePath,
    required this.bytes,
  });
}
