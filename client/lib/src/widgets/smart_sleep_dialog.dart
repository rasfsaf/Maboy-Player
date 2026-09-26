import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../design_system.dart';
import '../services/smart_sleep_service.dart';

/// Shows the Smart Sleep Mode configuration and status modal.
Future<void> showSmartSleepDialog(BuildContext context, AppController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SmartSleepSheet(controller: controller),
  );
}

class SmartSleepSheet extends StatelessWidget {
  const SmartSleepSheet({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.smartSleepService,
      builder: (context, _) {
        final service = controller.smartSleepService;
        final enabled = service.isEnabled;
        final state = service.state;

        return Material(
          color: const Color(0xFF18181B),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: MaboyColors.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.bedtime_outlined,
                      color: MaboyColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Умный таймер сна',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Мягкое затухание при засыпании',
                          style: TextStyle(
                            fontSize: 12,
                            color: MaboyColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: enabled,
                    activeColor: MaboyColors.primary,
                    onChanged: (val) => service.setEnabled(val),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildStatusCard(context, service),
              const SizedBox(height: 20),
              const Text(
                'Базовое окно бездействия',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: MaboyColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [15, 30, 45, 60].map((minutes) {
                  final isSelected =
                      service.config.inactivityTimeoutMinutes == minutes;
                  return ChoiceChip(
                    label: Text('$minutes мин'),
                    selected: isSelected,
                    onSelected: enabled
                        ? (selected) {
                            if (selected) {
                              service.setInactivityTimeoutMinutes(minutes);
                            }
                          }
                        : null,
                    selectedColor: MaboyColors.primary.withAlpha(40),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? MaboyColors.primary
                          : MaboyColors.textMuted,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    backgroundColor: const Color(0xFF27272A),
                    side: BorderSide(
                      color: isSelected
                          ? MaboyColors.primary
                          : Colors.transparent,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Длительность затухания',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: MaboyColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [60, 90].map((seconds) {
                  final isSelected =
                      service.config.fadeDurationSeconds == seconds;
                  return ChoiceChip(
                    label: Text('$seconds сек'),
                    selected: isSelected,
                    onSelected: enabled
                        ? (selected) {
                            if (selected) {
                              service.setFadeDurationSeconds(seconds);
                            }
                          }
                        : null,
                    selectedColor: MaboyColors.primary.withAlpha(40),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? MaboyColors.primary
                          : MaboyColors.textMuted,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    backgroundColor: const Color(0xFF27272A),
                    side: BorderSide(
                      color: isSelected
                          ? MaboyColors.primary
                          : Colors.transparent,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Остановка на границе трека',
                  style: TextStyle(fontSize: 14, color: Colors.white),
                ),
                subtitle: const Text(
                  'Не включать следующий трек, если текущий закончился во время затухания',
                  style: TextStyle(fontSize: 12, color: MaboyColors.textMuted),
                ),
                value: service.config.trackBoundaryGuardEnabled,
                activeColor: MaboyColors.primary,
                onChanged: enabled
                    ? (val) => service.setTrackBoundaryGuardEnabled(val)
                    : null,
              ),
            ],
          ),
        ),
      );
    },
    );
  }

  Widget _buildStatusCard(BuildContext context, SmartSleepService service) {
    if (!service.isEnabled) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF27272A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: MaboyColors.textMuted, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Включите режим, чтобы плеер сам определил засыпание и мягко затухал.',
                style: TextStyle(color: MaboyColors.textMuted, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (service.state == SmartSleepState.monitoring) {
      final remSec = service.remainingSeconds;
      final minutes = remSec ~/ 60;
      final seconds = remSec % 60;
      final timeStr =
          '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MaboyColors.primary.withAlpha(20),
          border: Border.all(color: MaboyColors.primary.withAlpha(50)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.sensors,
                  color: MaboyColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Мониторинг сна активен',
                  style: TextStyle(
                    color: MaboyColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Text(
                  timeStr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: 1.0 - service.inactivityProgress,
                backgroundColor: Colors.white12,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(MaboyColors.primary),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Прикосновение или движение сбросит таймер',
                    style:
                        TextStyle(color: MaboyColors.textMuted, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => service.addBonusExtension(),
                  child: const Text('+20 мин'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (service.state == SmartSleepState.fading) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.amber.withAlpha(25),
          border: Border.all(color: Colors.amber.withAlpha(80)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.volume_down,
                  color: Colors.amber,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Затухание звука...',
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => service.recordUserActivity(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                  child: const Text('Не сплю (+20 мин)'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Встряхните телефон или коснитесь экрана, чтобы отменить затухание.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF27272A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.bedtime, color: MaboyColors.textMuted, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Режим готов. Запустится автоматически при включении трека.',
              style: TextStyle(color: MaboyColors.textMuted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
