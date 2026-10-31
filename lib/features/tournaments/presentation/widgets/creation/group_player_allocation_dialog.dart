import 'package:flutter/material.dart';

import '../../../domain/tournament_models.dart';

class GroupPlayerAllocationDialog extends StatefulWidget {
  const GroupPlayerAllocationDialog({super.key, required this.initialGroups});

  final List<List<TournamentPlayer>> initialGroups;

  @override
  State<GroupPlayerAllocationDialog> createState() =>
      _GroupPlayerAllocationDialogState();
}

class _GroupPlayerAllocationDialogState
    extends State<GroupPlayerAllocationDialog> {
  late final List<List<TournamentPlayer>> _groups = [
    for (final group in widget.initialGroups)
      List<TournamentPlayer>.from(group),
  ];
  _GroupPlayerPosition? _selectedPosition;

  void _swap(_GroupPlayerPosition first, _GroupPlayerPosition second) {
    if (first == second) return;
    setState(() {
      final player = _groups[first.groupIndex][first.playerIndex];
      _groups[first.groupIndex][first.playerIndex] =
          _groups[second.groupIndex][second.playerIndex];
      _groups[second.groupIndex][second.playerIndex] = player;
      _selectedPosition = null;
    });
  }

  void _selectOrSwap(_GroupPlayerPosition position) {
    setState(() {
      final selected = _selectedPosition;
      if (selected == null) {
        _selectedPosition = position;
      } else {
        final player = _groups[selected.groupIndex][selected.playerIndex];
        _groups[selected.groupIndex][selected.playerIndex] =
            _groups[position.groupIndex][position.playerIndex];
        _groups[position.groupIndex][position.playerIndex] = player;
        _selectedPosition = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(title: const Text('Benutzerdefinierte Gruppen')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final columns = width >= 1000
              ? 3
              : width >= 620
              ? 2
              : 1;
          final spacing = 12.0;
          final cardWidth = columns == 1
              ? width
              : (width - spacing * (columns - 1)) / columns;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Spieler per Drag-and-drop zwischen den Gruppen tauschen. '
                'Alternativ zwei Spieler nacheinander antippen.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              if (_selectedPosition != null) ...[
                const SizedBox(height: 8),
                const Text('Jetzt den Spieler zum Tauschen auswählen.'),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (
                    var groupIndex = 0;
                    groupIndex < _groups.length;
                    groupIndex++
                  )
                    SizedBox(
                      width: cardWidth,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${groupLabel(groupIndex + 1)} · ${_groups[groupIndex].length} Spieler',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              for (
                                var playerIndex = 0;
                                playerIndex < _groups[groupIndex].length;
                                playerIndex++
                              )
                                _playerTile(
                                  context,
                                  _GroupPlayerPosition(groupIndex, playerIndex),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                key: const ValueKey('apply-custom-groups'),
                onPressed: () => Navigator.pop(
                  context,
                  _groups.map(List<TournamentPlayer>.unmodifiable).toList(),
                ),
                child: const Text('Gruppen übernehmen'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _playerTile(BuildContext context, _GroupPlayerPosition position) {
    final player = _groups[position.groupIndex][position.playerIndex];
    final selected = _selectedPosition == position;
    final key = ValueKey(
      'group-player-${position.groupIndex}-${position.playerIndex}',
    );
    return DragTarget<_GroupPlayerPosition>(
      key: key,
      onAcceptWithDetails: (details) => _swap(details.data, position),
      builder: (context, candidates, rejected) =>
          LongPressDraggable<_GroupPlayerPosition>(
            data: position,
            feedback: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 240,
                child: ListTile(
                  leading: const Icon(Icons.drag_indicator),
                  title: Text(player.name),
                ),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.35,
              child: _tileBody(player, selected),
            ),
            child: InkWell(
              onTap: () => _selectOrSwap(position),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  color: candidates.isNotEmpty
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _tileBody(player, selected),
              ),
            ),
          ),
    );
  }

  Widget _tileBody(TournamentPlayer player, bool selected) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 56),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Icon(
            selected ? Icons.swap_horiz : Icons.drag_indicator,
            semanticLabel: selected ? 'Ausgewählt' : 'Verschieben',
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(player.name)),
        ],
      ),
    ),
  );
}

class _GroupPlayerPosition {
  const _GroupPlayerPosition(this.groupIndex, this.playerIndex);

  final int groupIndex;
  final int playerIndex;

  @override
  bool operator ==(Object other) =>
      other is _GroupPlayerPosition &&
      other.groupIndex == groupIndex &&
      other.playerIndex == playerIndex;

  @override
  int get hashCode => Object.hash(groupIndex, playerIndex);
}
