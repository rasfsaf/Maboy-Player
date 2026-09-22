import 'package:flutter/foundation.dart';

/// In-memory model for the transfer/download log.
///
/// Backed by an ordered list (oldest first) so the panel always shows the
/// same item in the same row, which makes the log read like a console.
enum TransferKind { download, ingest }

class TransferEntry {
  TransferEntry({
    required this.id,
    required this.title,
    required this.kind,
  }) : status = TransferStatus.queued;

  final String id;
  final String title;
  final TransferKind kind;

  TransferStatus status = TransferStatus.queued;
  double progress = 0;
  String? detail;
  String? error;
  DateTime? finishedAt;

  bool get isActive =>
      status == TransferStatus.queued ||
      status == TransferStatus.running;

  TransferEntry snapshot() => TransferEntry(
        id: id,
        title: title,
        kind: kind,
      )
        ..status = status
        ..progress = progress
        ..detail = detail
        ..error = error
        ..finishedAt = finishedAt;
}

enum TransferStatus { queued, running, done, failed }

/// Holds the live list of transfers. Owns the "expanded / collapsed" flag.
class TransferLog extends ChangeNotifier {
  final List<TransferEntry> _entries = <TransferEntry>[];
  bool _expanded = true;

  List<TransferEntry> get entries => List.unmodifiable(_entries);
  bool get expanded => _expanded;
  int get activeCount => _entries.where((e) => e.isActive).length;
  int get totalCount => _entries.length;

  void setExpanded(bool value) {
    if (_expanded == value) return;
    _expanded = value;
    notifyListeners();
  }

  void toggle() => setExpanded(!_expanded);

  TransferEntry begin({
    required String id,
    required String title,
    required TransferKind kind,
    String? detail,
  }) {
    final existing = _find(id);
    if (existing != null) {
      existing.status = TransferStatus.running;
      existing.progress = 0;
      existing.detail = detail;
      existing.error = null;
      notifyListeners();
      return existing;
    }
    final entry = TransferEntry(
      id: id,
      title: title,
      kind: kind,
    )
      ..status = TransferStatus.running
      ..progress = 0
      ..detail = detail;
    _entries.add(entry);
    notifyListeners();
    return entry;
  }

  void update(String id, {double? progress, String? detail}) {
    final entry = _find(id);
    if (entry == null) return;
    if (progress != null) entry.progress = progress.clamp(0.0, 1.0);
    if (detail != null) entry.detail = detail;
    notifyListeners();
  }

  void finish(String id, {String? detail}) {
    final entry = _find(id);
    if (entry == null) return;
    entry.status = TransferStatus.done;
    entry.progress = 1;
    entry.detail = detail;
    entry.finishedAt = DateTime.now();
    notifyListeners();
  }

  void fail(String id, String error) {
    final entry = _find(id);
    if (entry == null) return;
    entry.status = TransferStatus.failed;
    entry.error = error;
    entry.finishedAt = DateTime.now();
    notifyListeners();
  }

  void clearFinished() {
    _entries.removeWhere(
      (e) =>
          e.status == TransferStatus.done ||
          e.status == TransferStatus.failed,
    );
    notifyListeners();
  }

  TransferEntry? _find(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }
}