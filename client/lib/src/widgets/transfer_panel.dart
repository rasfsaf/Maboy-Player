import 'package:flutter/material.dart';

import '../design_system.dart';
import '../transfer_log.dart';

/// Floating panel that summarizes in-flight and finished transfers.
/// Collapses to a compact pill showing only the active count.
class TransferPanel extends StatefulWidget {
  const TransferPanel({super.key, required this.log});

  final TransferLog log;

  @override
  State<TransferPanel> createState() => _TransferPanelState();
}

class _TransferPanelState extends State<TransferPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: widget.log.expanded ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    widget.log.addListener(_onLog);
  }

  @override
  void dispose() {
    widget.log.removeListener(_onLog);
    _controller.dispose();
    super.dispose();
  }

  void _onLog() {
    if (widget.log.expanded && _controller.value != 1) {
      _controller.forward();
    } else if (!widget.log.expanded && _controller.value != 0) {
      _controller.reverse();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final entries = log.entries;

    if (entries.isEmpty) return const SizedBox.shrink();

    return Positioned(
      right: 16,
      bottom: MediaQuery.of(context).padding.bottom + 96,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width.clamp(280, 420).toDouble(),
        ),
        child: Material(
          color: MaboyColors.surface,
          elevation: 16,
          shadowColor: Colors.black.withValues(alpha: 0.55),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: const BorderSide(color: MaboyColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Header(
                      log: log,
                      onToggle: log.toggle,
                      onClear: log.clearFinished,
                    ),
                    ClipRect(
                      child: Align(
                        alignment: Alignment.topCenter,
                        heightFactor: t,
                        child: Opacity(
                          opacity: t,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: 320 * t,
                            ),
                            child: log.expanded
                                ? _LogList(entries: entries)
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.log,
    required this.onToggle,
    required this.onClear,
  });

  final TransferLog log;
  final VoidCallback onToggle;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final active = log.activeCount;
    final finished = log.totalCount - active;

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            AnimatedRotation(
              turns: log.expanded ? 0 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                log.expanded
                    ? Icons.expand_more_rounded
                    : Icons.expand_less_rounded,
                color: MaboyColors.textMuted,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'TRANSFERS',
              style: TextStyle(
                color: MaboyColors.textSubtle,
                fontSize: 11,
                letterSpacing: 2.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 12),
            _Pill(
              label: active > 0 ? '$active active' : 'idle',
              color: active > 0 ? MaboyColors.accent : MaboyColors.textMuted,
            ),
            if (finished > 0) ...[
              const SizedBox(width: 6),
              _Pill(
                label: '$finished done',
                color: MaboyColors.success,
              ),
            ],
            const Spacer(),
            if (finished > 0)
              IconButton(
                onPressed: onClear,
                visualDensity: VisualDensity.compact,
                tooltip: 'Clear finished',
                icon: const Icon(
                  Icons.cleaning_services_outlined,
                  color: MaboyColors.textMuted,
                  size: 18,
                ),
              ),
            IconButton(
              onPressed: onToggle,
              visualDensity: VisualDensity.compact,
              tooltip: log.expanded ? 'Hide' : 'Show',
              icon: Icon(
                log.expanded
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: MaboyColors.textMuted,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LogList extends StatelessWidget {
  const _LogList({required this.entries});

  final List<TransferEntry> entries;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        return _LogRow(entry: entries[index]);
      },
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: Colors.white.withValues(alpha: 0.05),
      ),
      itemCount: entries.length,
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final TransferEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusIcon(status: entry.status),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MaboyColors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (entry.detail != null || entry.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      entry.error ?? entry.detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: entry.error != null
                            ? MaboyColors.danger
                            : MaboyColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                if (entry.isActive)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: entry.progress > 0 ? entry.progress : null,
                      minHeight: 4,
                      backgroundColor: MaboyColors.surfaceHigh,
                      color: MaboyColors.accent,
                    ),
                  ),
              ],
            ),
          ),
          if (entry.isActive)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 4),
              child: SizedBox(
                width: 38,
                child: Text(
                  '${(entry.progress * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: MaboyColors.accent,
                    fontFeatures: [FontFeature.tabularFigures()],
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final TransferStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case TransferStatus.running:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: MaboyColors.accent,
          ),
        );
      case TransferStatus.queued:
        return const Icon(
          Icons.schedule_outlined,
          color: MaboyColors.textMuted,
          size: 18,
        );
      case TransferStatus.done:
        return const Icon(
          Icons.check_circle_rounded,
          color: MaboyColors.success,
          size: 18,
        );
      case TransferStatus.failed:
        return const Icon(
          Icons.error_outline_rounded,
          color: MaboyColors.danger,
          size: 18,
        );
    }
  }
}

/// Compact pill — used inside toolbars / buttons to surface active transfers
/// without opening the panel.
class TransferIndicator extends StatelessWidget {
  const TransferIndicator({
    super.key,
    required this.log,
    required this.onTap,
  });

  final TransferLog log;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = log.activeCount;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Transfers',
          onPressed: onTap,
          icon: const Icon(
            Icons.swap_vert_rounded,
            color: MaboyColors.textMuted,
          ),
        ),
        if (active > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: MaboyColors.accent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                boxShadow: [
                  BoxShadow(
                    color: MaboyColors.accent.withValues(alpha: 0.5),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Text(
                '$active',
                style: const TextStyle(
                  color: Color(0xff001214),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}