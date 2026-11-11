import 'package:flutter/material.dart';

import '../../../domain/tournament_models.dart';
import 'best_of_comparison_table.dart';
import 'group_run_section.dart';
import 'mini_knockout_group_run_section.dart';
import 'stage_surface.dart';

typedef MiniKnockoutBracketBuilder =
    Widget Function(
      TournamentGroup group,
      int qualifyingRank,
      void Function(GroupMatch match) onEditResult,
      bool canEditResults,
    );

class GroupStageRunSection extends StatefulWidget {
  const GroupStageRunSection({
    super.key,
    required this.stage,
    required this.standingsFor,
    required this.onEditResult,
    required this.canEditResults,
    required this.miniKnockoutBracketBuilder,
    this.onEditPositions,
  });

  final GroupTournamentRunStage stage;
  final List<PlayerStanding> Function(
    TournamentGroup group,
    List<String> tieBreakers,
  )
  standingsFor;
  final void Function(GroupMatch match) onEditResult;
  final bool canEditResults;
  final MiniKnockoutBracketBuilder miniKnockoutBracketBuilder;
  final VoidCallback? onEditPositions;

  @override
  State<GroupStageRunSection> createState() => _GroupStageRunSectionState();
}

class _GroupStageRunSectionState extends State<GroupStageRunSection> {
  int _selectedGroup = 0;
  GroupTournamentRunStage get stage => widget.stage;
  List<PlayerStanding> Function(TournamentGroup, List<String>)
  get standingsFor => widget.standingsFor;
  void Function(GroupMatch) get onEditResult => widget.onEditResult;
  bool get canEditResults => widget.canEditResults;
  MiniKnockoutBracketBuilder get miniKnockoutBracketBuilder =>
      widget.miniKnockoutBracketBuilder;
  VoidCallback? get onEditPositions => widget.onEditPositions;

  @override
  Widget build(BuildContext context) {
    final standingsByGroup = {
      for (final group in stage.groups)
        if (['round_robin', 'swiss'].contains(group.playType))
          group: standingsFor(group, stage.tieBreakers),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 840 ||
            MediaQuery.textScalerOf(context).scale(16) > 24;
        final selected = _selectedGroup.clamp(
          0,
          stage.groups.isEmpty ? 0 : stage.groups.length - 1,
        );
        return StageSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!compact) ...[
                Text(
                  stage.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
              ],
              if (stage.groups.any((g) => g.playType == 'swiss'))
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Swiss: Nächste Runde erst nach allen Ergebnissen der vorherigen Runde. Wertung: Punkte, Buchholz (Gegnerpunkte), Leg-Differenz, gewonnene Legs, Startreihenfolge. Freilos: 3 Punkte, kein gespieltes Match.',
                  ),
                ),
              if (compact && stage.groups.length > 1) ...[
                DropdownButtonFormField<int>(
                  key: ValueKey('group-$selected'),
                  initialValue: selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Gruppe auswählen',
                  ),
                  items: [
                    for (var i = 0; i < stage.groups.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(stage.groups[i].name),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _selectedGroup = value);
                  },
                ),
                const SizedBox(height: 12),
              ],
              for (var index = 0; index < stage.groups.length; index++)
                if (!compact || index == selected)
                  if (_isEliminationGroupPlayType(stage.groups[index].playType))
                    MiniKnockoutGroupRunSection(
                      key: ValueKey(stage.groups[index]),
                      group: stage.groups[index],
                      onEditResult: onEditResult,
                      canEditResults: canEditResults,
                      bracket: miniKnockoutBracketBuilder(
                        stage.groups[index],
                        _requiredRankForMiniGroup(stage, index),
                        onEditResult,
                        canEditResults,
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (stage.groups[index].playType == 'round_robin' &&
                            stage.groups[index].players.any(
                              (p) =>
                                  stage.groups[index].matches
                                      .where(
                                        (m) =>
                                            m.hasPlayers &&
                                            (m.homePlayer == p ||
                                                m.awayPlayer == p),
                                      )
                                      .length <
                                  stage.groups[index].players.length - 1,
                            ))
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Begrenzte Gruppenphase · Es werden die geplanten Begegnungen gewertet.',
                            ),
                          ),
                        GroupRunSection(
                          key: ValueKey(stage.groups[index]),
                          group: stage.groups[index],
                          groupNumber: index + 1,
                          qualificationPlan: stage.qualificationPlan,
                          tieBreakers: stage.tieBreakers,
                          standings: standingsByGroup[stage.groups[index]]!,
                          onEditResult: onEditResult,
                          canEditResults: canEditResults,
                        ),
                      ],
                    ),
              ExpansionTile(
                key: PageStorageKey('group-setup-${stage.name}'),
                title: const Text('Gruppen verwalten'),
                leading: const Icon(Icons.tune),
                childrenPadding: const EdgeInsets.only(bottom: 12),
                children: [
                  OutlinedButton.icon(
                    onPressed: onEditPositions,
                    icon: const Icon(Icons.open_with),
                    label: const Text('Positionen bearbeiten'),
                  ),
                  const Text(
                    'Teilnehmer können vor der ersten Begegnung oder Ergebniseingabe getauscht werden.',
                  ),
                ],
              ),
              if (stage.qualificationPlan != null &&
                  stage.qualificationPlan!.extraCount > 0 &&
                  stage.groups.every(
                    (group) =>
                        ['round_robin', 'swiss'].contains(group.playType),
                  )) ...[
                const SizedBox(height: 4),
                BestOfComparisonTable(
                  stage: stage,
                  standingsByGroup: standingsByGroup,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  int _requiredRankForMiniGroup(GroupTournamentRunStage stage, int groupIndex) {
    final plan = stage.qualificationPlan;
    if (plan == null) {
      return 1;
    }

    final fixedForGroup = groupIndex < plan.fixedByGroup.length
        ? plan.fixedByGroup[groupIndex]
        : plan.fixedPerGroup;
    final groupNumber = groupIndex + 1;
    final extraRank = plan.extraGroups.contains(groupNumber)
        ? plan.extraRank
        : 0;
    final requiredRank = fixedForGroup > extraRank ? fixedForGroup : extraRank;
    return requiredRank < 1 ? 1 : requiredRank;
  }
}

bool _isEliminationGroupPlayType(String playType) {
  return playType == 'mini_knockout' ||
      playType == 'double_elimination' ||
      playType == 'triple_elimination';
}
