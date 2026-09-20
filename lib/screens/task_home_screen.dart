import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/task.dart';

class TaskHomeScreen extends StatefulWidget {
  const TaskHomeScreen({super.key});

  @override
  State<TaskHomeScreen> createState() => TaskHomeScreenState();
}

class TaskHomeScreenState extends State<TaskHomeScreen> {
  List<Task> _tasks = [];
  bool _isLoading = true;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    for (var node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  TextEditingController _getController(Task task) {
    if (!_controllers.containsKey(task.id)) {
      final controller = TextEditingController(text: task.title);
      controller.addListener(() {
        if (task.title != controller.text) {
          task.title = controller.text;
          _saveTasks();
        }
      });
      _controllers[task.id] = controller;
    } else {
      if (_controllers[task.id]!.text != task.title) {
        _controllers[task.id]!.text = task.title;
      }
    }
    return _controllers[task.id]!;
  }

  FocusNode _getFocusNode(Task task) {
    if (!_focusNodes.containsKey(task.id)) {
      final node = FocusNode();
      node.addListener(() {
        if (!node.hasFocus) {
          final controller = _controllers[task.id];
          if (controller != null && controller.text != task.title) {
            setState(() {
              task.title = controller.text;
            });
            _saveTasks();
          }

          if (task.title.trim().isEmpty && _tasks.length > 1) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted &&
                  _tasks.contains(task) &&
                  task.title.trim().isEmpty &&
                  _tasks.length > 1) {
                _deleteTask(task);
              }
            });
          }
        }
      });
      _focusNodes[task.id] = node;
    }
    return _focusNodes[task.id]!;
  }

  Future<void> loadTasks() => _loadTasks();

  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? tasksString = prefs.getString('tasks_key');
    if (tasksString != null) {
      try {
        final List<dynamic> decoded = jsonDecode(tasksString);
        setState(() {
          _tasks = decoded.map((item) => Task.fromJson(item)).toList();
          _isLoading = false;
        });
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
      }
    } else {
      setState(() {
        _tasks = [
          Task(id: DateTime.now().millisecondsSinceEpoch.toString(), title: ''),
        ];
        _isLoading = false;
      });
    }
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_tasks.map((t) => t.toJson()).toList());
    await prefs.setString('tasks_key', encoded);
  }

  void _insertTaskBelow(Task currentTask) {
    final index = _tasks.indexWhere((t) => t.id == currentTask.id);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final newTask = Task(id: '${timestamp}_${_tasks.length}', title: '');
    setState(() {
      if (index != -1 && index < _tasks.length - 1) {
        _tasks.insert(index + 1, newTask);
      } else {
        _tasks.add(newTask);
      }
    });
    _saveTasks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getFocusNode(newTask).requestFocus();
    });
  }

  void _addTaskAtEnd() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final newTask = Task(id: '${timestamp}_${_tasks.length}', title: '');
    setState(() {
      _tasks.add(newTask);
    });
    _saveTasks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getFocusNode(newTask).requestFocus();
    });
  }

  void _insertNewline(Task task) {
    final controller = _getController(task);
    final text = controller.text;
    final selection = controller.selection;

    if (selection.isValid) {
      final newText = text.replaceRange(selection.start, selection.end, '\n');
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + 1),
      );
    } else {
      controller.text = '$text\n';
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
    }
  }

  bool _isTaskActive(Task task) {
    if (task.isCompleted) return true;
    if (task.startDate == null) return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(
      task.startDate!.year,
      task.startDate!.month,
      task.startDate!.day,
    );
    return !start.isAfter(today);
  }

  List<Task> _getCompletedTasks() {
    final completed = _tasks.where((t) => t.isCompleted).toList();
    completed.sort(
      (a, b) => (b.completedAt ?? DateTime(0)).compareTo(
        a.completedAt ?? DateTime(0),
      ),
    );
    return completed;
  }

  void _focusPreviousTask(Task task) {
    final uncompleted = _tasks.where((t) => !t.isCompleted).toList();
    final completed = _getCompletedTasks();
    final list = [...uncompleted, ...completed];
    final index = list.indexWhere((t) => t.id == task.id);
    if (index > 0) {
      _getFocusNode(list[index - 1]).requestFocus();
    }
  }

  void _focusNextTask(Task task) {
    final uncompleted = _tasks.where((t) => !t.isCompleted).toList();
    final completed = _getCompletedTasks();
    final list = [...uncompleted, ...completed];
    final index = list.indexWhere((t) => t.id == task.id);
    if (index != -1 && index < list.length - 1) {
      _getFocusNode(list[index + 1]).requestFocus();
    }
  }

  void _toggleTaskCompletion(Task task) {
    setState(() {
      task.isCompleted = !task.isCompleted;
      if (task.isCompleted) {
        task.completedAt = DateTime.now();
      } else {
        task.completedAt = null;
      }
    });
    _saveTasks();
  }

  void _deleteTask(Task task) {
    final uncompleted = _tasks.where((t) => !t.isCompleted).toList();
    final completed = _getCompletedTasks();
    final list = [...uncompleted, ...completed];
    final index = list.indexWhere((t) => t.id == task.id);

    setState(() {
      _tasks.removeWhere((t) => t.id == task.id);
      _controllers.remove(task.id)?.dispose();
      _focusNodes.remove(task.id)?.dispose();
    });
    _saveTasks();

    if (_tasks.isEmpty) {
      _addTaskAtEnd();
    } else if (index > 0) {
      final newList = [
        ..._tasks.where((t) => !t.isCompleted),
        ..._getCompletedTasks(),
      ];
      if (newList.isNotEmpty) {
        final targetIndex = (index - 1 < newList.length)
            ? index - 1
            : newList.length - 1;
        _getFocusNode(newList[targetIndex]).requestFocus();
      }
    }
  }

  Future<void> _selectDueDate(Task task) async {
    final initialDate = task.dueDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        task.dueDate = picked;
        task.hasDueDate = true;
      });
      _saveTasks();
    }
  }

  Widget _buildTaskRow(Task task) {
    final controller = _getController(task);
    final focusNode = _getFocusNode(task);

    return Container(
      key: Key(task.id),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: task.isCompleted,
            shape: const CircleBorder(),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (val) {
              _toggleTaskCompletion(task);
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        _focusPreviousTask(task);
                        return KeyEventResult.handled;
                      } else if (event.logicalKey ==
                          LogicalKeyboardKey.arrowDown) {
                        _focusNextTask(task);
                        return KeyEventResult.handled;
                      } else if (event.logicalKey ==
                              LogicalKeyboardKey.backspace &&
                          task.title.isEmpty &&
                          _tasks.length > 1) {
                        _deleteTask(task);
                        return KeyEventResult.handled;
                      } else if (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                        if (HardwareKeyboard.instance.isShiftPressed) {
                          _insertNewline(task);
                          return KeyEventResult.handled;
                        } else {
                          _insertTaskBelow(task);
                          return KeyEventResult.handled;
                        }
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    maxLines: null,
                    onChanged: (value) {
                      task.title = value;
                      _saveTasks();
                    },
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 2),
                      hintText: 'タスクを入力...',
                    ),
                    style: TextStyle(
                      decoration: task.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                      color: task.isCompleted ? Colors.grey : null,
                    ),
                  ),
                ),
                if (task.dueDate != null || task.startDate != null) ...[
                  Padding(
                    padding: EdgeInsets.zero,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => _selectDueDate(task),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 1,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.track_changes,
                                  size: 12,
                                  color: task.isCompleted
                                      ? Colors.grey.withValues(alpha: 0.5)
                                      : Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  (task.startDate != null &&
                                          task.dueDate != null &&
                                          task.startDate != task.dueDate)
                                      ? '${task.startDate!.month}/${task.startDate!.day} 〜 ${task.dueDate!.month}/${task.dueDate!.day}'
                                      : '${(task.dueDate ?? task.startDate)!.year}/${(task.dueDate ?? task.startDate)!.month.toString().padLeft(2, '0')}/${(task.dueDate ?? task.startDate)!.day.toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: task.isCompleted
                                        ? Colors.grey.withValues(alpha: 0.5)
                                        : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (!task.isCompleted) ...[
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () {
                              setState(() {
                                task.startDate = null;
                                task.dueDate = null;
                                task.hasDueDate = false;
                              });
                              _saveTasks();
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.close,
                                size: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.track_changes, size: 18, color: Colors.grey),
            onPressed: () => _selectDueDate(task),
            tooltip: task.dueDate != null ? '期限を変更' : '期限を追加',
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18, color: Colors.grey),
            onPressed: () => _deleteTask(task),
            tooltip: '削除',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uncompletedTasks = _tasks
        .where((t) => !t.isCompleted && _isTaskActive(t))
        .toList();
    final completedTasks = _getCompletedTasks();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: SafeArea(
        top: true,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...uncompletedTasks.map(
                            (task) => _buildTaskRow(task),
                          ),
                          if (completedTasks.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text(
                                '完了済み',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            ...completedTasks.map(
                              (task) => _buildTaskRow(task),
                            ),
                          ],
                          SizedBox(
                            height: 200,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onDoubleTap: _addTaskAtEnd,
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
