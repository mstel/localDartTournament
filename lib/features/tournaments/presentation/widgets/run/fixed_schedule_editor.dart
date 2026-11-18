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
  late final Map<GroupMatch, String> _groupByMatch;
  late int _selectedStageIndex;
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
    _groupByMatch = _indexGroups();
    _selectedStageIndex = widget.stageIndex.clamp(
      0,
      widget.tournament.runStages.isEmpty
          ? 0
          : widget.tournament.runStages.length - 1,
    );
    _selectedBoard = 1;
    _reload();
  }

  Map<GroupMatch, String> _indexGroups() {
    final result = <GroupMatch, String>{};
    for (final stage in widget.tournament.runStages) {
      if (stage is GroupTournamentRunStage) {
        for (final group in stage.groups) {
          for (final match in group.matches) {
            result[match] = group.name;
          }
          for (final match in group.knockoutRounds.expand((round) => round)) {
            result[match] = group.name;
          }
          for (final match in group.placementMatches) {
            result[match] = group.name;
          }
        }
      } else if (stage is KnockoutTournamentRunStage) {
        for (final match in stage.matches) {
          result[match] = '-';
        }
      }
    }
    return result;
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
        .where((entry) => entry.stageIndex == _selectedStageIndex)
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
          .plan(widget.tournament, _selectedStageIndex)
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
    final slotSet =
        selectable
            .map((match) => match.fixedScheduleOrder)
            .whereType<int>()
            .toSet()
            .toList()
          ..sort();
    _matches = selectable;
    _slots = slotSet;
  }

  List<PlayEntry> _stageEntries() =>
      _controller.entries(widget.tournament)..sort((a, b) {
        final order = (a.match.fixedScheduleOrder ?? 1 << 30).compareTo(
          b.match.fixedScheduleOrder ?? 1 << 30,
        );
        return order != 0 ? order : a.origin.compareTo(b.origin);
      });

  String _groupLabel(GroupMatch match) =>
      _groupByMatch[match] ?? match.label ?? '-';

  String _playerOneLabel(GroupMatch match) => match.isKratzer
      ? match.participantLabel
      : match.homePlayer?.name ?? 'offen';

  String _playerTwoLabel(GroupMatch match) =>
      match.isKratzer ? '-' : match.awayPlayer?.name ?? 'offen';

  Future<void> _apply() async {
    setState(() => _saving = true);
    final stageEntries = _stageEntries();
    for (
      var index = 0;
      index < _matches.length && index < _slots.length;
      index++
    ) {
      if (stageEntries.any(
        (entry) =>
            identical(entry.match, _matches[index]) &&
            entry.stageIndex != _selectedStageIndex,
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
          SnackBar(
            content: Text('Spielplan konnte nicht gespeichert werden: $error'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final boardCount = widget.tournament.boardCount;
    final stages = widget.tournament.runStages;
    final phaseSelector = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: DropdownButtonFormField<int>(
        key: ValueKey('fixed-schedule-phase-$_selectedStageIndex'),
        initialValue: _selectedStageIndex,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Phase',
          border: OutlineInputBorder(),
        ),
        items: [
          for (var index = 0; index < stages.length; index++)
            DropdownMenuItem<int>(
              value: index,
              child: Text('${index + 1}. ${stages[index].name}'),
            ),
        ],
        onChanged: (stageIndex) {
          if (stageIndex == null) return;
          setState(() {
            _selectedStageIndex = stageIndex;
            _reload();
          });
        },
      ),
    );
    final boardSelector = widget.scope == FixedScheduleEditorScope.perBoard
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: DropdownButtonFormField<int>(
              key: ValueKey(
                'fixed-schedule-board-$_selectedStageIndex-$_selectedBoard',
              ),
              initialValue: _selectedBoard.clamp(1, boardCount),
              isExpanded: true,
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
            phaseSelector,
            boardSelector,
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Ziehen, um die Reihenfolge zu ändern. Bereits laufende oder '
                'beendete Begegnungen bleiben an ihrer Position.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: const [
                  SizedBox(width: 36),
                  Expanded(flex: 2, child: Text('Gruppe')),
                  Expanded(flex: 3, child: Text('Spieler 1')),
                  Expanded(flex: 3, child: Text('Spieler 2')),
                  SizedBox(width: 48),
                ],
              ),
            ),
            const Divider(height: 8),
            Expanded(
              child: _matches.isEmpty
                  ? const Center(child: Text('Keine editierbaren Begegnungen.'))
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
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
                          title: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _groupLabel(match),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  _playerOneLabel(match),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  _playerTwoLabel(match),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          trailing: SizedBox(
                            width: 48,
                            height: 48,
                            child: ReorderableDragStartListener(
                              index: index,
                              child: const Tooltip(
                                message: 'Ziehen, um die Reihenfolge zu ändern',
                                child: Icon(Icons.drag_indicator),
                              ),
                            ),
                          ),
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
