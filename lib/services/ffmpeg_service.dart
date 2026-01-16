import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// FFmpeg 转码服务
/// 负责将图片转换为视频
/// 在 Windows 上使用系统 FFmpeg（需要用户安装 FFmpeg 并添加到 PATH）
/// 
/// 重构说明：
/// - 使用 `compute()` 在隔离的 Isolate 中运行 FFmpeg 进程，避免阻塞 UI 线程
class FFmpegService {
  /// 将图片文件转换为 3 秒静态视频
  /// 
  /// [imageFile] 输入的图片文件
  /// 返回生成的视频文件
  /// 
  /// 处理流程：
  /// 1. 将图片复制到临时目录（解决 iOS 路径问题）
  /// 2. 使用 FFmpeg 转换为 3 秒视频（在后台 Isolate 中执行）
  /// 3. 返回生成的视频文件
  Future<File> convertImageToVideo(File imageFile) async {
    try {
      print('[FFmpegService] 开始转换图片为视频');
      print('[FFmpegService] 输入文件: ${imageFile.path}');
      
      // 检查输入文件是否存在
      if (!await imageFile.exists()) {
        throw Exception('输入图片文件不存在: ${imageFile.path}');
      }
      
      // 获取临时目录
      final tempDir = await getTemporaryDirectory();
      print('[FFmpegService] 临时目录: ${tempDir.path}');
      
      // 将图片复制到临时目录（解决 iOS 路径问题）
      final tempInputPath = '${tempDir.path}/temp_input.jpg';
      final tempInputFile = File(tempInputPath);
      await imageFile.copy(tempInputPath);
      print('[FFmpegService] 图片已复制到临时目录: $tempInputPath');
      
      // 生成输出文件路径（带时间戳）
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/temp_output_${timestamp}.mp4';
      final outputFile = File(outputPath);
      print('[FFmpegService] 输出文件路径: $outputPath');
      
      // 构建 FFmpeg 命令参数
      // -y: 覆盖已存在的文件
      // -loop 1: 循环输入图片
      // -i: 输入文件
      // -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100: 生成静音音频
      // -t 3: 持续 3 秒
      // -vf scale=720:-2: 缩放宽度为 720，高度自动计算（保持宽高比）
      // -pix_fmt yuv420p: 像素格式（兼容性好）
      // -c:v libx264: 视频编码器
      // -c:a aac: 音频编码器
      // -shortest: 以最短的输入流为准
      final commandArgs = [
        '-y',
        '-loop', '1',
        '-i', tempInputPath,
        '-f', 'lavfi',
        '-i', 'anullsrc=channel_layout=stereo:sample_rate=44100',
        '-t', '3',
        '-vf', 'scale=720:-2',
        '-pix_fmt', 'yuv420p',
        '-c:v', 'libx264',
        '-c:a', 'aac',
        '-shortest',
        outputPath,
      ];
      
      print('[FFmpegService] 执行 FFmpeg 命令: ffmpeg ${commandArgs.join(' ')}');
      
      // 使用 compute() 在后台 Isolate 中执行 FFmpeg 进程，避免阻塞 UI 线程
      final result = await compute(_runFFmpegProcess, _FFmpegProcessParams(
        command: 'ffmpeg',
        args: commandArgs,
        runInShell: true,
      ));
      
      if (result.exitCode == 0) {
        print('[FFmpegService] FFmpeg 转换成功');
        
        // 检查输出文件是否存在
        if (await outputFile.exists()) {
          final fileSize = await outputFile.length();
          print('[FFmpegService] 输出文件大小: ${fileSize} 字节');
          
          // 清理临时输入文件
          try {
            if (await tempInputFile.exists()) {
              await tempInputFile.delete();
              print('[FFmpegService] 已清理临时输入文件');
            }
          } catch (e) {
            print('[FFmpegService] 清理临时输入文件失败: $e');
          }
          
          return outputFile;
        } else {
          throw Exception('FFmpeg 转换成功但输出文件不存在: ${outputFile.path}');
        }
      } else {
        print('[FFmpegService] FFmpeg 转换失败');
        print('[FFmpegService] Exit Code: ${result.exitCode}');
        print('[FFmpegService] stderr: ${result.stderr}');
        print('[FFmpegService] stdout: ${result.stdout}');
        
        // 检查是否是 FFmpeg 未找到的错误
        final errorMessage = result.stderr.toString();
        if (errorMessage.contains('not found') || 
            errorMessage.contains('不是内部或外部命令') ||
            errorMessage.contains('系统找不到指定的文件')) {
          throw Exception(
            '未找到系统 FFmpeg。请安装 FFmpeg 并将其添加到系统 PATH 环境变量中。\n\n'
            '安装方法：\n'
            '1. 下载 FFmpeg: https://ffmpeg.org/download.html\n'
            '2. 解压到任意目录（如 C:\\ffmpeg）\n'
            '3. 将 FFmpeg 的 bin 目录添加到系统 PATH 环境变量\n'
            '4. 或者使用包管理器安装：\n'
            '   - Chocolatey: choco install ffmpeg\n'
            '   - Winget: winget install ffmpeg\n\n'
            '安装完成后，请重启应用程序。'
          );
        }
        
        throw Exception(
          'FFmpeg 转换失败 (Exit Code: ${result.exitCode})\n'
          'stderr: ${result.stderr}\n'
          'stdout: ${result.stdout}'
        );
      }
    } catch (e) {
      print('[FFmpegService] 转换过程发生异常: $e');
      print('[FFmpegService] 异常堆栈: ${StackTrace.current}');
      
      // 如果是 Process.run 的异常，可能是 FFmpeg 未找到
      if (e.toString().contains('No such file') || 
          e.toString().contains('not found') ||
          e.toString().contains('系统找不到指定的文件')) {
        throw Exception(
          '未找到系统 FFmpeg。请安装 FFmpeg 并将其添加到系统 PATH 环境变量中。\n\n'
          '安装方法：\n'
          '1. 下载 FFmpeg: https://ffmpeg.org/download.html\n'
          '2. 解压到任意目录（如 C:\\ffmpeg）\n'
          '3. 将 FFmpeg 的 bin 目录添加到系统 PATH 环境变量\n'
          '4. 或者使用包管理器安装：\n'
          '   - Chocolatey: choco install ffmpeg\n'
          '   - Winget: winget install ffmpeg\n\n'
          '安装完成后，请重启应用程序。'
        );
      }
      
      rethrow;
    }
  }
  
