import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/widgets/window_frame.dart';

void main() {
  testWidgets('borderless frame keeps window controls and drag available', (
    tester,
  ) async {
    const channel = MethodChannel('com.maboy.window');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: MaboyWindowFrame(child: Scaffold(body: Text('content'))),
      ),
    );
    expect(find.text('content'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Свернуть окно'));
    await tester.tap(find.bySemanticsLabel('Развернуть или восстановить окно'));
    await tester.tap(find.bySemanticsLabel('Закрыть окно'));
    await tester.drag(
      find.byKey(const Key('windowDragRegion')),
      const Offset(100, 0),
    );
    // Let the double-tap recognizer's short deadline expire before teardown.
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, ['minimize', 'toggleMaximize', 'close', 'startDrag']);
  });
}
