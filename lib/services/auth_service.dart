import 'dart:async';

import '../models/app_user.dart';
import 'api_service.dart';
import 'task_cache_service.dart';

class AuthService {
  AuthService._() {
    ApiService.instance.onSessionUserRefreshed = _onSessionUserRefreshed;
    ApiService.instance.onSessionExpired = _onSessionExpired;
  }

  static final instance = AuthService._();

  final StreamController<AppUser?> _authStateController =
      StreamController<AppUser?>.broadcast();

  AppUser? currentUser;
  AppUser? _expiredUser;
  bool isInitialized = false;
  Stream<AppUser?> get authStateChanges => _authStateController.stream;

  Future<void> _onSessionUserRefreshed(Map<String, dynamic> json) async {
    final refreshedUser = AppUser.fromJson(json);
    final previousUser = currentUser;
    if (previousUser != null && previousUser.id != refreshedUser.id) {
      await TaskCacheService.instance.migrateUserId(
        previousUser.id,
        refreshedUser.id,
      );
    }
    currentUser = refreshedUser;
    _authStateController.add(refreshedUser);
  }

  Future<void> _onSessionExpired() async {
    _expiredUser = currentUser;
    currentUser = null;
    _authStateController.add(null);
  }

  Future<void> initialize() async {
    try {
      currentUser = await ApiService.instance.restoreSession();
    } finally {
      isInitialized = true;
      _authStateController.add(currentUser);
    }
  }

  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    return _authenticate('/auth/login', {'email': email, 'password': password});
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await ApiService.instance.postPublic('/auth/register', {
      'email': email,
      'password': password,
      'displayName': displayName,
    });
  }

  Future<void> resendVerificationCode({required String email}) async {
    await ApiService.instance.postPublic('/auth/verification/resend', {
      'email': email,
    });
  }

  Future<AppUser> verifyEmail({
    required String email,
    required String code,
  }) async {
    return _authenticate('/auth/verify-email', {'email': email, 'code': code});
  }

  Future<AppUser> _authenticate(String path, Map<String, dynamic> body) async {
    final response = await ApiService.instance.postPublic(path, body);
    currentUser = await ApiService.instance.acceptSession(response);
    final expiredUser = _expiredUser;
    _expiredUser = null;
    if (expiredUser != null &&
        expiredUser.email.toLowerCase() == currentUser!.email.toLowerCase() &&
        expiredUser.id != currentUser!.id) {
      await TaskCacheService.instance.migrateUserId(
        expiredUser.id,
        currentUser!.id,
      );
    }
    _authStateController.add(currentUser);
    return currentUser!;
  }

  Future<void> signOut() async {
    _expiredUser = null;
    try {
      await ApiService.instance.post('/auth/logout', const {});
    } finally {
      await ApiService.instance.clearSession();
      currentUser = null;
      _authStateController.add(null);
    }
  }
}
