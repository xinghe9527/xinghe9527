import 'package:flutter/material.dart';
import '../services/api_manager.dart';
import '../services/api_config_manager.dart';

/// Provider 类型枚举
enum ProviderType {
  llm,    // LLM 聊天模型
  image,  // 图片生成
  video,  // 视频生成
}

/// 通用的 Provider 选择器组件
/// 
/// 用于在 UI 中快速切换不同服务的供应商
/// 支持自动弹出配置对话框（如果供应商未配置）
class ProviderSelector extends StatefulWidget {
  /// Provider 类型（LLM / 图片 / 视频）
  final ProviderType type;
  
  /// 主题颜色（可选，用于适配不同界面）
  final Color? color;
  
  /// 是否紧凑模式（更小的尺寸）
  final bool compact;
  
  /// 切换供应商后的回调
  final VoidCallback? onProviderChanged;

  const ProviderSelector({
    Key? key,
    required this.type,
    this.color,
    this.compact = false,
    this.onProviderChanged,
  }) : super(key: key);

  @override
  State<ProviderSelector> createState() => _ProviderSelectorState();
}

class _ProviderSelectorState extends State<ProviderSelector> {
  final ApiManager _apiManager = ApiManager();
  final ApiConfigManager _configManager = ApiConfigManager();

