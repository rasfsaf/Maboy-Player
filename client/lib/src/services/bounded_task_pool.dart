import 'dart:async';
import 'dart:collection';

/// Runs keyed asynchronous work with a hard concurrency limit.
///
/// A key can be queued only once. Re-enqueuing a pending key with [priority]
/// moves it to the front instead of creating duplicate network work.
class BoundedTaskPool<K> {
  BoundedTaskPool({required this.maxConcurrent})
    : assert(maxConcurrent > 0, 'maxConcurrent must be positive');

  final int maxConcurrent;
  final Queue<_TaskEntry<K>> _pending = Queue<_TaskEntry<K>>();
  final Map<K, _TaskEntry<K>> _entries = <K, _TaskEntry<K>>{};
  int _activeCount = 0;

  int get activeCount => _activeCount;
  int get pendingCount => _pending.length;
  bool contains(K key) => _entries.containsKey(key);

  Future<void> enqueue(
    K key,
    Future<void> Function() task, {
    bool priority = false,
  }) {
    final existing = _entries[key];
    if (existing != null) {
      if (priority && !existing.started) {
        _pending.remove(existing);
        _pending.addFirst(existing);
      }
      return existing.completer.future;
    }

    final entry = _TaskEntry<K>(key: key, task: task);
    _entries[key] = entry;
    if (priority) {
      _pending.addFirst(entry);
    } else {
      _pending.addLast(entry);
    }
    _pump();
    return entry.completer.future;
  }

  void _pump() {
    while (_activeCount < maxConcurrent && _pending.isNotEmpty) {
      final entry = _pending.removeFirst()..started = true;
      _activeCount++;
      unawaited(_run(entry));
    }
  }

  Future<void> _run(_TaskEntry<K> entry) async {
    try {
      await entry.task();
      entry.completer.complete();
    } catch (error, stackTrace) {
      entry.completer.completeError(error, stackTrace);
    } finally {
      _activeCount--;
      _entries.remove(entry.key);
      _pump();
    }
  }
}

class _TaskEntry<K> {
  _TaskEntry({required this.key, required this.task});

  final K key;
  final Future<void> Function() task;
  final Completer<void> completer = Completer<void>();
  bool started = false;
}
