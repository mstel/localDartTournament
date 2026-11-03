import 'package:flutter/material.dart';

import '../../../settings/data/planning_settings_storage.dart';
import '../../domain/tournament_format_planner.dart';
import '../../domain/tournament_models.dart';
import 'kratzer_engine.dart';

class KratzerDurationPreview extends StatelessWidget {
  const KratzerDurationPreview({
    super.key,
    required this.stages,
    required this.participantCount,
    required this.boards,
    required this.onBoardsChanged,
  });

  final List<TournamentStage> stages;
  final int participantCount;
  final int boards;
  final ValueChanged<int> onBoardsChanged;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: PlanningSettingsStorage().load(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Kratzer-Zeitvorschau konnte nicht geladen werden.'),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        );
      }
      final parameters = snapshot.data!;
      final planner = TournamentFormatPlanner(parameters: parameters);
      final estimates = [
        for (final stage in stages.where((stage) => stage.type == 'kratzer'))
          (
            stage: stage,
            estimate: const KratzerEngine().estimateDuration(
              playerCount: stage.knockoutParticipantCount ?? participantCount,
              lives: stage.lossLimit,
              boards: boards,
              playersPerBoard: stage.kratzerPlayersPerBoard,
              preferSameScratchCount: stage.kratzerPreferSameScratchCount,
              playUntilElimination: stage.kratzerPlayUntilElimination,
              baseMatchMinutes: planner.estimatedMatchMinutes(stage.gameFormat),
              boardIdleMinutes: parameters.boardIdleMinutes.toDouble(),
            ),
          ),
      ];
      final games = estimates.fold<int>(
        0,
        (total, entry) => total + entry.estimate.games,
      );
      final minutes = estimates.fold<int>(
        0,
        (total, entry) => total + entry.estimate.minutes,
      );
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Kratzer-Zeitvorschau',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                minutes < 60
                    ? 'ca. $minutes min'
                    : 'ca. ${minutes ~/ 60} h ${minutes % 60} min',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text('$games Partien bis eine Person übrig ist'),
              for (final entry in estimates)
                Text(
                  '${entry.stage.name}: ${entry.estimate.rounds} Runden · '
                  '${entry.stage.gameFormat.bestOfLegs} Legs · '
                  'Spielzeit je zusätzlichem Spieler +50 %',
                ),
              Text(
                'Je Runde wird die längste Board-Partie angesetzt; unbesetzte Boards '
                'werden mit ${parameters.boardIdleMinutes} min Leerstand berücksichtigt.',
              ),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('$boards Boards'),
                  IconButton(
                    tooltip: 'Ein Board weniger',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: boards > 1
                        ? () => onBoardsChanged(boards - 1)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  IconButton(
                    tooltip: 'Ein Board mehr',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: boards < 64
                        ? () => onBoardsChanged(boards + 1)
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              if (stages.any((stage) => stage.type != 'kratzer'))
                const Text(
                  'Die Vorschau berücksichtigt hier die Kratzer-Etappen; andere Etappen sind nicht eingerechnet.',
                ),
            ],
          ),
        ),
      );
    },
  );
}
