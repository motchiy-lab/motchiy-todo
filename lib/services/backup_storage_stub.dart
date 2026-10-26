import '../models/task.dart';
import 'backup_storage.dart';

BackupStorage createBackupStorage() => _UnsupportedBackupStorage();

class _UnsupportedBackupStorage implements BackupStorage {
  @override
  Future<BackupSettings> getSettings() async =>
      const BackupSettings(dailyEnabled: false, retentionDays: 30);

  @override
  Future<void> setDailyEnabled(bool enabled) async {
    throw UnsupportedError('Local backups are not supported on this platform.');
  }

  @override
  Future<void> setRetentionDays(int days) async {
    throw UnsupportedError('Local backups are not supported on this platform.');
  }

  @override
  Future<void> createDailyBackup(String userId, List<Task> tasks) async {
    throw UnsupportedError('Local backups are not supported on this platform.');
  }

  @override
  Future<void> createBackup(String userId, List<Task> tasks) async {
    throw UnsupportedError('Local backups are not supported on this platform.');
  }

  @override
  Future<DateTime?> latestBackupTime(String userId) async => null;

  @override
  Future<List<BackupFile>> listBackups(String userId) async => [];

  @override
  Future<String> readBackup(String path) async {
    throw UnsupportedError('Local backups are not supported on this platform.');
  }
}
