/// 提示词模板类别枚举
enum PromptCategory {
  llm('llm', 'LLM提示词'),           // LLM通用提示词（新增）
  script('script', '剧本生成'),
  character('character', '角色生成'),
  storyboard('storyboard', '分镜生成'),
  image('image', '图片生成'),
  video('video', '视频生成');

  final String id;
  final String displayName;
  const PromptCategory(this.id, this.displayName);
}

/// 提示词模板模型
class PromptTemplate {
  final String id;
  final PromptCategory category;
  final String name;
  final String content;
  final DateTime createdAt;
  final DateTime? updatedAt;

  PromptTemplate({
    required this.id,
    required this.category,
    required this.name,
    required this.content,
    required this.createdAt,
    this.updatedAt,
  });

  /// 从 JSON 创建
  factory PromptTemplate.fromJson(Map<String, dynamic> json) {
    return PromptTemplate(
      id: json['id'] as String,
      category: PromptCategory.values.firstWhere(
        (e) => e.id == json['categoryId'] as String,
        orElse: () => PromptCategory.script,
      ),
      name: json['name'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'categoryId': category.id,
      'name': name,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  /// 创建副本
  PromptTemplate copyWith({
    String? id,
    PromptCategory? category,
    String? name,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PromptTemplate(
      id: id ?? this.id,
      category: category ?? this.category,
      name: name ?? this.name,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
