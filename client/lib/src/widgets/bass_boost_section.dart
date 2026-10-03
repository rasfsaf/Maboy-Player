import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../design_system.dart';
import '../services/bass_boost_service.dart';

/// Bass Boost configuration section providing both global and per-playlist
/// low-frequency shelf boost controls inspired by Windows Audio Enhancements.
class BassBoostSection extends StatefulWidget {
  const BassBoostSection({super.key, required this.controller});

  final AppController controller;

  @override
  State<BassBoostSection> createState() => _BassBoostSectionState();
}

class _BassBoostSectionState extends State<BassBoostSection> {
  String? _selectedPlaylistId;

  @override
  void initState() {
    super.initState();
    // Default to the currently playing playlist if active, otherwise global.
    _selectedPlaylistId = widget.controller.playingFolder;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final bassService = c.bassBoostService;

    return ListenableBuilder(
      listenable: Listenable.merge([c, bassService]),
      builder: (context, _) {
        final isGlobal = _selectedPlaylistId == null;
        final hasOverride =
            !isGlobal && bassService.hasPlaylistOverride(_selectedPlaylistId!);

        final currentConfig = isGlobal
            ? bassService.globalConfig
            : (hasOverride
                ? bassService.getPlaylistConfig(_selectedPlaylistId!)!
                : bassService.globalConfig);

        final selectedPlaylist = isGlobal
            ? null
            : c.playlists.where((p) => p['id'] == _selectedPlaylistId).firstOrNull;

        final isCurrentlyPlayingThisScope = isGlobal
            ? c.playingFolder == null
            : c.playingFolder == _selectedPlaylistId;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: MaboyColors.surface.withValues(alpha: 0.94),
            border: Border.all(color: MaboyColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: MaboyColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.surround_sound,
                      color: MaboyColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Bass Boost (Усиление басов)',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            if (isCurrentlyPlayingThisScope && c.player.playing) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
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
                        const SizedBox(height: 2),
                        const Text(
                          'Параметрический усилитель низких частот · как в Windows',
                          style: TextStyle(
                            fontSize: 12,
                            color: MaboyColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: currentConfig.enabled,
                    onChanged: (enabled) {
                      if (isGlobal) {
                        bassService.setGlobalConfig(
                          currentConfig.copyWith(enabled: enabled),
                        );
                      } else {
                        bassService.setPlaylistConfig(
                          _selectedPlaylistId!,
                          currentConfig.copyWith(enabled: enabled),
                        );
                      }
                    },
                  ),
                ],
              ),
              const Divider(height: 24),

              // Scope selector (Global vs Playlist)
              Text(
                'Область действия:',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
                  border: Border.all(color: MaboyColors.border.withValues(alpha: 0.5)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: _selectedPlaylistId,
                    dropdownColor: MaboyColors.surfaceHigh,
                    icon: const Icon(Icons.arrow_drop_down, color: MaboyColors.textMuted),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Row(
                          children: [
                            const Icon(Icons.public, size: 18, color: MaboyColors.primary),
                            const SizedBox(width: 8),
                            const Text(
                              'Глобально (по умолчанию для всех треков)',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      for (final pl in c.playlists)
                        DropdownMenuItem<String?>(
                          value: pl['id'] as String,
                          child: Row(
                            children: [
                              Icon(
                                Icons.queue_music,
                                size: 18,
                                color: bassService.hasPlaylistOverride(pl['id'] as String)
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
                              if (c.playingFolder == pl['id'])
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text(
                                    '(играет)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: MaboyColors.secondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              if (bassService.hasPlaylistOverride(pl['id'] as String))
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: MaboyColors.secondary.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: const Text(
                                      'Свои бассы',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: MaboyColors.secondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (id) => setState(() => _selectedPlaylistId = id),
                  ),
                ),
              ),

              // Playlist override toggle banner
              if (!isGlobal) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hasOverride
                        ? MaboyColors.secondary.withValues(alpha: 0.08)
                        : MaboyColors.surfaceHigh.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: hasOverride
                          ? MaboyColors.secondary.withValues(alpha: 0.3)
                          : MaboyColors.border.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        hasOverride ? Icons.tune : Icons.link,
                        size: 20,
                        color: hasOverride ? MaboyColors.secondary : MaboyColors.textMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          hasOverride
                              ? 'Для «${selectedPlaylist?['name'] ?? 'плейлиста'}» задана индивидуальная настройка баса'
                              : 'Используются общие глобальные настройки для этой папки',
                          style: TextStyle(
                            fontSize: 12,
                            color: hasOverride ? MaboyColors.text : MaboyColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (hasOverride)
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () =>
                              bassService.removePlaylistConfig(_selectedPlaylistId!),
                          child: const Text('Сбросить к глобальным', style: TextStyle(fontSize: 11)),
                        )
                      else
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: MaboyColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () {
                            bassService.setPlaylistConfig(
                              _selectedPlaylistId!,
                              bassService.globalConfig.copyWith(enabled: true),
                            );
                          },
                          child: const Text('Настроить отдельно', style: TextStyle(fontSize: 11)),
                        ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // Frequency and Boost Level Controls
              Opacity(
                opacity: currentConfig.enabled ? 1.0 : 0.45,
                child: IgnorePointer(
                  ignoring: !currentConfig.enabled,
                  child: Column(
                    children: [
                      // Frequency Row
                      Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Frequency (Частота среза):',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Частотный порог усиления саб-баса',
                                  style: TextStyle(fontSize: 11, color: MaboyColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: MaboyColors.surfaceHigh,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: MaboyColors.border),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<double>(
                                  isExpanded: true,
                                  value: currentConfig.frequency,
                                  dropdownColor: MaboyColors.surfaceHigh,
                                  items: bassBoostFrequencies.map((f) {
                                    return DropdownMenuItem<double>(
                                      value: f,
                                      child: Text(
                                        '${f.toInt()} Hz',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (newFreq) {
                                    if (newFreq == null) return;
                                    _updateConfig(
                                      bassService,
                                      isGlobal,
                                      currentConfig.copyWith(frequency: newFreq),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Boost Level Row
                      Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Boost Level (Усиление):',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: currentConfig.gainDb > 0
                                            ? MaboyColors.primary.withValues(alpha: 0.2)
                                            : MaboyColors.surfaceHigh,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        currentConfig.gainDb == 0
                                            ? 'None (0 dB)'
                                            : '+${currentConfig.gainDb.toStringAsFixed(0)} dB',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: currentConfig.gainDb > 0
                                              ? MaboyColors.primary
                                              : MaboyColors.textMuted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Усиление в дБ с защитой от искажений',
                                  style: TextStyle(fontSize: 11, color: MaboyColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: MaboyColors.surfaceHigh,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: MaboyColors.border),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<double>(
                                  isExpanded: true,
                                  value: bassBoostLevels.contains(currentConfig.gainDb)
                                      ? currentConfig.gainDb
                                      : 0.0,
                                  dropdownColor: MaboyColors.surfaceHigh,
                                  items: bassBoostLevels.map((lvl) {
                                    return DropdownMenuItem<double>(
                                      value: lvl,
                                      child: Text(
                                        lvl == 0 ? 'None' : '+${lvl.toInt()} dB',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (newGain) {
                                    if (newGain == null) return;
                                    _updateConfig(
                                      bassService,
                                      isGlobal,
                                      currentConfig.copyWith(gainDb: newGain),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Interactive Slider for rapid tweaking
                      const SizedBox(height: 8),
                      Slider(
                        value: currentConfig.gainDb,
                        min: 0,
                        max: 24,
                        divisions: 8,
                        label: currentConfig.gainDb == 0
                            ? 'None'
                            : '+${currentConfig.gainDb.toStringAsFixed(0)} dB',
                        onChanged: (val) {
                          _updateConfig(
                            bassService,
                            isGlobal,
                            currentConfig.copyWith(gainDb: val),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _updateConfig(
    BassBoostService bassService,
    bool isGlobal,
    BassBoostConfig updated,
  ) {
    if (isGlobal) {
      bassService.setGlobalConfig(updated);
    } else {
      bassService.setPlaylistConfig(_selectedPlaylistId!, updated);
    }
  }
}
