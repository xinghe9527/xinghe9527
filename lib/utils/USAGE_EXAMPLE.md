# 错误处理工具类使用示例

本文档展示如何在项目中使用 `AppException` 和 `ApiErrorHandler`。

---

## 📚 目录
1. [快速开始](#快速开始)
2. [基础用法](#基础用法)
3. [进阶用法](#进阶用法)
4. [实战案例](#实战案例)

---

## 快速开始

### 导入

```dart
// 方式 1: 单独导入
import 'package:xinghe/utils/app_exception.dart';
import 'package:xinghe/utils/api_error_handler.dart';

// 方式 2: 批量导入（推荐）
import 'package:xinghe/utils/index.dart';
```

---

## 基础用法

### 1. 捕获并处理错误

```dart
Future<void> myFunction() async {
  try {
    // 执行可能出错的操作
    await apiService.chatCompletion(...);
    
  } catch (e, stackTrace) {
    // 获取用户友好的错误消息
    final errorMessage = ApiErrorHandler.handle(e, stackTrace);
    print('错误: $errorMessage');
    
    // 或者打印详细日志
    ApiErrorHandler.logError(
      e,
      stackTrace: stackTrace,
      context: '我的功能',
    );
  }
}
```

### 2. 抛出自定义异常

```dart
Future<void> validateInput(String input) async {
  if (input.isEmpty) {
    throw AppException(
      message: '输入不能为空',
      statusCode: 400,
    );
  }
  
  if (input.length < 10) {
    throw AppException(
      message: '输入内容太短，至少需要 10 个字符',
    );
  }
}
```

### 3. 使用工厂构造函数

```dart
// 网络错误
throw AppException.network();
throw AppException.network(message: '无法连接到服务器');

// 超时错误
throw AppException.timeout();

// 服务器错误
throw AppException.server(statusCode: 401);
throw AppException.server(
  statusCode: 500,
  message: '服务器崩溃了',
);

// 解析错误
throw AppException.parse();

// 未知错误
throw AppException.unknown(message: '发生了奇怪的事情');
```

---

## 进阶用法

### 1. 在 API 服务中使用

```dart
class MyApiService {
  Future<String> fetchData(String url) async {
    try {
      print('🚀 [API Request] $url');
      
      // 发送请求
      final response = await http.get(Uri.parse(url))
        .timeout(Duration(seconds: 30));
      
      print('✅ [API Response] ${response.statusCode}');
      
      // 检查状态码
      if (response.statusCode != 200) {
        throw ApiErrorHandler.createException(response);
      }
      
      // 解析响应
      try {
        final data = jsonDecode(response.body);
        return data['result'];
      } on FormatException catch (e, stackTrace) {
        throw AppException.parse(
          message: '服务器返回了无效的数据格式',
          originalError: e,
          stackTrace: stackTrace,
        );
      }
      
    } on SocketException catch (e, stackTrace) {
      // 网络连接错误
      ApiErrorHandler.logError(e, stackTrace: stackTrace, context: 'API 请求');
      throw AppException.network(
        originalError: e,
        stackTrace: stackTrace,
      );
      
    } on TimeoutException catch (e, stackTrace) {
      // 超时错误
      ApiErrorHandler.logError(e, stackTrace: stackTrace, context: 'API 请求');
      throw AppException.timeout(
        message: '服务器响应超时（30秒），请检查网络连接',
        originalError: e,
        stackTrace: stackTrace,
      );
      
    } catch (e, stackTrace) {
      // 其他错误
      ApiErrorHandler.logError(e, stackTrace: stackTrace, context: 'API 请求');
      rethrow;
    }
  }
}
```

### 2. 在 Provider 中使用

```dart
class MyProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;
  
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  
  Future<void> performAction() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      // 执行操作
      await apiService.doSomething();
      
      _isLoading = false;
      notifyListeners();
      
    } catch (e, stackTrace) {
      // 记录错误日志
      ApiErrorHandler.logError(
        e,
        stackTrace: stackTrace,
        context: '执行操作',
      );
      
      // 设置用户可见的错误消息
      _errorMessage = ApiErrorHandler.handle(e, stackTrace);
      _isLoading = false;
      notifyListeners();
    }
  }
  
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
```

### 3. 在 UI 中显示错误

```dart
class MyWidget extends StatelessWidget {
  Future<void> _handleButtonPress(BuildContext context) async {
    try {
      // 显示加载指示器
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(child: CircularProgressIndicator()),
      );
      
      // 执行操作
      await myService.doSomething();
      
      // 关闭加载指示器
      Navigator.pop(context);
      
      // 显示成功提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('操作成功！'),
          backgroundColor: Colors.green,
        ),
      );
      
    } catch (e, stackTrace) {
      // 关闭加载指示器
      Navigator.pop(context);
      
      // 获取用户友好的错误消息
      final errorMessage = ApiErrorHandler.handle(e, stackTrace);
      
      // 显示错误提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
          action: SnackBarAction(
            label: '重试',
            textColor: Colors.white,
            onPressed: () => _handleButtonPress(context),
          ),
        ),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => _handleButtonPress(context),
      child: Text('执行操作'),
    );
  }
}
```

---

## 实战案例

### 案例 1: 图片生成 API

```dart
Future<String> generateImage(String prompt) async {
  // 参数验证
  if (prompt.isEmpty) {
    throw AppException(
      message: '提示词不能为空',
      statusCode: 400,
    );
  }
  
  if (prompt.length > 1000) {
    throw AppException(
      message: '提示词太长，最多 1000 个字符',
      statusCode: 400,
    );
  }
  
  try {
    print('🎨 [Image Generation] 开始生成图片...');
    print('   提示词: $prompt');
    
    final response = await http.post(
      Uri.parse('$baseUrl/images/generations'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'prompt': prompt}),
    ).timeout(Duration(seconds: 120));  // 图片生成可能需要更长时间
    
    print('✅ [Image Generation] 状态码: ${response.statusCode}');
    
    // 处理不同的状态码
    if (response.statusCode == 401) {
      throw AppException.server(
        statusCode: 401,
        message: 'API Key 无效或已过期，请在设置中更新',
      );
    }
    
    if (response.statusCode == 429) {
      throw AppException.server(
        statusCode: 429,
        message: '图片生成请求过于频繁，请等待 1 分钟后再试',
      );
    }
    
    if (response.statusCode != 200) {
      throw ApiErrorHandler.createException(response);
    }
    
    // 解析响应
    final data = jsonDecode(response.body);
    final imageUrl = data['data'][0]['url'] as String?;
    
    if (imageUrl == null || imageUrl.isEmpty) {
      throw AppException.parse(
        message: '服务器返回的图片 URL 为空',
      );
    }
    
    print('✅ [Image Generation] 生成成功');
    return imageUrl;
    
  } on SocketException catch (e, stackTrace) {
    ApiErrorHandler.logError(e, stackTrace: stackTrace, context: '图片生成');
    throw AppException.network(
      message: '网络连接失败，无法生成图片',
      originalError: e,
      stackTrace: stackTrace,
    );
    
  } on TimeoutException catch (e, stackTrace) {
    ApiErrorHandler.logError(e, stackTrace: stackTrace, context: '图片生成');
    throw AppException.timeout(
      message: '图片生成超时（2分钟），请稍后重试',
      originalError: e,
      stackTrace: stackTrace,
    );
    
  } on FormatException catch (e, stackTrace) {
    ApiErrorHandler.logError(e, stackTrace: stackTrace, context: '图片生成');
    throw AppException.parse(
      message: '无法解析服务器返回的图片数据',
      originalError: e,
      stackTrace: stackTrace,
    );
    
  } catch (e, stackTrace) {
    ApiErrorHandler.logError(e, stackTrace: stackTrace, context: '图片生成');
    rethrow;
  }
}
```

### 案例 2: 文件上传

```dart
Future<String> uploadFile(File file) async {
  // 文件验证
  if (!await file.exists()) {
    throw AppException(
      message: '文件不存在',
      statusCode: 400,
    );
  }
  
  final fileSize = await file.length();
  if (fileSize > 100 * 1024 * 1024) {  // 100MB
    throw AppException(
      message: '文件太大，最大支持 100MB',
      statusCode: 413,
    );
  }
  
  try {
    print('📤 [File Upload] 开始上传文件...');
    print('   文件大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');
    
    // 创建 multipart 请求
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/upload'),
    );
    
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    
    // 发送请求
    final streamedResponse = await request.send()
      .timeout(Duration(minutes: 5));
    
    final response = await http.Response.fromStream(streamedResponse);
    
    print('✅ [File Upload] 状态码: ${response.statusCode}');
    
    if (response.statusCode != 200) {
      throw ApiErrorHandler.createException(response);
    }
    
    final data = jsonDecode(response.body);
    final fileUrl = data['url'] as String;
    
    print('✅ [File Upload] 上传成功: $fileUrl');
    return fileUrl;
    
  } on SocketException catch (e, stackTrace) {
    ApiErrorHandler.logError(e, stackTrace: stackTrace, context: '文件上传');
    throw AppException.network(
      message: '网络连接失败，无法上传文件',
      originalError: e,
      stackTrace: stackTrace,
    );
    
  } on TimeoutException catch (e, stackTrace) {
    ApiErrorHandler.logError(e, stackTrace: stackTrace, context: '文件上传');
    throw AppException.timeout(
      message: '文件上传超时，请检查网络连接或减小文件大小',
      originalError: e,
      stackTrace: stackTrace,
    );
    
  } catch (e, stackTrace) {
    ApiErrorHandler.logError(e, stackTrace: stackTrace, context: '文件上传');
    rethrow;
  }
}
```

### 案例 3: 批量操作错误处理

```dart
Future<List<String>> generateMultipleImages(List<String> prompts) async {
  if (prompts.isEmpty) {
    throw AppException(
      message: '提示词列表不能为空',
      statusCode: 400,
    );
  }
  
  final results = <String>[];
  final errors = <String, String>{};  // prompt -> errorMessage
  
  for (int i = 0; i < prompts.length; i++) {
    final prompt = prompts[i];
    
    try {
      print('🎨 [$i/${prompts.length}] 生成图片: $prompt');
      
      final imageUrl = await generateImage(prompt);
      results.add(imageUrl);
      
      print('✅ [$i/${prompts.length}] 生成成功');
      
    } catch (e, stackTrace) {
      // 记录错误但继续处理其他提示词
      final errorMessage = ApiErrorHandler.handle(e, stackTrace);
      errors[prompt] = errorMessage;
      
      print('❌ [$i/${prompts.length}] 生成失败: $errorMessage');
      
      // 添加空占位符
      results.add('');
    }
  }
  
  // 如果全部失败，抛出异常
  if (results.every((url) => url.isEmpty)) {
    throw AppException(
      message: '所有图片生成均失败，请检查网络连接和 API 配置',
    );
  }
  
  // 如果部分失败，记录警告
  if (errors.isNotEmpty) {
    print('⚠️ 部分图片生成失败:');
    errors.forEach((prompt, error) {
      print('   - $prompt: $error');
    });
  }
  
  return results;
}
```

---

## 🎯 最佳实践总结

### ✅ 推荐做法

1. **始终捕获异常**：不要让异常传播到 UI 层
2. **使用 ApiErrorHandler**：统一处理所有错误
3. **提供上下文**：使用 `logError` 时提供错误上下文
4. **保留堆栈跟踪**：传递 `stackTrace` 参数
5. **用户友好的提示**：错误消息要清晰、可操作
6. **区分错误类型**：使用不同的工厂构造函数

### ❌ 避免的做法

1. **空的 catch 块**：`catch (e) {}` 会吞掉所有错误
2. **泛化的错误消息**：`"出错了"` 对用户没有帮助
3. **忽略堆栈跟踪**：失去调试信息
4. **直接显示原始错误**：用户看不懂技术错误
5. **重复的错误处理**：在多处重复相同的逻辑

---

## 📝 检查清单

使用错误处理工具类时，请确保：

- [ ] 所有 API 调用都包含 try-catch
- [ ] 使用 ApiErrorHandler 处理错误
- [ ] 提供用户友好的错误消息
- [ ] 保留堆栈跟踪用于调试
- [ ] 记录详细的错误日志
- [ ] 为用户提供重试或其他操作选项
- [ ] 测试各种错误场景

---

**遵循这些最佳实践，您的应用将拥有健壮、用户友好的错误处理机制！** 🛡️
