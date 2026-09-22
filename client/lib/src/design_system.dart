import 'package:flutter/material.dart';

/// Maboy's production dark design tokens. Black is the canvas; restrained
/// graphite layers and an electric-blue signal color create depth without
/// falling back to the old black/green or rejected purple palette.
abstract final class MaboyColors {
  static const background = Color(0xff000000);
  static const surface = Color(0xff0c0d0f);
  static const surfaceHigh = Color(0xff15171a);
  static const border = Color(0xff25282d);
  static const primary = Color(0xff4c8dff);
  static const secondary = Color(0xff57d6e6);
  static const text = Color(0xfff4f5f7);
  static const textMuted = Color(0xff8d929b);
  static const danger = Color(0xffff5f69);
  static const warning = Color(0xffffb65c);
}

ThemeData buildMaboyTheme() {
  final scheme = const ColorScheme.dark(
    primary: MaboyColors.primary,
    onPrimary: Colors.white,
    secondary: MaboyColors.secondary,
    onSecondary: Color(0xff06171b),
    surface: MaboyColors.surface,
    onSurface: MaboyColors.text,
    error: MaboyColors.danger,
    onError: Colors.white,
  );

  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: MaboyColors.background,
    canvasColor: MaboyColors.surface,
    dividerColor: Colors.white.withValues(alpha: 0.07),
    textTheme: base.textTheme.apply(
      bodyColor: MaboyColors.text,
      displayColor: MaboyColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: MaboyColors.background,
      foregroundColor: MaboyColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 20,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: MaboyColors.surface,
      indicatorColor: MaboyColors.primary.withValues(alpha: 0.2),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? MaboyColors.text
              : MaboyColors.textMuted,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? MaboyColors.primary
              : MaboyColors.textMuted,
        ),
      ),
    ),
    cardTheme: const CardThemeData(
      color: MaboyColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(7)),
        side: BorderSide(color: MaboyColors.border),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: MaboyColors.textMuted,
      textColor: MaboyColors.text,
      subtitleTextStyle: TextStyle(color: MaboyColors.textMuted),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(5)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MaboyColors.surface,
      labelStyle: const TextStyle(color: MaboyColors.textMuted),
      hintStyle: const TextStyle(color: MaboyColors.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: MaboyColors.primary, width: 1.5),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: MaboyColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: MaboyColors.background,
      modalBackgroundColor: MaboyColors.background,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: MaboyColors.text,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: MaboyColors.primary,
      inactiveTrackColor: MaboyColors.surfaceHigh,
      thumbColor: MaboyColors.text,
      overlayColor: Color(0x333b82f6),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: MaboyColors.primary,
      linearTrackColor: MaboyColors.surfaceHigh,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: MaboyColors.surfaceHigh,
      contentTextStyle: TextStyle(color: MaboyColors.text),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Procedural background: no bitmap scaling artifacts and no network asset.
/// The pattern is intentionally low-contrast so track artwork stays dominant.
class MaboyBackdrop extends StatelessWidget {
  const MaboyBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: MaboyColors.background),
      const IgnorePointer(child: CustomPaint(painter: _MaboyPatternPainter())),
      child,
    ],
  );
}

class _MaboyPatternPainter extends CustomPainter {
  const _MaboyPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final signal = Paint()
      ..color = MaboyColors.primary.withValues(alpha: 0.045)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (var row = -1; row < size.height / 180 + 1; row++) {
      for (var column = -1; column < size.width / 220 + 1; column++) {
        final x = (column * 220 + (row.isEven ? 40 : 145)).toDouble();
        final y = (row * 180 + 70).toDouble();
        canvas.drawCircle(Offset(x, y), 44, line);
        canvas.drawArc(
          Rect.fromCircle(center: Offset(x, y), radius: 66),
          -0.8,
          2.1,
          false,
          signal,
        );
      }
    }

    const words = ['MABOY', 'PLAY', 'MUSIC', 'QUEUE', 'LOUD'];
    for (var i = 0; i < size.height / 120 + 1; i++) {
      final painter = TextPainter(
        text: TextSpan(
          text: words[i % words.length],
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.035),
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(22 + (i.isEven ? 0 : 92), 38 + i * 120));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MaboyBrand extends StatelessWidget {
  const MaboyBrand({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) => Text(
    'maboy',
    style: TextStyle(
      color: MaboyColors.text,
      fontSize: size,
      height: 1,
      fontWeight: FontWeight.w900,
      letterSpacing: -1.2,
    ),
  );
}
