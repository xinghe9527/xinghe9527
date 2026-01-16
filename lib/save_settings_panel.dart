import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'main.dart';

// ==================== 保存设置面板 ====================
class SaveSettingsPanel extends StatefulWidget {
  const SaveSettingsPanel({super.key});

  @override
  State<SaveSettingsPanel> createState() => _SaveSettingsPanelState();
}

class _SaveSettingsPanelState extends State<SaveSettingsPanel> {
  String _imageSavePath = '';
  String _videoSavePath = '';
  bool _autoSaveImages = false;
  bool _autoSaveVideos = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _imageSavePath = prefs.getString('image_save_path') ?? '';
        _videoSavePath = prefs.getString('video_save_path') ?? '';
        _autoSaveImages = prefs.getBool('auto_save_images') ?? false;
        _autoSaveVideos = prefs.getBool('auto_save_videos') ?? false;
      });
    } catch (e) {
      logService.error('加载保存设置失败', details: e.toString());
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('image_save_path', _imageSavePath);
      await prefs.setString('video_save_path', _videoSavePath);
      await prefs.setBool('auto_save_images', _autoSaveImages);
      await prefs.setBool('auto_save_videos', _autoSaveVideos);
      
      logService.action('保存设置已更新');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存设置已更新'), backgroundColor: AnimeColors.miku),
      );
    } catch (e) {
      logService.error('保存设置失败', details: e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e'), backgroundColor: AnimeColors.sakura),
      );
    }
  }

  Future<void> _selectImageSavePath() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择图片保存文件夹',
      );

      if (selectedDirectory != null) {
        setState(() {
          _imageSavePath = selectedDirectory;
        });
        logService.action('设置图片保存路径', details: selectedDirectory);
      }
    } catch (e) {
      logService.error('选择图片保存路径失败', details: e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择失败: $e'), backgroundColor: AnimeColors.sakura),
      );
    }
  }

  Future<void> _selectVideoSavePath() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择视频保存文件夹',
      );

      if (selectedDirectory != null) {
        setState(() {
          _videoSavePath = selectedDirectory;
        });
        logService.action('设置视频保存路径', details: selectedDirectory);
      }
    } catch (e) {
      logService.error('选择视频保存路径失败', details: e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择失败: $e'), backgroundColor: AnimeColors.sakura),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(32),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [AnimeColors.orangeAccent, AnimeColors.sakura]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.folder_outlined, color: Colors.white, size: 24),
                ),
                SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '保存设置',
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '配置自动保存路径',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 32),

            // 图片保存设置
            _buildSavePathCard(
              title: '图片保存路径',
              subtitle: '生成的图片将自动保存到此文件夹',
              icon: Icons.image_outlined,
              color: AnimeColors.blue,
              currentPath: _imageSavePath,
              autoSave: _autoSaveImages,
              onSelectPath: _selectImageSavePath,
              onAutoSaveChanged: (value) {
                setState(() => _autoSaveImages = value);
              },
            ),
            SizedBox(height: 24),

            // 视频保存设置
            _buildSavePathCard(
              title: '视频保存路径',
              subtitle: '生成的视频将自动保存到此文件夹',
              icon: Icons.video_library_outlined,
              color: AnimeColors.orangeAccent,
              currentPath: _videoSavePath,
              autoSave: _autoSaveVideos,
              onSelectPath: _selectVideoSavePath,
              onAutoSaveChanged: (value) {
                setState(() => _autoSaveVideos = value);
              },
            ),
            SizedBox(height: 32),

            // 保存按钮
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [AnimeColors.miku, AnimeColors.blue]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Container(
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.save_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('保存设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavePathCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String currentPath,
    required bool autoSave,
    required VoidCallback onSelectPath,
    required ValueChanged<bool> onAutoSaveChanged,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AnimeColors.glassBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                        Text(subtitle, style: TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),

              // 自动保存开关
              Row(
                children: [
                  Text('启用自动保存', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  Spacer(),
                  Switch(
                    value: autoSave,
                    onChanged: onAutoSaveChanged,
                    activeColor: color,
                  ),
                ],
              ),
              SizedBox(height: 12),

              // 路径显示和选择
              InkWell(
                onTap: onSelectPath,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.folder_open, color: color, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          currentPath.isEmpty ? '点击选择文件夹' : currentPath,
                          style: TextStyle(
                            color: currentPath.isEmpty ? Colors.white38 : Colors.white70,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 14),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
