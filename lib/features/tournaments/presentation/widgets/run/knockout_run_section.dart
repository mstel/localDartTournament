import 'dart:async';

import '../../../../../shared/widgets/sport_settings_section.dart';
import '../../../domain/knockout_round_names.dart';
import 'round_match_list.dart';
import 'package:flutter/material.dart';

import '../../../domain/tournament_models.dart';
import 'stage_surface.dart';

typedef KnockoutBracketBuilder =
    Widget Function(
      KnockoutTournamentRunStage stage,
      int qualifyingRank,
      FutureOr<void> Function(GroupMatch match) onEditResult,
      bool canEditResults,
      bool isEditMode,
      void Function(int fromSlotIndex, int toSlotIndex) onSwapSlot,
    );

class KnockoutRunSection extends StatelessWidget {
  const KnockoutRunSection({
    super.key,
    required this.stage,
    required this.qualifyingRank,
    required this.onEditResult,
    required this.canEditResults,
    required this.isEditMode,
    required this.canEditBracket,
    required this.onEditModeChanged,
    required this.onSwapSlot,
    required this.bracketBuilder,
  });

  final KnockoutTournamentRunStage stage;
  final int qualifyingRank;
  final FutureOr<void> Function(GroupMatch match) onEditResult;
  final bool canEditResults;
  final bool isEditMode;
  final bool canEditBracket;
  final ValueChanged<bool> onEditModeChanged;
  final void Function(int fromSlotIndex, int toSlotIndex) onSwapSlot;
  final KnockoutBracketBuilder bracketBuilder;

  Widget _editControls(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: canEditBracket
              ? () => onEditModeChanged(!isEditMode)
              : null,
          icon: Icon(isEditMode ? Icons.check_circle_outline : Icons.open_with),
          label: Text(
            isEditMode ? 'Bearbeitung beenden' : 'Positionen bearbeiten',
          ),
        ),
      ),
      if (!canEditBracket) ...[
        const SizedBox(height: 8),
        Text(
          canEditResults
              ? 'Positionen können nur geändert werden, solange in dieser K.-o.-Etappe noch kein Ergebnis eingetragen ist.'
              : 'Positionen können nur in der aktuellen Etappe bearbeitet werden.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ] else if (isEditMode) ...[
        const SizedBox(height: 8),
        Text(
          'Ziehe Spieler in Runde 1 auf einen anderen Platz oder ein Freilos.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 840 ||
            MediaQuery.textScalerOf(context).scale(16) > 24;
        return StageSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                stage.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                stage.eliminationLossLimit == 1
                    ? (compact ? 'Partien' : 'Turnierbaum')
                    : 'Eliminationsplan - Aus nach ${stage.eliminationLossLimit} Niederlagen',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (stage.eliminationLossLimit > 1)
                Text(
                  stage.finalEndsTournament
                      ? 'Das große Finale entscheidet unabhängig von übrigen Leben.'
                      : 'Kratzer-Modus · ${stage.eliminationLossLimit} Leben · Auch im Finale zählen die verbleibenden Leben.',
                ),
              const SizedBox(height: 12),
              if (compact && stage.rounds.isNotEmpty) ...[
                RoundMatchList(
                  key: ValueKey(stage),
                  rounds: [
                    ...stage.rounds,
                    if (stage.placementMatches.isNotEmpty)
                      stage.placementMatches,
                  ],
                  labels: [
                    for (var i = 0; i < stage.rounds.length; i++)
                      stage.eliminationLossLimit == 1
                          ? knockoutRoundName(i, stage.rounds.length)
                          : 'Runde ${i + 1}',
                    if (stage.placementMatches.isNotEmpty) 'Platzierung',
                  ],
                  onEditResult: (match) => onEditResult(match),
                  canEditResults: canEditResults,
                ),
                SportSettingsSection(
                  title: 'Turnierbaum & Setzung',
                  summary: 'Gesamter Verlauf und Positionen',
                  icon: Icons.account_tree_outlined,
                  children: [
                    _editControls(context),
                    if (stage.rounds.isEmpty)
                      const Text('Keine Paarungen in dieser Etappe.')
                    else
                      bracketBuilder(
                        stage,
                        qualifyingRank,
                        onEditResult,
                        canEditResults,
                        isEditMode && canEditBracket,
                        onSwapSlot,
                      ),
                  ],
                ),
              ] else ...[
                _editControls(context),
                if (stage.rounds.isEmpty)
                  const Text('Keine Paarungen in dieser Etappe.')
                else
                  bracketBuilder(
                    stage,
                    qualifyingRank,
                    onEditResult,
                    canEditResults,
                    isEditMode && canEditBracket,
                    onSwapSlot,
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
