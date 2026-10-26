import 'dart:convert';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models/app_user.dart';
import '../models/task.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/backup_storage.dart';
import '../services/desktop_window_service.dart';
import '../services/startup_service.dart';
import '../services/task_cache_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isAccountActionRunning = false;
  bool _isRefreshing = false;
  bool _isLoadingBackupSettings = true;
  bool _isCreatingBackup = false;
  bool _isRestoringBackup = false;
  bool _isCheckingServerConnection = false;
  bool? _serverConnected;
  String? _serverConnectionError;
  DateTime? _serverConnectionCheckedAt;
  bool _dailyBackupEnabled = true;
  int _backupRetentionDays = 30;
  DateTime? _latestBackup;

  @override
  void initState() {
    super.initState();
    _loadBackupSettings();
    _checkServerConnection();
  }

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  bool get _supportsStartup =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  Future<void> _loadBackupSettings() async {
    try {
      final settings = await BackupService.instance.getSettings();
      final userId = AuthService.instance.currentUser?.id;
      final latestBackup = userId == null
          ? null
          : await BackupService.instance.latestBackupTime(userId);
      if (!mounted) return;
      setState(() {
        _dailyBackupEnabled = settings.dailyEnabled;
        _backupRetentionDays = settings.retentionDays;
        _latestBackup = latestBackup;
        _isLoadingBackupSettings = false;
      });
    } catch (error) {
      debugPrint('Could not load local backup settings: $error');
      if (mounted) setState(() => _isLoadingBackupSettings = false);
    }
  }

  Future<void> _checkServerConnection() async {
    if (_isCheckingServerConnection) return;
    setState(() => _isCheckingServerConnection = true);
    try {
      await ApiService.instance.checkServerConnection();
      if (!mounted) return;
      setState(() {
        _serverConnected = true;
        _serverConnectionError = null;
        _serverConnectionCheckedAt = DateTime.now();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _serverConnected = false;
        _serverConnectionError = error.toString();
        _serverConnectionCheckedAt = DateTime.now();
      });
    } finally {
      if (mounted) setState(() => _isCheckingServerConnection = false);
    }
  }

  Future<void> _changeDailyBackup(bool enabled) async {
    try {
      await BackupService.instance.setDailyEnabled(enabled);
      if (mounted) setState(() => _dailyBackupEnabled = enabled);
    } catch (error) {
      _showBackupError(error);
    }
  }

  Future<void> _changeBackupRetention(int days) async {
    try {
      await BackupService.instance.setRetentionDays(days);
      if (mounted) setState(() => _backupRetentionDays = days);
    } catch (error) {
      _showBackupError(error);
    }
  }

  Future<void> _createBackupNow() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || _isCreatingBackup) return;
    setState(() => _isCreatingBackup = true);
    try {
      final cachedTasks = await TaskCacheService.instance.readTasks(userId);
      final tasks = cachedTasks ?? await ApiService.instance.getTasks();
      await BackupService.instance.createBackup(userId, tasks);
      final latestBackup = await BackupService.instance.latestBackupTime(
        userId,
      );
      if (mounted) {
        setState(() => _latestBackup = latestBackup);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('ローカルバックアップを作成しました')));
      }
    } catch (error) {
      _showBackupError(error);
    } finally {
      if (mounted) setState(() => _isCreatingBackup = false);
    }
  }

  Future<void> _pickBackupFile() async {
    if (_isRestoringBackup) return;
    try {
      final file = await file_selector.openFile(
        acceptedTypeGroups: const [
          file_selector.XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (file == null) return;
      await _restoreFromJson(
        utf8.decode(await file.readAsBytes()),
        sourceName: file.name,
      );
    } catch (error) {
      _showBackupError(error);
    }
  }

  Future<void> _chooseSavedBackup() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || _isRestoringBackup) return;
    try {
      final backups = await BackupService.instance.listBackups(userId);
      if (!mounted) return;
      if (backups.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('選択できるバックアップがありません')));
        return;
      }
      final selected = await showDialog<BackupFile>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('復元するバックアップを選択'),
          children: backups
              .map(
                (backup) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, backup),
                  child: Text(
                    DateFormat.yMd().add_Hm().format(
                      backup.modifiedAt.toLocal(),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      );
      if (selected == null) return;
      final contents = await BackupService.instance.readBackup(selected.path);
      await _restoreFromJson(
        contents,
        sourceName: selected.path.split(RegExp(r'[/\\]')).last,
      );
    } catch (error) {
      _showBackupError(error);
    }
  }

  Future<void> _restoreFromJson(
    String contents, {
    required String sourceName,
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || _isRestoringBackup) return;
    final backup = BackupService.decodeBackup(contents);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('バックアップを復元しますか？'),
        content: Text(
          '$sourceName から${backup.tasks.length}件の予定を読み込みます。'
          '現在の予定は削除せず統合します。同じIDで内容が異なる予定も両方残します。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('統合して復元'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isRestoringBackup = true);
    try {
      final cache = TaskCacheService.instance;
      List<Task>? cachedTasks;
      try {
        cachedTasks = await cache.readTasks(userId);
      } on FormatException catch (error) {
        debugPrint('Ignoring invalid local task cache during restore: $error');
        await cache.clearTasks(userId);
      }

      List<Task> remoteTasks = [];
      var remoteAvailable = true;
      try {
        remoteTasks = await ApiService.instance.getTasks();
      } catch (error) {
        remoteAvailable = false;
        debugPrint('Could not read remote tasks during restore: $error');
      }
      if (AuthService.instance.currentUser?.id != userId) return;

      final localAndBackup = cache.mergeTasks(cachedTasks ?? [], backup.tasks);
      final restoredTasks = cache.mergeTasks(remoteTasks, localAndBackup);
      await cache.saveLocalTasks(userId, restoredTasks);
      var synced = false;
      if (remoteAvailable) {
        try {
          await ApiService.instance.replaceTasks(restoredTasks);
          await cache.markSynced(userId);
          synced = true;
        } catch (error) {
          debugPrint('Restored tasks are waiting to sync: $error');
        }
      }
      await _restoreBackupSettings(backup.settings);
      if (!mounted) return;
      final status = synced
          ? 'サーバーと端末に復元しました'
          : '端末に復元しました。サーバー同期は次回の通信時に再試行します';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$status（${restoredTasks.length}件）')),
      );
    } catch (error) {
      _showBackupError(error);
    } finally {
      if (mounted) setState(() => _isRestoringBackup = false);
    }
  }

  Future<void> _restoreBackupSettings(Map<String, Object?>? settings) async {
    if (settings == null) return;
    final prefs = await SharedPreferences.getInstance();
    final updates = <String, dynamic>{};
    final themeIndex = settings['themeColorIndex'];
    if (themeIndex is int && themeIndex >= 0 && themeIndex < appThemes.length) {
      themeIndexNotifier.value = themeIndex;
      await prefs.setInt('theme_color_index', themeIndex);
      updates['themeColorIndex'] = themeIndex;
    }
    final themeModeIndex = settings['themeModeIndex'];
    if (themeModeIndex is int &&
        themeModeIndex >= 0 &&
        themeModeIndex < ThemeMode.values.length) {
      themeModeNotifier.value = ThemeMode.values[themeModeIndex];
      await prefs.setInt('theme_mode_index', themeModeIndex);
      updates['themeModeIndex'] = themeModeIndex;
    }
    final animations = settings['enableTabAnimations'];
    if (animations is bool) {
      enableTabAnimationsNotifier.value = animations;
      await prefs.setBool('enable_tab_animations', animations);
      updates['enableTabAnimations'] = animations;
    }
    if (updates.isNotEmpty) await _saveApiSettings(updates);
  }

  void _showBackupError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('ローカルバックアップを処理できませんでした: $error')));
  }

  Future<void> _saveApiSettings(Map<String, dynamic> settings) async {
    try {
      await ApiService.instance.patchSettings(settings);
    } catch (error) {
      debugPrint('Could not save settings to API: $error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('設定をサーバーに同期できませんでした: $error')));
      }
    }
  }

  Future<void> _changeTheme(int index) async {
    themeIndexNotifier.value = index;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_color_index', index);
    await _saveApiSettings({'themeColorIndex': index});
    setState(() {});
  }

  Future<void> _changeThemeMode(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode_index', mode.index);
    await _saveApiSettings({'themeModeIndex': mode.index});
    setState(() {});
  }

  Future<void> _changeTabAnimations(bool enabled) async {
    enableTabAnimationsNotifier.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enable_tab_animations', enabled);
    await _saveApiSettings({'enableTabAnimations': enabled});
    setState(() {});
  }

  Future<void> _changeCloseToTray(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('close_to_tray', enabled);
    await DesktopWindowService.instance.setCloseToTray(enabled);
    desktopCloseToTrayNotifier.value = enabled;
  }

  Future<void> _changeStartup(bool enabled) async {
    try {
      await StartupService.instance.setEnabled(enabled);
      desktopStartupNotifier.value = enabled;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('自動起動の設定を変更できませんでした: $error')));
      }
    }
  }

  Future<void> _refreshSettings() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> settings = {};
      try {
        settings = await ApiService.instance.getSettings();
      } on ApiException catch (error) {
        debugPrint('Could not refresh API settings: $error');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('サーバー設定を取得できませんでした: $error')));
        }
      }
      final themeIndex =
          settings['themeColorIndex'] ?? prefs.getInt('theme_color_index');
      final themeModeIndex =
          settings['themeModeIndex'] ?? prefs.getInt('theme_mode_index');
      final animations =
          settings['enableTabAnimations'] ??
          prefs.getBool('enable_tab_animations');
      if (themeIndex is int) {
        themeIndexNotifier.value = themeIndex;
        await prefs.setInt('theme_color_index', themeIndex);
      }
      if (themeModeIndex is int &&
          themeModeIndex >= 0 &&
          themeModeIndex < ThemeMode.values.length) {
        themeModeNotifier.value = ThemeMode.values[themeModeIndex];
        await prefs.setInt('theme_mode_index', themeModeIndex);
      }
      if (animations is bool) {
        enableTabAnimationsNotifier.value = animations;
        await prefs.setBool('enable_tab_animations', animations);
      }
      setState(() {});
      desktopCloseToTrayNotifier.value =
          prefs.getBool('close_to_tray') ?? false;
      if (_supportsStartup) {
        desktopStartupNotifier.value = await StartupService.instance
            .initialize();
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('設定を再読み込みしました')));
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
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
    setState(() => _isAccountActionRunning = true);
    try {
      await AuthService.instance.signOut();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ログアウトできませんでした: $error')));
      }
    } finally {
      if (mounted) setState(() => _isAccountActionRunning = false);
    }
  }

  Widget _buildAccountSection(bool isDark) {
    final currentUser = AuthService.instance.currentUser;
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
              title: Text(currentUser.displayName ?? 'アカウント'),
              subtitle: Text(currentUser.email),
              trailing: const Icon(Icons.check_circle),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isAccountActionRunning ? null : _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('ログアウト / 別アカウントでログイン'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildServerConnectionSection() {
    final connected = _serverConnected;
    final statusText = _isCheckingServerConnection
        ? '確認中...'
        : connected == null
        ? '未確認'
        : connected
        ? '接続中'
        : '接続できません';
    final statusColor = _isCheckingServerConnection
        ? Theme.of(context).colorScheme.primary
        : connected == true
        ? Colors.green
        : connected == false
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'サーバー接続',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          '現在のサーバーへの接続状態を確認できます',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: _isCheckingServerConnection
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    connected == true
                        ? Icons.cloud_done
                        : connected == false
                        ? Icons.cloud_off
                        : Icons.cloud_queue,
                    color: statusColor,
                  ),
            title: Text(
              statusText,
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _serverConnectionError ??
                  (_serverConnectionCheckedAt == null
                      ? '確認していません'
                      : '最終確認: ${DateFormat('yyyy/MM/dd HH:mm:ss').format(_serverConnectionCheckedAt!.toLocal())}'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: '接続状態を確認',
              onPressed: _isCheckingServerConnection
                  ? null
                  : _checkServerConnection,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountAvatar(AppUser user) {
    return CircleAvatar(
      backgroundImage: user.photoUrl == null
          ? null
          : NetworkImage(user.photoUrl!),
      child: user.photoUrl == null
          ? Text(
              user.email.isEmpty
                  ? '?'
                  : user.email.substring(0, 1).toUpperCase(),
            )
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
                  _buildAccountSection(isDark),
                  const SizedBox(height: 32),
                  _buildServerConnectionSection(),
                  if (!kIsWeb) ...[
                    const SizedBox(height: 32),
                    _buildBackupSection(isDark),
                  ],
                  if (_isDesktop) ...[
                    const SizedBox(height: 32),
                    const Text(
                      'ウィンドウを閉じたとき',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '閉じるボタンを押したときの動作を選択できます',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: desktopCloseToTrayNotifier,
                      builder: (context, closeToTray, child) =>
                          RadioGroup<bool>(
                            groupValue: closeToTray,
                            onChanged: (value) {
                              if (value != null) _changeCloseToTray(value);
                            },
                            child: const Column(
                              children: [
                                RadioListTile<bool>(
                                  contentPadding: EdgeInsets.zero,
                                  value: false,
                                  title: Text('アプリを終了する'),
                                  subtitle: Text('閉じるとアプリを終了します'),
                                ),
                                RadioListTile<bool>(
                                  contentPadding: EdgeInsets.zero,
                                  value: true,
                                  title: Text('タスクトレイに格納する'),
                                  subtitle: Text('アプリを終了せず、タスクトレイから再表示できます'),
                                ),
                              ],
                            ),
                          ),
                    ),
                  ],
                  if (_supportsStartup) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'スタートアップ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'OSへのサインイン時にアプリを起動します',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: desktopStartupNotifier,
                      builder: (context, enabled, child) => SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('OSとともに起動する'),
                        value: enabled,
                        onChanged: _changeStartup,
                      ),
                    ),
                  ],
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

  Widget _buildBackupSection(bool isDark) {
    final latestBackup = _latestBackup;
    final userId = AuthService.instance.currentUser?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ローカルバックアップ',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'タスクとテーマ設定をこの端末に保存します。アカウントごとに分けて保存されます。',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('毎日自動バックアップ'),
          subtitle: const Text('タスクを読み込んだとき、1日1回バックアップします'),
          value: _dailyBackupEnabled,
          onChanged: _isLoadingBackupSettings ? null : _changeDailyBackup,
        ),
        InputDecorator(
          decoration: const InputDecoration(labelText: '保持期間'),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _backupRetentionDays,
              isExpanded: true,
              items: BackupService.retentionOptions
                  .map(
                    (days) => DropdownMenuItem<int>(
                      value: days,
                      child: Text('$days日'),
                    ),
                  )
                  .toList(),
              onChanged: _isLoadingBackupSettings
                  ? null
                  : (days) {
                      if (days != null) _changeBackupRetention(days);
                    },
            ),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.backup_outlined),
          title: const Text('最新のバックアップ'),
          subtitle: Text(
            latestBackup == null
                ? 'まだ作成されていません'
                : DateFormat.yMd().add_Hm().format(latestBackup.toLocal()),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _isCreatingBackup || _isRestoringBackup || userId == null
                ? null
                : _createBackupNow,
            icon: _isCreatingBackup
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt),
            label: const Text('今すぐバックアップ'),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _isRestoringBackup || _isCreatingBackup
                  ? null
                  : _pickBackupFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('JSONファイルから復元'),
            ),
            OutlinedButton.icon(
              onPressed: _isRestoringBackup || _isCreatingBackup
                  ? null
                  : _chooseSavedBackup,
              icon: const Icon(Icons.history),
              label: const Text('保存済みバックアップから復元'),
            ),
          ],
        ),
        if (_isRestoringBackup)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
      ],
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
