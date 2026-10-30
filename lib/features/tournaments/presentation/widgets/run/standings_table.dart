import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/tournament_models.dart';
import '../../../domain/engines/qualification_certainty.dart';
import '../../../modes/swiss/swiss_engine.dart';

class StandingsTable extends StatefulWidget {
  const StandingsTable({
    super.key,
    required this.standings,
    required this.group,
    required this.groupNumber,
    required this.qualificationPlan,
    required this.tieBreakers,
    this.onPlayerTap,
    this.compact = false,
  });

  final List<PlayerStanding> standings;
  final TournamentGroup group;
  final int groupNumber;
  final QualificationPlan? qualificationPlan;
  final List<String> tieBreakers;
  final ValueChanged<TournamentPlayer>? onPlayerTap;
  final bool compact;

  @override
  State<StandingsTable> createState() => _StandingsTableState();
}

class _StandingsTableState extends State<StandingsTable> {
  final _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  bool _isFixedQualificationPlace(int place) {
    final plan = widget.qualificationPlan;
    if (plan == null) {
      return false;
    }

    final fixedForGroup = widget.groupNumber - 1 < plan.fixedByGroup.length
        ? plan.fixedByGroup[widget.groupNumber - 1]
        : plan.fixedPerGroup;
    return place <= fixedForGroup;
  }

  bool _isBestOfCandidatePlace(int place) {
    final plan = widget.qualificationPlan;
    if (plan == null) {
      return false;
    }

    return plan.extraCount > 0 &&
        place == plan.extraRank &&
        plan.extraGroups.contains(widget.groupNumber);
  }

