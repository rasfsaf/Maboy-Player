import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../design_system.dart';
import '../equalizer.dart';

class EqualizerPage extends StatelessWidget {
  const EqualizerPage({super.key, required this.controller});

  final AppController controller;

  Future<String?> _askName(
    BuildContext context, {
    String title = 'Сохранить пресет',
    String initial = '',
  }) async {
    final input = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Название'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    input.dispose();
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  Future<void> _save(BuildContext context) async {
    final name = await _askName(context);
    if (name == null || !context.mounted) return;
    try {
      await controller.saveEqualizerPreset(name);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _rename(BuildContext context, EqualizerPreset preset) async {
    final name = await _askName(
      context,
      title: 'Переименовать пресет',
      initial: preset.name,
    );
    if (name != null) await controller.renameEqualizerPreset(preset.id, name);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: MaboyBackdrop(
      child: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final active = controller.activeEqualizerPreset;
            final customActive = active != null && !active.isBuiltIn;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Назад',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(child: MaboyBrand(size: 32)),
                        Text(
                          'EQ / 06 BAND',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: MaboyColors.textMuted,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.7,
                              ),
                        ),
                        const SizedBox(width: 12),
                        Switch(
                          value: controller.equalizerEnabled,
                          onChanged: controller.setEqualizerEnabled,
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                  sliver: SliverList.list(
                    children: [
                      Text(
                        'Эквалайзер',
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.5,
                            ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Шесть музыкальных диапазонов · автоматический preamp против клиппинга',
                        style: TextStyle(color: MaboyColors.textMuted),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                        decoration: BoxDecoration(
                          color: MaboyColors.surface.withValues(alpha: 0.94),
                          border: Border.all(color: MaboyColors.border),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Column(
                          children: [
                            SizedBox(
                              height: 122,
                              child: CustomPaint(
                                painter: _EqualizerCurvePainter(
                                  gains: controller.equalizerGains,
                                  enabled: controller.equalizerEnabled,
                                ),
                                size: Size.infinite,
                              ),
                            ),
                            const Divider(height: 24),
                            SizedBox(
                              height: 265,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: List.generate(
                                  equalizerFrequencies.length,
                                  (index) => Expanded(
                                    child: _BandSlider(
                                      label: equalizerFrequencyLabels[index],
                                      value: controller.equalizerGains[index],
                                      enabled: controller.equalizerEnabled,
                                      onChanged: (value) => controller
                                          .setEqualizerBand(index, value),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Text(
                            active?.name ?? 'Ручная настройка',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const Spacer(),
                          OutlinedButton.icon(
                            onPressed: () => _save(context),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Сохранить'),
                          ),
                          if (customActive) ...[
                            const SizedBox(width: 8),
                            PopupMenuButton<String>(
                              tooltip: 'Действия с пресетом',
                              onSelected: (action) async {
                                if (action == 'rename') {
                                  await _rename(context, active);
                                } else if (action == 'delete') {
                                  await controller.deleteEqualizerPreset(
                                    active.id,
                                  );
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Переименовать'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Удалить'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: controller.equalizerPresets.map((preset) {
                          final selected =
                              controller.activeEqualizerPresetId == preset.id;
                          return ChoiceChip(
                            selected: selected,
                            showCheckmark: false,
                            label: Text(preset.name),
                            avatar: preset.id == 'metal_plus'
                                ? const Icon(Icons.bolt, size: 17)
                                : null,
                            onSelected: (_) =>
                                controller.selectEqualizerPreset(preset.id),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'DEVICE LOCAL  /  выбор и включение не синхронизируются',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: MaboyColors.textMuted,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}',
        style: const TextStyle(
          fontSize: 11,
          color: MaboyColors.textMuted,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      Expanded(
        child: RotatedBox(
          quarterTurns: 3,
          child: Slider(
            min: -12,
            max: 12,
            divisions: 48,
            value: value,
            onChanged: enabled ? onChanged : null,
          ),
        ),
      ),
      Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

class _EqualizerCurvePainter extends CustomPainter {
  const _EqualizerCurvePainter({required this.gains, required this.enabled});

  final List<double> gains;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.height / 2;
    final grid = Paint()
      ..color = MaboyColors.border
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, center), Offset(size.width, center), grid);
    for (var index = 0; index < gains.length; index++) {
      final x = size.width * index / (gains.length - 1);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    final path = Path();
    for (var index = 0; index < gains.length; index++) {
      final x = size.width * index / (gains.length - 1);
      final y = center - gains[index] / 24 * size.height;
      index == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = enabled ? MaboyColors.primary : MaboyColors.textMuted
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _EqualizerCurvePainter oldDelegate) =>
      oldDelegate.enabled != enabled || oldDelegate.gains != gains;
}
