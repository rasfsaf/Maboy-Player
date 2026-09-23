import 'dart:io' show Platform;
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'src/app_controller.dart';
import 'src/design_system.dart';
import 'src/home.dart';
import 'src/services/desktop_shortcuts_service.dart';
import 'src/services/media_service.dart';
import 'src/services/share_service.dart';
import 'src/widgets/window_frame.dart';

class MaboyScrollBehavior extends MaterialScrollBehavior {
  const MaboyScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MediaService.init();
  final controller = AppController();
  await controller.load();
  ShareService.init(
    onShare: (sharedText) {
      controller.handleIncomingShare(sharedText);
    },
  );
  runApp(MaboyApp(controller: controller));
}

class MaboyApp extends StatelessWidget {
  const MaboyApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Maboy',
    debugShowCheckedModeBanner: false,
    theme: buildMaboyTheme(),
    scrollBehavior: const MaboyScrollBehavior(),
    builder: (context, child) => Platform.isWindows && child != null
        ? MaboyWindowFrame(child: child)
        : child ?? const SizedBox.shrink(),
    home: DesktopShortcutsWrapper(
      controller: controller,
      child: HomePage(controller: controller),
    ),
  );
}
