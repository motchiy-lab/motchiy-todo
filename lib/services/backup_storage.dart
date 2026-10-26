import '../models/task.dart';

const backupRetentionOptions = [7, 30, 90, 180, 365];

class BackupFile {
  const BackupFile({required this.path, required this.modifiedAt});

  final String path;
  final DateTime modifiedAt;
}

class BackupSettings {
  const BackupSettings({
    required this.dailyEnabled,
    required this.retentionDays,
  });

  final bool dailyEnabled;
  final int retentionDays;
}

abstract interface class BackupStorage {
  Future<BackupSettings> getSettings();

  Future<void> setDailyEnabled(bool enabled);

  Future<void> setRetentionDays(int days);

  Future<void> createDailyBackup(String userId, List<Task> tasks);

  Future<void> createBackup(String userId, List<Task> tasks);

  Future<DateTime?> latestBackupTime(String userId);

  Future<List<BackupFile>> listBackups(String userId);

  Future<String> readBackup(String path);
}
