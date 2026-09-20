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
  int _currentIndex = 2; // ToDoリスト is the 3rd tab (index 2)
  final GlobalKey<TaskHomeScreenState> _taskHomeScreenKey = GlobalKey();

  late final List<Widget> _screens = [
    const CalendarScreen(),
    const WishlistScreen(),
    TaskHomeScreen(key: _taskHomeScreenKey),
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
            child: IndexedStack(index: _currentIndex, children: _screens),
          ),
        ],
      ),
      bottomNavigationBar: SizedBox(
        height: 75,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              bottom: -20,
              left: 16,
              right: 16,
              height: 75,
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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 左側の2つのアイテム
                      NavItem(
                        index: 0,
                        outlineIcon: Icons.calendar_month_outlined,
                        filledIcon: Icons.calendar_month,
                        label: 'カレンダー',
                        currentIndex: _currentIndex,
                        onTap: _onTabTapped,
                      ),
                      const SizedBox(width: 12),
                      NavItem(
                        index: 1,
                        outlineIcon: Icons.card_giftcard_outlined,
                        filledIcon: Icons.card_giftcard,
                        label: '欲しいもの',
                        currentIndex: _currentIndex,
                        onTap: _onTabTapped,
                      ),
                      // 中央のボタンのためのスペース（空白をあける）
                      const SizedBox(width: 70),
                      // 右側の2つのアイテム
                      NavItem(
                        index: 3,
                        outlineIcon: Icons.lightbulb_outline,
                        filledIcon: Icons.lightbulb,
                        label: 'アイデア',
                        currentIndex: _currentIndex,
                        onTap: _onTabTapped,
                      ),
                      const SizedBox(width: 12),
                      NavItem(
                        index: 4,
                        outlineIcon: Icons.settings_outlined,
                        filledIcon: Icons.settings,
                        label: '設定',
                        currentIndex: _currentIndex,
                        onTap: _onTabTapped,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              child: CenterNavItem(
                index: 2,
                filledIcon: Icons.checklist,
                label: 'ToDoリスト',
                currentIndex: _currentIndex,
                onTap: _onTabTapped,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
