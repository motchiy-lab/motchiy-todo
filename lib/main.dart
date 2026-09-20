import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/main_screen.dart';

final List<Color> appThemes = [
  const Color(0xFF5C8374), // セージグリーン
  const Color(0xFF4B6B94), // スレートブルー
  const Color(0xFFB86244), // ウォームテラコッタ
  const Color(0xFF7E6B8F), // ラベンダーローズ
  const Color(0xFF9E7B5E), // ウォームアンバー
  const Color(0xFF3B7A9E), // オーシャンブルー
];

final List<String> appThemeNames = [
  'セージグリーン',
  'スレートブルー',
  'ウォームテラコッタ',
  'ラベンダーローズ',
  'ウォームアンバー',
  'オーシャンブルー',
];

final ValueNotifier<int> themeIndexNotifier = ValueNotifier<int>(0);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  themeIndexNotifier.value = prefs.getInt('theme_color_index') ?? 0;

  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      minimumSize: Size(400, 500),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  runApp(const TaskApp());
}

class TaskApp extends StatelessWidget {
  const TaskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: themeIndexNotifier,
      builder: (context, themeIndex, child) {
        final seedColor = appThemes[themeIndex % appThemes.length];
        return MaterialApp(
          title: 'Motchiy ToDo',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: seedColor,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: seedColor,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          themeMode: ThemeMode.system,
          home: const MainScreen(),
        );
      },
    );
  }
}
