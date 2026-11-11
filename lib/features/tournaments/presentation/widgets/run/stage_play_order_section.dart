import 'round_match_list.dart';
import '../../../domain/knockout_round_names.dart';
import 'package:flutter/material.dart';

import '../../../domain/tournament_models.dart';
import '../../../../../shared/widgets/sport_metric_grid.dart';
import 'stage_surface.dart';

class StagePlayOrderSection extends StatefulWidget {
  const StagePlayOrderSection({
    super.key,
    required this.stage,
    required this.matches,
    required this.onEditResult,
    required this.canEditResults,
  });

  final TournamentRunStage stage;
  final List<GroupMatch> matches;
  final void Function(GroupMatch match) onEditResult;
  final bool canEditResults;

  @override
  State<StagePlayOrderSection> createState() => _StagePlayOrderSectionState();
}

class _StagePlayOrderSectionState extends State<StagePlayOrderSection> {
  bool _results = false;
  TournamentRunStage get stage => widget.stage;
  List<GroupMatch> get matches => widget.matches;
  @override
  Widget build(BuildContext context) {
    final rounds = <int, List<GroupMatch>>{};
    for (final match in matches.where(
      (m) => _results ? m.isResolved : !m.isResolved,
    )) {
      rounds.putIfAbsent(match.round, () => []).add(match);
    }
    final groupLabels = _groupLabelsByMatch();
    final completed = matches.where((m) => m.isResolved).length;
    final ordered = rounds.keys.toList()..sort();
    return StageSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            stage.name,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text('Begegnungsreihenfolge'),
          const SizedBox(height: 16),
          SportMetricGrid(
            metrics: [
              SportMetric(
                'Offene Begegnungen',
                '${matches.length - completed}',
                Icons.sports_score,
              ),
              SportMetric(
                'Ergebnisse',
                '$completed',
                Icons.check_circle_outline,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Offene Begegnungen'),
                selected: !_results,
                padding: const EdgeInsets.all(12),
                onSelected: (_) => setState(() => _results = false),
              ),
              ChoiceChip(
                label: const Text('Ergebnisse'),
                selected: _results,
                padding: const EdgeInsets.all(12),
                onSelected: (_) => setState(() => _results = true),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (ordered.isEmpty)
            Text(
              matches.isEmpty
                  ? 'Keine Begegnungen in dieser Phase.'
                  : _results
                  ? 'Noch keine Ergebnisse.'
                  : 'Alle Begegnungen abgeschlossen.',
            )
          else
            RoundMatchList(
              key: ValueKey((stage, _results)),
              rounds: [for (final round in ordered) rounds[round]!],
              labels: [
                for (final round in ordered) _roundTitle(rounds[round]!),
              ],
              useColumns: true,
              originLabelFor: (match) => groupLabels[match],
              leadingLabelFor: _leadingLabel,
              onEditResult: widget.onEditResult,
              canEditResults: widget.canEditResults,
            ),
        ],
      ),
    );
  }

  Map<GroupMatch, String> _groupLabelsByMatch() {
    final currentStage = stage;
    if (currentStage is! GroupTournamentRunStage) {
      return const {};
    }

    return {
      for (final group in currentStage.groups)
        for (final match in group.matches) match: group.name,
    };
  }

  String _roundTitle(List<GroupMatch> roundMatches) {
    if (roundMatches.every((match) => _isPlacementMatchLabel(match.label))) {
      return 'Platzierung';
    }
    final firstMatch = roundMatches.isEmpty ? null : roundMatches.first;
    if (firstMatch != null && firstMatch.isDecider) {
      return 'Decider';
    }
    return firstMatch == null ? 'Runde' : stageMatchName(stage, firstMatch);
  }

  String? _leadingLabel(GroupMatch match) {
    if (match.isDecider || _isPlacementMatchLabel(match.label)) {
      return match.label;
    }
    return stageMatchName(stage, match);
  }

  bool _isPlacementMatchLabel(String? label) {
    return label == 'Spiel um Platz 3' ||
        label == 'Spiel um Platz 5' ||
        label == 'Spiel um Platz 7' ||
        (label?.startsWith('Platz 5 Halbfinale') ?? false);
  }
}
