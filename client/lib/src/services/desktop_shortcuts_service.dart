import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';

/// Виджет-обёртка для безопасной обработки горячих клавиш на десктопе (Windows / Linux / macOS).
///
/// ВАЖНО:
/// 1. Обработка клавиш происходит ИСКЛЮЧИТЕЛЬНО тогда, когда окно Maboy находится в фокусе.
///    Если активно другое приложение, окно браузера или игра (полноэкранная или оконная),
///    события ввода не перехватываются.
/// 2. Если фокус находится внутри текстового поля (TextField / EditableText),
///    клавиши (пробел, стрелки, буквы) не перехватываются и передаются в поле ввода.
class DesktopShortcutsWrapper extends StatefulWidget {
  const DesktopShortcutsWrapper({
    super.key,
    required this.controller,
    required this.child,
  });

  final AppController controller;
  final Widget child;

  @override
  State<DesktopShortcutsWrapper> createState() =>
      _DesktopShortcutsWrapperState();
}

class _DesktopShortcutsWrapperState extends State<DesktopShortcutsWrapper> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'DesktopShortcutsFocus');
  double _lastNonZeroVolume = 1.0;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  bool _isInputActive() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    final context = focus.context;
    if (context == null) return false;

    // Check if focused widget is EditableText or an ancestor is an editable field
    bool isEditable = false;
    context.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        isEditable = true;
        return false;
      }
      return true;
    });
    if (context.widget is EditableText) {
      isEditable = true;
    }
    return isEditable;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!kIsWeb &&
        !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return KeyEventResult.ignored;
    }

    // Only respond to key-down events (skip key-up or repeat if already handled)
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    // If user is currently typing in a text field, do not consume playback shortcuts
    if (_isInputActive()) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isControlPressed =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    final c = widget.controller;

    // Space: Play / Pause
    if (key == LogicalKeyboardKey.space) {
      c.togglePlayback();
      return KeyEventResult.handled;
    }

    // Ctrl + ArrowRight: Next track
    if (isControlPressed && key == LogicalKeyboardKey.arrowRight) {
      if (c.hasNext) c.playNext();
      return KeyEventResult.handled;
    }

    // Ctrl + ArrowLeft: Previous track
    if (isControlPressed && key == LogicalKeyboardKey.arrowLeft) {
      if (c.hasPrevious) c.playPrevious();
      return KeyEventResult.handled;
    }

    // ArrowRight: Seek forward 5s
    if (!isControlPressed && key == LogicalKeyboardKey.arrowRight) {
      c.playbackManager.seekRelative(const Duration(seconds: 5));
      return KeyEventResult.handled;
    }

    // ArrowLeft: Seek backward 5s
    if (!isControlPressed && key == LogicalKeyboardKey.arrowLeft) {
      c.playbackManager.seekRelative(const Duration(seconds: -5));
      return KeyEventResult.handled;
    }

    // ArrowUp: Volume up 5%
    if (key == LogicalKeyboardKey.arrowUp) {
      c.setVolume((c.volume + 0.05).clamp(0.0, 1.0));
      return KeyEventResult.handled;
    }

    // ArrowDown: Volume down 5%
    if (key == LogicalKeyboardKey.arrowDown) {
      c.setVolume((c.volume - 0.05).clamp(0.0, 1.0));
      return KeyEventResult.handled;
    }

    // Key M: Mute / Unmute
    if (key == LogicalKeyboardKey.keyM) {
      if (c.volume > 0) {
        _lastNonZeroVolume = c.volume;
        c.setVolume(0.0);
      } else {
        c.setVolume(_lastNonZeroVolume > 0 ? _lastNonZeroVolume : 1.0);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // On mobile, bypass focus wrapping
    if (!kIsWeb &&
        !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return widget.child;
    }

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: widget.child,
    );
  }
}
