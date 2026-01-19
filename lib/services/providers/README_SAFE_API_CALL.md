# BaseApiProvider 安全 API 调用使用指南

## 📖 概述

`BaseApiProvider` 现在提供了两个强大的受保护方法，用于统一处理所有 API 调用的错误：

1. **`safeApiCall<T>`** - 安全的 API 调用包装器
2. **`checkHttpResponse`** - HTTP 响应检查器

所有子类都可以直接使用这些方法，无需重复编写错误处理代码。

---

## 🎯 核心方法

### 1. `safeApiCall<T>` - 安全的 API 调用包装器

#### 方法签名

```dart
Future<T> safeApiCall<T>({
  required Future<T> Function() apiCall,
  String? context,
})
```

#### 功能

- ✅ 自动捕获所有异常（网络错误、超时、HTTP 错误等）
- ✅ 将异常转换为用户友好的中文提示
- ✅ 记录详细的错误日志（包含堆栈跟踪）
- ✅ 抛出统一的 `AppException`

#### 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `apiCall` | `Future<T> Function()` | 实际的 API 调用函数 |
| `context` | `String?` | 错误上下文（如 "图片生成"），用于日志 |

---

### 2. `checkHttpResponse` - HTTP 响应检查器

#### 方法签名

```dart
void checkHttpResponse(
  dynamic response, {
  String? context,
  int expectedStatusCode = 200,
})
```

#### 功能

- ✅ 检查 HTTP 响应状态码
- ✅ 如果状态码不符合期望，自动抛出 `AppException`
- ✅ 记录错误日志

#### 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `response` | `dynamic` | HTTP 响应对象 |
| `context` | `String?` | 错误上下文 |
| `expectedStatusCode` | `int` | 期望的状态码（默认 200） |

---

## 💡 使用示例

### 示例 1: LLM 聊天补全

**修改前**（需要手动处理错误）：

```dart
@override
Future<String> chatCompletion({
  required String model,
  required List<Map<String, String>> messages,
  double temperature = 0.7,
  int? maxTokens,
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
      throw Exception('HTTP ${response.statusCode}');
    }
    
    final data = jsonDecode(response.body);
    return data['choices'][0]['message']['content'];
    
  } on SocketException catch (e, stackTrace) {
    print('❌ [CRITICAL ERROR CAUGHT] 网络错误: $e');
    print('📍 [Stack Trace]: $stackTrace');
    throw AppException.network(originalError: e, stackTrace: stackTrace);
    
  } on TimeoutException catch (e, stackTrace) {
    print('❌ [CRITICAL ERROR CAUGHT] 超时错误: $e');
    print('📍 [Stack Trace]: $stackTrace');
    throw AppException.timeout(originalError: e, stackTrace: stackTrace);
    
  } on FormatException catch (e, stackTrace) {
    print('❌ [CRITICAL ERROR CAUGHT] 解析错误: $e');
    print('📍 [Stack Trace]: $stackTrace');
    throw AppException.parse(originalError: e, stackTrace: stackTrace);
    
  } catch (e, stackTrace) {
    print('❌ [CRITICAL ERROR CAUGHT] 未知错误: $e');
    print('📍 [Stack Trace]: $stackTrace');
    throw ApiErrorHandler.createException(e, stackTrace);
  }
}
```

**修改后**（使用 `safeApiCall`）：

```dart
@override
Future<String> chatCompletion({
  required String model,
  required List<Map<String, String>> messages,
  double temperature = 0.7,
  int? maxTokens,
}) async {
  return await safeApiCall(
    context: 'LLM 聊天补全',
    apiCall: () async {
      print('🚀 [API Request] URL: $url');
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'messages': messages,
          'temperature': temperature,
          if (maxTokens != null) 'max_tokens': maxTokens,
        }),
      ).timeout(Duration(seconds: 60));
      
      print('✅ [API Response] Code: ${response.statusCode}');
      
      // 使用 checkHttpResponse 检查状态码
      checkHttpResponse(response, context: 'LLM 聊天补全');
      
      // 解析响应
      final data = jsonDecode(response.body);
      return data['choices'][0]['message']['content'] as String;
    },
  );
}
```

**优势**：
- ✅ 代码减少 50%+
- ✅ 错误处理统一、规范
- ✅ 自动记录详细日志
- ✅ 用户友好的错误提示

