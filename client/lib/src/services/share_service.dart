import 'dart:io';
import 'package:flutter/services.dart';

class ShareService {
  static const MethodChannel _channel = MethodChannel('com.maboy.player/share');
  static void Function(String text)? _onShareReceived;

  static void init({required void Function(String text) onShare}) {
    _onShareReceived = onShare;
    if (!Platform.isAndroid) return;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText') {
        final text = call.arguments as String?;
        if (text != null && text.trim().isNotEmpty) {
          _onShareReceived?.call(text.trim());
        }
      }
    });

    // Check for initial share that launched the app
    _checkInitialShare();
  }

  static Future<void> _checkInitialShare() async {
    try {
      final initial = await _channel.invokeMethod<String>('getInitialShare');
      if (initial != null && initial.trim().isNotEmpty) {
        _onShareReceived?.call(initial.trim());
      }
    } catch (_) {}
  }
}
