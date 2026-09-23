import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_system.dart';

/// Minimal app-owned controls for the native borderless Windows window.
/// Keeping this above Navigator makes close, maximize and drag available on
/// login, player and every pushed page without repeating controls in AppBars.
class MaboyWindowFrame extends StatelessWidget {
  const MaboyWindowFrame({super.key, required this.child});

  static const MethodChannel _channel = MethodChannel('com.maboy.window');
  final Widget child;

  static Future<void> _send(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException catch (error) {
      debugPrint('Windows window action $method failed: $error');
    } on MissingPluginException catch (error) {
      debugPrint('Windows window channel is unavailable: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 36,
        child: Material(
          color: MaboyColors.surface,
          child: Row(
            children: [
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.move,
                  child: GestureDetector(
                    key: const Key('windowDragRegion'),
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => unawaited(_send('startDrag')),
                    onDoubleTap: () => unawaited(_send('toggleMaximize')),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              _WindowButton(
                icon: Icons.remove,
                tooltip: 'Свернуть окно',
                onTap: () => unawaited(_send('minimize')),
              ),
              _WindowButton(
                icon: Icons.crop_square,
                tooltip: 'Развернуть или восстановить окно',
                onTap: () => unawaited(_send('toggleMaximize')),
              ),
              _WindowButton(
                icon: Icons.close,
                tooltip: 'Закрыть окно',
                danger: true,
                onTap: () => unawaited(_send('close')),
              ),
            ],
          ),
        ),
      ),
      Expanded(child: child),
    ],
  );
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.danger
        ? MaboyColors.danger
        : Colors.white.withValues(alpha: 0.1);
    final iconColor = (widget.danger && _isHovered)
        ? Colors.white
        : MaboyColors.textMuted;

    return Semantics(
      button: true,
      label: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 46,
            height: 36,
            color: _isHovered ? hoverColor : Colors.transparent,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 16, color: iconColor),
          ),
        ),
      ),
    );
  }
}