---

### 示例 2: 图片生成

```dart
@override
Future<String> generateImage({
  required String model,
  required String prompt,
  int width = 1024,
  int height = 1024,
  List<String>? referenceImages,
}) async {
  return await safeApiCall(
    context: '图片生成',
    apiCall: () async {
      print('🎨 [Image Generation] 开始生成图片');
      print('   提示词: $prompt');
      print('   尺寸: ${width}x$height');
      
      final response = await http.post(
        Uri.parse('$baseUrl/images/generations'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'prompt': prompt,
          'size': '${width}x$height',
        }),
      ).timeout(Duration(seconds: 120));  // 图片生成可能需要更长时间
      
      print('✅ [Image Generation] 状态码: ${response.statusCode}');
      
      // 检查响应
      checkHttpResponse(response, context: '图片生成');
      
      // 解析响应
      final data = jsonDecode(response.body);
      final imageUrl = data['data'][0]['url'] as String?;
      
      if (imageUrl == null || imageUrl.isEmpty) {
        throw AppException.parse(message: '服务器返回的图片 URL 为空');
      }
      
      print('✅ [Image Generation] 生成成功: $imageUrl');
      return imageUrl;
    },
  );
}
```

---

### 示例 3: 视频任务创建

```dart
@override
Future<String> createVideo({
  required String model,
  required String prompt,
  String size = '720x1280',
  int? seconds,
  File? inputReference,
}) async {
  return await safeApiCall(
    context: '视频任务创建',
    apiCall: () async {
      print('🎬 [Video Creation] 创建视频任务');
      print('   提示词: $prompt');
      print('   尺寸: $size');
      
      // 构建请求体
      final Map<String, dynamic> body = {
        'model': model,
        'prompt': prompt,
        'size': size,
        if (seconds != null) 'seconds': seconds,
      };
      
      // 如果有参考文件，先上传
      if (inputReference != null) {
        final uploadedUrl = await uploadVideoToOss(inputReference);
        body['input_reference'] = uploadedUrl;
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/videos/generations'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      ).timeout(Duration(seconds: 30));
      
      print('✅ [Video Creation] 状态码: ${response.statusCode}');
      
      // 检查响应
      checkHttpResponse(response, context: '视频任务创建');
      
      // 解析响应
      final data = jsonDecode(response.body);
      final taskId = data['id'] as String;
      
      print('✅ [Video Creation] 任务已创建: $taskId');
      return taskId;
    },
  );
}
```

---

### 示例 4: 视频任务查询

```dart
@override
Future<VideoTaskStatus> getVideoTask({
  required String taskId,
}) async {
  return await safeApiCall(
    context: '视频任务查询',
    apiCall: () async {
      print('🔍 [Video Task] 查询任务状态: $taskId');
      
      final response = await http.get(
        Uri.parse('$baseUrl/videos/$taskId'),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      ).timeout(Duration(seconds: 10));
      
      // 检查响应
      checkHttpResponse(response, context: '视频任务查询');
      
      // 解析响应
      final data = jsonDecode(response.body);
      final taskStatus = VideoTaskStatus.fromJson(data);
      
      print('✅ [Video Task] 任务状态: ${taskStatus.status} (${taskStatus.progress}%)');
      return taskStatus;
    },
  );
}
```

---

## 🎨 完整示例：优化后的 GeeknowProvider

```dart
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'base_provider.dart';
import '../../utils/index.dart';

class GeeknowProvider extends BaseApiProvider {
  @override
  final String baseUrl;
  
  @override
  final String apiKey;
  
  @override
  String get providerName => 'geeknow';

  GeeknowProvider({
    required this.baseUrl,
    required this.apiKey,
  });

  @override
  Future<String> chatCompletion({
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    return await safeApiCall(
      context: 'LLM 聊天补全',
      apiCall: () async {
        final response = await http.post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'messages': messages,
            'temperature': temperature,
            if (maxTokens != null) 'max_tokens': maxTokens,
          }),
        ).timeout(Duration(seconds: 60));
        
        checkHttpResponse(response, context: 'LLM 聊天补全');
        
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'] as String;
      },
    );
  }

  @override
  Future<String> generateImage({
    required String model,
    required String prompt,
    int width = 1024,
    int height = 1024,
    List<String>? referenceImages,
  }) async {
    return await safeApiCall(
      context: '图片生成',
      apiCall: () async {
        final response = await http.post(
          Uri.parse('$baseUrl/images/generations'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'prompt': prompt,
            'size': '${width}x$height',
          }),
        ).timeout(Duration(seconds: 120));
        
        checkHttpResponse(response, context: '图片生成');
        
        final data = jsonDecode(response.body);
        return data['data'][0]['url'] as String;
      },
    );
  }

  // 其他方法也使用相同的模式...
}
```

