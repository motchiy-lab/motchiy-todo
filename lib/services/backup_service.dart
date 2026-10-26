import 'dart:convert';

import '../models/task.dart';
import 'backup_storage.dart';
import 'backup_storage_stub.dart'
    if (dart.library.io) 'backup_storage_io.dart'
    as local_storage;

class BackupDocument {
  const BackupDocument({required this.tasks, this.settings});

  final List<Task> tasks;
  final Map<String, Object?>? settings;
}

class BackupService {
  BackupService({BackupStorage? storage})
    : _storage = storage ?? local_storage.createBackupStorage();

  static final instance = BackupService();
  static const retentionOptions = backupRetentionOptions;

  final BackupStorage _storage;

  Future<BackupSettings> getSettings() => _storage.getSettings();

  Future<void> setDailyEnabled(bool enabled) =>
      _storage.setDailyEnabled(enabled);

  Future<void> setRetentionDays(int days) => _storage.setRetentionDays(days);

  Future<void> createDailyBackup(String userId, List<Task> tasks) =>
      _storage.createDailyBackup(userId, tasks);

  Future<void> createBackup(String userId, List<Task> tasks) =>
      _storage.createBackup(userId, tasks);

  Future<DateTime?> latestBackupTime(String userId) =>
      _storage.latestBackupTime(userId);

  Future<List<BackupFile>> listBackups(String userId) =>
      _storage.listBackups(userId);

  Future<String> readBackup(String path) => _storage.readBackup(path);

  static BackupDocument decodeBackup(String contents) {
    final decoded = jsonDecode(contents);
    Object? rawTasks;
    Map<String, Object?>? settings;
    if (decoded is List) {
      rawTasks = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final version = decoded['formatVersion'];
      if (version != null && version != 1) {
        throw const FormatException('このバックアップ形式には対応していません。');
      }
      rawTasks = decoded['tasks'];
      final rawSettings = decoded['settings'];
      if (rawSettings != null) {
        if (rawSettings is! Map<String, dynamic>) {
          throw const FormatException('バックアップの設定データが不正です。');
        }
        settings = rawSettings;
      }
    }
    if (rawTasks is! List) {
      throw const FormatException('JSONに予定一覧がありません。');
    }
    final tasks = <Task>[];
    final ids = <String>{};
    for (final item in rawTasks) {
      if (item is! Map<String, dynamic> ||
          item['id'] is! String ||
          item['title'] is! String ||
          (item['description'] != null && item['description'] is! String) ||
          (item['isCompleted'] != null && item['isCompleted'] is! bool) ||
          (item['hasDueDate'] != null && item['hasDueDate'] is! bool) ||
          !_isValidDate(item['startDate']) ||
          !_isValidDate(item['dueDate']) ||
          !_isValidDate(item['completedAt'])) {
        throw const FormatException('予定データの形式が不正です。');
      }
      final task = Task.fromJson(item);
      if (task.id.isEmpty || !ids.add(task.id)) {
        throw const FormatException('予定IDが空、または重複しています。');
      }
      tasks.add(task);
    }
    if (settings != null) {
      if (settings['themeColorIndex'] != null &&
          settings['themeColorIndex'] is! int) {
        throw const FormatException('テーマ設定データが不正です。');
      }
      if (settings['themeModeIndex'] != null &&
          settings['themeModeIndex'] is! int) {
        throw const FormatException('テーマ設定データが不正です。');
      }
      if (settings['enableTabAnimations'] != null &&
          settings['enableTabAnimations'] is! bool) {
        throw const FormatException('テーマ設定データが不正です。');
      }
    }
    return BackupDocument(tasks: tasks, settings: settings);
  }

  static bool _isValidDate(Object? value) =>
      value == null || (value is String && DateTime.tryParse(value) != null);
}
