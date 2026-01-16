/// 场景生成状态枚举
enum SceneStatus {
  idle,        // 空闲/未开始
  queueing,    // 队列中
  processing,  // 处理中
  success,     // 成功
  error,        // 错误
}
