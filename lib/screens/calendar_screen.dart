import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/task.dart';

extension DateTimeExt on DateTime {
  bool atSameDayAs(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  List<Task> _tasks = [];
  bool _isLoading = true;
  bool _showHint = true;
  late DateTime _currentMonth;
  late DateTime _selectedDate;

  // Drag selection state
  final GlobalKey _gridKey = GlobalKey();
  DateTime? _dragStartDate;
  DateTime? _dragEndDate;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month, 1);
    _selectedDate = DateTime(now.year, now.month, now.day);
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final bool hintDismissed =
        prefs.getBool('calendar_hint_dismissed') ?? false;
    final String? tasksString = prefs.getString('tasks_key');
    List<Task> loadedTasks = [];
    if (tasksString != null) {
      try {
        final List<dynamic> decoded = jsonDecode(tasksString);
        loadedTasks = decoded.map((item) => Task.fromJson(item)).toList();
      } catch (e) {
        // ignore
      }
    }
    setState(() {
      _showHint = !hintDismissed;
      _tasks = loadedTasks;
      _isLoading = false;
    });
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_tasks.map((t) => t.toJson()).toList());
    await prefs.setString('tasks_key', encoded);
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    });
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _currentMonth = DateTime(now.year, now.month, 1);
      _selectedDate = DateTime(now.year, now.month, now.day);
    });
  }

  List<Map<String, dynamic>> _getGridDays() {
    final firstDayOfMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month,
      1,
    );
    final firstWeekday = firstDayOfMonth.weekday % 7;
    final daysInMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + 1,
      0,
    ).day;
    final daysInPrevMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month,
      0,
    ).day;

    List<Map<String, dynamic>> gridDays = [];

    for (int i = firstWeekday - 1; i >= 0; i--) {
      final day = daysInPrevMonth - i;
      final date = DateTime(_currentMonth.year, _currentMonth.month - 1, day);
      gridDays.add({'date': date, 'isCurrentMonth': false});
    }

    for (int i = 1; i <= daysInMonth; i++) {
      final date = DateTime(_currentMonth.year, _currentMonth.month, i);
      gridDays.add({'date': date, 'isCurrentMonth': true});
    }

    final totalCells = 42; // 常に6週間（42セル）固定にして高さを一定にする
    final remainingDays = totalCells - gridDays.length;
    for (int i = 1; i <= remainingDays; i++) {
      final date = DateTime(_currentMonth.year, _currentMonth.month + 1, i);
      gridDays.add({'date': date, 'isCurrentMonth': false});
    }

    return gridDays;
  }

  bool _isTaskOnDate(Task task, DateTime date) {
    final start = task.startDate ?? task.dueDate;
    final end = task.dueDate ?? task.startDate;
    if (start == null || end == null) return false;

    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);

    return !d.isBefore(s) && !d.isAfter(e);
  }

  List<Task> _getTasksForDate(DateTime date) {
    return _tasks.where((task) => _isTaskOnDate(task, date)).toList();
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
    setState(() {
      _tasks.removeWhere((t) => t.id == task.id);
    });
    _saveTasks();
  }

  Future<void> _createTaskForRange(DateTime start, DateTime end) async {
    final normalizedStart = DateTime(start.year, start.month, start.day);
    final normalizedEnd = DateTime(end.year, end.month, end.day);

    final actualStart = normalizedStart.isBefore(normalizedEnd)
        ? normalizedStart
        : normalizedEnd;
    final actualEnd = normalizedEnd.isAfter(normalizedStart)
        ? normalizedEnd
        : normalizedStart;

    final controller = TextEditingController();
    final dateStr = actualStart == actualEnd
        ? '${actualStart.year}年${actualStart.month}月${actualStart.day}日'
        : '${actualStart.month}/${actualStart.day} 〜 ${actualEnd.month}/${actualEnd.day}';

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$dateStr のタスクを追加', style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'タスク名を入力...',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final newTask = Task(
        id: '${timestamp}_${_tasks.length}',
        title: result.trim(),
        startDate: actualStart,
        dueDate: actualEnd,
        hasDueDate: true,
      );
      setState(() {
        _tasks.add(newTask);
        _selectedDate = actualStart;
      });
      _saveTasks();
    }
  }

  DateTime? _getDateFromLocalPosition(
    Offset localPos,
    List<Map<String, dynamic>> gridDays,
  ) {
    final RenderBox? box =
        _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;

    final width = box.size.width;
    final height = box.size.height;
    final numRows = gridDays.length ~/ 7;
    final colWidth = width / 7;
    final rowHeight = height / numRows;

    final col = (localPos.dx / colWidth).floor().clamp(0, 6);
    final row = (localPos.dy / rowHeight).floor().clamp(0, numRows - 1);

    final index = row * 7 + col;
    if (index >= 0 && index < gridDays.length) {
      return gridDays[index]['date'] as DateTime;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gridDays = _getGridDays();
    final selectedDateTasks = _getTasksForDate(_selectedDate);

    return SafeArea(
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 750),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Year/Month & Controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_currentMonth.year}年 ${_currentMonth.month}月',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Row(
                            children: [
                              OutlinedButton(
                                onPressed: _goToToday,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  '今日',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.chevron_left),
                                onPressed: _previousMonth,
                                tooltip: '前の月',
                              ),
                              IconButton(
                                icon: const Icon(Icons.chevron_right),
                                onPressed: _nextMonth,
                                tooltip: '次の月',
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (_showHint) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[850] : Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '💡 ヒント: カレンダー上でドラッグして1日または複数日の予定を追加し、日付をクリックしてその日の予定一覧を表示できます',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.grey[300]
                                        : Colors.grey[700],
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 24,
                                width: 24,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.close, size: 16),
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                  tooltip: '閉じる',
                                  onPressed: () async {
                                    setState(() {
                                      _showHint = false;
                                    });
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setBool(
                                      'calendar_hint_dismissed',
                                      true,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Calendar Card Container with Drag Selection
                      Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              // Weekday Header
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _buildWeekdayLabel('日', Colors.red[400]!),
                                  _buildWeekdayLabel('月', null),
                                  _buildWeekdayLabel('火', null),
                                  _buildWeekdayLabel('水', null),
                                  _buildWeekdayLabel('木', null),
                                  _buildWeekdayLabel('金', null),
                                  _buildWeekdayLabel('土', Colors.blue[400]!),
                                ],
                              ),
                              const Divider(height: 16),

                              // Days Grid with GestureDetector for dragging and single click selection
                              GestureDetector(
                                key: _gridKey,
                                onPanStart: (details) {
                                  final date = _getDateFromLocalPosition(
                                    details.localPosition,
                                    gridDays,
                                  );
                                  if (date != null) {
                                    setState(() {
                                      _isDragging = true;
                                      _dragStartDate = date;
                                      _dragEndDate = date;
                                    });
                                  }
                                },
                                onPanUpdate: (details) {
                                  if (_isDragging) {
                                    final date = _getDateFromLocalPosition(
                                      details.localPosition,
                                      gridDays,
                                    );
                                    if (date != null && date != _dragEndDate) {
                                      setState(() {
                                        _dragEndDate = date;
                                      });
                                    }
                                  }
                                },
                                onPanEnd: (details) {
                                  if (_isDragging &&
                                      _dragStartDate != null &&
                                      _dragEndDate != null) {
                                    final start = _dragStartDate!;
                                    final end = _dragEndDate!;

                                    setState(() {
                                      _isDragging = false;
                                      _dragStartDate = null;
                                      _dragEndDate = null;
                                    });

                                    _createTaskForRange(start, end);
                                  } else {
                                    setState(() {
                                      _isDragging = false;
                                      _dragStartDate = null;
                                      _dragEndDate = null;
                                    });
                                  }
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.grey[800]!
                                          : Colors.grey[350]!,
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: GridView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 7,
                                          childAspectRatio: 1.15,
                                        ),
                                    itemCount: gridDays.length,
                                    itemBuilder: (context, index) {
                                      final item = gridDays[index];
                                      final DateTime date = item['date'];
                                      final bool isCurrentMonth =
                                          item['isCurrentMonth'];

                                      final now = DateTime.now();
                                      final bool isToday =
                                          date.year == now.year &&
                                          date.month == now.month &&
                                          date.day == now.day;

                                      final bool isSelected =
                                          date.year == _selectedDate.year &&
                                          date.month == _selectedDate.month &&
                                          date.day == _selectedDate.day;

                                      // Check if date is within current drag range
                                      bool isInDragRange = false;
                                      if (_isDragging &&
                                          _dragStartDate != null &&
                                          _dragEndDate != null) {
                                        final s =
                                            _dragStartDate!.isBefore(
                                              _dragEndDate!,
                                            )
                                            ? _dragStartDate!
                                            : _dragEndDate!;
                                        final e =
                                            _dragEndDate!.isAfter(
                                              _dragStartDate!,
                                            )
                                            ? _dragEndDate!
                                            : _dragStartDate!;
                                        final dNorm = DateTime(
                                          date.year,
                                          date.month,
                                          date.day,
                                        );
                                        final sNorm = DateTime(
                                          s.year,
                                          s.month,
                                          s.day,
                                        );
                                        final eNorm = DateTime(
                                          e.year,
                                          e.month,
                                          e.day,
                                        );
                                        isInDragRange =
                                            !dNorm.isBefore(sNorm) &&
                                            !dNorm.isAfter(eNorm);
                                      }

                                      final dayTasks = _getTasksForDate(date);

                                      // セルの枠線（格子状）
                                      final borderColor = isDark
                                          ? Colors.grey[800]!
                                          : Colors.grey[300]!;

                                      return InkWell(
                                        onTap: () {
                                          setState(() {
                                            _selectedDate = date;
                                            if (!isCurrentMonth) {
                                              _currentMonth = DateTime(
                                                date.year,
                                                date.month,
                                                1,
                                              );
                                            }
                                          });
                                        },
                                        borderRadius: BorderRadius.circular(2),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: isInDragRange
                                                ? colorScheme.primary
                                                      .withValues(alpha: 0.3)
                                                : (isSelected
                                                      ? colorScheme.primary
                                                            .withValues(
                                                              alpha: 0.15,
                                                            )
                                                      : (isToday
                                                            ? colorScheme
                                                                  .secondaryContainer
                                                                  .withValues(
                                                                    alpha: 0.4,
                                                                  )
                                                            : Colors
                                                                  .transparent)),
                                            border: Border(
                                              right: BorderSide(
                                                color: (index % 7 != 6)
                                                    ? borderColor
                                                    : Colors.transparent,
                                                width: 0.5,
                                              ),
                                              bottom: BorderSide(
                                                color:
                                                    (index <
                                                        gridDays.length - 7)
                                                    ? borderColor
                                                    : Colors.transparent,
                                                width: 0.5,
                                              ),
                                            ),
                                          ),
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                            bottom: 2,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                    ),
                                                child: Align(
                                                  alignment: Alignment.topRight,
                                                  child: Text(
                                                    '${date.day}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          isToday ||
                                                              isSelected ||
                                                              isInDragRange
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                      color: !isCurrentMonth
                                                          ? (isDark
                                                                ? Colors
                                                                      .grey[700]
                                                                : Colors
                                                                      .grey[400])
                                                          : (date.weekday == 7
                                                                ? Colors
                                                                      .red[400]
                                                                : (date.weekday ==
                                                                          6
                                                                      ? Colors
                                                                            .blue[400]
                                                                      : (isDark
                                                                            ? Colors.grey[300]
                                                                            : Colors.grey[750]))),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Expanded(
                                                child: ListView(
                                                  physics:
                                                      const NeverScrollableScrollPhysics(),
                                                  padding: EdgeInsets.zero,
                                                  children: dayTasks.take(3).map((
                                                    task,
                                                  ) {
                                                    final start =
                                                        task.startDate ??
                                                        task.dueDate ??
                                                        date;
                                                    final end =
                                                        task.dueDate ??
                                                        task.startDate ??
                                                        date;

                                                    final dNorm = DateTime(
                                                      date.year,
                                                      date.month,
                                                      date.day,
                                                    );
                                                    final sNorm = DateTime(
                                                      start.year,
                                                      start.month,
                                                      start.day,
                                                    );
                                                    final eNorm = DateTime(
                                                      end.year,
                                                      end.month,
                                                      end.day,
                                                    );

                                                    final bool isStart = dNorm
                                                        .atSameDayAs(sNorm);
                                                    final bool isEnd = dNorm
                                                        .atSameDayAs(eNorm);

                                                    // 日付をまたぐ帯の連続性: 各日の各行でのスロット（タスクの並び順）を固定するための処理
                                                    // 曜日ごとのマージンや隙間をなくし、隣のセルと完全に結合させる
                                                    final bool isWeekStart =
                                                        date.weekday % 7 ==
                                                        0; // 日曜日
                                                    final bool isWeekEnd =
                                                        date.weekday % 7 ==
                                                        6; // 土曜日

                                                    // タスクの開始日または日曜日の場合に左側を丸める
                                                    final bool shouldRoundLeft =
                                                        isStart || isWeekStart;
                                                    // タスクの終了日または土曜日の場合に右側を丸める
                                                    final bool
                                                    shouldRoundRight =
                                                        isEnd || isWeekEnd;

                                                    final borderRadius =
                                                        BorderRadius.horizontal(
                                                          left: shouldRoundLeft
                                                              ? const Radius.circular(
                                                                  4,
                                                                )
                                                              : Radius.zero,
                                                          right:
                                                              shouldRoundRight
                                                              ? const Radius.circular(
                                                                  4,
                                                                )
                                                              : Radius.zero,
                                                        );

                                                    // セル同士の隙間や区切り線をなくし、帯を滑らかに繋げるための調整
                                                    final bool hasLeftCont =
                                                        !(isWeekStart ||
                                                            isStart);
                                                    final bool hasRightCont =
                                                        !(isWeekEnd || isEnd);

                                                    final double leftOffset =
                                                        hasLeftCont
                                                        ? -4.0
                                                        : 4.0;
                                                    final double rightExtra =
                                                        hasRightCont
                                                        ? 4.0
                                                        : 0.0;

                                                    return Transform.translate(
                                                      offset: Offset(
                                                        leftOffset,
                                                        0,
                                                      ),
                                                      child: Container(
                                                        height: 18,
                                                        margin:
                                                            const EdgeInsets.only(
                                                              bottom: 2,
                                                            ),
                                                        padding: EdgeInsets.only(
                                                          left:
                                                              (isWeekStart ||
                                                                  isStart)
                                                              ? 4
                                                              : 0,
                                                          right:
                                                              ((isWeekEnd ||
                                                                      isEnd)
                                                                  ? 4
                                                                  : 0) +
                                                              rightExtra,
                                                        ),
                                                        // 右側のはみ出しを適用
                                                        constraints:
                                                            BoxConstraints(
                                                              minWidth: 0,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              task.isCompleted
                                                              ? Colors.grey
                                                                    .withValues(
                                                                      alpha:
                                                                          0.3,
                                                                    )
                                                              : colorScheme
                                                                    .primary
                                                                    .withValues(
                                                                      alpha:
                                                                          0.85,
                                                                    ),
                                                          borderRadius:
                                                              borderRadius,
                                                        ),
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Text(
                                                          task.title.isEmpty
                                                              ? '無題'
                                                              : task.title,
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: colorScheme
                                                                .onPrimary,
                                                            decoration:
                                                                task.isCompleted
                                                                ? TextDecoration
                                                                      .lineThrough
                                                                : null,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    );
                                                  }).toList(),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      const SizedBox(height: 12),

                      if (selectedDateTasks.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[900] : Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? Colors.grey[800]!
                                  : Colors.grey[300]!,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'この日のタスクはありません',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: selectedDateTasks.length,
                          itemBuilder: (context, index) {
                            final task = selectedDateTasks[index];
                            final rangeStr =
                                (task.startDate != null &&
                                    task.dueDate != null &&
                                    task.startDate != task.dueDate)
                                ? '${task.startDate!.month}/${task.startDate!.day} 〜 ${task.dueDate!.month}/${task.dueDate!.day}'
                                : null;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.grey[800]!
                                      : Colors.grey[300]!,
                                ),
                              ),
                              child: ListTile(
                                leading: Checkbox(
                                  value: task.isCompleted,
                                  shape: const CircleBorder(),
                                  onChanged: (val) {
                                    _toggleTaskCompletion(task);
                                  },
                                ),
                                title: Text(
                                  task.title.isEmpty ? '(無題)' : task.title,
                                  style: TextStyle(
                                    decoration: task.isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: task.isCompleted
                                        ? Colors.grey
                                        : null,
                                  ),
                                ),
                                subtitle: rangeStr != null
                                    ? Text(
                                        rangeStr,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.grey[400]
                                              : Colors.grey[600],
                                        ),
                                      )
                                    : null,
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () => _deleteTask(task),
                                  tooltip: '削除',
                                ),
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildWeekdayLabel(String label, Color? color) {
    return SizedBox(
      width: 32,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: color,
        ),
      ),
    );
  }
}
