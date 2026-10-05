import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../design_system.dart';
import '../services/performance_service.dart';

/// Shows the performance settings dialog for configuring graphics quality,
/// low-end device optimizations (e.g. for Samsung Galaxy J4), and blur styles.
Future<void> showPerformanceSettingsDialog(
  BuildContext context,
  AppController controller,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => PerformanceSettingsDialog(controller: controller),
  );
}

class PerformanceSettingsDialog extends StatefulWidget {
  const PerformanceSettingsDialog({super.key, required this.controller});
  final AppController controller;

  @override
  State<PerformanceSettingsDialog> createState() =>
      _PerformanceSettingsDialogState();
}

class _PerformanceSettingsDialogState extends State<PerformanceSettingsDialog> {
  late PerformanceMode _currentMode;

  late bool _amoledBlack;
  late bool _batterySaver;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.controller.performanceService.mode;
    _amoledBlack = widget.controller.performanceService.enableAmoledBlack;
    _batterySaver = widget.controller.performanceService.batterySaver;
  }

  Future<void> _setMode(PerformanceMode mode) async {
    setState(() {
      _currentMode = mode;
      _amoledBlack = widget.controller.performanceService.enableAmoledBlack;
    });
    await widget.controller.performanceService.setMode(mode);
  }

  Future<void> _toggleAmoledBlack(bool value) async {
    setState(() => _amoledBlack = value);
    await widget.controller.performanceService.setAmoledBlack(value);
  }

  Future<void> _toggleBatterySaver(bool value) async {
    setState(() => _batterySaver = value);
    await widget.controller.performanceService.setBatterySaver(value);
  }

  @override
  Widget build(BuildContext context) {
    final perf = widget.controller.performanceService;
    final isOptimized = perf.isOptimized;

    return AlertDialog(
      backgroundColor: MaboyColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: const Row(
        children: [
          Icon(Icons.speed, color: MaboyColors.primary),
          SizedBox(width: 12),
          Text(
            'Производительность',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hardware status banner
              Container(
                decoration: BoxDecoration(
                  color: MaboyColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isOptimized
                        ? MaboyColors.primary.withValues(alpha: 0.35)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      isOptimized ? Icons.bolt : Icons.tune,
                      color: isOptimized
                          ? MaboyColors.primary
                          : MaboyColors.textMuted,
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isOptimized
                                ? 'Режим плавности: 60 FPS'
                                : 'Режим полного качества',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            perf.deviceSummary,
                            style: const TextStyle(
                              fontSize: 12,
                              color: MaboyColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'РЕЖИМ ГРАФИКИ И БЫСТРОДЕЙСТВИЯ',
                style: TextStyle(
                  color: MaboyColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),

              // Options
              _buildOptionTile(
                mode: PerformanceMode.auto,
                title: 'Авто (рекомендуется)',
                subtitle:
                    'Автоматически включает ускорение графики для слабых телефонов (Samsung Galaxy J4 и др.).',
                icon: Icons.auto_awesome,
              ),
              const SizedBox(height: 6),
              _buildOptionTile(
                mode: PerformanceMode.highPerformance,
                title: 'Высокая производительность',
                subtitle:
                    'Стильное акриловое стекло без нагрузки на GPU, мгновенный отклик, экономия батареи.',
                icon: Icons.rocket_launch,
              ),
              const SizedBox(height: 6),
              _buildOptionTile(
                mode: PerformanceMode.highQuality,
                title: 'Максимальные эффекты',
                subtitle:
                    'Матовое размытие BackdropFilter и постоянная анимация (для мощных ПК и флагманов).',
                icon: Icons.blur_on,
              ),

              const SizedBox(height: 16),
              const Text(
                'БАТАРЕЯ И ЭНЕРГОСБЕРЕЖЕНИЕ',
                style: TextStyle(
                  color: MaboyColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),

              // Battery Saver Switch
              Container(
                decoration: BoxDecoration(
                  color: MaboyColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.battery_saver, color: MaboyColors.primary, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Энергосбережение батареи',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Остановка сетевого поллинга при заблокированном экране.',
                            style: TextStyle(fontSize: 11, color: MaboyColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _batterySaver,
                      onChanged: _toggleBatterySaver,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // Super AMOLED Pure Black Switch
              Container(
                decoration: BoxDecoration(
                  color: MaboyColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.dark_mode, color: MaboyColors.secondary, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Super AMOLED глубокий черный',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '0% расхода дисплея на темных участках экрана J4.',
                            style: TextStyle(fontSize: 11, color: MaboyColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _amoledBlack,
                      onChanged: _toggleAmoledBlack,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),
              // Explanation of minimal visual loss
              Container(
                decoration: BoxDecoration(
                  color: MaboyColors.surfaceHigh.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(10),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: MaboyColors.textMuted,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'В режиме производительности сохраняется красивый темный дизайн и неоновые акценты, устраняя просадки FPS и перегрев.',
                        style: TextStyle(
                          fontSize: 12,
                          color: MaboyColors.textMuted,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Готово'),
        ),
      ],
    );
  }

  Widget _buildOptionTile({
    required PerformanceMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = _currentMode == mode;
    return InkWell(
      onTap: () => _setMode(mode),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? MaboyColors.primary.withValues(alpha: 0.12)
              : MaboyColors.surfaceHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? MaboyColors.primary.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                icon,
                size: 20,
                color: selected ? MaboyColors.primary : MaboyColors.textMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 14,
                      color: selected ? Colors.white : MaboyColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: MaboyColors.textMuted,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Padding(
                padding: EdgeInsets.only(left: 6, top: 2),
                child: Icon(
                  Icons.check_circle,
                  color: MaboyColors.primary,
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
