import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../main.dart';
import '../services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isAccountActionRunning = false;
  bool _isRefreshing = false;

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  DocumentReference<Map<String, dynamic>> get _settingsDocument =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid);

  Future<void> _saveCloudSettings(Map<String, dynamic> settings) async {
    await _settingsDocument.set({
      'settings': settings,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _changeTheme(int index) async {
    themeIndexNotifier.value = index;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_color_index', index);
    await _saveCloudSettings({'themeColorIndex': index});
    setState(() {});
  }

  Future<void> _changeThemeMode(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode_index', mode.index);
    await _saveCloudSettings({'themeModeIndex': mode.index});
    setState(() {});
  }

  Future<void> _changeTabAnimations(bool enabled) async {
    enableTabAnimationsNotifier.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enable_tab_animations', enabled);
    await _saveCloudSettings({'enableTabAnimations': enabled});
    setState(() {});
  }

  Future<void> _refreshSettings() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      themeIndexNotifier.value = prefs.getInt('theme_color_index') ?? 0;
      themeModeNotifier.value =
          ThemeMode.values[prefs.getInt('theme_mode_index') ?? 0];
      enableTabAnimationsNotifier.value =
          prefs.getBool('enable_tab_animations') ?? true;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('設定を再読み込みしました')));
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _switchAccount() async {
    setState(() => _isAccountActionRunning = true);
    try {
      final authService = AuthService();
      await authService.switchGoogleAccount();
    } on StateError catch (error) {
      if (error.message == 'Googleログインがキャンセルされました') {
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('アカウントを切り替えられませんでした: $error')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('アカウントを切り替えられませんでした: $error')));
      }
    } finally {
      if (mounted) setState(() => _isAccountActionRunning = false);
    }
  }

  Future<void> _signOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ログアウトしますか？'),
        content: const Text('次回利用時には、もう一度ログインが必要です。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ログアウト'),
          ),
        ],
      ),
    );
    if (shouldSignOut != true) return;
    await AuthService().signOut();
  }

  Widget _buildAccountSection(ColorScheme colorScheme, bool isDark) {
    final currentUser = FirebaseAuth.instance.currentUser;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'アカウント管理',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'ログイン中のアカウントや、利用するアカウントを管理できます',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        const SizedBox(height: 12),
        if (currentUser != null)
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: _buildAccountAvatar(currentUser),
              title: Text(currentUser.displayName ?? 'Googleアカウント'),
              subtitle: Text(currentUser.email ?? ''),
              trailing: const Icon(Icons.check_circle),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    _isAccountActionRunning ||
                        !AuthService.isGoogleSignInSupported
                    ? null
                    : _switchAccount,
                icon: _isAccountActionRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.swap_horiz),
                label: const Text('アカウントを変更'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isAccountActionRunning ? null : _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('ログアウト'),
              ),
            ),
          ],
        ),
        if (!AuthService.isGoogleSignInSupported)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'この環境ではGoogleログインを利用できません。',
              style: TextStyle(color: colorScheme.error, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildAccountAvatar(User user) {
    return CircleAvatar(
      backgroundImage: user.photoURL == null
          ? null
          : NetworkImage(user.photoURL!),
      child: user.photoURL == null
          ? Text((user.email ?? '?').substring(0, 1).toUpperCase())
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        elevation: 0,
        title: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 750),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '設定',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'アプリの設定をさまざまな変更',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (!_isMobile)
                    IconButton(
                      onPressed: _isRefreshing ? null : _refreshSettings,
                      tooltip: '再読み込み',
                      icon: _isRefreshing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 750),
            child: RefreshIndicator(
              onRefresh: _refreshSettings,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  const SizedBox(height: 8),
                  _buildAccountSection(colorScheme, isDark),
                  const SizedBox(height: 32),
                  const Text(
                    'カラーテーマ',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'アプリ全体のカラーテーマを変更できます',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 10),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _isMobile ? 2 : 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: _isMobile ? 2.6 : 4.0,
                    ),
                    itemCount: appThemes.length,
                    itemBuilder: (context, index) {
                      final isSelected = themeIndexNotifier.value == index;
                      return InkWell(
                        onTap: () => _changeTheme(index),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colorScheme.primary.withValues(alpha: 0.15)
                                : (isDark
                                      ? Colors.grey[900]
                                      : Colors.grey[100]),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? colorScheme.primary
                                  : (isDark
                                        ? Colors.grey[800]!
                                        : Colors.grey[300]!),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: appThemes[index],
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  appThemeNames[index],
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check,
                                  size: 18,
                                  color: colorScheme.primary,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    '外観モード',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'アプリの表示モード（ライト・ダーク・システム）を選択できます',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildModeButton(
                          title: 'システム',
                          icon: Icons.brightness_auto,
                          mode: ThemeMode.system,
                          isDark: isDark,
                          colorScheme: colorScheme,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildModeButton(
                          title: 'ライト',
                          icon: Icons.light_mode,
                          mode: ThemeMode.light,
                          isDark: isDark,
                          colorScheme: colorScheme,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildModeButton(
                          title: 'ダーク',
                          icon: Icons.dark_mode,
                          mode: ThemeMode.dark,
                          isDark: isDark,
                          colorScheme: colorScheme,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'タブ切り替えアニメーション',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'タブを切り替えるときのスライドとフェードを設定できます',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('アニメーションを使用する'),
                    value: enableTabAnimationsNotifier.value,
                    onChanged: _changeTabAnimations,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeButton({
    required String title,
    required IconData icon,
    required ThemeMode mode,
    required bool isDark,
    required ColorScheme colorScheme,
  }) {
    final isSelected = themeModeNotifier.value == mode;
    return InkWell(
      onTap: () => _changeThemeMode(mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.15)
              : (isDark ? Colors.grey[900] : Colors.grey[100]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : (isDark ? Colors.grey[800]! : Colors.grey[300]!),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected
                  ? colorScheme.primary
                  : (isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? colorScheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
