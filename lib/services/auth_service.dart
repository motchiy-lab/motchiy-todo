import 'dart:async';

import '../models/app_user.dart';
import 'api_service.dart';

class AuthService {
  AuthService._();

  static final instance = AuthService._();

  final StreamController<AppUser?> _authStateController =
      StreamController<AppUser?>.broadcast();

  AppUser? currentUser;
  Stream<AppUser?> get authStateChanges => _authStateController.stream;

  Future<void> initialize() async {
    currentUser = await ApiService.instance.restoreSession();
  }

  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    return _authenticate('/auth/login', {'email': email, 'password': password});
  }

  Future<AppUser> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    return _authenticate('/auth/register', {
      'email': email,
      'password': password,
      'displayName': displayName,
    });
  }

  Future<AppUser> _authenticate(String path, Map<String, dynamic> body) async {
    final response = await ApiService.instance.postPublic(path, body);
    currentUser = await ApiService.instance.acceptSession(response);
    _authStateController.add(currentUser);
    return currentUser!;
  }

  Future<void> signOut() async {
    try {
      await ApiService.instance.post('/auth/logout', const {});
    } finally {
      await ApiService.instance.clearSession();
      currentUser = null;
      _authStateController.add(null);
    }
  }
}
