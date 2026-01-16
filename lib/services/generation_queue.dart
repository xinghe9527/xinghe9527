import 'dart:async';
import 'package:synchronized/synchronized.dart';

/// 生成任务结果
class GenerationResult<T> {
  final int index;
  final T? data;
  final String? error;
  final double progress;

  GenerationResult({
    required this.index,
    this.data,
    this.error,
    this.progress = 0.0,
  });

  bool get isSuccess => error == null && data != null;
  bool get isError => error != null;
}

/// 生成任务回调
typedef GenerationCallback<T> = Future<T> Function();
typedef ProgressCallback = void Function(double progress);
typedef ResultCallback<T> = void Function(GenerationResult<T> result);

/// 并发生成队列管理器
/// 使用信号量限制同时进行的任务数量，避免UI冻结和API过载
class GenerationQueue {
  static final GenerationQueue _instance = GenerationQueue._internal();
  factory GenerationQueue() => _instance;
  GenerationQueue._internal();

  // 信号量：限制并发数（最多同时进行 2-3 个任务）
  final int _maxConcurrency = 3;
  int _activeTasks = 0;
  final Lock _lock = Lock();
  
  // 任务队列
  final List<_QueuedTask> _queue = [];
  bool _isProcessing = false;

  /// 添加任务到队列
  /// 
  /// [index] 任务索引（用于标识）
  /// [callback] 生成任务回调
  /// [onProgress] 进度回调（可选）
  /// [onResult] 结果回调
  Future<void> addTask<T>({
    required int index,
    required GenerationCallback<T> callback,
    ProgressCallback? onProgress,
    required ResultCallback<T> onResult,
  }) async {
    final task = _QueuedTask<T>(
      index: index,
      callback: callback,
      onProgress: onProgress,
      onResult: onResult,
    );

    await _lock.synchronized(() {
      _queue.add(task);
    });

    _processQueue();
  }

  /// 处理队列
  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    while (true) {
      // 检查是否有可用槽位和待处理任务
      await _lock.synchronized(() async {
        if (_activeTasks >= _maxConcurrency || _queue.isEmpty) {
          _isProcessing = false;
          return;
        }

        // 获取下一个任务
        final task = _queue.removeAt(0);
        _activeTasks++;
        
        // 异步执行任务（不阻塞队列处理）
        _executeTask(task).then((_) {
          _lock.synchronized(() {
            _activeTasks--;
          });
          // 继续处理队列
          _processQueue();
        });
      });

      if (!_isProcessing) break;
      
      // 短暂延迟，避免忙等待
      await Future.delayed(Duration(milliseconds: 50));
    }
  }

  /// 执行单个任务
  Future<void> _executeTask<T>(_QueuedTask<T> task) async {
    try {
      // 报告开始（0%）
      task.onProgress?.call(0.0);

      // 执行任务（异步执行，不阻塞 UI）
      // 注意：由于 API 调用需要网络访问，不能使用 compute() 隔离
      // 但通过并发限制（信号量）可以避免过载
      final result = await task.callback();

      // 报告完成（100%）
      task.onProgress?.call(1.0);

      // 通知结果
      task.onResult(GenerationResult<T>(
        index: task.index,
        data: result,
        progress: 1.0,
      ));
    } catch (e, stackTrace) {
      print('[GenerationQueue] 任务 ${task.index} 执行失败: $e');
      print('[GenerationQueue] 堆栈: $stackTrace');
      
      // 通知错误
      task.onResult(GenerationResult<T>(
        index: task.index,
        error: e.toString(),
        progress: 0.0,
      ));
    }
  }

  /// 清除队列
  void clear() {
    _lock.synchronized(() {
      _queue.clear();
    });
  }

  /// 获取当前活跃任务数
  int get activeTasks => _activeTasks;

  /// 获取队列长度
  int get queueLength {
    return _queue.length;
  }
}

/// 队列中的任务
class _QueuedTask<T> {
  final int index;
  final GenerationCallback<T> callback;
  final ProgressCallback? onProgress;
  final ResultCallback<T> onResult;

  _QueuedTask({
    required this.index,
    required this.callback,
    this.onProgress,
    required this.onResult,
  });
}

