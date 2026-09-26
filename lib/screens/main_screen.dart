import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'calendar_screen.dart';
import 'settings_screen.dart';
import 'task_home_screen.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/nav_bar.dart';
import '../main.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  int? _currentIndex = 1; // ToDoリスト is the 2nd tab (index 1)
  int? _previousIndex;
  late final List<Widget> _screens;
  final _calendarKey = GlobalKey<CalendarScreenState>();
  final _taskHomeKey = GlobalKey<TaskHomeScreenState>();
  late final AnimationController _tabAnimationController;

  @override
  void initState() {
    super.initState();
    _tabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 1,
    );
    _screens = [
      CalendarScreen(key: _calendarKey),
      TaskHomeScreen(key: _taskHomeKey),
      const SettingsScreen(),
    ];
  }

  void _onTabTapped(int index) {
    if (_currentIndex == index) {
      return;
    }

    _previousIndex = _currentIndex;
    setState(() {
      _currentIndex = index;
    });
    _tabAnimationController.forward(from: 0);
    if (index == 0) {
      _calendarKey.currentState?.loadTasks();
    } else if (index == 1) {
      _taskHomeKey.currentState?.loadTasks();
    }
  }

  @override
  void dispose() {
    _tabAnimationController.dispose();
    super.dispose();
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity;
    if (velocity == null || _currentIndex == null || velocity.abs() < 300) {
      return;
    }

    // A right swipe moves to the tab on the left; a left swipe moves right.
    final nextIndex = velocity > 0 ? _currentIndex! - 1 : _currentIndex! + 1;
    if (nextIndex >= 0 && nextIndex < _screens.length) {
      _onTabTapped(nextIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Column(
        children: [
          if (!kIsWeb &&
              (Platform.isWindows || Platform.isMacOS || Platform.isLinux))
            const CustomTitleBar(),
          Expanded(
            child: GestureDetector(
              onHorizontalDragEnd: _onHorizontalDragEnd,
              child: _currentIndex == null
                  ? Center(
                      child: Text(
                        'ToDoリストを閉じました',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 16,
                        ),
                      ),
                    )
                  : ValueListenableBuilder<bool>(
                      valueListenable: enableTabAnimationsNotifier,
                      builder: (context, enableAnimation, child) {
                        return enableAnimation
                            ? _AnimatedTabStack(
                                animation: _tabAnimationController,
                                currentIndex: _currentIndex!,
                                previousIndex: _previousIndex,
                                children: _screens,
                              )
                            : IndexedStack(
                                index: _currentIndex,
                                children: _screens,
                              );
                      },
                    ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Builder(
        builder: (context) {
          final navBarColor = isDark
              ? colorScheme.surfaceContainerHighest
              : Colors.white;

          return SafeArea(
            top: false,
            child: ColoredBox(
              color: navBarColor,
              child: Container(
                height: 88,
                decoration: BoxDecoration(
                  color: navBarColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 14,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxContentWidth = 420.0;
                    final availableWidth = constraints.maxWidth;

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: Align(
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: availableWidth > maxContentWidth
                              ? maxContentWidth
                              : availableWidth,
                          child: Row(
                            children: [
                              Expanded(
                                child: NavItem(
                                  index: 0,
                                  outlineIcon: Icons.calendar_month_outlined,
                                  filledIcon: Icons.calendar_month,
                                  label: 'カレンダー',
                                  currentIndex: _currentIndex ?? -1,
                                  selectedColor: colorScheme.onPrimary,
                                  onTap: _onTabTapped,
                                ),
                              ),
                              Expanded(
                                child: NavItem(
                                  index: 1,
                                  outlineIcon: Icons.checklist_outlined,
                                  filledIcon: Icons.checklist,
                                  label: 'ToDoリスト',
                                  currentIndex: _currentIndex ?? -1,
                                  selectedColor: colorScheme.onPrimary,
                                  onTap: _onTabTapped,
                                ),
                              ),
                              Expanded(
                                child: NavItem(
                                  index: 2,
                                  outlineIcon: Icons.settings_outlined,
                                  filledIcon: Icons.settings,
                                  label: '設定',
                                  currentIndex: _currentIndex ?? -1,
                                  selectedColor: colorScheme.onPrimary,
                                  onTap: _onTabTapped,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AnimatedTabStack extends StatelessWidget {
  final Animation<double> animation;
  final int currentIndex;
  final int? previousIndex;
  final List<Widget> children;

  const _AnimatedTabStack({
    required this.animation,
    required this.currentIndex,
    required this.previousIndex,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final isTransitioning =
            previousIndex != null && previousIndex != currentIndex;
        final direction = previousIndex != null && currentIndex > previousIndex!
            ? 1.0
            : -1.0;

        return Stack(
          fit: StackFit.expand,
          children: [
            for (var index = 0; index < children.length; index++)
              if (index == currentIndex ||
                  (isTransitioning && index == previousIndex))
                _buildTransitioningChild(
                  isCurrent: index == currentIndex,
                  direction: direction,
                  child: children[index],
                )
              else
                Offstage(child: children[index]),
          ],
        );
      },
    );
  }

  Widget _buildTransitioningChild({
    required bool isCurrent,
    required double direction,
    required Widget child,
  }) {
    final progress = animation.value;
    final opacity = isCurrent ? progress : 1 - progress;
    final translation = isCurrent
        ? direction * (1 - progress) * 0.08
        : -direction * progress * 0.08;

    return IgnorePointer(
      ignoring: !isCurrent,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: FractionalTranslation(
          translation: Offset(translation, 0),
          child: child,
        ),
      ),
    );
  }
}
