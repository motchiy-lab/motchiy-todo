import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/task.dart';
import 'backup_storage.dart';

BackupStorage createBackupStorage() => FileBackupStorage();

class FileBackupStorage implements BackupStorage {
  FileBackupStorage({this.rootDirectory});

  static const _dailyEnabledKey = 'daily_backup_enabled';
  static const _retentionDaysKey = 'backup_retention_days';

  final Directory? rootDirectory;

  @override
  Future<BackupSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final retentionDays = prefs.getInt(_retentionDaysKey) ?? 30;
    return BackupSettings(
      dailyEnabled: prefs.getBool(_dailyEnabledKey) ?? true,
      retentionDays: backupRetentionOptions.contains(retentionDays)
          ? retentionDays
          : 30,
    );
  }

  @override
  Future<void> setDailyEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dailyEnabledKey, enabled);
  }

  @override
  Future<void> setRetentionDays(int days) async {
    if (!backupRetentionOptions.contains(days)) {
      throw ArgumentError.value(days, 'days', 'Unsupported retention period');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_retentionDaysKey, days);
    await _pruneExpiredBackups(days);
  }

  @override
  Future<void> createDailyBackup(String userId, List<Task> tasks) async {
    final settings = await getSettings();
    await _pruneExpiredBackups(settings.retentionDays);
    if (!settings.dailyEnabled) return;

    final directory = await _userBackupDirectory(userId);
    final now = DateTime.now();
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File &&
          _isBackupFile(entity.path) &&
          _sameLocalDay(await entity.lastModified(), now)) {
        return;
      }
    }
    await createBackup(userId, tasks);
  }

  @override
  Future<void> createBackup(String userId, List<Task> tasks) async {
    final settings = await getSettings();
    final directory = await _userBackupDirectory(userId);
    final now = DateTime.now().toUtc();
    final prefs = await SharedPreferences.getInstance();
    final backup = <String, Object?>{
      'formatVersion': 1,
      'userId': userId,
      'createdAt': now.toIso8601String(),
      'tasks': tasks.map((task) => task.toJson()).toList(),
      'settings': {
        'themeColorIndex': prefs.getInt('theme_color_index') ?? 0,
        'themeModeIndex': prefs.getInt('theme_mode_index') ?? 0,
        'enableTabAnimations': prefs.getBool('enable_tab_animations') ?? true,
      },
    };
    final timestamp = now.toIso8601String().replaceAll(':', '-');
    final file = File(
      '${directory.path}${Platform.pathSeparator}backup_$timestamp.json',
    );
    final temporaryFile = File('${file.path}.tmp');
    try {
      await temporaryFile.writeAsString(jsonEncode(backup), flush: true);
      await temporaryFile.rename(file.path);
    } catch (_) {
      if (await temporaryFile.exists()) await temporaryFile.delete();
      rethrow;
    } finally {
      await _pruneExpiredBackups(settings.retentionDays);
    }
  }

  @override
  Future<DateTime?> latestBackupTime(String userId) async {
    final directory = await _userBackupDirectory(userId);
    DateTime? latest;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !_isBackupFile(entity.path)) continue;
      final modified = await entity.lastModified();
      if (latest == null || modified.isAfter(latest)) latest = modified;
    }
    return latest;
  }

  Future<Directory> _userBackupDirectory(String userId) async {
    final root = rootDirectory ?? await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}motchiy_todo_backups'
      '${Platform.pathSeparator}${Uri.encodeComponent(userId)}',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> _pruneExpiredBackups(int retentionDays) async {
    final root = rootDirectory ?? await getApplicationSupportDirectory();
    final backupRoot = Directory(
      '${root.path}${Platform.pathSeparator}motchiy_todo_backups',
    );
    if (!await backupRoot.exists()) return;
    final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
    await for (final entity in backupRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !_isBackupFile(entity.path)) continue;
      if ((await entity.lastModified()).isBefore(cutoff)) {
        await entity.delete();
      }
    }
  }

  bool _isBackupFile(String path) =>
      path.toLowerCase().endsWith('.json') &&
      path.split(Platform.pathSeparator).last.startsWith('backup_');

  bool _sameLocalDay(DateTime left, DateTime right) {
    final localLeft = left.toLocal();
    final localRight = right.toLocal();
    return localLeft.year == localRight.year &&
        localLeft.month == localRight.month &&
        localLeft.day == localRight.day;
  }
}
