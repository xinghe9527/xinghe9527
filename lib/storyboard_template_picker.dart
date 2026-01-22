import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/prompt_template.dart';

// ==================== 分镜模板选择对话框 ====================
// 支持三种模板类型：生图提示词、生视频提示词、综合提示词
class StoryboardTemplatePickerDialog extends StatefulWidget {
  final List<PromptTemplate> availableImageTemplates;
  final List<PromptTemplate> availableVideoTemplates;
  final List<PromptTemplate> availableComprehensiveTemplates;
  final String? selectedImageTemplateId;
  final String? selectedVideoTemplateId;
  final String? selectedComprehensiveTemplateId;
  final Function(String?, String?, String?) onSelect; // (image, video, comprehensive)
  final VoidCallback onManageTemplates;

  const StoryboardTemplatePickerDialog({
    super.key,
    required this.availableImageTemplates,
    required this.availableVideoTemplates,
    required this.availableComprehensiveTemplates,
    this.selectedImageTemplateId,
    this.selectedVideoTemplateId,
    this.selectedComprehensiveTemplateId,
    required this.onSelect,
    required this.onManageTemplates,
  });

  @override
  State<StoryboardTemplatePickerDialog> createState() => _StoryboardTemplatePickerDialogState();
}

class _StoryboardTemplatePickerDialogState extends State<StoryboardTemplatePickerDialog> {
  String _currentCategory = 'comprehensive'; // 'image', 'video', 'comprehensive'
  String? _tempSelectedImageId;
  String? _tempSelectedVideoId;
  String? _tempSelectedComprehensiveId;

  @override
  void initState() {
    super.initState();
    _tempSelectedImageId = widget.selectedImageTemplateId;
    _tempSelectedVideoId = widget.selectedVideoTemplateId;
    _tempSelectedComprehensiveId = widget.selectedComprehensiveTemplateId;
    
    // 如果有综合提示词选择，默认显示综合提示词选项卡
    if (_tempSelectedComprehensiveId != null) {
      _currentCategory = 'comprehensive';
    } else if (_tempSelectedImageId != null) {
      _currentCategory = 'image';
    } else if (_tempSelectedVideoId != null) {
      _currentCategory = 'video';
    }
  }

  List<PromptTemplate> _getCurrentTemplates() {
    switch (_currentCategory) {
      case 'image':
        return widget.availableImageTemplates;
      case 'video':
        return widget.availableVideoTemplates;
      case 'comprehensive':
        return widget.availableComprehensiveTemplates;
      default:
        return [];
    }
  }

  String? _getCurrentSelectedId() {
    switch (_currentCategory) {
      case 'image':
        return _tempSelectedImageId;
      case 'video':
        return _tempSelectedVideoId;
      case 'comprehensive':
        return _tempSelectedComprehensiveId;
      default:
        return null;
    }
  }

  void _setCurrentSelectedId(String? id) {
    setState(() {
      switch (_currentCategory) {
        case 'image':
          _tempSelectedImageId = id;
          break;
        case 'video':
          _tempSelectedVideoId = id;
          break;
        case 'comprehensive':
          // 联动逻辑：选择综合提示词时，自动取消图片和视频模板
          _tempSelectedComprehensiveId = id;
          if (id != null) {
            _tempSelectedImageId = null;
            _tempSelectedVideoId = null;
          }
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentTemplates = _getCurrentTemplates();
    final currentSelectedId = _getCurrentSelectedId();
    
    // 定义颜色
    final sakura = Color(0xFFFF6B9D);
    final orange = Color(0xFFFFB74D);
    final purple = Color(0xFF6C5CE7);
    final glassBg = Color(0xFF0f0f1e).withOpacity(0.95);
    final cardBg = Color(0xFF1a1a2e).withOpacity(0.7);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 600,
            height: 700,
            decoration: BoxDecoration(
              color: glassBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              children: [
                // 标题栏
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.dashboard_customize, color: purple, size: 24),
                      SizedBox(width: 12),
                      Text(
                        '分镜提示词模板管理',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                
                // 三个选项卡
                Padding(
                  padding: EdgeInsets.all(20),
                  child: Row(
                    children: [
                      _buildCategoryTab('image', '生图提示词', sakura),
                      SizedBox(width: 12),
                      _buildCategoryTab('video', '生视频提示词', orange),
                      SizedBox(width: 12),
                      _buildCategoryTab('comprehensive', '综合提示词', purple),
                    ],
                  ),
                ),
                
                // 模板列表
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: currentTemplates.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.library_books_outlined, size: 64, color: Colors.white24),
                                SizedBox(height: 16),
                                Text(
                                  '暂无模板，请前往设置添加',
                                  style: TextStyle(color: Colors.white54, fontSize: 14),
                                ),
                                SizedBox(height: 16),
                                TextButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    widget.onManageTemplates();
                                  },
                                  icon: Icon(Icons.settings, size: 16),
                                  label: Text('管理模板'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: purple,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView(
                            children: [
                              // "不使用模板" 选项
                              _buildTemplateOption(null, '不使用模板', currentSelectedId, cardBg, purple),
                              SizedBox(height: 8),
                              // 模板列表
                              ...currentTemplates.map((template) => Padding(
                                padding: EdgeInsets.only(bottom: 8),
                                child: _buildTemplateOption(template.id, template.name, currentSelectedId, cardBg, purple),
                              )),
                            ],
                          ),
                  ),
                ),
                
                // 底部按钮
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                  ),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onManageTemplates();
                        },
                        icon: Icon(Icons.settings, size: 16),
                        label: Text('管理模板'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white54,
                        ),
                      ),
                      Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('取消', style: TextStyle(color: Colors.white54)),
                      ),
                      SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          widget.onSelect(
                            _tempSelectedImageId,
                            _tempSelectedVideoId,
                            _tempSelectedComprehensiveId,
                          );
                          Navigator.pop(context);
                        },
                        icon: Icon(Icons.check, size: 18),
                        label: Text('确定'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: purple,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTab(String category, String label, Color color) {
    final isSelected = _currentCategory == category;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _currentCategory = category),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : Colors.white.withOpacity(0.1),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.white54,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTemplateOption(String? id, String name, String? currentSelectedId, Color cardBg, Color purple) {
    final isSelected = currentSelectedId == id;
    return InkWell(
      onTap: () => _setCurrentSelectedId(id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? purple.withOpacity(0.1) : cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? purple : Colors.white.withOpacity(0.05),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? purple : Colors.white38,
              size: 20,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: isSelected ? purple : Colors.white70,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
