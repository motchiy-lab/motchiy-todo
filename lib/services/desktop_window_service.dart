import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

final desktopCloseToTrayNotifier = ValueNotifier<bool>(false);

class DesktopWindowService extends WindowListener {
  DesktopWindowService._();

  static final instance = DesktopWindowService._();

  TrayIcon? _trayIcon;
  bool _closeToTray = false;

  Future<void> initialize({required bool closeToTray}) async {
    _closeToTray = closeToTray;
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    if (_closeToTray) {
      await _showTrayIcon();
    }
  }

  Future<void> setCloseToTray(bool enabled) async {
    if (enabled) {
      await _showTrayIcon();
    } else {
      await _hideTrayIcon();
    }
    _closeToTray = enabled;
  }

  @override
  void onWindowClose() {
    if (_closeToTray) {
      unawaited(windowManager.hide());
    } else {
      unawaited(_quit());
    }
  }

  Future<void> _showTrayIcon() async {
    if (_trayIcon == null) {
      final trayIcon = TrayIcon.create();
      if (trayIcon == null) {
        throw StateError('Could not create the system tray icon.');
      }
      _trayIcon = trayIcon;
      trayIcon.icon = ImageAsset.fromAsset('assets/app_icon.png');
      trayIcon.addListener((event) {
        if (event is TrayIconDoubleClickedEvent) {
          unawaited(_showWindow());
        }
      });

      final menu = Menu.create();
      if (menu == null) {
        throw StateError('Could not create the system tray menu.');
      }
      final showItem = MenuItem.createWithLabelAndType(
        'ウィンドウを表示',
        MenuItemType.normal,
      );
      final quitItem = MenuItem.createWithLabelAndType(
        'アプリを終了',
        MenuItemType.normal,
      );
      if (showItem == null || quitItem == null) {
        throw StateError('Could not create system tray menu items.');
      }
      showItem.addListener((event) {
        if (event is MenuItemClickedEvent) {
          unawaited(_showWindow());
        }
      });
      quitItem.addListener((event) {
        if (event is MenuItemClickedEvent) {
          unawaited(_quit());
        }
      });
      menu.addItem(showItem);
      menu.addSeparator();
      menu.addItem(quitItem);
      trayIcon.setContextMenuTrigger(ContextMenuTrigger.rightClicked);
      trayIcon.setContextMenu(menu);
      trayIcon.setTooltip('Motchiy ToDo');
    }
    _trayIcon!.setVisible(true);
  }

  Future<void> _hideTrayIcon() {
    final trayIcon = _trayIcon;
    if (trayIcon == null) return Future<void>.value();
    trayIcon.setVisible(false);
    trayIcon.dispose();
    _trayIcon = null;
    return Future<void>.value();
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    await _hideTrayIcon();
    await windowManager.destroy();
  }
}
