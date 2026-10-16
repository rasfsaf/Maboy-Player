import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../design_system.dart';

/// Dialog for manually entering track title and artist, with an option to refresh metadata automatically.
class EditTrackDialog extends StatefulWidget {
  const EditTrackDialog({
    super.key,
    required this.controller,
    required this.track,
  });

  final AppController controller;
  final Map<String, dynamic> track;

  @override
  State<EditTrackDialog> createState() => _EditTrackDialogState();
}

class _EditTrackDialogState extends State<EditTrackDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  bool _isRefreshing = false;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.track['title'] as String? ?? '',
    );
    _artistController = TextEditingController(
      text: widget.track['artist'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    super.dispose();
  }

  Future<void> _refreshOnlineMetadata() async {
    setState(() => _isRefreshing = true);
    final id = widget.track['id'] as String;
    final success = await widget.controller.refreshTrackMetadata(id);
    if (!mounted) return;
    setState(() => _isRefreshing = false);

    if (success) {
      final updated = widget.controller.tracks
          .where((t) => t['id'] == id)
          .firstOrNull;
      if (updated != null) {
        _titleController.text = updated['title'] as String? ?? '';
        _artistController.text = updated['artist'] as String? ?? '';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Метаданные успешно обновлены'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось найти новые метаданные'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Название не может быть пустым');
      return;
    }

    final id = widget.track['id'] as String;
    await widget.controller.updateTrackMetadata(
      id,
      title: title,
      artist: _artistController.text.trim().isNotEmpty
          ? _artistController.text.trim()
          : null,
    );

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isYouTube = widget.track['provider'] == 'youtube';

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.edit_note, color: MaboyColors.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Редактировать трек',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Название',
                hintText: 'Введите название песни',
                errorText: _titleError,
                prefixIcon: const Icon(Icons.music_note, size: 20),
              ),
              onChanged: (_) {
                if (_titleError != null) {
                  setState(() => _titleError = null);
                }
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _artistController,
              decoration: const InputDecoration(
                labelText: 'Исполнитель',
                hintText: 'Введите имя исполнителя или группы',
                prefixIcon: const Icon(Icons.person, size: 20),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isRefreshing ? null : _refreshOnlineMetadata,
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(
                _isRefreshing
                    ? 'Поиск метаданных...'
                    : (isYouTube
                        ? 'Пересобрать из YouTube'
                        : 'Пересобрать из файла'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

Future<bool?> showEditTrackDialog(
  BuildContext context,
  AppController controller,
  Map<String, dynamic> track,
) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => EditTrackDialog(
      controller: controller,
      track: track,
    ),
  );
}
