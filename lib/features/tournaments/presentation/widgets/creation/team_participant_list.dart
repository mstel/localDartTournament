import '../../../../../shared/widgets/sport_menu.dart';
import 'package:flutter/material.dart';
import '../../../domain/tournament_models.dart';

/// A team is one tournament entrant; its roster is retained separately.
class TeamParticipantList extends StatefulWidget {
  const TeamParticipantList({
    super.key,
    required this.players,
    required this.onRename,
    required this.onRemove,
    required this.onMerge,
    required this.onSplit,
    required this.onReorder,
  });
  final List<TournamentPlayer> players;
  final ValueChanged<int> onRename, onRemove, onSplit;
  final void Function(int source, int target) onMerge;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  State<TeamParticipantList> createState() => _TeamParticipantListState();
}

class _TeamParticipantListState extends State<TeamParticipantList> {
  bool _isReordering = false;

  Future<void> _choosePartner(BuildContext context, int source) async {
    final target = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Mit wem ein Team bilden?'),
        children: [
          for (var i = 0; i < widget.players.length; i++)
            if (i != source)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(widget.players[i].name),
                ),
              ),
        ],
      ),
    );
    if (target != null) widget.onMerge(source, target);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.players.any((p) => p.isTeam)
                          ? '${widget.players.length} Teilnehmer · ${widget.players.expand((p) => p.individuals).length} Spieler'
                          : '${widget.players.length} Spieler im Turnier',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      _isReordering
                          ? 'Ziehe die Spieler in die gewünschte Setzreihenfolge.'
                          : 'Ziehe Spieler aufeinander, um Teams zu bilden.',
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _isReordering
                    ? 'Reihenfolge übernehmen'
                    : 'Reihenfolge ändern',
                onPressed: () => setState(() => _isReordering = !_isReordering),
                icon: Icon(_isReordering ? Icons.check : Icons.swap_vert),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isReordering)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: widget.players.length,
              onReorderItem: widget.onReorder,
              itemBuilder: (context, i) {
                final player = widget.players[i];
                return Card(
                  key: ObjectKey(player),
                  child: ListTile(
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: const SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                    title: Text(player.name),
                    subtitle: player.isTeam
                        ? Text(
                            '${player.members.length} Spieler · ${player.members.map((p) => p.name).join(', ')}',
                          )
                        : null,
                    trailing: _actions(context, i),
                  ),
                );
              },
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < widget.players.length; i++)
                  SizedBox(
                    width: constraints.maxWidth < 600
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 8) / 2,
                    child: DragTarget<int>(
                      onWillAcceptWithDetails: (d) => d.data != i,
                      onAcceptWithDetails: (d) => widget.onMerge(d.data, i),
                      builder: (context, candidates, rejected) {
                        final tile = Card(
                          color: candidates.isEmpty
                              ? null
                              : Theme.of(context).colorScheme.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  widget.players[i].name,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                if (widget.players[i].isTeam)
                                  Text(
                                    '${widget.players[i].members.length} Spieler · ${widget.players[i].members.map((p) => p.name).join(', ')}',
                                  ),
                                _actions(context, i),
                              ],
                            ),
                          ),
                        );
                        final feedback = Material(
                          elevation: 6,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(widget.players[i].name),
                          ),
                        );
                        return Listener(
                          child: LongPressDraggable<int>(
                            data: i,
                            feedback: feedback,
                            child: Draggable<int>(
                              data: i,
                              affinity: Axis.horizontal,
                              feedback: feedback,
                              child: tile,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
        ],
      );
    },
  );

  Widget _actions(BuildContext context, int index) => Wrap(
    children: [
      if (widget.players[index].profileId == null &&
          !widget.players[index].isTeam)
        IconButton(
          tooltip: 'Umbenennen',
          onPressed: () => widget.onRename(index),
          icon: const Icon(Icons.edit),
        ),
      PopupMenuButton<String>(
        tooltip: 'Team bearbeiten',
        icon: const Icon(Icons.group_add),
        onSelected: (action) {
          if (action == 'split') {
            widget.onSplit(index);
          } else {
            _choosePartner(context, index);
          }
        },
        itemBuilder: (_) => [
          if (widget.players.length > 1)
            const PopupMenuItem(
              value: 'merge',
              child: SportMenuLabel(
                label: 'Mit Spieler / Team verbinden',
                icon: Icons.group_add_outlined,
              ),
            ),
          if (widget.players[index].isTeam)
            const PopupMenuItem(
              value: 'split',
              child: SportMenuLabel(
                label: 'Team auflösen',
                icon: Icons.group_remove_outlined,
              ),
            ),
        ],
      ),
      IconButton(
        tooltip: 'Teilnehmer entfernen',
        onPressed: () => widget.onRemove(index),
        icon: const Icon(Icons.close),
      ),
    ],
  );
}
