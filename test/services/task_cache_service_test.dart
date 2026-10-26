import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:motchiy_todo/models/task.dart';
import 'package:motchiy_todo/services/task_cache_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('migrates the legacy task cache to one user only', () async {
    final task = Task(id: 'task-1', title: 'Keep this task');
    SharedPreferences.setMockInitialValues({
      'tasks_key': jsonEncode([task.toJson()]),
    });
    final cache = TaskCacheService.instance;

    final firstUserTasks = await cache.readTasks('first-user');
    final secondUserTasks = await cache.readTasks('second-user');

    expect(firstUserTasks?.single.title, 'Keep this task');
    expect(secondUserTasks, isNull);
  });

  test('tracks local changes until they have been synced', () async {
    final cache = TaskCacheService.instance;
    final tasks = [Task(id: 'task-1', title: 'Offline task')];

    await cache.saveLocalTasks('user-1', tasks);
    expect(await cache.hasPendingSync('user-1'), isTrue);
    expect((await cache.readTasks('user-1'))?.single.title, 'Offline task');

    await cache.markSynced('user-1');
    expect(await cache.hasPendingSync('user-1'), isFalse);
  });

  test('merges different task sets without dropping conflicting versions', () {
    final cache = TaskCacheService.instance;
    final remote = [
      Task(id: 'shared', title: 'Server version'),
      Task(id: 'remote-only', title: 'Server only'),
    ];
    final local = [
      Task(id: 'shared', title: 'Local version'),
      Task(id: 'local-only', title: 'Local only'),
    ];

    final merged = cache.mergeTasks(remote, local);

    expect(merged.map((task) => task.title), [
      'Server version',
      'Server only',
      'Local version',
      'Local only',
    ]);
    expect(merged[2].id, 'shared_preserved');
    expect(cache.sameTasks(merged, cache.mergeTasks(merged, local)), isTrue);
  });
}