---

## 📊 效果对比

### 代码量对比

| 指标 | 修改前 | 修改后 | 减少 |
|------|--------|--------|------|
| **代码行数** | ~50 行/方法 | ~20 行/方法 | **60%** |
| **try-catch 块** | 每个方法都需要 | 不需要 | **100%** |
| **错误处理代码** | 重复 | 统一 | **100%** |
| **日志代码** | 重复 | 自动 | **100%** |

### 维护性对比

| 方面 | 修改前 | 修改后 |
|------|--------|--------|
| **错误处理逻辑** | 分散在各个方法 | 集中在基类 |
| **修改错误提示** | 需要修改所有方法 | 只需修改一处 |
| **添加新错误类型** | 需要修改所有方法 | 自动支持 |
| **代码一致性** | 容易不一致 | 完全一致 |

---

## ✅ 最佳实践

### 1. 始终使用 `safeApiCall`

```dart
// ✅ 推荐
Future<String> myApiMethod() async {
  return await safeApiCall(
    context: '我的 API 操作',
    apiCall: () async {
      // API 调用逻辑
    },
  );
}

// ❌ 不推荐（除非有特殊需求）
Future<String> myApiMethod() async {
  try {
    // 手动错误处理
  } catch (e) {
    // ...
  }
}
```

### 2. 提供清晰的上下文

```dart
// ✅ 推荐
await safeApiCall(
  context: '图片生成',  // 清晰的上下文
  apiCall: () async { ... },
);

// ⚠️ 可以但不够清晰
await safeApiCall(
  context: 'API 调用',  // 太泛化
  apiCall: () async { ... },
);

// ❌ 不推荐
await safeApiCall(
  apiCall: () async { ... },  // 缺少上下文
);
```

### 3. 使用 `checkHttpResponse` 检查响应

```dart
// ✅ 推荐
final response = await http.post(...);
checkHttpResponse(response, context: '图片生成');

// ✅ 也可以手动检查
if (response.statusCode != 200) {
  throw AppException.server(statusCode: response.statusCode);
}
```

### 4. 在 `apiCall` 中添加详细日志

```dart
await safeApiCall(
  context: '图片生成',
  apiCall: () async {
    // ✅ 记录请求信息
    print('🚀 [API Request] URL: $url');
    print('📦 [API Payload]: $body');
    
    final response = await http.post(...);
    
    // ✅ 记录响应信息
    print('✅ [API Response] Code: ${response.statusCode}');
    print('📄 [API Body]: ${response.body}');
    
    return result;
  },
);
```

---

## 🚀 升级指南

### 步骤 1: 识别需要升级的方法

查找所有包含大量 try-catch 块的 API 方法。

### 步骤 2: 提取核心逻辑

将 try-catch 块内的核心逻辑提取出来。

### 步骤 3: 包装到 `safeApiCall`

```dart
// 原代码
try {
  // 核心逻辑
} catch (e) {
  // 错误处理
}

// 新代码
return await safeApiCall(
  context: '操作名称',
  apiCall: () async {
    // 核心逻辑
  },
);
```

### 步骤 4: 测试

确保所有错误场景都能正确处理。

---

## 🎉 总结

使用 `BaseApiProvider` 的安全 API 调用方法后：

- ✅ **代码更简洁**：减少 60% 的代码量
- ✅ **错误处理统一**：所有错误都通过同一逻辑处理
- ✅ **维护更容易**：修改一处，全局生效
- ✅ **日志更完整**：自动记录所有错误
- ✅ **用户体验更好**：统一的中文错误提示

**这是一个强大的工具，请在所有 API Provider 实现中使用！** 🛡️
