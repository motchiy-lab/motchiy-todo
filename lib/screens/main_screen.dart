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

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int? _currentIndex = 2; // ToDoリスト is the 3rd tab (index 2)
  final GlobalKey<TaskHomeScreenState> _taskHomeScreenKey = GlobalKey();

  late final List<Widget> _screens = [
    const CalendarScreen(),
    const WishlistScreen(),
    TaskHomeScreen(
      key: _taskHomeScreenKey,
      onBack: () {
        setState(() {
          _currentIndex = null;
        });
      },
    ),
    const IdeaScreen(),
    const SettingsScreen(),
  ];

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
      if (index == 2) {
        _taskHomeScreenKey.currentState?.loadTasks();
      }
    });
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
        ],
      ),
      bottomNavigationBar: SizedBox(
        height: 92,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              bottom: 12,
              left: 16,
              right: 16,
              height: 68,
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? colorScheme.surfaceContainerHighest
                      : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final selectedIndex = _currentIndex;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          if (selectedIndex != null)
                            AnimatedAlign(
                              alignment: Alignment(
                                -0.8 + selectedIndex * 0.4,
                                0,
                              ),
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: colorScheme.primary.withValues(
                                        alpha: 0.35,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Row(
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
                                  outlineIcon: Icons.card_giftcard_outlined,
                                  filledIcon: Icons.card_giftcard,
                                  label: '欲しいもの',
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
                                  currentIndex: _currentIndex ?? -1,
                                  selectedColor: colorScheme.onPrimary,
                                  onTap: _onTabTapped,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
