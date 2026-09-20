import 'package:flutter/material.dart';

import '../main.dart';
import 'calendar_screen.dart';
import 'idea_screen.dart';
import 'settings_screen.dart';
import 'task_home_screen.dart';
import 'wishlist_screen.dart';

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
      body: IndexedStack(index: _currentIndex, children: _screens),
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
                      _NavItem(
                        index: 0,
                        outlineIcon: Icons.calendar_month_outlined,
                        filledIcon: Icons.calendar_month,
                        label: 'カレンダー',
                        currentIndex: _currentIndex,
                        onTap: _onTabTapped,
                      ),
                      const SizedBox(width: 12),
                      _NavItem(
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
                      _NavItem(
                        index: 3,
                        outlineIcon: Icons.lightbulb_outline,
                        filledIcon: Icons.lightbulb,
                        label: 'アイデア',
                        currentIndex: _currentIndex,
                        onTap: _onTabTapped,
                      ),
                      const SizedBox(width: 12),
                      _NavItem(
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
              child: _CenterNavItem(
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

class _NavItem extends StatefulWidget {
  final int index;
  final IconData outlineIcon;
  final IconData filledIcon;
  final String label;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.index,
    required this.outlineIcon,
    required this.filledIcon,
    required this.label,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.currentIndex == widget.index;
    final colorScheme = Theme.of(context).colorScheme;
    final color = isSelected ? colorScheme.primary : Colors.grey;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap(widget.index),
        child: SizedBox(
          width: 50, // 幅を少しコンパクトに調整
          height: 55, // 高さを縮めて間隔を狭く
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // アイコンの位置を少し上に調整
              Positioned(
                top: 10,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: 1.0,
                    end: _isHovered ? 1.15 : 1.0,
                  ),
                  duration: const Duration(milliseconds: 150),
                  builder: (context, scale, child) {
                    return Transform.scale(scale: scale, child: child);
                  },
                  child: Icon(
                    isSelected ? widget.filledIcon : widget.outlineIcon,
                    color: color,
                    size: 22,
                  ),
                ),
              ),
              if (showNavLabelsOnHoverNotifier.value && _isHovered)
                Positioned(
                  bottom: 10, // 文字をアイコンに近づける
                  child: ValueListenableBuilder<bool>(
                    valueListenable: showNavLabelsOnHoverNotifier,
                    builder: (context, showLabel, child) {
                      if (!showLabel || !_isHovered) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: color,
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterNavItem extends StatefulWidget {
  final int index;
  final IconData filledIcon;
  final String label;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _CenterNavItem({
    required this.index,
    required this.filledIcon,
    required this.label,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<_CenterNavItem> createState() => _CenterNavItemState();
}

class _CenterNavItemState extends State<_CenterNavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.currentIndex == widget.index;
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap(widget.index),
        child: SizedBox(
          width: 70,
          height: 65, // 高さを縮めてコンパクトに
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // 中央ボタンの位置を調整
              Positioned(
                top: 2,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: 1.0,
                    end: _isHovered ? 1.12 : 1.0,
                  ),
                  duration: const Duration(milliseconds: 150),
                  builder: (context, scale, child) {
                    return Transform.scale(scale: scale, child: child);
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      widget.filledIcon,
                      color: colorScheme.onPrimary,
                      size: 26,
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: showNavLabelsOnHoverNotifier,
                builder: (context, showLabel, child) {
                  if (!showLabel || !_isHovered) return const SizedBox.shrink();
                  return Positioned(
                    bottom: 0, // 中央ボタンの文字をアイコンに近づける
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? colorScheme.primary
                            : Colors.grey[700],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
