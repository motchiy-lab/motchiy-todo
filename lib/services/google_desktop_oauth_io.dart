import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';

class GoogleDesktopOAuth {
  static Future<Map<String, String>> authenticate(
    String clientId,
    String clientSecret,
  ) async {
    final verifier = _randomUrlSafeString(64);
    final challenge = base64Url
        .encode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // Google desktop OAuth requires the loopback URI without a path.
    final redirectUri = 'http://127.0.0.1:${server.port}';

    try {
      final authorizationUri = Uri.https(
        'accounts.google.com',
        '/o/oauth2/v2/auth',
        <String, String>{
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': 'openid email profile',
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'access_type': 'offline',
          'prompt': 'select_account',
        },
      );
      if (!await launchUrl(authorizationUri)) {
        throw StateError('Googleログイン画面を開けませんでした。');
      }

      final request = await server.first;
      final code = request.uri.queryParameters['code'];
      final error = request.uri.queryParameters['error'];
      request.response
        ..statusCode = code == null ? HttpStatus.badRequest : HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(
          code == null
              ? '<h1>Googleログインに失敗しました。この画面を閉じてください。</h1>'
              : '<h1>ログイン完了</h1><p>この画面を閉じてアプリに戻ってください。</p>',
        );
      await request.response.close();
      if (code == null) {
        throw StateError(
          error == 'access_denied'
              ? 'Googleログインがキャンセルされました'
              : 'Googleログインに失敗しました。',
        );
      }

      final tokens = await _exchangeCode(
        clientId,
        clientSecret,
        code,
        verifier,
        redirectUri,
      );
      final idToken = tokens['id_token'];
      final accessToken = tokens['access_token'];
      if (idToken is! String || accessToken is! String) {
        throw StateError('Googleから認証トークンを取得できませんでした。');
      }
      return <String, String>{'id_token': idToken, 'access_token': accessToken};
    } finally {
      await server.close(force: true);
    }
  }

  static Future<Map<String, dynamic>> _exchangeCode(
    String clientId,
    String clientSecret,
    String code,
    String verifier,
    String redirectUri,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.https('oauth2.googleapis.com', '/token'),
      );
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
      request.write(
        Uri(
          queryParameters: <String, String>{
            'client_id': clientId,
            if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
            'code': code,
            'code_verifier': verifier,
            'grant_type': 'authorization_code',
            'redirect_uri': redirectUri,
          },
        ).query,
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      if (response.statusCode != HttpStatus.ok || decoded is! Map) {
        final error = decoded is Map ? decoded['error'] : null;
        final description = decoded is Map
            ? decoded['error_description']
            : null;
        final detail = [
          if (error is String) error,
          if (description is String) description,
        ].join(': ');
        throw StateError(
          'Googleトークンの取得に失敗しました'
          '${detail.isEmpty ? '' : ' ($detail)'}',
        );
      }
      return Map<String, dynamic>.from(decoded);
    } finally {
      client.close(force: true);
    }
  }

  static String _randomUrlSafeString(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }
}
