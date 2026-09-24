import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../design_system.dart';
import '../services/storage_service.dart';

/// Shows the storage settings dialog for toggling SD-card preference
/// and viewing storage volume status.
Future<void> showStorageSettingsDialog(
  BuildContext context,
  AppController controller,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => StorageSettingsDialog(controller: controller),
  );
}

class StorageSettingsDialog extends StatefulWidget {
  const StorageSettingsDialog({super.key, required this.controller});
  final AppController controller;

  @override
  State<StorageSettingsDialog> createState() => _StorageSettingsDialogState();
}

class _StorageSettingsDialogState extends State<StorageSettingsDialog> {
  late bool _preferSd;
  List<StorageVolumeInfo>? _volumes;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _preferSd = widget.controller.storageService.preferSdCard;
    _loadVolumes();
  }

  Future<void> _loadVolumes() async {
    setState(() => _isLoading = true);
    final vols = await widget.controller.storageService.getStorageVolumes();
    if (mounted) {
      setState(() {
        _volumes = vols;
        _isLoading = false;
      });
    }
  }

  Future<void> _togglePreferSd(bool value) async {
    setState(() => _preferSd = value);
    await widget.controller.storageService.setPreferSdCard(value);
    widget.controller.notifyListeners();
  }

  @override
  Widget build(BuildContext context) {
    final sdVolume = _volumes?.where((v) => v.isRemovable).firstOrNull;
    final isSdUsable = sdVolume != null &&
        sdVolume.freeBytes >= StorageService.minFreeSpaceBytes;

    return AlertDialog(
      backgroundColor: MaboyColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: const Row(
        children: [
          Icon(Icons.sd_card, color: MaboyColors.primary),
          SizedBox(width: 12),
          Text(
            'Хранилище музыки',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // Switch row
              Container(
                decoration: BoxDecoration(
                  color: MaboyColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Загружать на SD-карту',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sdVolume == null
                                ? 'SD-карта не обнаружена'
                                : _preferSd
                                    ? (isSdUsable
                                        ? 'SD активна для загрузок'
                                        : 'SD переполнена (активен фоллбек)')
                                    : 'Отключено пользователем',
                            style: TextStyle(
                              fontSize: 12,
                              color: sdVolume == null
                                  ? MaboyColors.textMuted
                                  : _preferSd
                                      ? (isSdUsable
                                          ? MaboyColors.secondary
                                          : MaboyColors.warning)
                                      : MaboyColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _preferSd,
                      onChanged: _togglePreferSd,
                      activeColor: MaboyColors.primary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Volume list
              const Text(
                'Носители информации:',
                style: TextStyle(
                  color: MaboyColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_volumes == null || _volumes!.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: MaboyColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Информация о дисках недоступна',
                    style: TextStyle(color: MaboyColors.textMuted, fontSize: 13),
                  ),
                )
              else
                ..._volumes!.map((vol) {
                  final isThisSd = vol.isRemovable;
                  final isActiveForDownload = isThisSd
                      ? (_preferSd && vol.freeBytes >= StorageService.minFreeSpaceBytes)
                      : (!_preferSd || !isSdUsable);

                  final usedBytes = vol.totalBytes > vol.freeBytes
                      ? vol.totalBytes - vol.freeBytes
                      : 0;
                  final ratio = vol.totalBytes > 0
                      ? (usedBytes / vol.totalBytes).clamp(0.0, 1.0)
                      : 0.0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: MaboyColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isActiveForDownload
                            ? MaboyColors.secondary.withValues(alpha: 0.4)
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isThisSd ? Icons.sd_card : Icons.storage,
                              size: 18,
                              color: isActiveForDownload
                                  ? MaboyColors.secondary
                                  : MaboyColors.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                vol.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (isActiveForDownload)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: MaboyColors.secondary
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Загрузка сюда',
                                  style: TextStyle(
                                    color: MaboyColors.secondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (vol.totalBytes > 0) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: ratio,
                              backgroundColor: Colors.white.withValues(alpha: 0.1),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isActiveForDownload
                                    ? MaboyColors.secondary
                                    : MaboyColors.textMuted,
                              ),
                              minHeight: 4,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Свободно ${vol.freeSpaceFormatted} из ${vol.totalSpaceFormatted}',
                            style: const TextStyle(
                              color: MaboyColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 4),
                          Text(
                            vol.path,
                            style: const TextStyle(
                              color: MaboyColors.textMuted,
                              fontSize: 10,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  );
                }),

              const SizedBox(height: 8),
              // Explanation text
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
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
                        'При переполнении SD (< 150 МБ) или её извлечении треки автоматически загружаются во внутреннюю память. Уже скачанные треки всегда доступны.',
                        style: TextStyle(
                          color: MaboyColors.textMuted,
                          fontSize: 11,
                          height: 1.3,
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}
