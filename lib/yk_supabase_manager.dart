import 'dart:io';

import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_udid/flutter_udid.dart';
import 'package:flutter/foundation.dart';

@immutable
class YkUser {
  final String id;
  final String? email;
  final String? phone;
  final String? userType;
  final String? nickname;

  const YkUser({required this.id, this.email, this.phone, this.userType, this.nickname});
}

@immutable
class YkFileObject {
  final String name;
  final String? bucketId;
  final String? owner;
  final String? id;
  final String? updatedAt;
  final String? createdAt;
  final String? lastAccessedAt;
  final Map<String, dynamic>? metadata;
  final Bucket? buckets;

  const YkFileObject({
    required this.name,
    required this.bucketId,
    required this.owner,
    required this.id,
    required this.updatedAt,
    required this.createdAt,
    required this.lastAccessedAt,
    required this.metadata,
    required this.buckets,
  });
}

class YkSupabaseManagerDelegate {
  final void Function(bool, String?) onLoading;

  YkSupabaseManagerDelegate({required this.onLoading});
}

class YkSupabaseManager {
  final Map<String, DateTime> _fnLastCallAt = {};
  final Set<String> _fnInFlight = {};
  Duration _fnRateLimitWindow = const Duration(milliseconds: 500);

  YkSupabaseManager._internal() {
    _logger = Logger("YkSupabaseManager");
    if (kDebugMode) {
      Logger.root.level = Level.ALL;
    } else {
      Logger.root.level = Level.SEVERE;
    }

    _logger.onRecord.listen((value) {
      print("[${value.level}][${value.loggerName}][${value.message}]");
    });
  }

  static final YkSupabaseManager _instance = YkSupabaseManager._internal();

  static YkSupabaseManager get instance => _instance;

  SupabaseClient get _client => Supabase.instance.client;

  GoTrueClient get _auth => _client.auth;

  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;

  YkUser? get currentYkUser => _toYkUser(_auth.currentUser);

  Stream<YkUser?> get onUserChange => onAuthStateChange.map((e) => _toYkUser(e.session?.user));

  late Logger _logger;

  YkSupabaseManagerDelegate? _delegate;

  static Future<dynamic> initialize({required String url, required String
  anonKey, YkSupabaseManagerDelegate? delegate}) {
    YkSupabaseManager._instance._delegate = delegate;
    return Supabase.initialize(url: url, anonKey: anonKey).then((value) {
      return value.client.realtime.accessToken ?? "";
    });
  }

  static Future<void> initializeFromEnv() {
    const url = String.fromEnvironment('SUPABASE_URL');
    const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    return Supabase.initialize(url: url, anonKey: anonKey);
  }

  void setFnRateLimitWindow(Duration window) {
    _fnRateLimitWindow = window;
  }

  Future<String> getDeviceId() async {
    if (kIsWeb) {
      return 'web';
    }
    try {
      final id = await FlutterUdid.consistentUdid;
      return id;
    } catch (e) {
      _log('getDeviceId failed: $e');
      return 'unknown';
    }
  }
}

/// MARK: DataBase
extension YkSupabaseDataBaseExtension on YkSupabaseManager {
  Future<List<Map<String, dynamic>>> dbSelect(
    String table, {
    String? orderBy,
    bool ascending = true,
    Map<String, dynamic>? eq,
    Map<String, List<dynamic>>? inFilter,
    int? limit,
  }) async {
    return _withLoading(() async {
      dynamic q = _client.from(table).select();
      q = _applyEq(q, eq);
      q = _applyIn(q, inFilter);
      q = _applyOrder(q, orderBy, ascending);
      q = _applyLimit(q, limit);
      final res = await q;
      return (res as List).cast<Map<String, dynamic>>();
    });
  }

  Future<Map<String, dynamic>> dbInsert(String table, Map<String, dynamic> values) async {
    return _withLoading(() async {
      final res = await _client.from(table).insert(values).select().single();
      return res;
    });
  }

