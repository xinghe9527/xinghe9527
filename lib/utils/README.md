# Utils 工具类库

本目录包含应用中的通用工具类和辅助函数。

## 📁 文件说明

### `app_exception.dart`
**自定义异常类**

统一管理应用中的所有异常，提供友好的错误提示。

#### 核心功能
- ✅ 中文错误消息（给用户看的）
- ✅ HTTP 状态码（如果适用）
- ✅ 原始错误对象（用于调试）
- ✅ 堆栈跟踪（用于调试）
- ✅ 格式化的 `toString()` 输出

#### 使用示例

```dart
// 创建自定义异常
throw AppException(
  message: '网络连接失败',
  statusCode: 500,
  originalError: error,
  stackTrace: stackTrace,
);

// 使用工厂构造函数
throw AppException.network();
throw AppException.timeout();
throw AppException.server(statusCode: 401);
throw AppException.parse();
```

---

### `api_error_handler.dart`
**API 错误处理工具类**

将各种异常转换为用户友好的中文提示。

#### 核心功能
- ✅ 统一错误处理逻辑
- ✅ 中文错误提示
- ✅ 支持多种错误类型
- ✅ HTTP 状态码映射
- ✅ 友好的错误日志

#### 使用示例

##### 1. 基本使用

```dart
try {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) {
    throw response;
  }
} catch (e, stackTrace) {
  // 获取用户友好的错误消息
  final errorMessage = ApiErrorHandler.handle(e, stackTrace);
  
  // 显示给用户
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(errorMessage)),
  );
}
```

##### 2. 创建统一异常

```dart
try {
  await someApiCall();
} catch (e, stackTrace) {
  // 转换为 AppException
  final appException = ApiErrorHandler.createException(e, stackTrace);
  throw appException;
}
```

##### 3. 友好的错误日志

```dart
try {
  await apiService.generateImage(prompt);
} catch (e, stackTrace) {
  // 打印友好的错误日志
  ApiErrorHandler.logError(
    e,
    stackTrace: stackTrace,
    context: '图片生成',
  );
}
```

#### 支持的错误类型

##### HTTP 状态码
- `400` → 请求参数错误，请检查输入内容
- `401` → API Key 无效或已过期，请在设置中更新
- `403` → 访问被拒绝，您的账号没有此权限
- `404` → 请求的 API 接口不存在，请检查配置
- `429` → 请求过于频繁，请稍等片刻再试
- `500` → 服务器内部错误，请稍后重试
- `502` → 网关错误，服务暂时不可用
- `503` → 服务维护中，请稍后重试

##### 网络异常
- `SocketException` → 网络连接失败，请检查您的网络设置
- `TimeoutException` → 请求超时，服务器响应时间过长，请稍后重试
- `http.ClientException` → 网络请求失败

##### 数据异常
- `FormatException` → 数据格式错误，无法解析服务器响应
- `TypeError` → 数据类型错误，请联系技术支持

---

## 🎯 最佳实践

### 1. 在 API 调用中使用

```dart
class ApiService {
  Future<String> chatCompletion({
    required String model,
    required List<Map<String, dynamic>> messages,
  }) async {
    try {
      print('🚀 [API Request] URL: $url');
      
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(Duration(seconds: 60));
      
      print('✅ [API Response] Code: ${response.statusCode}');
      
      if (response.statusCode != 200) {
        // 使用 ApiErrorHandler 处理错误
        throw ApiErrorHandler.createException(response);
      }
      
      final data = jsonDecode(response.body);
      return data['content'];
      
    } on SocketException catch (e, stackTrace) {
      ApiErrorHandler.logError(e, stackTrace: stackTrace, context: 'API 请求');
      throw AppException.network(originalError: e, stackTrace: stackTrace);
      
    } on TimeoutException catch (e, stackTrace) {
      ApiErrorHandler.logError(e, stackTrace: stackTrace, context: 'API 请求');
      throw AppException.timeout(originalError: e, stackTrace: stackTrace);
      
    } on FormatException catch (e, stackTrace) {
      ApiErrorHandler.logError(e, stackTrace: stackTrace, context: 'JSON 解析');
      throw AppException.parse(originalError: e, stackTrace: stackTrace);
      
    } catch (e, stackTrace) {
      ApiErrorHandler.logError(e, stackTrace: stackTrace, context: 'API 请求');
      throw ApiErrorHandler.createException(e, stackTrace);
    }
  }
}
```

### 2. 在 UI 中显示错误

```dart
class MyWidget extends StatelessWidget {
  Future<void> _generateContent() async {
    try {
      final result = await apiService.chatCompletion(...);
      // 成功处理
      
    } catch (e, stackTrace) {
      // 获取用户友好的错误消息
      final errorMessage = ApiErrorHandler.handle(e, stackTrace);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }
}
```

### 3. 在 Provider 中使用

```dart
class AutoModeProvider extends ChangeNotifier {
  Future<void> _generateScript(String projectId, String input) async {
    try {
      final apiService = apiConfigManager.createApiService();
      final result = await apiService.chatCompletion(...);
      
      // 保存结果
      project.currentScript = result;
      notifyListeners();
      
    } catch (e, stackTrace) {
      // 记录错误日志
      ApiErrorHandler.logError(
        e,
        stackTrace: stackTrace,
        context: '剧本生成',
      );
      
      // 设置错误消息（将显示给用户）
      project.errorMessage = ApiErrorHandler.handle(e, stackTrace);
      notifyListeners();
    }
  }
}
```

---

## 🚀 优势

### 1. **统一的错误处理**
所有错误都通过统一的工具类处理，代码更简洁、更易维护。

### 2. **用户友好的提示**
所有错误消息都是中文的、人类可读的，用户能够理解发生了什么。

### 3. **完整的调试信息**
保留原始错误和堆栈跟踪，方便开发者调试问题。

### 4. **易于扩展**
新增错误类型或修改错误提示非常简单，只需修改工具类即可。

---

## 📝 注意事项

1. **不要吞掉异常**：始终使用 `try-catch` 捕获并处理异常
2. **提供上下文**：使用 `logError` 时提供错误上下文，便于定位问题
3. **保留堆栈跟踪**：传递 `stackTrace` 参数，便于调试
4. **用户体验优先**：错误消息要清晰、友好、可操作

---

## 🔮 未来扩展

- [ ] 支持多语言错误提示
- [ ] 错误上报到远程服务（如 Sentry）
- [ ] 错误统计和分析
- [ ] 自动重试机制
- [ ] 错误恢复建议

---

**这两个工具类是应用错误处理的核心基础设施，请在所有 API 调用和关键操作中使用！** 🛡️
