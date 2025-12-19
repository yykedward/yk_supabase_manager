# yk_supabase_manager

`yk_supabase_manager` 是一个基于 `supabase_flutter` 的封装库，旨在简化 Flutter 应用中与 Supabase 的集成。它提供了一套统一、易用的 API 来管理认证（Auth）、数据库（Database）、存储（Storage）和云函数（Functions），并内置了全局 Loading 状态管理和错误处理机制。

## ✨ 特性 (Features)

*   **单例管理**: 通过 `YkSupabaseManager.instance` 统一管理 Supabase 实例。
*   **简化的认证流程 (Auth)**:
    *   支持邮箱/密码登录与注册。
    *   支持手机号/密码登录与注册。
    *   支持带元数据（Metadata）的注册。
    *   提供统一的 `YkUser` 模型，方便获取用户信息。
    *   支持通过 Edge Function 注册手机用户。
*   **数据库操作 (Database)**:
    *   封装了常用的 CRUD 操作：`dbSelect`, `dbInsert`, `dbUpdate`, `dbDelete`。
    *   支持简单的过滤 (`eq`, `inFilter`)、排序 (`orderBy`) 和分页 (`limit`)。
    *   支持调用数据库 RPC 函数。
*   **云函数调用 (Functions)**:
    *   提供 `fnInvoke` 方法调用 Edge Functions。
    *   内置防抖/限流机制 (`_fnRateLimitWindow`)，防止频繁调用。
*   **存储管理 (Storage)**:
    *   支持列出 Bucket 中的文件。
    *   支持通过 Signed URL 上传文件。
    *   支持删除文件。
*   **实用工具 (Utilities)**:
    *   **设备 ID**: 集成 `flutter_udid` 获取一致的设备 ID。
    *   **Loading 代理**: 通过 `YkSupabaseManagerDelegate` 统一处理异步操作的 Loading 状态。
    *   **日志系统**: 集成 `logging` 包，区分 Debug/Release 模式的日志级别。

## 📦 安装 (Installation)

在你的 `pubspec.yaml` 文件中添加 `yk_supabase_manager`：

```yaml
dependencies:
  yk_supabase_manager:
    git:
      url: https://github.com/yykedward/yk_supabase_manager.git
```

## 🚀 快速开始 (Getting Started)

### 1. 初始化

在应用启动时（如 `main.dart`）进行初始化：

```dart
import 'package:yk_supabase_manager/yk_supabase_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 方式 1: 直接传入 URL 和 Key
  await YkSupabaseManager.initialize(
    url: 'YOUR_SUPABASE_URL',
    anonKey: 'YOUR_SUPABASE_ANON_KEY',
    delegate: YkSupabaseManagerDelegate(
      onLoading: (isLoading, message) {
        // 在这里处理全局 Loading 显示/隐藏
        print('Loading: $isLoading, Message: $message');
      },
    ),
  );

  // 方式 2: 从环境变量读取 (SUPABASE_URL, SUPABASE_ANON_KEY)
  // await YkSupabaseManager.initializeFromEnv();

  runApp(const MyApp());
}
```

### 2. 认证 (Auth)

```dart
final manager = YkSupabaseManager.instance;

// 邮箱登录
await manager.authSignInWithPassword('email@example.com', 'password123');

// 监听用户状态变化
manager.onUserChange.listen((YkUser? user) {
  if (user != null) {
    print('用户已登录: ${user.id}');
  } else {
    print('用户未登录');
  }
});

// 登出
await manager.authSignOut();
```

### 3. 数据库操作 (Database)

```dart
final manager = YkSupabaseManager.instance;

// 查询数据
final users = await manager.dbSelect(
  'users',
  eq: {'status': 'active'},
  orderBy: 'created_at',
  limit: 10,
);

// 插入数据
await manager.dbInsert('todos', {
  'title': 'Buy milk',
  'is_complete': false,
});
```

### 4. 云函数 (Functions)

```dart
final manager = YkSupabaseManager.instance;

try {
  final result = await manager.fnInvoke(
    'my-function',
    body: {'foo': 'bar'},
  );
  print(result);
} catch (e) {
  print('Error: $e');
}
```

### 5. 存储 (Storage)

```dart
final manager = YkSupabaseManager.instance;

// 列出文件
final files = await manager.listFiles('avatars', prefix: 'user_123/');

// 删除文件
await manager.deleteFile('avatars', 'user_123/profile.jpg');
```

## ⚠️ 注意事项

*   **错误处理**: 所有异步操作如果失败，都会抛出异常，并自动记录日志。建议在 UI 层进行 `try-catch` 处理。
*   **Loading 状态**: 初始化时传入的 `YkSupabaseManagerDelegate` 会自动拦截大部分异步操作的开始和结束，无需手动管理 Loading 状态。

## 📝 License

MIT
