import 'package:flutter/material.dart';
import '../../application/tournament_duration_range.dart';
import '../../domain/tournament_format_planner.dart';
import 'planning_match_breakdown_view.dart';

class PlanningSuggestionCard extends StatelessWidget {
  const PlanningSuggestionCard({
    super.key,
    required this.suggestion,
    required this.onSelected,
  });
  final TournamentFormatSuggestion suggestion;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final durationRange = TournamentDurationRange.forEstimate(
      estimatedMinutes: suggestion.estimatedMinutes,
      matches: suggestion.configurations.isNotEmpty
          ? [
              for (
                var index = 0;
                index < suggestion.configurations.length;
                index++
              )
                (
                  bestOfLegs:
                      suggestion.configurations[index].gameFormat.bestOfLegs,
                  matchCount: index < suggestion.stageMatchCounts.length
                      ? suggestion.stageMatchCounts[index]
                      : 1,
                ),
            ]
          : [
              for (final stage in suggestion.stages)
                (bestOfLegs: stage.format.bestOfLegs, matchCount: 1),
            ],
    );
    final minMinutes = durationRange.minimumMinutes;
    final maxMinutes = durationRange.maximumMinutes;
    final minH = minMinutes ~/ 60;
    final minM = minMinutes % 60;
    final maxH = maxMinutes ~/ 60;
    final maxM = maxMinutes % 60;
    final spanText =
        'Spanne: ${minH > 0 ? '$minH h ' : ''}$minM min – ${maxH > 0 ? '$maxH h ' : ''}$maxM min';
    final estH = suggestion.estimatedMinutes ~/ 60;
    final estM = suggestion.estimatedMinutes % 60;
    final durationText = 'ca. ${estH > 0 ? '$estH h ' : ''}$estM min';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Fix 1.3: Titel + Dauer prominent an erster Stelle
                    Text(suggestion.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          durationText,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '· $spanText',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            suggestion.configurations.isNotEmpty
                                ? suggestion
                                      .configurations
                                      .first
                                      .gameFormat
                                      .label
                                : suggestion.format.label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Fix 1.4: Qualifikationspfeile nur anzeigen wo sie relevant sind
                    // (nicht für die letzte/einzige Etappe eines mehrstufigen Turniers)
                    if (suggestion.configurations.isNotEmpty) ...[
                      for (
                        var i = 0;
                        i < suggestion.configurations.length;
                        i++
                      ) ...[
                        Builder(
                          builder: (context) {
                            final stage = suggestion.configurations[i];
                            final isLast =
                                i == suggestion.configurations.length - 1;
                            final participants = stage.type == 'groups'
                                ? stage.groupSizes.fold<int>(0, (a, b) => a + b)
                                : stage.knockoutParticipantCount;
                            // Fix 1.4: Kein "→ X weiter" bei der letzten Etappe
                            final qualifier =
                                (!isLast &&
                                    suggestion.configurations.length > 1)
                                ? ' → ${stage.qualifiedParticipantCount ?? 1} weiter'
                                : '';
                            return Text(
                              '${stage.name}: ${stage.gameFormat.label} · $participants Spieler$qualifier',
                            );
                          },
                        ),
                      ],
                      // Fix 1.5: Leg-Spanne aus stageMatchCounts + format
                      for (
                        var i = 0;
                        i < suggestion.stageMatchCounts.length;
                        i++
                      ) ...[
                        Builder(
                          builder: (context) {
                            final stage = suggestion.configurations[i];
                            final matchCount = suggestion.stageMatchCounts[i];
                            final bo = stage.gameFormat.bestOfLegs;
                            final minLegs = (bo ~/ 2 + 1);
                            final maxLegs = bo;
                            return Text(
                              '${i + 1}. ${stage.name}: $matchCount Spiele · $minLegs–$maxLegs Legs/Spiel',
                              style: theme.textTheme.bodySmall,
                            );
                          },
                        ),
                      ],
                    ],

                    if (suggestion.configurations.isEmpty)
                      for (final stage in suggestion.stages)
                        Text('${stage.label}: ${stage.format.label}'),

                    const SizedBox(height: 4),
                    Text(
                      '${suggestion.variableMatches ? 'ca. ' : ''}${suggestion.totalMatches} Spiele gesamt'
                      ' · mind. ${suggestion.minimumMatchesPerPlayer} je Spieler'
                      ' · ${suggestion.effectiveBoards} Boards',
                    ),

                    if (suggestion.configurations.isEmpty)
                      PlanningMatchBreakdownView(
                        breakdown: suggestion.matchBreakdown,
                      ),

                    // Fix 1.6: Hinweistext nur einmal – wenn vorhanden, am Ende kompakt
                    if (suggestion.configurations.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Simulation mit Boardplanung. Dauer variiert je Ergebnisverlauf.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),

                    for (final stage in suggestion.configurations.where(
                      (s) => s.groupPlayType == 'swiss',
                    ))
                      Text(
                        'Swiss: ${stage.groupRoundRobinRepeats.join(" / ")} Runden – wartet auf alle Partien je Runde.',
                        style: theme.textTheme.bodySmall,
                      ),

                    // Detaillierte Zeitblöcke (collapsible würde hier zu viel Aufwand sein)
                    if (suggestion.duration case final duration?) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Gruppen: ${duration.groupSlots} Zeitblöcke × ${duration.matchMinutes.toStringAsFixed(1)} min = ${duration.groupMinutes} min'
                        '  |  K.-o.: ${duration.knockoutSlots} Zeitblöcke × ${duration.knockoutMatchMinutes.toStringAsFixed(1)} min = ${duration.knockoutMinutes} min'
                        '  |  Gesamt: ${duration.totalMinutes} min',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],

                    if (suggestion.isClosestAlternative)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Nächstbeste Lösung außerhalb der gewünschten Vorgaben',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
