import 'package:flutter/material.dart';

import 'src/app_controller.dart';
import 'src/home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  await controller.load();
  runApp(MaboyApp(controller: controller));
}

class MaboyApp extends StatelessWidget {
  const MaboyApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Maboy',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: const Color(0xff0d0d0f),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xffa4efb4),
            brightness: Brightness.dark,
          ),
        ),
        home: HomePage(controller: controller),
      );
}