  Future<Map<String, dynamic>> dbUpdate(String table, Map<String, dynamic> values, {Map<String, dynamic>? eq}) async {
    return _withLoading(() async {
      dynamic q = _client.from(table).update(values);
      q = _applyEq(q, eq);
      final res = await q.select().single();
      return (res as Map<String, dynamic>);
    });
  }

  Future<void> dbDelete(String table, {Map<String, dynamic>? eq}) async {
    return _withLoading(() async {
      dynamic q = _client.from(table).delete();
      q = _applyEq(q, eq);
      await q;
    });
  }

  Future<dynamic> dbRpc(String fn, Map<String, dynamic> params) async {
    return _withLoading(() async {
      final res = await _client.rpc(fn, params: params);
      return res;
    });
  }

  Future<dynamic> fnInvoke(String name, {dynamic body, Duration? window}) async {
    return _withLoading(() async {
      final now = DateTime.now();
      final w = window ?? _fnRateLimitWindow;
      final last = _fnLastCallAt[name];
      if (last != null && now.difference(last) < w) {
        _log('fn $name throttled');
        throw Exception('请求过于频繁，请稍后再试');
      }
      if (_fnInFlight.contains(name)) {
        _log('fn $name in-flight');
        throw Exception('请求过于频繁，请稍后再试');
      }
      _fnInFlight.add(name);
      _fnLastCallAt[name] = now;
      try {
        final res = await _client.functions.invoke(name, body: body);
        return res.data;
      } finally {
        _fnInFlight.remove(name);
      }
    });
  }
}

/// MARK: Auth
extension YkSupabaseAuthExtension on YkSupabaseManager {
  Future<void> authSignInWithPassword(String email, String password) {
    return _withLoading(() => _signInWithPassword(email: email, password: password));
  }

  Future<void> authSignInWithPhone(String phone, String password) {
    return _withLoading(() => _signInWithPassword(phone: phone, password: password));
  }

  Future<void> authSignUpWithMetadata(String email, String password, {Map<String, dynamic>? data}) async {
    await _withLoading(() => _signUp(email: email, password: password, data: data, logTag: 'email+metadata'));
  }

  Future<void> authSignUpPhoneWithMetadata(String phone, String password, {Map<String, dynamic>? data}) async {
    await _withLoading(() => _signUp(phone: phone, password: password, data: data, logTag: 'phone+metadata'));
  }

  Future<void> authSignOut() {
    return _withLoading(() => _auth.signOut());
  }

  Future<void> authResetPasswordForEmail(String email, {required String redirectTo}) {
    return _withLoading(() => _auth.resetPasswordForEmail(email, redirectTo: redirectTo));
  }

  Future<void> authUpdatePassword(String password) {
    return _withLoading(() => _updateUser(password: password, logTag: 'password'));
  }

  Future<void> authUpdateUserMetadata(Map<String, dynamic> data) {
    return _withLoading(() => _updateUser(data: data, logTag: 'metadata'));
  }

  Future<Map<String, dynamic>> authRegisterPhoneViaEdge(String phone, String password, {Map<String, dynamic>? metadata}) async {
    return _withLoading(() async {
      if (!_isStrongPassword(password)) {
        return {'code': 400, 'message': '密码不符合安全要求'};
      }
      final Map<String, dynamic> payload = {'phone': phone, 'password': password};
      if (metadata != null) {
        payload.addAll(metadata);
      }
      final data = await fnInvoke('register-phone-user', body: payload);
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'code': 500, 'message': '服务响应异常'};
    }, '正在注册');
  }
}

/// MARK: Storage
extension YkSupabaseStorageExtension on YkSupabaseManager {
  Future<List<YkFileObject>> listFiles(String bucket, {required String prefix}) async {
    final storage = Supabase.instance.client.storage.from(bucket);
    final files = await storage.list(path: prefix);
    return files.map((e) => YkFileObjectInitExtension.makeFrom(fileObject: e)).toList();
  }

