import 'package:flutter/material.dart';

import '../../../domain/tournament_models.dart';

/// Kurzlabel `gespielte/angesetzte Begegnungen` für einen Gruppenkopf.
String groupMatchProgressLabel(TournamentGroup group) {
  final played = group.matches
      .where((match) => match.hasPlayers && match.hasResult)
      .length;
  final total = group.matches.where((match) => match.hasPlayers).length;
  return '$played/$total';
}

/// Weiterkommensregel einer Gruppe, inklusive Vergleichsplätzen.
String groupAdvancementLabel(QualificationPlan? plan, int groupNumber) {
  final fixedPlaces = plan?.fixedForGroup(groupNumber) ?? 2;
  if (plan == null ||
      plan.extraCount <= 0 ||
      !plan.extraGroups.contains(groupNumber)) {
    return 'Top $fixedPlaces weiter';
  }

  return plan.extraCount == 1
      ? 'Top $fixedPlaces & bester ${plan.extraRank}. Platz'
      : 'Top $fixedPlaces & ${plan.extraCount} beste ${plan.extraRank}. Plätze';
}

class BestOfComparisonTable extends StatefulWidget {
  const BestOfComparisonTable({
    super.key,
    required this.stage,
    required this.standingsByGroup,
  });

  final GroupTournamentRunStage stage;
  final Map<TournamentGroup, List<PlayerStanding>> standingsByGroup;

  @override
  State<BestOfComparisonTable> createState() => _BestOfComparisonTableState();
}

class _BestOfComparisonTableState extends State<BestOfComparisonTable> {
  final _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  int _compareCandidates(BestOfCandidate a, BestOfCandidate b) {
    for (final tieBreaker in widget.stage.tieBreakers) {
      final comparison = switch (tieBreaker) {
        'points' => b.standing.points.compareTo(a.standing.points),
        'legDifference' => b.standing.legDifference.compareTo(
          a.standing.legDifference,
        ),
        'legsFor' => b.standing.legsFor.compareTo(a.standing.legsFor),
        _ => 0,
      };

      if (comparison != 0) {
        return comparison;
      }
    }

    final deciderComparison = _compareBestOfDeciders(a, b);
    if (deciderComparison != 0) {
      return deciderComparison;
    }

    final groupCompare = a.groupNumber.compareTo(b.groupNumber);
    if (groupCompare != 0) {
      return groupCompare;
    }
    return a.standing.player.name.compareTo(b.standing.player.name);
  }

  int _compareBestOfDeciders(BestOfCandidate a, BestOfCandidate b) {
    for (final group in widget.stage.groups) {
      for (final match in group.matches.where(
        (match) =>
            match.isDecider &&
            match.label == 'Beste-N Decider' &&
            match.hasResult,
      )) {
        final home = match.homePlayer;
        final away = match.awayPlayer;
        if (home == null || away == null || match.winner == null) {
          continue;
        }
        final isDirectMatch =
            (home.name == a.standing.player.name &&
                away.name == b.standing.player.name) ||
            (home.name == b.standing.player.name &&
                away.name == a.standing.player.name);
        if (!isDirectMatch) {
          continue;
        }
        return match.winner!.name == a.standing.player.name ? -1 : 1;
      }
    }

    return 0;
  }

