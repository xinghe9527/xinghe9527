import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import '../models/prompt_template.dart';
import '../services/prompt_store.dart';

/// 提示词配置视图 - 全屏管理界面
class PromptConfigView extends StatefulWidget {
  const PromptConfigView({super.key});

  @override
  State<PromptConfigView> createState() => _PromptConfigViewState();
}

class _PromptConfigViewState extends State<PromptConfigView> {
  PromptCategory _selectedCategory = PromptCategory.script;
  final Map<String, TextEditingController> _contentControllers = {};
  String? _editingTemplateId;
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await promptStore.initialize();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      _loadTemplatesForCategory(_selectedCategory);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (var controller in _contentControllers.values) {
      controller.dispose();
    }
    _contentControllers.clear();
    super.dispose();
  }

  void _loadTemplatesForCategory(PromptCategory category) {
    final templates = promptStore.getTemplates(category);
    
    // 为每个模板创建控制器
    for (var template in templates) {
      if (!_contentControllers.containsKey(template.id)) {
        _contentControllers[template.id] = TextEditingController(text: template.content);
      }
    }
  }

  void _selectCategory(PromptCategory category) {
    if (_selectedCategory != category) {
      setState(() {
        _selectedCategory = category;
        _editingTemplateId = null;
        _nameController.clear();
      });
      _loadTemplatesForCategory(category);
    }
  }

  void _startEditing(PromptTemplate template) {
    setState(() {
      _editingTemplateId = template.id;
      _nameController.text = template.name;
      if (!_contentControllers.containsKey(template.id)) {
        _contentControllers[template.id] = TextEditingController(text: template.content);
      } else {
        _contentControllers[template.id]!.text = template.content;
      }
    });
  }

  void _startAdding() {
    setState(() {
      _editingTemplateId = 'new_${DateTime.now().millisecondsSinceEpoch}';
      _nameController.clear();
      if (!_contentControllers.containsKey(_editingTemplateId!)) {
        _contentControllers[_editingTemplateId!] = TextEditingController();
      } else {
        _contentControllers[_editingTemplateId!]!.clear();
      }
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingTemplateId = null;
      _nameController.clear();
    });
  }

  Future<void> _saveTemplate() async {
    final name = _nameController.text.trim();
    final contentController = _contentControllers[_editingTemplateId];
    
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('请输入模板名称'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (contentController == null || contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('请输入模板内容'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final content = contentController.text.trim();
    final isNew = _editingTemplateId!.startsWith('new_');

    try {
      if (isNew) {
        final template = PromptTemplate(
          id: '${_selectedCategory.id}_${DateTime.now().millisecondsSinceEpoch}',
          category: _selectedCategory,
          name: name,
          content: content,
          createdAt: DateTime.now(),
        );
        await promptStore.addTemplate(template);
      } else {
        try {
          final existingTemplate = promptStore.getTemplateById(_editingTemplateId!, _selectedCategory);
          if (existingTemplate != null) {
            final updatedTemplate = existingTemplate.copyWith(
              name: name,
              content: content,
              updatedAt: DateTime.now(),
            );
            await promptStore.updateTemplate(updatedTemplate);
          }
        } catch (e) {
          // 模板不存在，创建新模板
          final template = PromptTemplate(
            id: _editingTemplateId!,
            category: _selectedCategory,
            name: name,
            content: content,
            createdAt: DateTime.now(),
          );
          await promptStore.addTemplate(template);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存成功'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        setState(() {
          _editingTemplateId = null;
          _nameController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteTemplate(PromptTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '确认删除',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        content: Text(
          '是否确认删除模板"${template.name}"？',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('确认删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await promptStore.deleteTemplate(template.id, template.category);
        _contentControllers.remove(template.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('删除成功'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('删除失败: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Color _getCategoryColor(PromptCategory category) {
    switch (category) {
      case PromptCategory.llm:
        return Color(0xFF00D4AA); // Miku Green
      case PromptCategory.script:
        return Color(0xFF00D4FF); // Blue
      case PromptCategory.character:
        return Color(0xFFFF9800); // Orange
      case PromptCategory.scene:
        return Color(0xFF00D4AA); // Miku Green (场景生成)
      case PromptCategory.prop:
        return Color(0xFFFFB74D); // Orange (物品生成)
      case PromptCategory.storyboard:
        return Color(0xFF6C5CE7); // Purple
      case PromptCategory.image:
        return Color(0xFFFF6B9D); // Pink
      case PromptCategory.video:
        return Color(0xFFFFB74D); // Orange
      case PromptCategory.comprehensive:
        return Color(0xFF9C27B0); // Deep Purple (综合提示词)
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Color(0xFF0f0f1e),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00D4FF)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Color(0xFF0f0f1e),
      body: SafeArea(
        child: Column(
          children: [
            // 顶部标题栏
            _buildHeader(),
            // 主体内容
            Expanded(
              child: Row(
                children: [
                  // 左侧导航栏
                  _buildNavigationRail(),
                  // 右侧内容区
                  Expanded(
                    child: _buildContentArea(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Color(0xFF1a1a2e),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_motion, color: _getCategoryColor(_selectedCategory), size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '提示词模板管理',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '管理和编辑 AI 提示词模板',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close, color: Colors.white70),
            tooltip: '关闭',
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationRail() {
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: Color(0xFF1a1a2e),
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: ListView.builder(
        padding: EdgeInsets.symmetric(vertical: 16),
        itemCount: PromptCategory.values.length,
        itemBuilder: (context, index) {
          final category = PromptCategory.values[index];
          final isSelected = _selectedCategory == category;
          final color = _getCategoryColor(category);

          return InkWell(
            onTap: () => _selectCategory(category),
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withOpacity(0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? color.withOpacity(0.5)
                      : Colors.white.withOpacity(0.1),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _getCategoryIcon(category),
                    size: 20,
                    color: isSelected ? color : Colors.white60,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      category.displayName,
                      style: TextStyle(
                        color: isSelected ? color : Colors.white70,
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _getCategoryIcon(PromptCategory category) {
    switch (category) {
      case PromptCategory.llm:
        return Icons.auto_awesome;
      case PromptCategory.script:
        return Icons.description_outlined;
      case PromptCategory.character:
        return Icons.person_outline;
      case PromptCategory.scene:
        return Icons.landscape_outlined; // 场景生成
      case PromptCategory.prop:
        return Icons.inventory_2_outlined; // 物品生成
      case PromptCategory.storyboard:
        return Icons.view_agenda_outlined;
      case PromptCategory.image:
        return Icons.image_outlined;
      case PromptCategory.video:
        return Icons.video_library_outlined;
      case PromptCategory.comprehensive:
        return Icons.dashboard_customize; // 综合提示词（同时包含图片和视频）
    }
  }

  Widget _buildContentArea() {
    return Container(
      color: Color(0xFF0f0f1e),
      child: Column(
        children: [
          // 工具栏
          _buildToolbar(),
          // 模板列表
          Expanded(
            child: _buildTemplateList(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Color(0xFF1a1a2e),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          Text(
            '${_selectedCategory.displayName}模板',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          Spacer(),
          ElevatedButton.icon(
            onPressed: _startAdding,
            icon: Icon(Icons.add, size: 18),
            label: Text('新建模板'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _getCategoryColor(_selectedCategory),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateList() {
    return AnimatedBuilder(
      animation: promptStore,
      builder: (context, child) {
        final templates = promptStore.getTemplates(_selectedCategory);

        if (templates.isEmpty && _editingTemplateId == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.text_snippet_outlined,
                  size: 64,
                  color: Colors.white24,
                ),
                SizedBox(height: 16),
                Text(
                  '暂无模板',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '点击"新建模板"开始创建',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.all(24),
          itemCount: templates.length + (_editingTemplateId != null && _editingTemplateId!.startsWith('new_') ? 1 : 0),
          itemBuilder: (context, index) {
            if (_editingTemplateId != null && 
                _editingTemplateId!.startsWith('new_') && 
                index == templates.length) {
              return _buildTemplateEditor(null);
            }

            final template = templates[index];
            final isEditing = _editingTemplateId == template.id;

            if (isEditing) {
              return _buildTemplateEditor(template);
            } else {
              return _buildTemplateCard(template);
            }
          },
        );
      },
    );
  }

  Widget _buildTemplateCard(PromptTemplate template) {
    final color = _getCategoryColor(template.category);
    
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.name,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '创建于: ${_formatDate(template.createdAt)}',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _startEditing(template),
                  icon: Icon(Icons.edit_outlined, size: 18, color: color),
                  tooltip: '编辑',
                ),
                IconButton(
                  onPressed: () => _deleteTemplate(template),
                  icon: Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  tooltip: '删除',
                ),
              ],
            ),
          ),
          // 内容预览
          Container(
            padding: EdgeInsets.all(16),
            child: Text(
              template.content,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.6,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateEditor(PromptTemplate? template) {
    final isNew = template == null;
    final color = _getCategoryColor(_selectedCategory);
    final contentController = _editingTemplateId != null
        ? _contentControllers[_editingTemplateId!]
        : null;

    if (contentController == null) return SizedBox.shrink();

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isNew ? Icons.add_circle_outline : Icons.edit_outlined,
                  color: color,
                  size: 20,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: '输入模板名称...',
                      hintStyle: TextStyle(color: Colors.white38),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 内容编辑区
          Container(
            padding: EdgeInsets.all(16),
            child: TextField(
              controller: contentController,
              enabled: true,
              readOnly: false,
              enableInteractiveSelection: true,
              maxLines: null,
              minLines: 10,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.6,
              ),
              decoration: InputDecoration(
                hintText: '输入模板内容...',
                hintStyle: TextStyle(color: Colors.white24),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(12),
              ),
            ),
          ),
          // 操作按钮
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _cancelEditing,
                  child: Text(
                    '取消',
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
                SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _saveTemplate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text('保存'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
