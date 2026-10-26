import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/app_user.dart';
import '../models/task.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiService {
  ApiService._();

  static final instance = ApiService._();

  static const _accessTokenKey = 'api_access_token';
  static const _refreshTokenKey = 'api_refresh_token';
  static const _accessTokenExpiryKey = 'api_access_token_expiry';
  static const _userKey = 'api_user';

  final http.Client _client = http.Client();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  Future<String?>? _refreshing;
  Future<void> Function(Map<String, dynamic>)? onSessionUserRefreshed;
  Future<void> Function()? onSessionExpired;

  Uri _uri(String path) {
    final base = Uri.parse(apiBaseUrl);
    if (base.host == 'api.example.com') {
      throw const ApiException(
        'APIの接続先が未設定です。lib/config/api_config.dartを編集してください。',
      );
    }
    if (base.scheme != 'https' &&
        !(base.scheme == 'http' &&
            (base.host == 'localhost' || base.host == '127.0.0.1'))) {
      throw const ApiException('API接続先にはHTTPSを指定してください。');
    }
    final endpointPath = path.replaceFirst(RegExp(r'^/+'), '');
    return base.resolve('/todo-app/$endpointPath');
  }

  Future<dynamic> postPublic(String path, Map<String, dynamic> body) async {
    return _send('POST', path, body: body, authorized: false);
  }

  Future<dynamic> get(String path) async =>
      _send('GET', path, authorized: true);

  Future<void> checkServerConnection() async {
    final response = await _send(
      'GET',
      '/health',
      authorized: false,
      timeout: const Duration(seconds: 5),
    );
    if (response is! Map<String, dynamic> || response['status'] != 'ok') {
      throw const ApiException('サーバーから正常な応答がありません。');
    }
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async =>
      _send('POST', path, body: body, authorized: true);

  Future<dynamic> put(String path, Map<String, dynamic> body) async =>
      _send('PUT', path, body: body, authorized: true);

  Future<dynamic> patch(String path, Map<String, dynamic> body) async =>
      _send('PATCH', path, body: body, authorized: true);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    required bool authorized,
    bool retryUnauthorized = true,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (authorized) {
      final token = await _getAccessToken();
      if (token == null) throw const ApiException('ログインしてください。');
      headers['Authorization'] = 'Bearer $token';
    }

    final uri = _uri(path);
    final encodedBody = body == null ? null : jsonEncode(body);
    late final http.StreamedResponse response;
    try {
      response = await _client
          .send(
            http.Request(method, uri)
              ..headers.addAll(headers)
              ..body = encodedBody ?? '',
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const ApiException('APIへの接続がタイムアウトしました。');
    } on http.ClientException catch (error) {
      throw ApiException('APIに接続できませんでした: ${error.message}');
    }
    final responseBody = await response.stream.bytesToString();
    final decoded = _decodeResponse(responseBody);

    if (response.statusCode == 401 && authorized && retryUnauthorized) {
      final refreshedToken = await _refreshAccessToken();
      if (refreshedToken != null) {
        return _send(
          method,
          path,
          body: body,
          authorized: true,
          retryUnauthorized: false,
          timeout: timeout,
        );
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map && decoded['message'] is String
          ? decoded['message'] as String
          : 'API request failed (${response.statusCode}).';
      throw ApiException(message, statusCode: response.statusCode);
    }
    return decoded;
  }

  dynamic _decodeResponse(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const ApiException('APIから不正なJSON応答が返されました。');
    }
  }

  Future<String?> _getAccessToken() async {
    final expiresAtText = await _storage.read(key: _accessTokenExpiryKey);
    final expiresAt = expiresAtText == null
        ? null
        : DateTime.tryParse(expiresAtText);
    if (expiresAt != null &&
        !expiresAt.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
      return _refreshAccessToken();
    }
    return await _storage.read(key: _accessTokenKey);
  }

  Future<String?> _refreshAccessToken() {
    return _refreshing ??= _doRefreshAccessToken().whenComplete(() {
      _refreshing = null;
    });
  }

  Future<String?> _doRefreshAccessToken() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null) {
      await clearSession();
      return null;
    }
    try {
      final response = await _send(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': refreshToken},
        authorized: false,
      );
      if (response is! Map<String, dynamic>) {
        throw const ApiException('APIのトークン更新応答が不正です。');
      }
      final user = response['user'];
      if (user is! Map<String, dynamic>) {
        throw const ApiException('APIのトークン更新応答にユーザー情報がありません。');
      }
      final refreshedUser = AppUser.fromJson(user);
      await _storeTokens(response);
      await _storage.write(
        key: _userKey,
        value: jsonEncode(refreshedUser.toJson()),
      );
      await onSessionUserRefreshed?.call(user);
      return await _storage.read(key: _accessTokenKey);
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await clearSession();
        await onSessionExpired?.call();
        return null;
      }
      rethrow;
    }
  }

  Future<AppUser> acceptSession(dynamic response) async {
    if (response is! Map<String, dynamic>) {
      throw const ApiException('APIのログイン応答が不正です。');
    }
    final userJson = response['user'];
    if (userJson is! Map<String, dynamic>) {
      throw const ApiException('APIのログイン応答にユーザー情報がありません。');
    }
    final user = AppUser.fromJson(userJson);
    await _storeTokens(response);
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
    return user;
  }

  Future<void> _storeTokens(Map<String, dynamic> response) async {
    final accessToken = response['accessToken'];
    final refreshToken = response['refreshToken'];
    final expiresIn = response['expiresIn'];
    if (accessToken is! String ||
        refreshToken is! String ||
        expiresIn is! num ||
        expiresIn <= 0) {
      throw const ApiException('APIのトークン応答が不正です。');
    }
    final expiry = DateTime.now()
        .add(Duration(seconds: expiresIn.toInt()))
        .toIso8601String();
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    await _storage.write(key: _accessTokenExpiryKey, value: expiry);
  }

  Future<AppUser?> restoreSession() async {
    final accessToken = await _storage.read(key: _accessTokenKey);
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    final userJson = await _storage.read(key: _userKey);
    if ((accessToken == null && refreshToken == null) || userJson == null) {
      await clearSession();
      return null;
    }
    final decoded = jsonDecode(userJson);
    if (decoded is! Map<String, dynamic>) {
      await clearSession();
      throw const ApiException('保存されたユーザー情報が不正です。再度ログインしてください。');
    }
    return AppUser.fromJson(decoded);
  }

  Future<List<Task>> getTasks() async {
    final response = await get('/tasks');
    if (response is! Map<String, dynamic> || response['tasks'] is! List) {
      throw const ApiException('APIのタスク一覧応答が不正です。');
    }
    return (response['tasks'] as List).map((item) {
      if (item is! Map<String, dynamic>) {
        throw const ApiException('APIのタスク応答に不正な項目があります。');
      }
      return Task.fromJson(item);
    }).toList();
  }

  Future<void> replaceTasks(List<Task> tasks) async {
    await put('/tasks', {'tasks': tasks.map((task) => task.toJson()).toList()});
  }

  Future<Map<String, dynamic>> getSettings() async {
    final response = await get('/settings');
    if (response is! Map<String, dynamic>) {
      throw const ApiException('APIの設定応答が不正です。');
    }
    return response;
  }

  Future<void> patchSettings(Map<String, dynamic> settings) async {
    await patch('/settings', settings);
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _accessTokenExpiryKey);
    await _storage.delete(key: _userKey);
  }
}