  bool _allCandidateGroupsComplete(List<BestOfCandidate> candidates) {
    return candidates.every((candidate) {
      final group = widget.stage.groups[candidate.groupNumber - 1];
      return group.matches.every((match) => match.hasResult);
    });
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.stage.qualificationPlan;
    if (plan == null || plan.extraCount == 0 || plan.extraGroups.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    final candidates = <BestOfCandidate>[];
    for (
      var groupIndex = 0;
      groupIndex < widget.stage.groups.length;
      groupIndex++
    ) {
      final groupNumber = groupIndex + 1;
      if (!plan.extraGroups.contains(groupNumber)) {
        continue;
      }

      final standings =
          widget.standingsByGroup[widget.stage.groups[groupIndex]] ?? const [];
      final candidateIndex = plan.extraRank - 1;
      if (candidateIndex >= 0 && candidateIndex < standings.length) {
        candidates.add(
          BestOfCandidate(
            groupName: widget.stage.groups[groupIndex].name,
            groupNumber: groupNumber,
            place: plan.extraRank,
            standing: standings[candidateIndex],
          ),
        );
      }
    }

    candidates.sort(_compareCandidates);
    final allComplete = _allCandidateGroupsComplete(candidates);

    // Dieselben Farben wie in den Abschlusstabellen: dunkles Gruen mit hellem
    // Text fuer sichere Plaetze, ein helleres Gruen bzw. ein dunkles Gruen fuer
    // noch offene Vergleiche. Alle Farben werden mit dem Text kontrastreich
    // kombiniert, damit die Tabelle in Licht- und Dunkelthema lesbar bleibt.
    final sureRowColor = isDark
        ? const Color(0xFF144D34)
        : const Color(0xFF0B6B45);
    final sureTextColor = isDark ? const Color(0xFF86EFAC) : Colors.white;
    final possibleRowColor = isDark
        ? const Color(0xFF163828)
        : const Color(0xFFD6F5E3);
    final possibleTextColor = isDark
        ? const Color(0xFFA7F3D0)
        : const Color(0xFF064E3B);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final columnSpacing = availableWidth.isFinite && availableWidth > 260
            ? ((availableWidth - 260) / 5).clamp(12.0, 36.0).toDouble()
            : 12.0;

        return Container(
          margin: const EdgeInsets.only(top: 4),
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
                'Beste ${plan.extraCount} der ${plan.extraRank}. Plätze',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Vergleich aus ${_formatGroups(plan.extraGroups)}',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Scrollbar(
                controller: _horizontalController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _horizontalController,
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: columnSpacing,
                    horizontalMargin: 12,
                    headingRowHeight: 44,
                    dataRowMinHeight: 48,
                    dataRowMaxHeight: 72,
                    headingRowColor: WidgetStateProperty.all(
                      colorScheme.surfaceContainerHighest,
                    ),
                    headingTextStyle: textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                    dataTextStyle: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                    columns: const [
                      DataColumn(label: Text('#')),
                      DataColumn(label: Text('Gruppe')),
                      DataColumn(label: Text('Teilnehmer')),
                      DataColumn(label: Text('Pkt')),
                      DataColumn(label: Text('Legs')),
                      DataColumn(label: Text('Diff')),
                    ],
                    rows: [
                      for (var index = 0; index < candidates.length; index++)
                        _buildRow(
                          context: context,
                          index: index,
                          candidate: candidates[index],
                          advances: index < plan.extraCount,
                          allComplete: allComplete,
                          sureRowColor: sureRowColor,
                          sureTextColor: sureTextColor,
                          possibleRowColor: possibleRowColor,
                          possibleTextColor: possibleTextColor,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  DataRow _buildRow({
    required BuildContext context,
    required int index,
    required BestOfCandidate candidate,
    required bool advances,
    required bool allComplete,
    required Color sureRowColor,
    required Color sureTextColor,
    required Color possibleRowColor,
    required Color possibleTextColor,
  }) {
    Color? rowColor;
    Color? textColor;
    FontWeight? fontWeight;
    if (advances) {
      rowColor = allComplete ? sureRowColor : possibleRowColor;
      textColor = allComplete ? sureTextColor : possibleTextColor;
      fontWeight = allComplete ? FontWeight.w600 : FontWeight.w500;
    }

    final cellStyle = textColor == null && fontWeight == null
        ? null
        : Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: textColor,
            fontWeight: fontWeight,
          );

    return DataRow(
      color: WidgetStateProperty.all(rowColor),
      cells: [
        DataCell(Text('${index + 1}', style: cellStyle)),
        DataCell(Text(candidate.groupName, style: cellStyle)),
        DataCell(
          Tooltip(
            message: advances && allComplete
                ? 'Kommt sicher weiter'
                : 'Vergleich um Zusatzplatz',
            child: Text(candidate.standing.player.name, style: cellStyle),
          ),
        ),
        DataCell(Text('${candidate.standing.points}', style: cellStyle)),
        DataCell(
          Text(
            '${candidate.standing.legsFor}:'
            '${candidate.standing.legsAgainst}',
            style: cellStyle,
          ),
        ),
        DataCell(Text('${candidate.standing.legDifference}', style: cellStyle)),
      ],
    );
  }

  String _formatGroups(List<int> groups) {
    if (groups.length == 1) {
      return groupLabel(groups.first);
    }

    return groups.map(groupLabel).join(', ');
  }
}
