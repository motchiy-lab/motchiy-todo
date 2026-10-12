import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

final desktopStartupNotifier = ValueNotifier<bool>(false);

class StartupService {
  StartupService._();

  static final instance = StartupService._();

  Future<bool> initialize() async {
    if (!Platform.isWindows && !Platform.isLinux) {
      throw UnsupportedError(
        'Startup launch is supported on Windows and Linux only.',
      );
    }
    launchAtStartup.setup(
      appName: 'Motchiy ToDo',
      appPath: Platform.resolvedExecutable,
      packageName: 'motchiy.todo',
    );
    return launchAtStartup.isEnabled();
  }

  Future<void> setEnabled(bool enabled) async {
    await initialize();
    final succeeded = enabled
        ? await launchAtStartup.enable()
        : await launchAtStartup.disable();
    if (!succeeded) {
      throw StateError('Could not update the startup setting.');
    }
  }
}
