import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Maboy design tokens. Inspired by the visual references but driven by
/// Maboy's own name and palette: deep black canvas, layered graphite surfaces,
/// electric turquoise-blue accent. No hardcoded track or artist names.
abstract final class MaboyColors {
  // Backgrounds: pure black canvas, charcoal/onyx surfaces for depth.
  static const background = Color(0xff000000);
  static const surface = Color(0xff0b0d10);
  static const surfaceHigh = Color(0xff14181c);
  static const surfaceMuted = Color(0xff1c2026);
  static const border = Color(0xff252a30);

  // Single signal color: turquoise-blue. Used for primary actions, focus
  // rings, equalizer highlights and active state across light + dark themes.
  static const accent = Color(0xff03e6ff);
  static const accentDim = Color(0xff0fb6c7);

  // Typography.
  static const text = Color(0xfff2f5f7);
  static const textMuted = Color(0xff8a9099);
  static const textSubtle = Color(0xff5a6068);

  // Status colors. Kept restrained so the accent dominates.
  static const danger = Color(0xffff5f69);
  static const warning = Color(0xffffb65c);
  static const success = Color(0xff41e0a3);
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
}

abstract final class AppRadius {
  static const sm = 6.0;
  static const md = 10.0;
  static const lg = 14.0;
  static const xl = 20.0;
  static const pill = 999.0;
}

ThemeData buildMaboyTheme() {
  final scheme = ColorScheme.dark(
    primary: MaboyColors.accent,
    onPrimary: const Color(0xff001214),
    secondary: MaboyColors.accentDim,
    onSecondary: Colors.white,
    surface: MaboyColors.surface,
    onSurface: MaboyColors.text,
    surfaceContainerHighest: MaboyColors.surfaceMuted,
    error: MaboyColors.danger,
    onError: Colors.white,
    outline: MaboyColors.border,
    outlineVariant: MaboyColors.border,
  );

  final base = ThemeData.dark(useMaterial3: true);

  // Build Inter typography once and reuse it across the theme.
  final interText = GoogleFonts.interTextTheme(base.textTheme).apply(
    bodyColor: MaboyColors.text,
    displayColor: MaboyColors.text,
  );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: MaboyColors.background,
    canvasColor: MaboyColors.surface,
    dividerColor: Colors.white.withValues(alpha: 0.06),
    textTheme: interText,
    primaryTextTheme: interText,
    appBarTheme: AppBarTheme(
      backgroundColor: MaboyColors.background,
      foregroundColor: MaboyColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 20,
      titleTextStyle: GoogleFonts.inter(
        color: MaboyColors.text,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: MaboyColors.surface,
      indicatorColor: MaboyColors.accent.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => GoogleFonts.inter(
          color: states.contains(WidgetState.selected)
              ? MaboyColors.text
              : MaboyColors.textMuted,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          fontSize: 11,
          letterSpacing: 0.3,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? MaboyColors.accent
              : MaboyColors.textMuted,
          size: 24,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: MaboyColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: MaboyColors.border),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: MaboyColors.textMuted,
      textColor: MaboyColors.text,
      titleTextStyle: GoogleFonts.inter(
        color: MaboyColors.text,
        fontWeight: FontWeight.w500,
      ),
      subtitleTextStyle: GoogleFonts.inter(
        color: MaboyColors.textMuted,
        fontWeight: FontWeight.w400,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MaboyColors.surface,
      labelStyle: GoogleFonts.inter(color: MaboyColors.textMuted),
      hintStyle: GoogleFonts.inter(color: MaboyColors.textMuted),
      prefixIconColor: MaboyColors.textMuted,
      suffixIconColor: MaboyColors.textMuted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: MaboyColors.accent, width: 1.5),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: MaboyColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: MaboyColors.border),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: MaboyColors.surface,
      modalBackgroundColor: MaboyColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MaboyColors.accent,
        foregroundColor: const Color(0xff001214),
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        textStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: MaboyColors.text,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        textStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: MaboyColors.accent,
        textStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: MaboyColors.accent,
      inactiveTrackColor: MaboyColors.surfaceHigh,
      thumbColor: MaboyColors.text,
      overlayColor: Color(0x3303e6ff),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: MaboyColors.accent,
      linearTrackColor: MaboyColors.surfaceHigh,
      circularTrackColor: MaboyColors.surfaceHigh,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: MaboyColors.surfaceHigh,
      contentTextStyle: GoogleFonts.inter(color: MaboyColors.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),
    iconTheme: const IconThemeData(color: MaboyColors.text, size: 22),
    splashColor: MaboyColors.accent.withValues(alpha: 0.10),
    highlightColor: MaboyColors.accent.withValues(alpha: 0.05),
  );
}

/// Procedural low-contrast backdrop. Stays out of the way so track artwork
/// stays dominant. Inspired by reference #1 (TRON-style faint grid) but
/// driven by Maboy brand words.
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
      ..color = Colors.white.withValues(alpha: 0.030)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final signal = Paint()
      ..color = MaboyColors.accent.withValues(alpha: 0.040)
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
            color: Colors.white.withValues(alpha: 0.030),
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

/// Brand wordmark. Lower-case, heavy weight, tight tracking — a neutral
/// foundation that any theme color can sit on top of.
class MaboyBrand extends StatelessWidget {
  const MaboyBrand({super.key, this.size = 30, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        'maboy',
        style: GoogleFonts.inter(
          color: color ?? MaboyColors.text,
          fontSize: size,
          height: 1,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.4,
        ),
      );
}