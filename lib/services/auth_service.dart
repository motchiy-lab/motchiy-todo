import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/api_config.dart';
import '../models/app_user.dart';
import 'api_service.dart';
import 'google_desktop_oauth_stub.dart'
    if (dart.library.io) 'google_desktop_oauth_io.dart';

class AuthService {
  AuthService._();

  static final instance = AuthService._();
  static bool get isGoogleSignInSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: googleOAuthClientId,
    serverClientId: googleOAuthClientId,
  );
  final StreamController<AppUser?> _authStateController =
      StreamController<AppUser?>.broadcast();

  AppUser? currentUser;
  Stream<AppUser?> get authStateChanges => _authStateController.stream;

  Future<void> initialize() async {
    currentUser = await ApiService.instance.restoreSession();
  }

  Future<AppUser> signInWithGoogle({bool forceAccountSelection = false}) async {
    if (!isGoogleSignInSupported) {
      throw UnsupportedError('このプラットフォームではGoogleログインを利用できません。');
    }

    try {
      final dynamic response;
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux ||
              defaultTargetPlatform == TargetPlatform.macOS)) {
        response = await GoogleDesktopOAuth.authenticate(
          forceAccountSelection: forceAccountSelection,
        );
      } else {
        if (forceAccountSelection) await _googleSignIn.signOut();
        final account = await _googleSignIn.signIn();
        if (account == null) {
          throw StateError('Googleログインがキャンセルされました');
        }
        final authentication = await account.authentication;
        final idToken = authentication.idToken;
        if (idToken == null || idToken.isEmpty) {
          throw StateError('GoogleからIDトークンを取得できませんでした。');
        }
        response = await ApiService.instance.postPublic('/auth/google', {
          'idToken': idToken,
        });
      }
      currentUser = await ApiService.instance.acceptSession(response);
      _authStateController.add(currentUser);
      return currentUser!;
    } on PlatformException catch (error) {
      if (error.code == 'sign_in_failed') {
        throw StateError(
          'Googleログインに失敗しました。API側でこのアプリのGoogle OAuthクライアントIDを許可してください。',
        );
      }
      rethrow;
    }
  }

  Future<AppUser> switchGoogleAccount() {
    return signInWithGoogle(forceAccountSelection: true);
  }

  Future<void> signOut() async {
    try {
      await ApiService.instance.post('/auth/logout', const {});
    } finally {
      await ApiService.instance.clearSession();
      currentUser = null;
      _authStateController.add(null);
      if (defaultTargetPlatform != TargetPlatform.windows &&
          isGoogleSignInSupported) {
        await _googleSignIn.signOut();
      }
    }
  }
}
