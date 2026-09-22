import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/widgets/marquee_text.dart';

void main() {
  testWidgets('MarqueeText renders static text when content fits within constraints',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: MarqueeText('Short Title'),
          ),
        ),
      ),
    );

    // Initial pump
    await tester.pump();

    // Verify static Text widget exists
    expect(find.text('Short Title'), findsOneWidget);
    // Since it fits, there is no Stack with repeated copies inside MarqueeText
    expect(
      find.descendant(
        of: find.byType(MarqueeText),
        matching: find.byType(Stack),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'MarqueeText creates infinite marquee copies and scrolls when overflowing',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 100,
            child: MarqueeText('Very Long Symphony Track Title Number 99 in E Minor'),
          ),
        ),
      ),
    );

    // Pump widget and allow post-frame callback to trigger animation
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Because width is 100 and text is much longer, multiple copies are placed in the Stack
    // to create the seamless infinite wrap effect.
    final marqueeStackFinder = find.descendant(
      of: find.byType(MarqueeText),
      matching: find.byType(Stack),
    );
    expect(marqueeStackFinder, findsOneWidget);

    final textFinders = find.text('Very Long Symphony Track Title Number 99 in E Minor');
    expect(textFinders, findsAtLeastNWidgets(2));

    // Pump some duration to verify continuous movement without crashing
    await tester.pump(const Duration(seconds: 2));
    expect(textFinders, findsAtLeastNWidgets(2));
  });

  testWidgets('MarqueeText resets and recalculates when text changes',
      (tester) async {
    String currentText = 'First Very Long Track Title That Exceeds The Constrained Container Width';

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              child: MarqueeText(currentText),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text(currentText), findsAtLeastNWidgets(2));

    // Change to short text
    currentText = 'Short';
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              child: MarqueeText(currentText),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Now it fits, so only one static text widget is rendered
    expect(find.text('Short'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MarqueeText),
        matching: find.byType(Stack),
      ),
      findsNothing,
    );
  });
}
