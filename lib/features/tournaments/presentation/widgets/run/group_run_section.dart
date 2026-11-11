import 'package:flutter/material.dart';

import '../../../domain/tournament_models.dart';
import 'result_entry.dart';
import 'mobile_group_matches.dart';
import 'standings_table.dart';

class GroupRunSection extends StatefulWidget {
  const GroupRunSection({
    super.key,
    required this.group,
    required this.groupNumber,
    required this.qualificationPlan,
    required this.tieBreakers,
    required this.standings,
    required this.onEditResult,
    required this.canEditResults,
  });

  final TournamentGroup group;
  final int groupNumber;
  final QualificationPlan? qualificationPlan;
  final List<String> tieBreakers;
  final List<PlayerStanding> standings;
  final void Function(GroupMatch match) onEditResult;
  final bool canEditResults;

  @override
  State<GroupRunSection> createState() => _GroupRunSectionState();
}

class _GroupRunSectionState extends State<GroupRunSection> {
  bool _showMatches = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620 ||
            MediaQuery.textScalerOf(context).scale(16) > 24) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: MobileGroupMatches(
              group: widget.group,
              table: StandingsTable(
                standings: widget.standings,
                group: widget.group,
                groupNumber: widget.groupNumber,
                qualificationPlan: widget.qualificationPlan,
                tieBreakers: widget.tieBreakers,
              ),
              onEditResult: widget.onEditResult,
              canEditResults: widget.canEditResults,
            ),
          );
        }
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
                widget.group.name,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              StandingsTable(
                standings: widget.standings,
                group: widget.group,
                groupNumber: widget.groupNumber,
                qualificationPlan: widget.qualificationPlan,
                tieBreakers: widget.tieBreakers,
              ),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  setState(() {
                    _showMatches = !_showMatches;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    border: Border.all(color: colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _showMatches
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Begegnungen',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Chip(
                        label: Text(
                          '${widget.group.playType == 'swiss' ? (widget.group.players.length ~/ 2) * widget.group.matches.map((m) => m.round).toSet().length : widget.group.matches.length}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showMatches) ...[
                const SizedBox(height: 8),
                for (final match in widget.group.matches)
                  MatchResultTile(
                    match: match,
                    onEditResult: widget.onEditResult,
                    canEditResult: widget.canEditResults,
                    leadingLabel: match.isDecider ? match.label : null,
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
