import '../models/task.dart';
import 'backup_storage.dart';
import 'backup_storage_stub.dart'
    if (dart.library.io) 'backup_storage_io.dart'
    as local_storage;

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
}
