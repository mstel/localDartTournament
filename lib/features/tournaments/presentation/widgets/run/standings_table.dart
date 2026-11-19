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
    this.showDraws = true,
  });

  final List<PlayerStanding> standings;
  final TournamentGroup group;
  final int groupNumber;
  final QualificationPlan? qualificationPlan;
  final List<String> tieBreakers;
  final ValueChanged<TournamentPlayer>? onPlayerTap;
  final bool compact;
  final bool showDraws;

  @override
  State<StandingsTable> createState() => _StandingsTableState();
}

class _StandingsTableState extends State<StandingsTable> {
  final _horizontalController = ScrollController();
  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  QualificationPlaceStatus? _qualificationStatus(int place) =>
      widget.qualificationPlan?.statusFor(widget.groupNumber, place);

  bool _isFixedQualificationPlace(int place) =>
      _qualificationStatus(place) == QualificationPlaceStatus.fixed;

  bool _isBestOfCandidatePlace(int place) =>
      _qualificationStatus(place) == QualificationPlaceStatus.comparison;

  void _sortBy(int columnIndex) {
    setState(() {
      if (_sortColumnIndex != columnIndex) {
        _sortColumnIndex = columnIndex;
        _sortAscending = columnIndex == 1;
      } else if (_sortAscending == (columnIndex == 1)) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumnIndex = null;
        _sortAscending = true;
      }
    });
  }

  List<PlayerStanding> _sortedStandings() {
    final standings = [...widget.standings];
    final column = _sortColumnIndex;
    if (column == null) return standings;
    int compare(PlayerStanding a, PlayerStanding b) => switch (column) {
      1 => a.player.name.toLowerCase().compareTo(b.player.name.toLowerCase()),
      2 => a.played.compareTo(b.played),
      3 => a.wins.compareTo(b.wins),
      4 when widget.showDraws => a.draws.compareTo(b.draws),
      _ => 0,
    };
    standings.sort((a, b) {
      final result = compare(a, b);
      return result == 0 || _sortAscending ? result : -result;
    });
    return standings;
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
    final colorScheme = Theme.of(context).colorScheme;
    final isDarkMode = colorScheme.brightness == Brightness.dark;
    final sureColor = isDarkMode
        ? const Color(0xFF144D34)
        : const Color(0xFF0B6B45);
    final possibleColor = isDarkMode
        ? const Color(0xFF163828)
        : const Color(0xFFD6F5E3);
    final bestOfColor = colorScheme.primaryContainer;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount =
            8 +
            (widget.showDraws ? 1 : 0) +
            (widget.group.playType == 'swiss' ? 1 : 0);
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
        final standings = _sortedStandings();
        return Scrollbar(
          controller: _horizontalController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            child: DataTable(
              sortColumnIndex: _sortColumnIndex,
              sortAscending: _sortAscending,
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
                DataColumn(
                  label: const Text('Teilnehmer'),
                  onSort: (_, _) => _sortBy(1),
                ),
                DataColumn(
                  numeric: true,
                  label: const Text('Sp'),
                  onSort: (_, _) => _sortBy(2),
                ),
                DataColumn(
                  numeric: true,
                  label: const Text('S'),
                  onSort: (_, _) => _sortBy(3),
                ),
                if (widget.showDraws)
                  DataColumn(
                    numeric: true,
                    label: const Text('U'),
                    onSort: (_, _) => _sortBy(4),
                  ),
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
                for (var index = 0; index < standings.length; index++)
                  _buildRow(
                    context: context,
                    index: index,
                    standings: standings,
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
    required List<PlayerStanding> standings,
    required bool isDarkMode,
    required Color sureColor,
    required Color possibleColor,
    required Color bestOfColor,
  }) {
    final place = index + 1;
    final standing = standings[index];
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
      cellTextColor = Theme.of(context).colorScheme.onPrimaryContainer;
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
          Tooltip(
            message: switch (_qualificationStatus(place)) {
              QualificationPlaceStatus.fixed => 'Kommt sicher weiter',
              QualificationPlaceStatus.comparison =>
                'Vergleich um Zusatzplatz',
              _ => 'Scheidet nach aktuellem Stand aus',
            },
            child: _StandingText(
              widget.compact
                  ? standing.player.shortDisplayName
                  : standing.player.name,
              textColor: cellTextColor,
              fontWeight: fontWeight,
            ),
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
        if (widget.showDraws)
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
