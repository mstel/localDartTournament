import '../../../../../shared/widgets/sport_settings_section.dart';
import 'round_match_list.dart';
import 'package:flutter/material.dart';

import '../../../domain/tournament_models.dart';

class MiniKnockoutGroupRunSection extends StatefulWidget {
  const MiniKnockoutGroupRunSection({
    super.key,
    required this.group,
    required this.bracket,
    this.onEditResult,
    this.canEditResults = false,
  });

  final TournamentGroup group;
  final Widget bracket;
  final ValueChanged<GroupMatch>? onEditResult;
  final bool canEditResults;

  @override
  State<MiniKnockoutGroupRunSection> createState() =>
      _MiniKnockoutGroupRunSectionState();
}

class _MiniKnockoutGroupRunSectionState
    extends State<MiniKnockoutGroupRunSection> {
  final _bracketKey = GlobalKey();
  final _roundsKey = GlobalKey();
  bool _expanded = false;
  TournamentGroup get group => widget.group;
  ValueChanged<GroupMatch>? get onEditResult => widget.onEditResult;
  bool get canEditResults => widget.canEditResults;
  Widget get bracket => KeyedSubtree(key: _bracketKey, child: widget.bracket);
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 840 ||
            MediaQuery.textScalerOf(context).scale(16) > 24;
        return Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                group.name,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                group.playType == 'mini_knockout'
                    ? 'Mini-KO-Phase'
                    : _groupPlayTypeLabel(group.playType),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (group.knockoutRounds.isEmpty)
                const Text('Keine Paarungen in dieser Gruppe.')
              else if (compact) ...[
                RoundMatchList(
                  key: _roundsKey,
                  rounds: [
                    ...group.knockoutRounds,
                    if (group.placementMatches.isNotEmpty)
                      group.placementMatches,
                  ],
                  onEditResult: onEditResult ?? (_) {},
                  canEditResults: canEditResults,
                ),
                SportSettingsSection(
                  title: 'Gruppenbaum',
                  summary: 'Gesamter Verlauf dieser Gruppe',
                  icon: Icons.account_tree_outlined,
                  initiallyExpanded: _expanded,
                  onExpansionChanged: (value) => _expanded = value,
                  children: [bracket],
                ),
              ] else
                bracket,
            ],
          ),
        );
      },
    );
  }
}

String _groupPlayTypeLabel(String playType) {
  return switch (playType) {
    'round_robin' => 'Jeder gegen jeden',
    'mini_knockout' => 'Mini-KO in der Gruppe',
    'double_elimination' => 'Doppel-KO in der Gruppe',
    'triple_elimination' => 'Triple-KO in der Gruppe',
    _ => playType,
  };
}
