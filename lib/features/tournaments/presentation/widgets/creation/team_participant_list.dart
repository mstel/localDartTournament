import '../../../../../shared/widgets/sport_menu.dart';
import 'package:flutter/material.dart';
import '../../../domain/tournament_models.dart';

/// A team is one tournament entrant; its roster is retained separately.
class TeamParticipantList extends StatelessWidget {
  const TeamParticipantList({
    super.key,
    required this.players,
    required this.onRename,
    required this.onRemove,
    required this.onMerge,
    required this.onSplit,
    this.onAssignProfile,
    this.useCatalogAssignment = false,
  });
  final List<TournamentPlayer> players;
  final ValueChanged<int> onRename, onRemove, onSplit;
  final void Function(int source, int target) onMerge;
  final ValueChanged<int>? onAssignProfile;
  final bool useCatalogAssignment;

  Future<void> _choosePartner(BuildContext context, int source) async {
    final target = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Mit wem ein Team bilden?'),
        children: [
          for (var i = 0; i < players.length; i++)
            if (i != source)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(players[i].name),
                ),
              ),
        ],
      ),
    );
    if (target != null) onMerge(source, target);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            players.any((p) => p.isTeam)
                ? '${players.length} Teilnehmer · ${players.expand((p) => p.individuals).length} Spieler'
                : '${players.length} Spieler im Turnier',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text(
            'Spieler aufeinander ziehen, um ein Doppel oder größeres Team zu bilden. Auf Touch-Geräten kurz gedrückt halten. Alternativ das Team-Menü verwenden.',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < players.length; i++)
                SizedBox(
                  width: constraints.maxWidth < 600
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 8) / 2,
                  child: DragTarget<int>(
                    onWillAcceptWithDetails: (d) => d.data != i,
                    onAcceptWithDetails: (d) => onMerge(d.data, i),
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
                                players[i].name,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              if (players[i].isTeam)
                                Text(
                                  '${players[i].members.length} Spieler · ${players[i].members.map((p) => p.name).join(', ')}',
                                ),
                              Wrap(
                                children: [
                                  if (players[i].profileId == null &&
                                      !players[i].isTeam)
                                    IconButton(
                                      tooltip:
                                          useCatalogAssignment &&
                                              onAssignProfile != null
                                          ? 'Spieler aus Katalog zuweisen'
                                          : 'Umbenennen',
                                      onPressed: () {
                                        if (useCatalogAssignment &&
                                            onAssignProfile != null) {
                                          onAssignProfile!(i);
                                        } else {
                                          onRename(i);
                                        }
                                      },
                                      icon: const Icon(Icons.edit),
                                    ),
                                  if (players[i].profileId == null &&
                                      useCatalogAssignment)
                                    PopupMenuButton<String>(
                                      tooltip: 'Weitere Spieleraktionen',
                                      onSelected: (action) {
                                        if (action == 'rename') onRename(i);
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'rename',
                                          child: SportMenuLabel(
                                            label: 'Namen ändern',
                                            icon:
                                                Icons.drive_file_rename_outline,
                                          ),
                                        ),
                                      ],
                                    ),
                                  PopupMenuButton<String>(
                                    tooltip: 'Team bearbeiten',
                                    icon: const Icon(Icons.group_add),
                                    onSelected: (action) {
                                      if (action == 'split') {
                                        onSplit(i);
                                      } else {
                                        _choosePartner(context, i);
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      if (players.length > 1)
                                        const PopupMenuItem(
                                          value: 'merge',
                                          child: SportMenuLabel(
                                            label:
                                                'Mit Spieler / Team verbinden',
                                            icon: Icons.group_add_outlined,
                                          ),
                                        ),
                                      if (players[i].isTeam)
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
                                    onPressed: () => onRemove(i),
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                      final feedback = Material(
                        elevation: 6,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(players[i].name),
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
}
