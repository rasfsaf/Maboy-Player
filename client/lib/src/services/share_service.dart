import 'dart:io';
import 'package:flutter/services.dart';

typedef ShareCallback = void Function(String text, {String? title});

class ShareService {
  static const MethodChannel _channel = MethodChannel('com.maboy.player/share');
  static ShareCallback? _onShareReceived;

  static void init({required ShareCallback onShare}) {
    _onShareReceived = onShare;
    if (!Platform.isAndroid) return;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText') {
        _dispatch(call.arguments);
      }
    });

    // Check for initial share that launched the app
    _checkInitialShare();
  }

  static void _dispatch(dynamic arguments) {
    if (arguments is Map) {
      final text = arguments['text'] as String?;
      final subject = arguments['subject'] as String?;
      if (text != null && text.trim().isNotEmpty) {
        _onShareReceived?.call(text.trim(), title: subject?.trim());
      }
    } else if (arguments is String && arguments.trim().isNotEmpty) {
      _onShareReceived?.call(arguments.trim());
    }
  }

  static Future<void> _checkInitialShare() async {
    try {
      final initial = await _channel.invokeMethod<dynamic>('getInitialShare');
      if (initial != null) {
        _dispatch(initial);
      }
    } catch (_) {}
  }
}