  @override
  Widget build(BuildContext context) {
    // 获取当前供应商名称
    final currentProviderName = _getCurrentProviderName();
    final displayName = _getProviderDisplayName(currentProviderName ?? '未设置');
    
    // 获取图标和标签
    final icon = _getIcon();
    final label = _getLabel();
    final themeColor = widget.color ?? _getDefaultColor();

    if (widget.compact) {
      // 紧凑模式：只显示图标和当前供应商
      return PopupMenuButton<String>(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: themeColor.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: themeColor),
              SizedBox(width: 6),
              Text(
                displayName,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, size: 16, color: Colors.white54),
            ],
          ),
        ),
        itemBuilder: (context) => _buildMenuItems(),
        onSelected: (providerId) => _onProviderSelected(providerId),
      );
    }

    // 标准模式：完整显示
    return OutlinedButton.icon(
      onPressed: () => _showProviderMenu(context),
      icon: Icon(icon, size: 18, color: themeColor),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          Text(
            displayName,
            style: TextStyle(
              color: themeColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: 4),
          Icon(Icons.arrow_drop_down, size: 16, color: Colors.white54),
        ],
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: themeColor.withOpacity(0.5)),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// 显示供应商选择菜单
  void _showProviderMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      items: _buildMenuItems(),
    ).then((providerId) {
      if (providerId != null) {
        _onProviderSelected(providerId);
      }
    });
  }

  /// 构建菜单项
  List<PopupMenuEntry<String>> _buildMenuItems() {
    final availableProviders = _getAvailableProviders();
    final currentProvider = _getCurrentProviderName();

    return availableProviders.map((providerId) {
      final isSelected = providerId == currentProvider;
      final displayName = _getProviderDisplayName(providerId);

      return PopupMenuItem<String>(
        value: providerId,
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: isSelected ? (widget.color ?? Colors.blue) : Colors.white38,
            ),
            SizedBox(width: 12),
            Text(
              displayName,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  /// 处理供应商选择
  Future<void> _onProviderSelected(String providerId) async {
    print('🔄 [ProviderSelector] 切换 ${_getLabel()} 供应商: $providerId');

    // 检查是否已配置
    final isConfigured = _isProviderConfigured(providerId);

    if (!isConfigured) {
      // 未配置，弹出配置对话框
      final result = await _showConfigDialog(context, providerId);
      if (result == null || !result) {
        print('⚠️ [ProviderSelector] 用户取消配置');
        return;
      }
    }

    // 切换供应商
    try {
      switch (widget.type) {
        case ProviderType.llm:
          _apiManager.setLlmProvider(
            providerId,
            baseUrl: _configManager.llmBaseUrl,
            apiKey: _configManager.llmApiKey,
          );
          _configManager.setLlmProvider(providerId);
          break;
        case ProviderType.image:
          _apiManager.setImageProvider(
            providerId,
            baseUrl: _configManager.imageBaseUrl,
            apiKey: _configManager.imageApiKey,
          );
          _configManager.setImageProvider(providerId);
          break;
        case ProviderType.video:
          _apiManager.setVideoProvider(
            providerId,
            baseUrl: _configManager.videoBaseUrl,
            apiKey: _configManager.videoApiKey,
          );
          _configManager.setVideoProvider(providerId);
          break;
      }

      setState(() {});
      widget.onProviderChanged?.call();

      // 显示成功提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_getLabel()} 供应商已切换到 ${_getProviderDisplayName(providerId)}'),
            duration: Duration(seconds: 2),
            backgroundColor: widget.color ?? Colors.blue,
          ),
        );
      }

      print('✅ [ProviderSelector] ${_getLabel()} 供应商切换成功');
    } catch (e, stackTrace) {
      print('❌ [CRITICAL ERROR CAUGHT] 切换供应商失败: $e');
      print('📍 [Stack Trace]: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('切换供应商失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 显示配置对话框
  Future<bool?> _showConfigDialog(BuildContext context, String providerId) async {
    final displayName = _getProviderDisplayName(providerId);
    final apiKeyController = TextEditingController();
    final baseUrlController = TextEditingController();

    // 根据供应商类型预填充默认 URL
    if (providerId == 'geeknow') {
      switch (widget.type) {
        case ProviderType.llm:
          baseUrlController.text = GeeknowModels.defaultBaseUrl;
          break;
        case ProviderType.image:
          baseUrlController.text = GeeknowImageModels.defaultBaseUrl;
          break;
        case ProviderType.video:
          baseUrlController.text = GeeknowVideoModels.defaultBaseUrl;
          break;
      }
    }

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(_getIcon(), color: widget.color ?? Colors.blue),
            SizedBox(width: 12),
            Text(
              '配置 $displayName',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Container(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '请配置 ${_getLabel()} 服务的 API 信息',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              SizedBox(height: 20),
              // API Key 输入框
              TextField(
                controller: apiKeyController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'API Key',
                  labelStyle: TextStyle(color: Colors.white54),
                  hintText: '输入 API Key',
                  hintStyle: TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: widget.color ?? Colors.blue),
                  ),
                ),
              ),
              SizedBox(height: 16),
              // Base URL 输入框
              TextField(
                controller: baseUrlController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Base URL',
                  labelStyle: TextStyle(color: Colors.white54),
                  hintText: 'https://api.example.com/v1',
                  hintStyle: TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: widget.color ?? Colors.blue),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final apiKey = apiKeyController.text.trim();
              final baseUrl = baseUrlController.text.trim();

              if (apiKey.isEmpty || baseUrl.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('请填写完整的 API Key 和 Base URL'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              // 保存配置
              try {
                switch (widget.type) {
                  case ProviderType.llm:
                    _configManager.setLlmConfig(apiKey, baseUrl);
                    break;
                  case ProviderType.image:
                    _configManager.setImageConfig(apiKey, baseUrl);
                    break;
                  case ProviderType.video:
                    _configManager.setVideoConfig(apiKey, baseUrl);
                    break;
                }

                print('✅ [ProviderSelector] 配置已保存');
                Navigator.of(context).pop(true);
              } catch (e) {
                print('❌ [ProviderSelector] 保存配置失败: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('保存配置失败: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.color ?? Colors.blue,
            ),
            child: Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 获取当前供应商名称
  String? _getCurrentProviderName() {
    switch (widget.type) {
      case ProviderType.llm:
        return _apiManager.llmProviderName;
      case ProviderType.image:
        return _apiManager.imageProviderName;
      case ProviderType.video:
        return _apiManager.videoProviderName;
    }
  }

  /// 获取可用的供应商列表
  List<String> _getAvailableProviders() {
    // 目前支持的供应商
    return ['geeknow', 'custom'];
    // TODO: 未来可以从 ApiManager 动态获取
  }

  /// 检查供应商是否已配置
  bool _isProviderConfigured(String providerId) {
    switch (widget.type) {
      case ProviderType.llm:
        return _configManager.hasLlmConfig;
      case ProviderType.image:
        return _configManager.hasImageConfig;
      case ProviderType.video:
        return _configManager.hasVideoConfig;
    }
  }

  /// 获取供应商显示名称
  String _getProviderDisplayName(String providerId) {
    switch (providerId.toLowerCase()) {
      case 'geeknow':
        return 'GeekNow';
      case 'custom':
        return 'Custom';
      default:
        return providerId;
    }
  }

  /// 获取图标
  IconData _getIcon() {
    switch (widget.type) {
      case ProviderType.llm:
        return Icons.chat_bubble_outline;
      case ProviderType.image:
        return Icons.image_outlined;
      case ProviderType.video:
        return Icons.videocam_outlined;
    }
  }

  /// 获取标签
  String _getLabel() {
    switch (widget.type) {
      case ProviderType.llm:
        return 'LLM';
      case ProviderType.image:
        return '图片';
      case ProviderType.video:
        return '视频';
    }
  }

  /// 获取默认颜色
  Color _getDefaultColor() {
    switch (widget.type) {
      case ProviderType.llm:
        return Color(0xFF5DADE2); // 蓝色
      case ProviderType.image:
        return Color(0xFFEC7063); // 粉色
      case ProviderType.video:
        return Color(0xFF9B59B6); // 紫色
    }
  }
}
