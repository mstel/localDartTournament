import 'package:flutter/material.dart';

import '../../../application/order_of_play/order_of_play_controller.dart';
import '../../../domain/tournament_models.dart';

enum FixedScheduleEditorScope { overall, perBoard }

/// Drag-and-drop editor for a persisted fixed schedule.
///
/// The dialog only changes `fixedScheduleOrder` values in memory. The caller
/// decides when those changes are written to storage via [onApply].
class FixedScheduleEditorDialog extends StatefulWidget {
  const FixedScheduleEditorDialog({
    super.key,
    required this.tournament,
    required this.stageIndex,
    required this.scope,
    required this.onApply,
  });

  final CreatedTournament tournament;
  final int stageIndex;
  final FixedScheduleEditorScope scope;
  final Future<void> Function() onApply;

  @override
  State<FixedScheduleEditorDialog> createState() =>
      _FixedScheduleEditorDialogState();
}

class _FixedScheduleEditorDialogState extends State<FixedScheduleEditorDialog> {
  final OrderOfPlayController _controller = const OrderOfPlayController();
  late final Map<GroupMatch, int?> _initialOrders;
  late int _selectedBoard;
  late List<GroupMatch> _matches;
  late List<int> _slots;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _initialOrders = {
      for (final entry in _controller.entries(widget.tournament))
        entry.match: entry.match.fixedScheduleOrder,
    };
    _selectedBoard = 1;
    _reload();
  }

  void _reload() {
    final all = _controller.entries(widget.tournament)
      ..sort((a, b) {
        final order = (a.match.fixedScheduleOrder ?? 1 << 30).compareTo(
          b.match.fixedScheduleOrder ?? 1 << 30,
        );
        return order != 0 ? order : a.origin.compareTo(b.origin);
      });
    final stageEntries = all
        .where((entry) => entry.stageIndex == widget.stageIndex)
        .toList();
    final selectable = <GroupMatch>[];
    if (widget.scope == FixedScheduleEditorScope.overall) {
      selectable.addAll(
        stageEntries
            .where(
              (entry) =>
                  !entry.match.isResolved &&
                  !(entry.match.startedAt != null &&
                      entry.match.finishedAt == null),
            )
            .map((entry) => entry.match),
      );
    } else {
      final boardAssignments = _controller
          .plan(widget.tournament, widget.stageIndex)
          .planned
          .where((assignment) => assignment.board == _selectedBoard);
      selectable.addAll(
        boardAssignments
            .where(
              (assignment) =>
                  !assignment.entry.match.isResolved &&
                  !(assignment.entry.match.startedAt != null &&
                      assignment.entry.match.finishedAt == null),
            )
            .map((assignment) => assignment.entry.match),
      );
    }
    final slotSet = selectable
        .map((match) => match.fixedScheduleOrder)
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    _matches = selectable;
    _slots = slotSet;
  }

  List<PlayEntry> _stageEntries() => _controller.entries(widget.tournament)
    ..sort((a, b) {
      final order = (a.match.fixedScheduleOrder ?? 1 << 30).compareTo(
        b.match.fixedScheduleOrder ?? 1 << 30,
      );
      return order != 0 ? order : a.origin.compareTo(b.origin);
    });

  String _label(GroupMatch match) {
    final entry = _controller
        .entries(widget.tournament)
        .where((candidate) => identical(candidate.match, match))
        .firstOrNull;
    return entry?.origin ??
        '${match.homePlayer?.name ?? 'offen'} – ${match.awayPlayer?.name ?? 'offen'}';
  }

  Future<void> _apply() async {
    setState(() => _saving = true);
    final stageEntries = _stageEntries();
    for (var index = 0; index < _matches.length && index < _slots.length; index++) {
      if (stageEntries.any(
        (entry) =>
            identical(entry.match, _matches[index]) &&
            entry.stageIndex != widget.stageIndex,
      )) {
        continue;
      }
      _matches[index].fixedScheduleOrder = _slots[index];
    }
    try {
      await widget.onApply();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      for (final entry in _initialOrders.entries) {
        entry.key.fixedScheduleOrder = entry.value;
      }
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Spielplan konnte nicht gespeichert werden: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final boardCount = widget.tournament.boardCount;
    final boardSelector = widget.scope == FixedScheduleEditorScope.perBoard
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: DropdownButtonFormField<int>(
              initialValue: _selectedBoard.clamp(1, boardCount),
              decoration: const InputDecoration(
                labelText: 'Board',
                border: OutlineInputBorder(),
              ),
              items: [
                for (var board = 1; board <= boardCount; board++)
                  DropdownMenuItem<int>(
                    value: board,
                    child: Text(widget.tournament.boardDisplayName(board)),
                  ),
              ],
              onChanged: (board) {
                if (board == null) return;
                setState(() {
                  _selectedBoard = board;
                  _reload();
                });
              },
            ),
          )
        : const SizedBox.shrink();

    return AlertDialog(
      title: Text(
        widget.scope == FixedScheduleEditorScope.overall
            ? 'Spielplan gesamt bearbeiten'
            : 'Spielplan je Board bearbeiten',
      ),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            boardSelector,
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Ziehen, um die Reihenfolge zu ändern. Bereits laufende oder '
                'beendete Begegnungen bleiben an ihrer Position.',
              ),
            ),
            Expanded(
              child: _matches.isEmpty
                  ? const Center(child: Text('Keine editierbaren Begegnungen.'))
                  : ReorderableListView.builder(
                      itemCount: _matches.length,
                      onReorderItem: (oldIndex, newIndex) {
                        setState(() {
                          final match = _matches.removeAt(oldIndex);
                          _matches.insert(newIndex, match);
                        });
                      },
                      itemBuilder: (context, index) {
                        final match = _matches[index];
                        return ListTile(
                          key: ValueKey(match),
                          leading: CircleAvatar(child: Text('${index + 1}')),
                          title: Text(_label(match), maxLines: 2),
                          trailing: const Icon(Icons.drag_indicator),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () {
                  for (final entry in _initialOrders.entries) {
                    entry.key.fixedScheduleOrder = entry.value;
                  }
                  Navigator.of(context).pop(false);
                },
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _saving ? null : _apply,
          child: const Text('Speichern & Anwenden'),
        ),
      ],
    );
  }
}
