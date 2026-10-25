import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:motchiy_todo/models/task.dart';
import 'package:motchiy_todo/services/backup_storage_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory rootDirectory;
  late FileBackupStorage service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    rootDirectory = await Directory.systemTemp.createTemp(
      'motchiy-backup-test-',
    );
    service = FileBackupStorage(rootDirectory: rootDirectory);
  });

  tearDown(() async {
    if (await rootDirectory.exists()) {
      await rootDirectory.delete(recursive: true);
    }
  });

  test('creates daily backups once per user and local day', () async {
    final tasks = [Task(id: 'task-1', title: 'Important task')];

    await service.createDailyBackup('user-1', tasks);
    await service.createDailyBackup('user-1', tasks);
    await service.createDailyBackup('user-2', tasks);

    final userOneDirectory = Directory(
      '${rootDirectory.path}${Platform.pathSeparator}motchiy_todo_backups'
      '${Platform.pathSeparator}user-1',
    );
    final userTwoDirectory = Directory(
      '${rootDirectory.path}${Platform.pathSeparator}motchiy_todo_backups'
      '${Platform.pathSeparator}user-2',
    );
    final userOneFiles = await userOneDirectory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    final userTwoFiles = await userTwoDirectory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    expect(userOneFiles, hasLength(1));
    expect(userTwoFiles, hasLength(1));

    final contents =
        jsonDecode(await userOneFiles.single.readAsString()) as Map;
    expect(contents['userId'], 'user-1');
    expect(contents['tasks'][0]['title'], 'Important task');
    expect(contents['settings']['themeColorIndex'], 0);
  });

  test('retention changes remove only expired backup files', () async {
    final userDirectory = Directory(
      '${rootDirectory.path}${Platform.pathSeparator}motchiy_todo_backups'
      '${Platform.pathSeparator}user-1',
    );
    await userDirectory.create(recursive: true);
    final expiredBackup = File(
      '${userDirectory.path}${Platform.pathSeparator}backup_old.json',
    );
    final retainedBackup = File(
      '${userDirectory.path}${Platform.pathSeparator}backup_recent.json',
    );
    final unrelatedFile = File(
      '${userDirectory.path}${Platform.pathSeparator}notes.json',
    );
    await expiredBackup.writeAsString('{}');
    await retainedBackup.writeAsString('{}');
    await unrelatedFile.writeAsString('{}');
    final now = DateTime.now();
    await expiredBackup.setLastModified(now.subtract(const Duration(days: 10)));
    await retainedBackup.setLastModified(now.subtract(const Duration(days: 2)));
    await unrelatedFile.setLastModified(now.subtract(const Duration(days: 10)));

    await service.setRetentionDays(7);

    expect(await expiredBackup.exists(), isFalse);
    expect(await retainedBackup.exists(), isTrue);
    expect(await unrelatedFile.exists(), isTrue);
  });

  test(
    'daily backups can be disabled while manual backups remain available',
    () async {
      await service.setDailyEnabled(false);

      await service.createDailyBackup('user-1', []);
      await service.createBackup('user-1', []);
      final backupDirectory = Directory(
        '${rootDirectory.path}${Platform.pathSeparator}motchiy_todo_backups'
        '${Platform.pathSeparator}user-1',
      );
      final backups = await backupDirectory
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      expect(backups, hasLength(1));
    },
  );

  test('expired backups are pruned when daily backups are disabled', () async {
    final userDirectory = Directory(
      '${rootDirectory.path}${Platform.pathSeparator}motchiy_todo_backups'
      '${Platform.pathSeparator}user-1',
    );
    await userDirectory.create(recursive: true);
    final expiredBackup = File(
      '${userDirectory.path}${Platform.pathSeparator}backup_old.json',
    );
    await expiredBackup.writeAsString('{}');
    await expiredBackup.setLastModified(
      DateTime.now().subtract(const Duration(days: 31)),
    );
    await service.setDailyEnabled(false);

    await service.createDailyBackup('user-1', []);
    expect(await expiredBackup.exists(), isFalse);
  });
}
