import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/services/bounded_task_pool.dart';

void main() {
  test('pool never exceeds its concurrency limit', () async {
    final pool = BoundedTaskPool<int>(maxConcurrent: 3);
    var active = 0;
    var peak = 0;
    final gate = Completer<void>();

    final futures = [
      for (var index = 0; index < 8; index++)
        pool.enqueue(index, () async {
          active++;
          if (active > peak) peak = active;
          await gate.future;
          active--;
        }),
    ];

    await Future<void>.delayed(Duration.zero);
    expect(pool.activeCount, 3);
    expect(pool.pendingCount, 5);
    expect(peak, 3);

    gate.complete();
    await Future.wait(futures);
    expect(pool.activeCount, 0);
    expect(pool.pendingCount, 0);
  });

  test(
    'duplicate key shares work and priority promotes pending task',
    () async {
      final pool = BoundedTaskPool<String>(maxConcurrent: 1);
      final gate = Completer<void>();
      final order = <String>[];

      final first = pool.enqueue('first', () async {
        order.add('first');
        await gate.future;
      });
      final last = pool.enqueue('last', () async => order.add('last'));
      final promoted = pool.enqueue(
        'promoted',
        () async => order.add('promoted'),
      );
      final duplicate = pool.enqueue(
        'promoted',
        () async => order.add('duplicate'),
        priority: true,
      );

      expect(identical(promoted, duplicate), isTrue);
      gate.complete();
      await Future.wait([first, last, promoted, duplicate]);
      expect(order, ['first', 'promoted', 'last']);
    },
  );
}
