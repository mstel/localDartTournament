import '../../../../../shared/widgets/sport_section_navigation.dart';
import 'package:flutter/material.dart';

import '../../../domain/tournament_models.dart';

enum StageViewMode {
  dashboard,
  results,
  settings,
  director,
  overview,
  playOrder,
  orderOfPlay,
  players,
}

class StageProgressBar extends StatelessWidget {
  const StageProgressBar({
    super.key,
    required this.stages,
    required this.activeStageIndex,
    required this.completedStageIndexes,
    required this.onStageSelected,
  });

  final List<TournamentRunStage> stages;
  final int activeStageIndex;
  final Set<int> completedStageIndexes;
  final ValueChanged<int> onStageSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 840 ||
            MediaQuery.textScalerOf(context).scale(16) > 24) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SportSectionNavigation<int>(
              label: 'Etappe',
              selected: activeStageIndex,
              onChanged: onStageSelected,
              sections: [
                for (var i = 0; i < stages.length; i++)
                  SportSection(
                    i,
                    '${i + 1}. ${stages[i].name}',
                    completedStageIndexes.contains(i)
                        ? Icons.check_circle_outline
                        : Icons.flag_outlined,
                  ),
              ],
            ),
          );
        }
        return Material(
          color: colorScheme.surface,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                for (var index = 0; index < stages.length; index++) ...[
                  _StageProgressChip(
                    label: stages[index].name,
                    number: index + 1,
                    isActive: index == activeStageIndex,
                    isComplete: completedStageIndexes.contains(index),
                    onTap: () => onStageSelected(index),
                  ),
                  if (index < stages.length - 1)
                    Container(
                      width: 28,
                      height: 1,
                      color: colorScheme.outlineVariant,
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StageProgressChip extends StatelessWidget {
  const _StageProgressChip({
    required this.label,
    required this.number,
    required this.isActive,
    required this.isComplete,
    required this.onTap,
  });

  final String label;
  final int number;
  final bool isActive;
  final bool isComplete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = isActive
        ? colorScheme.primaryContainer
        : colorScheme.surface;
    final borderColor = isActive
        ? colorScheme.primary
        : colorScheme.outlineVariant;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: isComplete
                  ? colorScheme.primary
                  : colorScheme.surface,
              child: Icon(
                isComplete ? Icons.check : Icons.flag_outlined,
                size: 15,
                color: isComplete ? colorScheme.onPrimary : colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text('$number. $label'),
          ],
        ),
      ),
    );
  }
}

class StageViewModeSwitch extends StatelessWidget {
  const StageViewModeSwitch({
    super.key,
    required this.selectedMode,
    required this.onModeChanged,
    this.canLead = true,
  });

  final StageViewMode selectedMode;
  final ValueChanged<StageViewMode> onModeChanged;
  final bool canLead;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
    child: SportSectionNavigation<StageViewMode>(
      label: 'Turnieransicht',
      selected: selectedMode,
      onChanged: onModeChanged,
      sections: [
        if (canLead)
          const SportSection(
            StageViewMode.dashboard,
            'Dashboard',
            Icons.dashboard_outlined,
          ),
        if (canLead)
          const SportSection(
            StageViewMode.director,
            'Leitung',
            Icons.sports_score_rounded,
          ),
        const SportSection(
          StageViewMode.results,
          'Ergebnisse',
          Icons.sports_score_outlined,
        ),
        if (canLead)
          const SportSection(
            StageViewMode.settings,
            'Einstellungen',
            Icons.tune_outlined,
          ),
      ],
    ),
  );
}

class StageFooter extends StatelessWidget {
  const StageFooter({
    super.key,
    required this.canCompleteStage,
    required this.isLastStage,
    required this.isViewingActiveStage,
    required this.activeStageName,
    required this.onCompleteStage,
    required this.onFinishEarly,
    this.onReopenPreviousStage,
    this.canReopenPreviousStage = false,
    this.onResetCurrentStage,
    this.canResetCurrentStage = false,
  });

  final bool canCompleteStage;
  final bool isLastStage;
  final bool isViewingActiveStage;
  final String activeStageName;
  final VoidCallback onCompleteStage;
  final VoidCallback onFinishEarly;
  final VoidCallback? onReopenPreviousStage;
  final bool canReopenPreviousStage;
  final VoidCallback? onResetCurrentStage;
  final bool canResetCurrentStage;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              !isViewingActiveStage
                  ? 'Vorschau: Ergebnisse und Abschluss sind nur in der aktuellen Etappe "$activeStageName" möglich.'
                  : canCompleteStage
                  ? 'Alle Ergebnisse dieser Etappe sind eingetragen.'
                  : 'Trage alle Ergebnisse ein, um die Etappe abzuschliessen.',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: isViewingActiveStage && !canCompleteStage
                      ? onFinishEarly
                      : null,
                  icon: const Icon(Icons.block_outlined),
                  label: const Text('Etappe vorzeitig beenden'),
                ),
                FilledButton.icon(
                  onPressed: canCompleteStage && isViewingActiveStage
                      ? onCompleteStage
                      : null,
                  icon: Icon(
                    isLastStage
                        ? Icons.check_circle_outline
                        : Icons.arrow_forward,
                  ),
                  label: Text(
                    isLastStage
                        ? 'Turnier abschliessen'
                        : 'Etappe abschliessen',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
