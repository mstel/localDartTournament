import 'dart:async';

import 'package:flutter/material.dart';

import '../../tournaments/data/tournament_storage.dart';
import '../../tournaments/data/tournament_trash.dart';

/// Verwaltung des lokalen Papierkorbs unter Einstellungen → Daten.
class TournamentTrashPanel extends StatefulWidget {
  const TournamentTrashPanel({
    super.key,
    this.service,
    this.storage,
  });

  final TournamentTrash? service;
  final TournamentStorage? storage;

  @override
  State<TournamentTrashPanel> createState() => _TournamentTrashPanelState();
}

class _TournamentTrashPanelState extends State<TournamentTrashPanel> {
  late final TournamentTrash _service = widget.service ?? TournamentTrash();
  late final TournamentStorage _storage = widget.storage ?? TournamentStorage();
  List<TrashedTournament> _entries = const [];
  bool _busy = true;
  bool _failed = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    setState(() => _busy = true);
    try {
      final entries = await _service.list();
      if (mounted) setState(() => _entries = entries);
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = 'Papierkorb konnte nicht gelesen werden: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String content,
    required String actionLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const ValueKey('trash-confirm-action'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _run(String successMessage, Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _failed = false;
      _message = null;
    });
    try {
      await action();
      await _reload();
      if (mounted) setState(() => _message = successMessage);
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = 'Vorgang fehlgeschlagen: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(TrashedTournament entry) async {
    final confirmed = await _confirm(
      title: 'Turnier wiederherstellen?',
      content:
          '„${entry.name}“ wird aus dem Papierkorb wiederhergestellt. '
          'Ein vorhandenes Turnier mit derselben ID wird überschrieben.',
      actionLabel: 'Wiederherstellen',
    );
    if (!confirmed || !mounted) return;
    await _run('Turnier wiederhergestellt.', () async {
      await _storage.saveTournamentWithIntent(
        entry.toTournament(),
        allowUnfinishingCompleted: true,
      );
      await _service.remove(entry.entryId);
    });
  }

  Future<void> _deleteForever(TrashedTournament entry) async {
    final confirmed = await _confirm(
      title: 'Endgültig löschen?',
      content:
          '„${entry.name}“ wird dauerhaft aus dem Papierkorb entfernt. '
          'Danach ist diese Fassung nicht mehr wiederherstellbar.',
      actionLabel: 'Endgültig löschen',
    );
    if (!confirmed || !mounted) return;
    await _run(
      'Eintrag endgültig gelöscht.',
      () => _service.remove(entry.entryId),
    );
  }

  Future<void> _empty() async {
    final confirmed = await _confirm(
      title: 'Papierkorb leeren?',
      content:
          'Alle gespeicherten Turnier-Versionen werden dauerhaft entfernt.',
      actionLabel: 'Papierkorb leeren',
    );
    if (!confirmed || !mounted) return;
    await _run('Papierkorb geleert.', () async {
      await _service.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('trash-panel'),
      child: ExpansionTile(
        key: const ValueKey('trash-expansion'),
        leading: const Icon(Icons.delete_outline),
        title: const Text('Papierkorb'),
        subtitle: Text(
          _busy
              ? 'Wird geladen …'
              : '${_entries.length} wiederherstellbare Turnier-Version(en)',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_entries.isEmpty && !_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Keine gelöschten Turniere.'),
            ),
          for (final entry in _entries)
            Card(
              key: ValueKey('trash-entry-${entry.entryId}'),
              child: ListTile(
                title: Text(entry.name),
                subtitle: Text(
                  '${entry.reason.label} · ${_formatDate(entry.savedAt)}'
                  '${entry.note == null ? '' : ' · ${entry.note}'}',
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      key: ValueKey('trash-restore-${entry.entryId}'),
                      tooltip: 'Wiederherstellen',
                      icon: const Icon(Icons.restore),
                      onPressed: _busy ? null : () => _restore(entry),
                    ),
                    IconButton(
                      key: ValueKey('trash-delete-${entry.entryId}'),
                      tooltip: 'Endgültig löschen',
                      icon: const Icon(Icons.delete_forever_outlined),
                      onPressed: _busy ? null : () => _deleteForever(entry),
                    ),
                  ],
                ),
              ),
            ),
          if (_entries.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: const ValueKey('trash-empty'),
                onPressed: _busy ? null : _empty,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Papierkorb leeren'),
              ),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SelectableText(
                _message!,
                style: TextStyle(
                  color: _failed ? theme.colorScheme.error : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