  /// 合并多个视频文件
  /// 
  /// [videoFiles] 要合并的视频文件列表（按顺序）
  /// 返回合并后的视频文件
  Future<File> concatVideos(List<File> videoFiles) async {
    try {
      print('[FFmpegService] 开始合并视频');
      print('[FFmpegService] 视频文件数量: ${videoFiles.length}');
      
      if (videoFiles.isEmpty) {
        throw Exception('没有视频文件需要合并');
      }

      if (videoFiles.length == 1) {
        // 只有一个文件，直接返回
        return videoFiles.first;
      }

      // 检查所有文件是否存在
      for (final file in videoFiles) {
        if (!await file.exists()) {
          throw Exception('视频文件不存在: ${file.path}');
        }
      }

      // 获取临时目录
      final tempDir = await getTemporaryDirectory();
      
      // 创建文件列表文件（FFmpeg concat 需要）
      final listFilePath = '${tempDir.path}/concat_list_${DateTime.now().millisecondsSinceEpoch}.txt';
      final listFile = File(listFilePath);
      
      // 写入文件列表（使用绝对路径，Windows 需要转义）
      final fileListContent = videoFiles.map((file) {
        final path = file.path.replaceAll('\\', '/');
        return "file '$path'";
      }).join('\n');
      
      await listFile.writeAsString(fileListContent);
      print('[FFmpegService] 文件列表: $fileListContent');

      // 生成输出文件路径
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/merged_video_${timestamp}.mp4';
      final outputFile = File(outputPath);
      print('[FFmpegService] 输出文件路径: $outputPath');

      // 构建 FFmpeg 命令
      // -f concat: 使用 concat 协议
      // -safe 0: 允许不安全的文件路径
      // -i: 输入文件列表
      // -c copy: 直接复制流，不重新编码（更快）
      final commandArgs = [
        '-y',
        '-f', 'concat',
        '-safe', '0',
        '-i', listFilePath,
        '-c', 'copy',
        outputPath,
      ];

      print('[FFmpegService] 执行 FFmpeg 命令: ffmpeg ${commandArgs.join(' ')}');

      // 使用 compute() 在后台 Isolate 中执行
      final result = await compute(_runFFmpegProcess, _FFmpegProcessParams(
        command: 'ffmpeg',
        args: commandArgs,
        runInShell: true,
      ));

      // 清理文件列表
      try {
        if (await listFile.exists()) {
          await listFile.delete();
        }
      } catch (e) {
        print('[FFmpegService] 清理文件列表失败: $e');
      }

      if (result.exitCode == 0) {
        if (await outputFile.exists()) {
          final fileSize = await outputFile.length();
          print('[FFmpegService] 视频合并成功');
          print('[FFmpegService] 输出文件大小: ${fileSize} 字节');
          return outputFile;
        } else {
          throw Exception('FFmpeg 合并成功但输出文件不存在');
        }
      } else {
        throw Exception(
          'FFmpeg 合并失败 (Exit Code: ${result.exitCode})\n'
          'stderr: ${result.stderr}\n'
          'stdout: ${result.stdout}'
        );
      }
    } catch (e) {
      print('[FFmpegService] 合并视频失败: $e');
      print('[FFmpegService] 异常堆栈: ${StackTrace.current}');
      rethrow;
    }
  }

