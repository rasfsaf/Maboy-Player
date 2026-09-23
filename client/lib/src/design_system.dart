import 'dart:ui' show ImageFilter, lerpDouble;
import 'package:flutter/material.dart';

/// Graphite surfaces keep text readable above translucent, artwork-led layers.
/// Coral marks playback actions; cyan is reserved for secondary signals.
abstract final class MaboyColors {
  static const background = Color(0xff0b0d11);
  static const surface = Color(0xff171a20);
  static const surfaceHigh = Color(0xff23272f);
  static const border = Color(0xff41454e);
  static const primary = Color(0xfff36d79);
  static const secondary = Color(0xff59d6dc);
  static const text = Color(0xfff7f5f5);
  static const textMuted = Color(0xffa5a5ad);
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
    cardColor: MaboyColors.surfaceHigh,
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
      height: 70,
      backgroundColor: const Color(0xff111318),
      indicatorColor: MaboyColors.primary.withValues(alpha: 0.16),
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
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: MaboyColors.textMuted,
      textColor: MaboyColors.text,
      subtitleTextStyle: TextStyle(color: MaboyColors.textMuted),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MaboyColors.surface,
      labelStyle: const TextStyle(color: MaboyColors.textMuted),
      hintStyle: const TextStyle(color: MaboyColors.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MaboyColors.primary, width: 1.5),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: MaboyColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: MaboyColors.background,
      modalBackgroundColor: MaboyColors.background,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: MaboyColors.text,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: MaboyColors.primary,
      inactiveTrackColor: MaboyColors.surfaceHigh,
      thumbColor: MaboyColors.text,
      overlayColor: Color(0x33f36d79),
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

/// Ambient light sits behind every page; translucent panels blur this layer.
/// A shared background avoids blank glass when a track has no artwork.
class MaboyBackdrop extends StatelessWidget {
  const MaboyBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xff202a31),
              MaboyColors.background,
              Color(0xff19161f),
            ],
            stops: [0, 0.52, 1],
          ),
        ),
      ),
      const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.75, -0.85),
              radius: 1.1,
              colors: [Color(0x4459d6dc), Colors.transparent],
            ),
          ),
        ),
      ),
      child,
    ],
  );
}

/// Blur belongs on panels, not the whole page, to keep scrolling inexpensive.
class MaboyGlassPanel extends StatelessWidget {
  const MaboyGlassPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 20,
    this.opacity = 0.72,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double opacity;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: MaboyColors.surface.withValues(alpha: opacity),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        ),
        child: Material(type: MaterialType.transparency, child: child),
      ),
    ),
  );
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

/// Custom proxy decorator for reorderable lists ensuring smooth dark theme visuals
/// without blinding white or grey slabs during dragging.
///
/// The pickup scale/elevation is animated once; the drag position itself is not
/// rebuilt here, so the overlay stays on the compositor and does not stutter.
Widget maboyReorderProxyDecorator(
  Widget child,
  int index,
  Animation<double> animation,
) {
  return AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (BuildContext context, Widget? child) {
      final animValue = Curves.easeOutCubic.transform(animation.value);
      final elevation = lerpDouble(0, 6, animValue) ?? 0;
      final scale = lerpDouble(1, 1.015, animValue) ?? 1;
      return Transform.scale(
        scale: scale,
        child: Material(
          elevation: elevation,
          color: MaboyColors.surfaceHigh,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: MaboyColors.surfaceHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: MaboyColors.primary.withValues(alpha: 0.45 * animValue),
                width: 1.5,
              ),
            ),
            child: child,
          ),
        ),
      );
    },
  );
}
