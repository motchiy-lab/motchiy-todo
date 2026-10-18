import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models/app_user.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'main_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService.instance;
    return StreamBuilder<AppUser?>(
      stream: authService.authStateChanges,
      initialData: authService.currentUser,
      builder: (context, snapshot) {
        return snapshot.data == null
            ? const SignInScreen()
            : _SettingsLoader(key: ValueKey(snapshot.data!.id));
      },
    );
  }
}

class _SettingsLoader extends StatefulWidget {
  const _SettingsLoader({super.key});

  @override
  State<_SettingsLoader> createState() => _SettingsLoaderState();
}

class _SettingsLoaderState extends State<_SettingsLoader> {
  late final Future<void> _settingsLoad = _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> settings = {};
    try {
      settings = await ApiService.instance.getSettings();
    } on ApiException catch (error) {
      debugPrint('Could not load API settings; using local settings: $error');
    }
    final themeColor =
        settings['themeColorIndex'] ?? prefs.getInt('theme_color_index');
    final themeMode =
        settings['themeModeIndex'] ?? prefs.getInt('theme_mode_index');
    final enableTabAnimations =
        settings['enableTabAnimations'] ??
        prefs.getBool('enable_tab_animations');
    if (themeColor is int) {
      themeIndexNotifier.value = themeColor;
      await prefs.setInt('theme_color_index', themeColor);
    }
    if (themeMode is int &&
        themeMode >= 0 &&
        themeMode < ThemeMode.values.length) {
      themeModeNotifier.value = ThemeMode.values[themeMode];
      await prefs.setInt('theme_mode_index', themeMode);
    }
    if (enableTabAnimations is bool) {
      enableTabAnimationsNotifier.value = enableTabAnimations;
      await prefs.setBool('enable_tab_animations', enableTabAnimations);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _settingsLoad,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return const MainScreen();
      },
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _isSigningIn = false;
  bool _isRegistering = false;
  String? _error;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSigningIn = true;
      _error = null;
    });
    try {
      if (_isRegistering) {
        await AuthService.instance.register(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          displayName: _displayNameController.text.trim(),
        );
      } else {
        await AuthService.instance.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.task_alt, size: 64),
                    const SizedBox(height: 20),
                    const Text(
                      'Motchiy ToDo',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isRegistering
                          ? 'アカウントを作成してタスクと設定を同期します。'
                          : 'メールアドレスでログインしてタスクと設定を同期します。',
                    ),
                    const SizedBox(height: 28),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          if (_isRegistering) ...[
                            TextFormField(
                              controller: _displayNameController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: '表示名',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (_isRegistering &&
                                    (value == null || value.trim().isEmpty)) {
                                  return '表示名を入力してください。';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'メールアドレス',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null ||
                                  !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                      .hasMatch(value.trim())) {
                                return '有効なメールアドレスを入力してください。';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            autofillHints: [
                              _isRegistering
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: const InputDecoration(
                              labelText: 'パスワード',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'パスワードを入力してください。';
                              }
                              if (_isRegistering && value.length < 12) {
                                return '12文字以上で入力してください。';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _isSigningIn ? null : _submit,
                              icon: const Icon(Icons.login),
                              label: Text(
                                _isSigningIn
                                    ? '処理中...'
                                    : _isRegistering
                                    ? 'アカウントを作成'
                                    : 'ログイン',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    TextButton(
                      onPressed: _isSigningIn
                          ? null
                          : () => setState(() {
                              _isRegistering = !_isRegistering;
                              _error = null;
                            }),
                      child: Text(
                        _isRegistering
                            ? 'すでにアカウントをお持ちの方はログイン'
                            : 'アカウントをお持ちでない方はこちら',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
