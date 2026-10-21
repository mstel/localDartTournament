import '../../../shared/widgets/sport_menu.dart';
import 'package:dart_tournament_manager/shared/widgets/adaptive_content.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import '../data/backup_service.dart';
import 'android_backup_export.dart';
import 'backup_file_dialogs.dart';
import 'cloud_backup_panel.dart';

class BackupPanel extends StatefulWidget {
  const BackupPanel({
    super.key,
    this.service,
    this.dialogs = const BackupFileDialogs(),
    this.trailing,
  });
  final BackupService? service;
  final BackupFileDialogs dialogs;
  final Widget? trailing;
  @override
  State<BackupPanel> createState() => _BackupPanelState();
}

class _BackupPanelState extends State<BackupPanel> {
  static const _areaNames = {
    'tournaments.json': 'Turniere und Ergebnisse',
    'app_database.sqlite': 'Spielerprofile und Ranglisten',
    'planning_settings.json': 'Turnierplanung',
  };
  bool _busy = false;
  String? _message;
  bool _failed = false;
  Future<BackupService> _service() async =>
      widget.service ?? await BackupService.create();

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
      _failed = false;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = error is FormatException
              ? error.message
              : 'Vorgang fehlgeschlagen. Die Datei konnte nicht verarbeitet werden. '
                    'Bitte Speicherort, freien Speicher und App-Version prüfen.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() => _run(() async {
    final categories = await showDialog<Set<String>>(
      context: context,
      builder: (context) => const _SelectiveCategoryDialog(
        title: 'Backup exportieren',
        description:
            'Wähle die Kategorien aus, die in der Datei gesichert werden sollen:',
        confirmLabel: 'Exportieren',
        availableFiles: BackupService.categoryNames,
      ),
    );
    if (categories == null || categories.isEmpty) return;

    if (Platform.isAndroid) {
      final saved = await exportAndroidBackup(
        service: await _service(),
        categories: categories,
      );
      if (mounted && saved) {
        setState(
          () => _message = 'Backup am gewählten Speicherort gespeichert.',
        );
      }
      return;
    }
    final target = await widget.dialogs.savePath();
    if (target == null) return;
    await (await _service()).exportTo(File(target), categories: categories);
    if (mounted) setState(() => _message = 'Backup gespeichert:\n$target');
  });

  Future<void> _import() => _run(() async {
    final selected = await widget.dialogs.open();
    if (selected == null) return;
    if (await selected.length() > BackupService.maximumBytes) {
      throw const FormatException('Backup ist größer als 128 MB.');
    }
    final service = await _service();
    final preview = await service.inspect(await selected.readAsBytes());
    if (!mounted) return;

    final selectedCategories = await showDialog<Set<String>>(
      context: context,
      builder: (context) => _SelectiveCategoryDialog(
        title: 'Backup wiederherstellen',
        description:
            'Erstellt: ${preview.createdAt.toLocal()}\n'
            '${preview.tournaments} Turniere in der Datei gefunden.\n\n'
            'Wähle die Kategorien aus, die du wiederherstellen möchtest (nicht ausgewählte bleiben unverändert):',
        confirmLabel: 'Wiederherstellen',
        availableFiles: preview.files
            .where((file) => BackupService.categoryNames.contains(file))
            .toList(),
        warning:
            'Die ausgewählten Kategorien werden durch das Backup überschrieben. '
            'Vorher wird dein aktueller Stand automatisch gesichert.',
      ),
    );
    if (selectedCategories == null || selectedCategories.isEmpty) return;

    final safety = await service.restore(
      preview,
      selectedCategories: selectedCategories,
    );
    if (mounted) {
      setState(
        () => _message =
            'Wiederhergestellt (${selectedCategories.map((c) => _areaNames[c] ?? c).join(', ')}).\n'
            'Sicherung des vorherigen Stands:\n${safety.path}\nBitte App neu starten.',
      );
    }
  });

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AdaptiveContentList(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Datensicherung',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const CloudBackupPanel(),
        const SizedBox(height: 12),
        const Text(
          'Sichere Turniere mit Ergebnissen, lokale Spielerprofile, '
          'Ranglisten und Einstellungen in einer Datei. Das Supabase-Backup '
          'wird separat mit dem Betreiberkonto gespeichert und wiederhergestellt.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Die Datei ist nicht verschlüsselt und enthält Spieler-, Turnier- und '
          'Geräteeinstellungen. Bewahre lokale Exportdateien geschützt auf.',
        ),
        const SizedBox(height: 24),
        SportMenuGroup(
          title: 'Sicherung verwalten',
          actions: [
            SportMenuAction(
              label: 'Backup exportieren',
              description: 'Aktuellen Stand als Datei sichern.',
              icon: Icons.save_alt,
              onTap: _busy ? null : _export,
            ),
            SportMenuAction(
              label: 'Backup wiederherstellen',
              description: 'Gesicherte Datei prüfen und einlesen.',
              icon: Icons.restore,
              onTap: _busy ? null : _import,
            ),
          ],
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: LinearProgressIndicator(),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: SelectableText(
              _message!,
              style: TextStyle(
                color: _failed ? Theme.of(context).colorScheme.error : null,
              ),
            ),
          ),
        if (widget.trailing != null) ...[
          const SizedBox(height: 16),
          widget.trailing!,
        ],
      ],
    ),
  );
}

class _SelectiveCategoryDialog extends StatefulWidget {
  const _SelectiveCategoryDialog({
    required this.title,
    required this.description,
    required this.confirmLabel,
    required this.availableFiles,
    this.warning,
  });

  final String title;
  final String description;
  final String confirmLabel;
  final List<String> availableFiles;
  final String? warning;

  @override
  State<_SelectiveCategoryDialog> createState() =>
      _SelectiveCategoryDialogState();
}

class _SelectiveCategoryDialogState extends State<_SelectiveCategoryDialog> {
  static const _labels = {
    'tournaments.json': 'Turniere und Ergebnisse',
    'app_database.sqlite': 'Spielerprofile, Ranglisten und Bestleistungen',
    'planning_settings.json': 'Turnierplanung und Voreinstellungen',
  };

  late final Set<String> _selected = Set.from(widget.availableFiles);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.description),
            const SizedBox(height: 16),
            for (final file in widget.availableFiles)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(_labels[file] ?? file),
                value: _selected.contains(file),
                onChanged: (val) => setState(() {
                  if (val == true) {
                    _selected.add(file);
                  } else {
                    _selected.remove(file);
                  }
                }),
              ),
            if (widget.warning != null) ...[
              const SizedBox(height: 12),
              Text(
                widget.warning!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: _selected.isEmpty
            ? null
            : () => Navigator.pop(context, Set<String>.from(_selected)),
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
