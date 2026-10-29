import 'package:flutter/material.dart';

import '../../../domain/tournament_models.dart';

class GroupPositionsDialog extends StatefulWidget {
  const GroupPositionsDialog({super.key, required this.stage});

  final GroupTournamentRunStage stage;

  @override
  State<GroupPositionsDialog> createState() => _GroupPositionsDialogState();
}

class _GroupPositionsDialogState extends State<GroupPositionsDialog> {
  TournamentPlayer? _selected;

  void _select(TournamentPlayer player) {
    final selected = _selected;
    if (selected == null || selected == player) {
      setState(() => _selected = selected == player ? null : player);
      return;
    }
    Navigator.pop(context, [selected, player]);
  }

  void _swap(TournamentPlayer first, TournamentPlayer second) {
    if (first != second) Navigator.pop(context, [first, second]);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final width = (screenSize.width - 32).clamp(280.0, 1400.0);
    final height = (screenSize.height - 48).clamp(240.0, 900.0);
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
                      'Gruppenpositionen bearbeiten',
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
                'Spieler antippen oder auf einen anderen Spieler ziehen, '
                'um ihre Plätze zu tauschen. Gruppengrößen bleiben erhalten.',
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.extent(
                  maxCrossAxisExtent: 400,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: [
                    for (final group in widget.stage.groups)
                      _groupCard(group, theme),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupCard(TournamentGroup group, ThemeData theme) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(group.name, style: theme.textTheme.titleMedium),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: group.players.length,
              itemBuilder: (context, index) {
                final player = group.players[index];
                final isSelected = _selected == player;
                final colors = theme.colorScheme;
                final row = Material(
                  color: isSelected
                      ? colors.secondaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _select(player),
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

                return DragTarget<TournamentPlayer>(
                  onWillAcceptWithDetails: (details) => details.data != player,
                  onAcceptWithDetails: (details) => _swap(details.data, player),
                  builder: (context, candidates, rejected) => DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: candidates.isEmpty
                          ? null
                          : Border.all(color: colors.primary, width: 2),
                    ),
                    child: LongPressDraggable<TournamentPlayer>(
                      data: player,
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
