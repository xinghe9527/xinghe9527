/// Auto Mode 工作流步骤枚举
enum AutoModeStep {
  script,    // 剧本生成
  character, // 角色生成
  layout,    // 分镜生成
  image,     // 图片生成
  video,     // 视频生成
  finalize,  // 最终合并
}
