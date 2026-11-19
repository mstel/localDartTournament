import 'package:flutter/material.dart';

import '../../../domain/engines/group_standings_engine.dart';
import '../../../domain/tournament_models.dart';
import '../creation/stage_setup_widgets.dart' show tieBreakerExplanation;
import 'best_of_comparison_table.dart';
import 'standings_table.dart';

/// Pflicht-Dialog nach Ende einer Gruppenphase.
///
/// Zeigt Abschlusstabellen, die angewandten Tie-Breaker inklusive Formel und –
/// falls vorhanden – Entscheidungsspiele sowie den Vergleich um Zusatzplätze.
/// Der Dialog muss ausdrücklich bestätigt werden, bevor die nächste Phase
/// gestartet werden kann.
class GroupEndReviewDialog extends StatelessWidget {
  const GroupEndReviewDialog({
    super.key,
    required this.tournament,
    required this.stageIndex,
    required this.stage,
  });

  final CreatedTournament tournament;
  final int stageIndex;
  final GroupTournamentRunStage stage;

  static Future<bool?> show({
    required BuildContext context,
    required CreatedTournament tournament,
    required int stageIndex,
    required GroupTournamentRunStage stage,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => GroupEndReviewDialog(
        tournament: tournament,
        stageIndex: stageIndex,
        stage: stage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final standingsByGroup = <TournamentGroup, List<PlayerStanding>>{
      for (final group in stage.groups)
        group: const GroupStandingsEngine().calculate(
          group,
          stage.tieBreakers,
          tournament: tournament,
        ),
    };
    final deciderMatches = [
      for (final group in stage.groups)
        for (final match in group.matches)
          if (match.isDecider) match,
    ];
    final plan = stage.qualificationPlan;

    return AlertDialog(
      key: const ValueKey('group-end-review-dialog'),
      title: Row(
        children: [
          const Icon(Icons.fact_check, color: Color(0xFF70E0BA)),
          const SizedBox(width: 10),
          Expanded(child: Text('Gruppenphase beendet · ${stage.name}')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Prüfe die Abschlusstabellen und die angewandten Tie-Breaker. '
                  'Bei Gleichstand an einer Weiterkommensgrenze werden '
                  'Entscheidungsspiele bzw. ein Vergleich um Zusatzplätze '
                  'angezeigt.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                for (
                  var groupIndex = 0;
                  groupIndex < stage.groups.length;
                  groupIndex++
                ) ...[
                  Text(
                    stage.groups[groupIndex].name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: StandingsTable(
                        standings:
                            standingsByGroup[stage.groups[groupIndex]] ??
                            const [],
                        group: stage.groups[groupIndex],
                        groupNumber: groupIndex + 1,
                        qualificationPlan: plan,
                        tieBreakers: stage.tieBreakers,
                        compact: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Tie-Breaker in dieser Reihenfolge',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                for (var index = 0; index < stage.tieBreakers.length; index++)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      child: Text('${index + 1}'),
                    ),
                    title: Text(tieBreakerLabel(stage.tieBreakers[index])),
                    subtitle: Text(
                      tieBreakerExplanation(stage.tieBreakers[index]),
                    ),
                  ),
                if (plan != null && plan.extraCount > 0) ...[
                  const SizedBox(height: 8),
                  BestOfComparisonTable(
                    stage: stage,
                    standingsByGroup: standingsByGroup,
                  ),
                ],
                if (deciderMatches.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Entscheidungsspiele / Zwischenrunde',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  for (final match in deciderMatches)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.sports),
                      title: Text(
                        '${match.homePlayer?.name ?? 'Offen'} · '
                        '${match.awayPlayer?.name ?? 'Offen'}',
                      ),
                      subtitle: Text(
                        match.hasResult
                            ? '${match.homeScore ?? '–'} : '
                                  '${match.awayScore ?? '–'}'
                            : 'Noch offen',
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        FilledButton(
          key: const ValueKey('group-end-review-acknowledge'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Verstanden · weiter'),
        ),
      ],
    );
  }
}