  /// 提取视频首帧（用于生成缩略图）
  /// 
  /// [videoPath] 视频文件路径
  /// [outputPath] 输出图片路径
  /// [timeOffset] 提取的时间点（默认 0.1 秒，避免黑屏）
  /// 返回是否成功
  Future<bool> extractFrame({
    required String videoPath,
    required String outputPath,
    Duration timeOffset = const Duration(milliseconds: 100),
  }) async {
    try {
      print('[FFmpegService] 开始提取视频首帧');
      print('[FFmpegService] 视频文件: $videoPath');
      print('[FFmpegService] 输出路径: $outputPath');
      
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        throw Exception('视频文件不存在: $videoPath');
      }
      
      // 计算时间偏移（秒）
      final seconds = timeOffset.inMilliseconds / 1000.0;
      
      // 构建 FFmpeg 命令
      // -ss: 指定时间点
      // -i: 输入视频
      // -vframes 1: 只提取一帧
      // -q:v 2: 高质量 JPEG（1-31，2 是高质量）
      final commandArgs = [
        '-y',
        '-ss', seconds.toStringAsFixed(3),
        '-i', videoPath,
        '-vframes', '1',
        '-q:v', '2',
        outputPath,
      ];
      
      print('[FFmpegService] 执行 FFmpeg 命令: ffmpeg ${commandArgs.join(' ')}');
      
      // 使用 compute() 在后台 Isolate 中执行
      final result = await compute(_runFFmpegProcess, _FFmpegProcessParams(
        command: 'ffmpeg',
        args: commandArgs,
        runInShell: true,
      ));
      
      if (result.exitCode == 0) {
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          print('[FFmpegService] 视频首帧提取成功: $outputPath');
          return true;
        } else {
          print('[FFmpegService] FFmpeg 提取成功但输出文件不存在');
          return false;
        }
      } else {
        print('[FFmpegService] FFmpeg 提取失败');
        print('[FFmpegService] Exit Code: ${result.exitCode}');
        print('[FFmpegService] stderr: ${result.stderr}');
        return false;
      }
    } catch (e) {
      print('[FFmpegService] 提取视频首帧失败: $e');
      return false;
    }
  }

  /// 清理临时文件
  /// 
  /// [videoFile] 要删除的视频文件
  Future<void> cleanupTempFile(File videoFile) async {
    try {
      if (await videoFile.exists()) {
        await videoFile.delete();
        print('[FFmpegService] 已清理临时视频文件: ${videoFile.path}');
      }
    } catch (e) {
      print('[FFmpegService] 清理临时文件失败: $e');
    }
  }
}

/// FFmpeg 进程参数（用于传递给 compute 函数）
class _FFmpegProcessParams {
  final String command;
  final List<String> args;
  final bool runInShell;
  
  _FFmpegProcessParams({
    required this.command,
    required this.args,
    required this.runInShell,
  });
}

/// FFmpeg 进程结果（从 compute 函数返回）
class _FFmpegProcessResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  
  _FFmpegProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

/// 在后台 Isolate 中运行 FFmpeg 进程
/// 
/// 此函数在隔离的 Isolate 中执行，不会阻塞 UI 线程
/// 
/// [params] FFmpeg 进程参数
/// 返回进程执行结果
Future<_FFmpegProcessResult> _runFFmpegProcess(_FFmpegProcessParams params) async {
  try {
    final result = await Process.run(
      params.command,
      params.args,
      runInShell: params.runInShell,
    );
    
    return _FFmpegProcessResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  } catch (e) {
    // 将异常转换为结果对象
    return _FFmpegProcessResult(
      exitCode: -1,
      stdout: '',
      stderr: e.toString(),
    );
  }
}
