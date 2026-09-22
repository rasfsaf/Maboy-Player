import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'src/app_controller.dart';
import 'src/design_system.dart';
import 'src/home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // google_fonts ships Inter. Disable runtime fetching in test environments
  // (which lack internet) so the test harness uses the cached fallback.
  GoogleFonts.config.allowRuntimeFetching = !_isRunningInTestMode();
  runApp(const MaboyApp());
}

bool _isRunningInTestMode() {
  bool inTest = false;
  assert(() {
    inTest = true;
    return true;
  }());
  return inTest;
}

class MaboyApp extends StatefulWidget {
  const MaboyApp({super.key});

  @override
  State<MaboyApp> createState() => _MaboyAppState();
}

class _MaboyAppState extends State<MaboyApp> {
  final AppController _controller = AppController();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'maboy',
      debugShowCheckedModeBanner: false,
      theme: buildMaboyTheme(),
      home: HomePage(controller: _controller),
    );
  }
}