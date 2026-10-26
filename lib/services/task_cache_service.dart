import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/task.dart';

class TaskCacheService {
  TaskCacheService._();

  static final instance = TaskCacheService._();

  String _tasksKey(String userId) => 'tasks_${Uri.encodeComponent(userId)}';

  String _pendingSyncKey(String userId) => '${_tasksKey(userId)}_sync_pending';

  Future<List<Task>?> readTasks(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKey = _tasksKey(userId);
    var encoded = prefs.getString(scopedKey);
    if (encoded == null) {
      encoded = prefs.getString('tasks_key');
      if (encoded == null) return null;
      final tasks = _decodeTasks(encoded);
      await prefs.setString(scopedKey, encoded);
      await prefs.remove('tasks_key');
      return tasks;
    }
    return _decodeTasks(encoded);
  }

  Future<void> saveLocalTasks(String userId, List<Task> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _tasksKey(userId),
      jsonEncode(tasks.map((task) => task.toJson()).toList()),
    );
    await prefs.setBool(_pendingSyncKey(userId), true);
  }

  Future<void> saveRemoteTasks(String userId, List<Task> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _tasksKey(userId),
      jsonEncode(tasks.map((task) => task.toJson()).toList()),
    );
    await prefs.remove(_pendingSyncKey(userId));
  }

  Future<void> markSynced(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingSyncKey(userId));
  }

  Future<bool> hasPendingSync(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pendingSyncKey(userId)) ?? false;
  }

  Future<void> clearTasks(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tasksKey(userId));
    await prefs.remove(_pendingSyncKey(userId));
  }

  Future<void> migrateUserId(String oldUserId, String newUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final oldTasksKey = _tasksKey(oldUserId);
    final newTasksKey = _tasksKey(newUserId);
    if (!prefs.containsKey(newTasksKey) && prefs.containsKey(oldTasksKey)) {
      final tasks = prefs.getString(oldTasksKey);
      if (tasks != null) await prefs.setString(newTasksKey, tasks);
      if (prefs.getBool(_pendingSyncKey(oldUserId)) ?? false) {
        await prefs.setBool(_pendingSyncKey(newUserId), true);
      }
      await prefs.remove(oldTasksKey);
      await prefs.remove(_pendingSyncKey(oldUserId));
    }
  }

  List<Task> mergeTasks(List<Task> preferred, List<Task> preserved) {
    final merged = List<Task>.of(preferred);
    final tasksById = <String, Task>{for (final task in merged) task.id: task};
    for (final task in preserved) {
      final existing = tasksById[task.id];
      if (existing == null) {
        merged.add(task);
        tasksById[task.id] = task;
        continue;
      }
      if (jsonEncode(existing.toJson()) == jsonEncode(task.toJson())) continue;

      final baseId = '${task.id}_preserved';
      var preservedId = baseId;
      var suffix = 2;
      while (tasksById.containsKey(preservedId)) {
        final candidate = tasksById[preservedId]!;
        if (jsonEncode(candidate.toJson()) ==
            jsonEncode({...task.toJson(), 'id': preservedId})) {
          preservedId = '';
          break;
        }
        preservedId = '${baseId}_${suffix++}';
      }
      if (preservedId.isEmpty) continue;
      final preservedTask = Task.fromJson({
        ...task.toJson(),
        'id': preservedId,
      });
      merged.add(preservedTask);
      tasksById[preservedId] = preservedTask;
    }
    return merged;
  }

  bool sameTasks(List<Task> left, List<Task> right) =>
      jsonEncode(left.map((task) => task.toJson()).toList()) ==
      jsonEncode(right.map((task) => task.toJson()).toList());

  List<Task> _decodeTasks(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      throw const FormatException('Saved tasks must be a list.');
    }
    return decoded.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Saved task has an invalid format.');
      }
      return Task.fromJson(item);
    }).toList();
  }
}
