import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'google_desktop_oauth_stub.dart'
    if (dart.library.io) 'google_desktop_oauth_io.dart';

class AuthService {
  static const _desktopClientId = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_ID',
  );
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  static bool get isGoogleSignInSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInWithGoogle({
    bool forceAccountSelection = false,
  }) async {
    if (!isGoogleSignInSupported) {
      throw UnsupportedError('このプラットフォームではGoogleログインを利用できません。');
    }

    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        if (_desktopClientId.isEmpty) {
          throw StateError(
            'Windows版Googleログインの設定がありません。'
            'GOOGLE_DESKTOP_CLIENT_IDを指定して起動してください。',
          );
        }
        final tokens = await GoogleDesktopOAuth.authenticate(_desktopClientId);
        return await _auth.signInWithCredential(
          GoogleAuthProvider.credential(
            idToken: tokens['id_token'],
            accessToken: tokens['access_token'],
          ),
        );
      }

      if (forceAccountSelection) {
        await _googleSignIn.signOut();
      }
      final account = await _googleSignIn.signIn();
      if (account == null) {
        throw StateError('Googleログインがキャンセルされました');
      }
      final authentication = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: authentication.accessToken,
        idToken: authentication.idToken,
      );
      return await _auth.signInWithCredential(credential);
    } on PlatformException catch (error) {
      if (error.code == 'sign_in_failed') {
        throw StateError(
          'Googleログインの設定が不足しています。'
          'Firebase ConsoleでGoogleログインを有効化し、'
          'AndroidアプリのSHA-1とOAuthクライアントを登録してください。',
        );
      }
      rethrow;
    }
  }

  Future<UserCredential> switchGoogleAccount() {
    return signInWithGoogle(forceAccountSelection: true);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    if (defaultTargetPlatform != TargetPlatform.windows &&
        isGoogleSignInSupported) {
      await _googleSignIn.signOut();
    }
  }
}
