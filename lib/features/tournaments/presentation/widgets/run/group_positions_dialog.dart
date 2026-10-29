import 'dart:math';

import 'package:flutter/material.dart';

import '../../../domain/engines/group_player_allocation_engine.dart';
import '../../../domain/tournament_models.dart';

class GroupPositionsDialog extends StatefulWidget {
  const GroupPositionsDialog({
    super.key,
    required this.stage,
    this.ratings = const {},
  });

  final GroupTournamentRunStage stage;
  final Map<String, int> ratings;

  @override
  State<GroupPositionsDialog> createState() => _GroupPositionsDialogState();
}

class _GroupPositionsDialogState extends State<GroupPositionsDialog> {
  late List<List<TournamentPlayer>> _groups;
  GroupPlayerAllocationMode _mode = GroupPlayerAllocationMode.manual;
  _GroupPlayerPosition? _selected;

  @override
  void initState() {
    super.initState();
    _groups = [
      for (final group in widget.stage.groups) [...group.players],
    ];
  }

  void _swap(_GroupPlayerPosition first, _GroupPlayerPosition second) {
    if (first == second ||
        first.groupIndex < 0 ||
        second.groupIndex < 0 ||
        first.groupIndex >= _groups.length ||
        second.groupIndex >= _groups.length) {
      return;
    }
    final firstIndex = _groups[first.groupIndex].indexOf(first.player);
    final secondIndex = _groups[second.groupIndex].indexOf(second.player);
    if (firstIndex < 0 || secondIndex < 0) return;
    setState(() {
      _groups[first.groupIndex][firstIndex] = second.player;
      _groups[second.groupIndex][secondIndex] = first.player;
      _selected = null;
      _mode = GroupPlayerAllocationMode.manual;
    });
  }

  void _select(_GroupPlayerPosition position) {
    final selected = _selected;
    if (selected == null || selected.player == position.player) {
      setState(() => _selected = selected == position ? null : position);
      return;
    }
    _swap(selected, position);
  }

  void _allocate(GroupPlayerAllocationMode mode) {
    setState(() {
      _mode = mode;
      _selected = null;
      if (mode == GroupPlayerAllocationMode.manual) return;
      final players = _groups.expand((group) => group).toList();
      final arranged = const GroupPlayerAllocationEngine().allocate(
        players: players,
        groupSizes: [for (final group in _groups) group.length],
        mode: mode,
        ratings: widget.ratings,
        random: Random(),
      );
      var offset = 0;
      final nextGroups = <List<TournamentPlayer>>[];
      for (final group in _groups) {
        nextGroups.add(arranged.skip(offset).take(group.length).toList());
        offset += group.length;
      }
      _groups = nextGroups;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final width = (screenSize.width - 32).clamp(280.0, 1400.0);
    final height = (screenSize.height - 48).clamp(300.0, 900.0);
    final theme = Theme.of(context);

    return Dialog(
      child: SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Gruppen neu einteilen',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dialog schließen',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Verteilung auswählen oder Spieler per Drag-and-drop '
                'zwischen den Gruppen verschieben. Änderungen werden erst '
                'mit „Übernehmen“ gespeichert.',
              ),
              const SizedBox(height: 4),
              Text(
                'Stärkestufen nutzen lokale ELO-Wertungen; Spieler ohne '
                'Wertung werden gleich gewichtet.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final picker =
                      DropdownButtonFormField<GroupPlayerAllocationMode>(
                        initialValue: _mode,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Gruppenverteilung',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: GroupPlayerAllocationMode.strengthLevels,
                            child: Text('Stärkestufen bündeln'),
                          ),
                          DropdownMenuItem(
                            value: GroupPlayerAllocationMode.balanced,
                            child: Text('Stärke ausgeglichen verteilen'),
                          ),
                          DropdownMenuItem(
                            value: GroupPlayerAllocationMode.random,
                            child: Text('Zufällige Verteilung'),
                          ),
                          DropdownMenuItem(
                            value: GroupPlayerAllocationMode.manual,
                            child: Text('Manuell per Drag-and-drop'),
                          ),
                        ],
                        onChanged: (mode) {
                          if (mode != null) setState(() => _mode = mode);
                        },
                      );
                  if (constraints.maxWidth < 560) {
                    return picker;
                  }
                  return Row(
                    children: [
                      Expanded(child: picker),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _mode == GroupPlayerAllocationMode.manual
                            ? null
                            : () => _allocate(_mode),
                        icon: const Icon(Icons.shuffle),
                        label: const Text('Neu einteilen'),
                      ),
                    ],
                  );
                },
              ),
              if (MediaQuery.sizeOf(context).width < 560) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _mode == GroupPlayerAllocationMode.manual
                        ? null
                        : () => _allocate(_mode),
                    icon: const Icon(Icons.shuffle),
                    label: const Text('Neu einteilen'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: GridView.extent(
                  maxCrossAxisExtent: 400,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: [
                    for (
                      var index = 0;
                      index < widget.stage.groups.length;
                      index++
                    )
                      _groupCard(index, widget.stage.groups[index], theme),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, [
                      for (final group in _groups)
                        List<TournamentPlayer>.of(group),
                    ]),
                    child: const Text('Übernehmen'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupCard(int groupIndex, TournamentGroup group, ThemeData theme) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(group.name, style: theme.textTheme.titleMedium),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: _groups[groupIndex].length,
                  itemBuilder: (context, index) {
                    final player = _groups[groupIndex][index];
                    final position = _GroupPlayerPosition(groupIndex, player);
                    final isSelected = _selected == position;
                    final colors = theme.colorScheme;
                    final row = Material(
                      color: isSelected
                          ? colors.secondaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _select(position),
                        child: SizedBox(
                          height: 48,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.check_circle
                                      : Icons.person_outline,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    player.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.drag_indicator, size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );

                    return DragTarget<_GroupPlayerPosition>(
                      onWillAcceptWithDetails: (details) =>
                          details.data.player != player,
                      onAcceptWithDetails: (details) =>
                          _swap(details.data, position),
                      builder: (context, candidates, rejected) => DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: candidates.isEmpty
                              ? null
                              : Border.all(color: colors.primary, width: 2),
                        ),
                        child: LongPressDraggable<_GroupPlayerPosition>(
                          data: position,
                          feedback: Material(
                            elevation: 6,
                            borderRadius: BorderRadius.circular(8),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 320),
                              child: row,
                            ),
                          ),
                          childWhenDragging: Opacity(opacity: 0.35, child: row),
                          child: row,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
}

class _GroupPlayerPosition {
  const _GroupPlayerPosition(this.groupIndex, this.player);

  final int groupIndex;
  final TournamentPlayer player;

  @override
  bool operator ==(Object other) =>
      other is _GroupPlayerPosition &&
      other.groupIndex == groupIndex &&
      other.player == player;

  @override
  int get hashCode => Object.hash(groupIndex, player);
}
