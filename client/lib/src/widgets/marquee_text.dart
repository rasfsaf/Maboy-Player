import 'package:flutter/material.dart';

/// A marquee text widget that automatically scrolls when the text overflows its
/// available bounded width.
///
/// Instead of jumping back to the start when reaching the end, it implements a
/// seamless infinite loop: as the text moves off the left edge, a duplicate
/// enters from the right edge with a clean gap, creating a continuous ticker effect.
class MarqueeText extends StatefulWidget {
  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.gap = 48.0,
    this.velocity = 35.0,
  });

  /// The text to display.
  final String text;

  /// Optional text style. Ambient [DefaultTextStyle] will be merged into this.
  final TextStyle? style;

  /// Blank spacing (in logical pixels) between consecutive repetitions.
  final double gap;

  /// Scroll speed in logical pixels per second.
  final double velocity;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _wasOverflowing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text || widget.style != oldWidget.style) {
      _controller.reset();
      if (_wasOverflowing) {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final textScaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final defaultStyle = DefaultTextStyle.of(context).style;
    final effectiveStyle = widget.style != null
        ? defaultStyle.merge(widget.style)
        : defaultStyle;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || constraints.maxWidth <= 0) {
          return Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            softWrap: false,
          );
        }

        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: effectiveStyle),
          maxLines: 1,
          textDirection: textDirection,
          textScaler: textScaler,
        )..layout();

        final overflow = painter.width > constraints.maxWidth;

        if (!overflow) {
          if (_wasOverflowing) {
            _wasOverflowing = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _controller.isAnimating) {
                _controller.stop();
              }
            });
          }
          return Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            softWrap: false,
          );
        }

        final cycleDistance = painter.width + widget.gap;
        final targetDurationMs = (cycleDistance / widget.velocity * 1000)
            .round()
            .clamp(1000, 120000);
        final targetDuration = Duration(milliseconds: targetDurationMs);

        if (_controller.duration != targetDuration) {
          _controller.duration = targetDuration;
        }

        if (!_wasOverflowing || !_controller.isAnimating) {
          _wasOverflowing = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_controller.isAnimating) {
              _controller.repeat();
            }
          });
        }

        final staticChild = Text(
          widget.text,
          style: widget.style,
          maxLines: 1,
          softWrap: false,
        );

        return SizedBox(
          width: constraints.maxWidth,
          height: painter.height,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final offset = -_controller.value * cycleDistance;
                final copies = <Widget>[];
                double currentX = offset;
                while (copies.length < 2 || currentX < constraints.maxWidth) {
                  copies.add(
                    Positioned(
                      left: currentX,
                      top: 0,
                      bottom: 0,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: child,
                      ),
                    ),
                  );
                  currentX += cycleDistance;
                }

                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: copies,
                );
              },
              child: staticChild,
            ),
          ),
        );
      },
    );
  }
}