  bool _isSureQualification(PlayerStanding standing, int place) {
    final plan = widget.qualificationPlan;
    if (plan == null) return false;
    final groupIndex = widget.groupNumber - 1;
    final fixedPlaces = groupIndex >= 0 && groupIndex < plan.fixedByGroup.length
        ? plan.fixedByGroup[groupIndex]
        : plan.fixedPerGroup;
    return const QualificationCertainty().isCertain(
      standing: standing,
      place: place,
      fixedPlaces: fixedPlaces,
      standings: widget.standings,
      matches: widget.group.matches,
      tieBreakers: widget.tieBreakers,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final sureColor = isDarkMode
        ? const Color(0xFF144D34)
        : const Color(0xFF0B6B45);
    final possibleColor = isDarkMode
        ? const Color(0xFF163828)
        : const Color(0xFFD6F5E3);
    final bestOfColor = isDarkMode
        ? const Color(0xFF3B3216)
        : const Color(0xFFFFF1C2);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = 9 + (widget.group.playType == 'swiss' ? 1 : 0);
        final baseSpacing = widget.compact ? 8.0 : 16.0;
        final widestName = widget.standings.fold<double>(
          72,
          (width, standing) => math.max(
            width,
            (widget.compact
                        ? standing.player.shortDisplayName
                        : standing.player.name)
                    .length *
                (widget.compact ? 7 : 8),
          ),
        );
        final minimumContentWidth =
            (widget.compact ? 12 : 24) +
            widestName +
            (columnCount - 2) * (widget.compact ? 30 : 38);
        final columnSpacing = math.max(
          baseSpacing,
          constraints.hasBoundedWidth
              ? (constraints.maxWidth - minimumContentWidth) / (columnCount - 1)
              : baseSpacing,
        );
        return Scrollbar(
          controller: _horizontalController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: columnSpacing,
              horizontalMargin: widget.compact ? 6 : 12,
              headingRowHeight: widget.compact ? 32 : 36,
              dataRowMinHeight: widget.compact ? 34 : 40,
              dataRowMaxHeight: widget.compact ? 38 : 44,
              headingTextStyle: widget.compact
                  ? Theme.of(context).textTheme.labelSmall
                  : null,
              dataTextStyle: widget.compact
                  ? Theme.of(context).textTheme.bodySmall
                  : null,
              columns: [
                const DataColumn(numeric: true, label: Text('#')),
                const DataColumn(label: Text('Spieler')),
                const DataColumn(numeric: true, label: Text('Sp')),
                const DataColumn(numeric: true, label: Text('S')),
                const DataColumn(numeric: true, label: Text('U')),
                const DataColumn(numeric: true, label: Text('N')),
                const DataColumn(numeric: true, label: Text('Legs')),
                const DataColumn(numeric: true, label: Text('Diff')),
                const DataColumn(numeric: true, label: Text('Pkt')),
                if (widget.group.playType == 'swiss')
                  const DataColumn(
                    numeric: true,
                    label: Tooltip(
                      message:
                          'Summe der Punkte der gespielten Gegner; Freilose zählen nicht mit.',
                      child: Text('Buchholz'),
                    ),
                  ),
              ],
              rows: [
                for (var index = 0; index < widget.standings.length; index++)
                  _buildRow(
                    context: context,
                    index: index,
                    isDarkMode: isDarkMode,
                    sureColor: sureColor,
                    possibleColor: possibleColor,
                    bestOfColor: bestOfColor,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  DataRow _buildRow({
    required BuildContext context,
    required int index,
    required bool isDarkMode,
    required Color sureColor,
    required Color possibleColor,
    required Color bestOfColor,
  }) {
    final place = index + 1;
    final standing = widget.standings[index];
    final isFixed = _isFixedQualificationPlace(place);
    final isSure = isFixed && _isSureQualification(standing, place);
    final isPossible = isFixed && !isSure;
    final isBestOf = _isBestOfCandidatePlace(place);

    Color? rowColor;
    Color? cellTextColor;
    FontWeight? fontWeight;

    if (isSure) {
      rowColor = sureColor;
      cellTextColor = isDarkMode ? const Color(0xFF86EFAC) : Colors.white;
      fontWeight = FontWeight.w600;
    } else if (isPossible) {
      rowColor = possibleColor;
      cellTextColor = isDarkMode
          ? const Color(0xFFA7F3D0)
          : const Color(0xFF064E3B);
      fontWeight = FontWeight.w500;
    } else if (isBestOf) {
      rowColor = bestOfColor;
      cellTextColor = isDarkMode
          ? const Color(0xFFFDE68A)
          : const Color(0xFF78350F);
      fontWeight = FontWeight.w500;
    }

    return DataRow(
      color: WidgetStateProperty.resolveWith((states) => rowColor),
      cells: [
        DataCell(
          _StandingText(
            '${index + 1}',
            textColor: cellTextColor,
            fontWeight: fontWeight,
          ),
        ),
        DataCell(
          _StandingText(
            widget.compact
                ? standing.player.shortDisplayName
                : standing.player.name,
            textColor: cellTextColor,
            fontWeight: fontWeight,
          ),
          onTap: widget.onPlayerTap == null
              ? null
              : () => widget.onPlayerTap!(standing.player),
        ),
        DataCell(
          _StandingText(
            '${standing.played}',
            textColor: cellTextColor,
            fontWeight: fontWeight,
          ),
        ),
        DataCell(
          _StandingText(
            '${standing.wins}',
            textColor: cellTextColor,
            fontWeight: fontWeight,
          ),
        ),
        DataCell(
          _StandingText(
            '${standing.draws}',
            textColor: cellTextColor,
            fontWeight: fontWeight,
          ),
        ),
        DataCell(
          _StandingText(
            '${standing.losses}',
            textColor: cellTextColor,
            fontWeight: fontWeight,
          ),
        ),
        DataCell(
          _StandingText(
            '${standing.legsFor}:${standing.legsAgainst}',
            textColor: cellTextColor,
            fontWeight: fontWeight,
          ),
        ),
        DataCell(
          _StandingText(
            '${standing.legDifference}',
            textColor: cellTextColor,
            fontWeight: fontWeight,
          ),
        ),
        DataCell(
          _StandingText(
            '${standing.points}',
            textColor: cellTextColor,
            fontWeight: fontWeight,
          ),
        ),
        if (widget.group.playType == 'swiss')
          DataCell(
            _StandingText(
              '${SwissEngine.buchholz(widget.group, standing.player, widget.standings)}',
              textColor: cellTextColor,
              fontWeight: fontWeight,
            ),
          ),
      ],
    );
  }
}

class _StandingText extends StatelessWidget {
  const _StandingText(this.text, {this.textColor, this.fontWeight});

  final String text;
  final Color? textColor;
  final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: textColor, fontWeight: fontWeight),
    );
  }
}
