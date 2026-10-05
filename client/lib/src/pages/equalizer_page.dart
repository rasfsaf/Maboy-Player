import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../design_system.dart';
import '../equalizer.dart';
import '../widgets/bass_boost_section.dart';

class EqualizerPage extends StatefulWidget {
  const EqualizerPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<EqualizerPage> createState() => _EqualizerPageState();
}

class _EqualizerPageState extends State<EqualizerPage> {
  String? _selectedFolderId;

  @override
  void initState() {
    super.initState();
    _selectedFolderId = widget.controller.playingFolder;
  }

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
      await widget.controller.saveEqualizerPreset(
        name,
        folderId: _selectedFolderId,
      );
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
    if (name != null) {
      await widget.controller.renameEqualizerPreset(preset.id, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final eqService = controller.equalizerService;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MaboyBackdrop(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([controller, eqService]),
            builder: (context, _) {
              final isGlobal = _selectedFolderId == null;
              final hasOverride = !isGlobal &&
                  eqService.hasFolderOverride(_selectedFolderId!);

              final currentConfig = isGlobal
                  ? eqService.globalConfig
                  : (hasOverride
                      ? eqService.getFolderConfig(_selectedFolderId!)!
                      : eqService.globalConfig);

              final activePreset = controller.equalizerPresets
                  .where((preset) => preset.id == currentConfig.presetId)
                  .firstOrNull;
              final customActive =
                  activePreset != null && !activePreset.isBuiltIn;

              final selectedPlaylist = isGlobal
                  ? null
                  : controller.playlists
                      .where((p) => p['id'] == _selectedFolderId)
                      .firstOrNull;

              final isCurrentlyPlayingThisScope = isGlobal
                  ? controller.playingFolder == null
                  : controller.playingFolder == _selectedFolderId;

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
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: MaboyColors.textMuted,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.7,
                                    ),
                          ),
                          const SizedBox(width: 12),
                          Switch(
                            value: currentConfig.enabled,
                            onChanged: (enabled) =>
                                eqService.setScopeEnabled(
                              _selectedFolderId,
                              enabled,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                    sliver: SliverList.list(
                      children: [
                        Row(
                          children: [
                            Text(
                              'Эквалайзер',
                              style: Theme.of(context)
                                  .textTheme
                                  .displaySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -1.5,
                                  ),
                            ),
                            if (isCurrentlyPlayingThisScope &&
                                controller.player.playing) ...[
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: MaboyColors.secondary
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Играет сейчас',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: MaboyColors.secondary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 10,
                                      ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Шесть музыкальных диапазонов · автоматический preamp против клиппинга',
                          style: TextStyle(color: MaboyColors.textMuted),
                        ),
                        const SizedBox(height: 18),

                        // Scope selector (Global vs Playlist/Folder)
                        Text(
                          'Область действия:',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: MaboyColors.textMuted,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.1,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: MaboyColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color:
                                  MaboyColors.border.withValues(alpha: 0.5),
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String?>(
                              isExpanded: true,
                              value: _selectedFolderId,
                              dropdownColor: MaboyColors.surfaceHigh,
                              icon: const Icon(
                                Icons.arrow_drop_down,
                                color: MaboyColors.textMuted,
                              ),
                              items: [
                                DropdownMenuItem<String?>(
                                  value: null,
                                  child: Row(
                                    children: const [
                                      Icon(
                                        Icons.public,
                                        size: 18,
                                        color: MaboyColors.primary,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Глобально (по умолчанию для всех треков)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                for (final pl in controller.playlists)
                                  DropdownMenuItem<String?>(
                                    value: pl['id'] as String,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.queue_music,
                                          size: 18,
                                          color: eqService.hasFolderOverride(
                                                  pl['id'] as String)
                                              ? MaboyColors.secondary
                                              : MaboyColors.textMuted,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Папка: ${pl['name']}',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (controller.playingFolder ==
                                            pl['id'])
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                left: 6),
                                            child: Text(
                                              '(играет)',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: MaboyColors.secondary,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        if (eqService.hasFolderOverride(
                                            pl['id'] as String))
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                left: 6),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 5,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: MaboyColors.secondary
                                                    .withValues(alpha: 0.18),
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                              child: const Text(
                                                'Свой EQ',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color:
                                                      MaboyColors.secondary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                              onChanged: (id) =>
                                  setState(() => _selectedFolderId = id),
                            ),
                          ),
                        ),

                        // Folder override banner
                        if (!isGlobal) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: hasOverride
                                  ? MaboyColors.secondary
                                      .withValues(alpha: 0.08)
                                  : MaboyColors.surfaceHigh
                                      .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: hasOverride
                                    ? MaboyColors.secondary
                                        .withValues(alpha: 0.3)
                                    : MaboyColors.border
                                        .withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  hasOverride ? Icons.tune : Icons.link,
                                  size: 20,
                                  color: hasOverride
                                      ? MaboyColors.secondary
                                      : MaboyColors.textMuted,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    hasOverride
                                        ? 'Для «${selectedPlaylist?['name'] ?? 'папки'}» задана индивидуальная настройка эквалайзера'
                                        : 'Используются общие глобальные настройки для этой папки',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: hasOverride
                                          ? MaboyColors.text
                                          : MaboyColors.textMuted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (hasOverride)
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () => eqService
                                        .removeFolderConfig(_selectedFolderId!),
                                    child: const Text(
                                      'Сбросить к глобальным',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  )
                                else
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: MaboyColors.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () {
                                      eqService.setFolderConfig(
                                        _selectedFolderId!,
                                        eqService.globalConfig
                                            .copyWith(enabled: true),
                                      );
                                    },
                                    child: const Text(
                                      'Настроить отдельно',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // Equalizer Curve & Sliders Box
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
                                    gains: currentConfig.gains,
                                    enabled: currentConfig.enabled,
                                  ),
                                  size: Size.infinite,
                                ),
                              ),
                              const Divider(height: 24),
                              SizedBox(
                                height: 265,
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: List.generate(
                                    equalizerFrequencies.length,
                                    (index) => Expanded(
                                      child: _BandSlider(
                                        label: equalizerFrequencyLabels[index],
                                        value: currentConfig.gains[index],
                                        enabled: currentConfig.enabled,
                                        onChanged: (value) =>
                                            eqService.setScopeBand(
                                          _selectedFolderId,
                                          index,
                                          value,
                                        ),
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
                              activePreset?.name ??
                                  (currentConfig.presetId == 'manual'
                                      ? 'Ручная настройка'
                                      : currentConfig.presetId),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
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
                                    await _rename(context, activePreset);
                                  } else if (action == 'delete') {
                                    await controller.deleteEqualizerPreset(
                                      activePreset.id,
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
                                currentConfig.presetId == preset.id;
                            return ChoiceChip(
                              selected: selected,
                              showCheckmark: false,
                              label: Text(preset.name),
                              avatar: preset.id == 'metal_plus'
                                  ? const Icon(Icons.bolt, size: 17)
                                  : null,
                              onSelected: (_) => eqService.setScopePreset(
                                _selectedFolderId,
                                preset,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'DEVICE LOCAL  /  настройки эквалайзера сохраняются на этом устройстве',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: MaboyColors.textMuted,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.1,
                                  ),
                        ),
                        const SizedBox(height: 24),
                        BassBoostSection(controller: controller),
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
