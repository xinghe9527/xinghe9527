# 字体配置指南

## ✅ 已完成的配置

您的应用现在使用 **Google Fonts - 思源黑体 (Noto Sans SC)**，这是一款优雅的中文字体，非常适合现代化的 UI。

### 已修改的文件：
1. `pubspec.yaml` - 添加了 `google_fonts: ^6.2.1` 依赖
2. `lib/main.dart` - 添加了全局字体配置

### 当前字体效果：
- ✨ 优雅的中文显示
- 📱 清晰的界面文字
- 🎨 现代化的视觉风格

---

## 🎨 其他推荐字体选项

如果您想尝试其他字体，只需修改 `lib/main.dart` 中的字体设置：

### 1. **更多圆润风格**
```dart
// 使用 Noto Sans SC（圆润）
fontFamily: GoogleFonts.notoSansSc().fontFamily,
textTheme: GoogleFonts.notoSansScTextTheme(ThemeData.dark().textTheme),
```

### 2. **更锐利专业风格**
```dart
// 使用 Roboto（现代、锐利）
fontFamily: GoogleFonts.roboto().fontFamily,
textTheme: GoogleFonts.robotoTextTheme(ThemeData.dark().textTheme),
```

### 3. **优雅文艺风格**
```dart
// 使用 Lato（优雅）
fontFamily: GoogleFonts.lato().fontFamily,
textTheme: GoogleFonts.latoTextTheme(ThemeData.dark().textTheme),
```

### 4. **中文优化 - 更多选择**
```dart
// 方案 A: ZCOOL XiaoWei（站酷小薇）- 可爱风格
fontFamily: GoogleFonts.zcoolXiaoWei().fontFamily,
textTheme: GoogleFonts.zcoolXiaoWeiTextTheme(ThemeData.dark().textTheme),

// 方案 B: Ma Shan Zheng（马善政楷书）- 书法风格
fontFamily: GoogleFonts.maShanZheng().fontFamily,
textTheme: GoogleFonts.maShanZhengTextTheme(ThemeData.dark().textTheme),

// 方案 C: ZCOOL QingKe HuangYou（站酷庆科黄油体）- 可爱圆润
fontFamily: GoogleFonts.zcoolQingKeHuangYou().fontFamily,
textTheme: GoogleFonts.zcoolQingKeHuangYouTextTheme(ThemeData.dark().textTheme),
```

### 5. **科技动漫风格**
```dart
// 使用 Orbitron（未来科技感）
fontFamily: GoogleFonts.orbitron().fontFamily,
textTheme: GoogleFonts.orbitronTextTheme(ThemeData.dark().textTheme),
```

---

## 🔧 如何切换字体

### 方法 1：全局切换（推荐）
在 `lib/main.dart` 的 `ThemeData` 中修改：

```dart
theme: ThemeData(
  // ... 其他配置 ...
  fontFamily: GoogleFonts.你想要的字体().fontFamily,
  textTheme: GoogleFonts.你想要的字体TextTheme(ThemeData.dark().textTheme),
),
```

### 方法 2：局部使用不同字体
在特定的 Text widget 中使用：

```dart
Text(
  '特殊文字',
  style: GoogleFonts.orbitron(  // 使用科技风格字体
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  ),
)
```

---

## 📚 探索更多字体

访问 Google Fonts 网站查看所有可用字体：
- 🌐 https://fonts.google.com/
- 筛选支持中文的字体：选择 "Language" > "Chinese Simplified"

找到喜欢的字体后，使用以下格式：
```dart
GoogleFonts.字体名称().fontFamily
```

字体名称转换规则（驼峰命名）：
- "Noto Sans SC" → `notoSansSc`
- "Roboto" → `roboto`
- "ZCOOL XiaoWei" → `zcoolXiaoWei`

---

## 🎯 快速测试字体效果

热重载后即可看到字体变化，无需重启应用！

1. 修改 `lib/main.dart` 中的字体设置
2. 保存文件
3. 按 `r` 键热重载
4. 查看效果

---

## ⚡ 性能说明

Google Fonts 会在首次使用时下载字体文件，之后会缓存。首次加载可能稍慢，但后续使用会很快。

如果需要**完全离线**使用，请参考方案 2（下面）。

---

## 📦 方案 2：使用本地字体文件（可选）

如果您想使用自定义字体文件（如 OTF/TTF）：

### 步骤：
1. 将字体文件放入 `fonts/` 目录
2. 在 `pubspec.yaml` 中配置：
```yaml
flutter:
  fonts:
    - family: CustomFont
      fonts:
        - asset: fonts/CustomFont-Regular.ttf
        - asset: fonts/CustomFont-Bold.ttf
          weight: 700
```
3. 在代码中使用：
```dart
fontFamily: 'CustomFont'
```

---

## 🎨 当前推荐

对于您的**动漫制作应用**，推荐使用：
1. **Noto Sans SC**（当前）- 平衡、专业、清晰 ⭐
2. **Orbitron** - 科技感强，适合动漫/未来主题
3. **ZCOOL QingKe HuangYou** - 可爱圆润，适合轻松氛围

---

## 💡 提示

- 所有字体更改都会立即应用到整个应用
- 可以混合使用多种字体（标题用一种，正文用另一种）
- Google Fonts 完全免费且开源

享受您的新字体！✨
