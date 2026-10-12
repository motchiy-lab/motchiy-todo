import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';

class GoogleDesktopOAuth {
  static Future<dynamic> authenticate({
    required bool forceAccountSelection,
  }) async {
    final state = _randomUrlSafeString(32);
    final verifier = _randomUrlSafeString(64);
    final challenge = base64Url
        .encode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}/callback';

    try {
      final start = await ApiService.instance.postPublic(
        '/auth/google/desktop/start',
        {
          'redirectUri': redirectUri,
          'state': state,
          'codeChallenge': challenge,
          'codeChallengeMethod': 'S256',
          'forceAccountSelection': forceAccountSelection,
        },
      );
      if (start is! Map<String, dynamic> ||
          start['authorizationUrl'] is! String) {
        throw const ApiException('APIのGoogleログイン開始応答が不正です。');
      }
      final authorizationUri = Uri.tryParse(
        start['authorizationUrl'] as String,
      );
      if (authorizationUri == null ||
          authorizationUri.scheme != 'https' ||
          authorizationUri.host.isEmpty) {
        throw const ApiException('APIから不正なGoogleログインURLが返されました。');
      }
      if (!await launchUrl(authorizationUri)) {
        throw StateError('Googleログイン画面を開けませんでした。');
      }

      final request = await server.first.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw StateError('Googleログインがキャンセルされました');
        },
      );
      final callbackState = request.uri.queryParameters['state'];
      final code = request.uri.queryParameters['code'];
      final error = request.uri.queryParameters['error'];
      request.response
        ..statusCode = callbackState == state && code != null
            ? HttpStatus.ok
            : HttpStatus.badRequest
        ..headers.contentType = ContentType.html
        ..write(
          callbackState == state && code != null
              ? '<h1>ログイン完了</h1><p>この画面を閉じてアプリに戻ってください。</p>'
              : '<h1>ログインに失敗しました。この画面を閉じてください。</h1>',
        );
      await request.response.close();

      if (callbackState != state) {
        throw StateError('Googleログインの検証に失敗しました。もう一度お試しください。');
      }
      if (code == null) {
        throw StateError(
          error == 'access_denied'
              ? 'Googleログインがキャンセルされました'
              : 'Googleログインに失敗しました。',
        );
      }

      return await ApiService.instance.postPublic(
        '/auth/google/desktop/exchange',
        {
          'code': code,
          'codeVerifier': verifier,
          'redirectUri': redirectUri,
        },
      );
    } finally {
      await server.close(force: true);
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