  Future<String> uploadToSignedUrl({required String bucket, required String key, required String token, required File file}) async {
    return _withLoading(() {
      final storage = Supabase.instance.client.storage.from(bucket);
      return storage.uploadToSignedUrl(key, token, file);
    });
  }

  Future<void> deleteFile(String bucket, String path) async {
    return _withLoading(() {
      final storage = Supabase.instance.client.storage.from(bucket);
      return storage.remove([path]);
    });
  }
}

/// MARK: Private
extension YkSupabasePrivateExtension on YkSupabaseManager {

  void _notifyLoading(bool isLoading, [String? message]) {
    final cb = _delegate?.onLoading;
    if (cb != null) {
      cb(isLoading, message);
    }
  }

  Future<T> _withLoading<T>(Future<T> Function() action, [String? message]) async {
    _notifyLoading(true, message);
    try {
      final result = await action();
      return result;
    } on PostgrestException catch (e) {
      _error('postgrest: ${e.message}');
      throw Exception(e.message);
    } on AuthException catch (e) {
      _error('auth: ${e.message}');
      throw Exception(e.message);
    } catch (e) {
      _error('unexpected: $e');
      throw Exception('$e');
    } finally {
      _notifyLoading(false, null);
    }
  }

  YkUser? _toYkUser(User? user) {
    if (user == null) return null;
    final meta = user.userMetadata ?? {};
    return YkUser(
      id: user.id,
      email: user.email,
      phone: meta['phone'] as String?,
      userType: meta['user_type'] as String?,
      nickname: meta['nickname'] as String?,
    );
  }

  bool _isStrongPassword(String password) {
    if (password.length < 8) return false;
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(password);
    final hasDigit = RegExp(r'\d').hasMatch(password);
    return hasLetter && hasDigit;
  }

  Future<void> _signUp({String? email, String? phone, required String password, Map<String, dynamic>? data, required String logTag}) async {
    final res = await _auth.signUp(email: email, phone: phone, password: password, data: data);
    if (res.user == null && res.session == null) {
      _log('signUp($logTag) returned no user/session');
    }
  }

  Future<void> _signInWithPassword({String? email, String? phone, required String password}) {
    return _auth.signInWithPassword(email: email, phone: phone, password: password);
  }

  Future<void> _updateUser({String? password, Map<String, dynamic>? data, String? logTag}) async {
    await _auth.updateUser(UserAttributes(password: password, data: data));
  }

  dynamic _applyEq(dynamic q, Map<String, dynamic>? eq) {
    if (eq != null) {
      for (final entry in eq.entries) {
        q = q.eq(entry.key, entry.value);
      }
    }
    return q;
  }

  dynamic _applyOrder(dynamic q, String? orderBy, bool ascending) {
    if (orderBy != null) {
      q = q.order(orderBy, ascending: ascending);
    }
    return q;
  }

  dynamic _applyLimit(dynamic q, int? limit) {
    if (limit != null) {
      q = q.limit(limit);
    }
    return q;
  }

  dynamic _applyIn(dynamic q, Map<String, List<dynamic>>? inFilter) {
    if (inFilter != null) {
      for (final entry in inFilter.entries) {
        q = q.in_(entry.key, entry.value);
      }
    }
    return q;
  }

  _log(String msg) {
    _logger.info(msg);
  }

  _error(String msg) {
    _logger.severe(msg);
  }
}

extension YkFileObjectInitExtension on YkFileObject {
  static YkFileObject makeFrom({required FileObject fileObject}) {
    return YkFileObject(
      id: fileObject.id,
      name: fileObject.name,
      bucketId: fileObject.bucketId,
      owner: fileObject.owner,
      updatedAt: fileObject.updatedAt,
      createdAt: fileObject.createdAt,
      lastAccessedAt: fileObject.lastAccessedAt,
      metadata: fileObject.metadata,
      buckets: fileObject.buckets,
    );
  }
}
