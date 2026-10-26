import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models/app_user.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/custom_title_bar.dart';
import 'main_screen.dart';

bool get _isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService.instance;
    return StreamBuilder<AppUser?>(
      stream: authService.authStateChanges,
      initialData: authService.currentUser,
      builder: (context, snapshot) {
        if (!authService.isInitialized) {
          return Scaffold(
            body: Column(
              children: [
                if (_isDesktopPlatform) const CustomTitleBar(),
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
            ),
          );
        }
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
          return Scaffold(
            body: Column(
              children: [
                if (_isDesktopPlatform) const CustomTitleBar(),
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
            ),
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
  bool _needsEmailCode = false;
  String? _error;
  String? _successMessage;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _verificationCodeController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _displayNameController.dispose();
    _verificationCodeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSigningIn = true;
      _error = null;
      _successMessage = null;
    });
    try {
      if (_isRegistering) {
        await AuthService.instance.register(
          email: _emailController.text.trim(),
          displayName: _displayNameController.text.trim(),
        );
        if (mounted) {
          setState(() {
            _needsEmailCode = true;
            _successMessage = '確認コードをメールで送信しました。メールをご確認ください。';
          });
        }
      } else {
        await AuthService.instance.requestLoginCode(
          email: _emailController.text.trim(),
        );
        if (mounted) {
          setState(() {
            _needsEmailCode = true;
            _successMessage = 'アカウントが登録済みの場合、認証コードをメールで送信しました。';
          });
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _successMessage = null;
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _verifyEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSigningIn = true;
      _error = null;
      _successMessage = null;
    });
    try {
      if (_isRegistering) {
        await AuthService.instance.verifyEmail(
          email: _emailController.text.trim(),
          code: _verificationCodeController.text.trim(),
        );
      } else {
        await AuthService.instance.verifyLoginCode(
          email: _emailController.text.trim(),
          code: _verificationCodeController.text.trim(),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _successMessage = null;
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _resendVerificationCode() async {
    if (!_isValidEmail(_emailController.text)) {
      setState(() {
        _successMessage = null;
        _error = '有効なメールアドレスを入力してください。';
      });
      return;
    }
    setState(() {
      _isSigningIn = true;
      _error = null;
      _successMessage = null;
    });
    try {
      if (_isRegistering) {
        await AuthService.instance.resendVerificationCode(
          email: _emailController.text.trim(),
        );
      } else {
        await AuthService.instance.requestLoginCode(
          email: _emailController.text.trim(),
        );
      }
      if (mounted) {
        setState(() {
          _successMessage = _isRegistering
              ? '認証コードを再送信しました。メールをご確認ください。'
              : 'アカウントが登録済みの場合、認証コードを再送信しました。';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _successMessage = null;
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (_isDesktopPlatform) const CustomTitleBar(),
          Expanded(
            child: SafeArea(
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
                            _needsEmailCode
                                ? 'メールに届いた6桁の認証コードを入力してください。'
                                : _isRegistering
                                ? 'アカウントを作成してタスクと設定を同期します。'
                                : 'メールアドレスに届くワンタイムパスワードでログインします。',
                          ),
                          const SizedBox(height: 28),
                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                if (_needsEmailCode) ...[
                                  _emailField(),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _verificationCodeController,
                                    keyboardType: TextInputType.number,
                                    autofillHints: const [
                                      AutofillHints.oneTimeCode,
                                    ],
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _verifyEmail(),
                                    decoration: const InputDecoration(
                                      labelText: '認証コード',
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (value) {
                                      if (value == null ||
                                          !RegExp(r'^\d{6}$')
                                              .hasMatch(value.trim())) {
                                        return 'メールに届いた6桁のコードを入力してください。';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                      onPressed: _isSigningIn
                                          ? null
                                          : _verifyEmail,
                                      icon: const Icon(Icons.verified_user),
                                      label: Text(
                                        _isSigningIn
                                            ? '確認中...'
                                            : _isRegistering
                                            ? 'メールアドレスを認証'
                                            : 'ログイン',
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _isSigningIn
                                        ? null
                                        : _resendVerificationCode,
                                    child: const Text('認証コードを再送信'),
                                  ),
                                ] else ...[
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
                                            (value == null ||
                                                value.trim().isEmpty)) {
                                          return '表示名を入力してください。';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  _emailField(),
                                  const SizedBox(height: 12),
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
                          if (_successMessage != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _successMessage!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          if (!_needsEmailCode)
                            TextButton(
                              onPressed: _isSigningIn
                                  ? null
                                  : () => setState(() {
                                      _isRegistering = !_isRegistering;
                                      _error = null;
                                      _successMessage = null;
                                    }),
                              child: Text(
                                _isRegistering
                                    ? 'すでにアカウントをお持ちの方はログイン'
                                    : 'アカウントをお持ちでない方はこちら',
                              ),
                            ),
                          if (_needsEmailCode)
                            TextButton(
                              onPressed: _isSigningIn
                                  ? null
                                  : () => setState(() {
                                      _needsEmailCode = false;
                                      _isRegistering = false;
                                      _error = null;
                                      _successMessage = null;
                                    }),
                              child: const Text('ログイン画面に戻る'),
                            ),
                          if (!_needsEmailCode && !_isRegistering)
                            TextButton(
                              onPressed: _isSigningIn
                                  ? null
                                  : () => setState(() {
                                      _needsEmailCode = true;
                                      _error = null;
                                      _successMessage = null;
                                    }),
                              child: const Text('認証コードを入力・再送信'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        labelText: 'メールアドレス',
        border: OutlineInputBorder(),
      ),
      validator: (value) {
        if (!_isValidEmail(value)) {
          return '有効なメールアドレスを入力してください。';
        }
        return null;
      },
    );
  }

  bool _isValidEmail(String? value) =>
      value != null &&
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
}
