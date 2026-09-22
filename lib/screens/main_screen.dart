import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'calendar_screen.dart';
import 'idea_screen.dart';
import 'settings_screen.dart';
import 'task_home_screen.dart';
import 'wishlist_screen.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/nav_bar.dart';
import '../main.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int? _currentIndex = 2; // ToDoリスト is the 3rd tab (index 2)
  late final List<Widget> _screens;
  final _taskHomeKey = GlobalKey<TaskHomeScreenState>();

  @override
  void initState() {
    super.initState();
    _screens = [
      const CalendarScreen(),
      const WishlistScreen(),
      TaskHomeScreen(key: _taskHomeKey),
      const IdeaScreen(),
      const SettingsScreen(),
    ];
  }

  void _onTabTapped(int index) {
    if (_currentIndex == index) {
      return;
    }

    setState(() {
      _currentIndex = index;
    });
    if (index == 2) {
      _taskHomeKey.currentState?.loadTasks();
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity;
    if (velocity == null || _currentIndex == null || velocity.abs() < 300) {
      return;
    }

    // A right swipe moves to the tab on the left; a left swipe moves right.
    final nextIndex = velocity > 0 ? _currentIndex! - 1 : _currentIndex! + 1;
    if (nextIndex >= 0 && nextIndex < 5) {
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
                  : IndexedStack(index: _currentIndex, children: _screens),
            ),
          ),
        ],
      ),
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: showNavLabelsNotifier,
        builder: (context, showNavLabels, child) {
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
                                  showLabel: showNavLabels,
                                  currentIndex: _currentIndex ?? -1,
                                  selectedColor: colorScheme.onPrimary,
                                  onTap: _onTabTapped,
                                ),
                              ),
                              Expanded(
                                child: NavItem(
                                  index: 1,
                                  outlineIcon: Icons.card_giftcard_outlined,
                                  filledIcon: Icons.card_giftcard,
                                  label: '欲しいもの',
                                  showLabel: showNavLabels,
                                  currentIndex: _currentIndex ?? -1,
                                  selectedColor: colorScheme.onPrimary,
                                  onTap: _onTabTapped,
                                ),
                              ),
                              Expanded(
                                child: NavItem(
                                  index: 2,
                                  outlineIcon: Icons.checklist_outlined,
                                  filledIcon: Icons.checklist,
                                  label: 'ToDoリスト',
                                  showLabel: showNavLabels,
                                  currentIndex: _currentIndex ?? -1,
                                  selectedColor: colorScheme.onPrimary,
                                  onTap: _onTabTapped,
                                ),
                              ),
                              Expanded(
                                child: NavItem(
                                  index: 3,
                                  outlineIcon: Icons.lightbulb_outline,
                                  filledIcon: Icons.lightbulb,
                                  label: 'アイデア',
                                  showLabel: showNavLabels,
                                  currentIndex: _currentIndex ?? -1,
                                  selectedColor: colorScheme.onPrimary,
                                  onTap: _onTabTapped,
                                ),
                              ),
                              Expanded(
                                child: NavItem(
                                  index: 4,
                                  outlineIcon: Icons.settings_outlined,
                                  filledIcon: Icons.settings,
                                  label: '設定',
                                  showLabel: showNavLabels,
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
