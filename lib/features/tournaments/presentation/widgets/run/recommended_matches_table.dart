import 'dart:math' show max, min;

import 'package:flutter/material.dart';

import '../../../../../shared/theme/tournament_display_palette.dart';
import '../../../domain/tournament_models.dart';

class RecommendedMatchGroup {
  const RecommendedMatchGroup({
    required this.name,
    required this.matches,
    this.isDelayed = false,
    this.playedMatches,
    this.totalMatches,
  });

  final String name;
  final List<GroupMatch> matches;
  final bool isDelayed;
  final int? playedMatches;
  final int? totalMatches;
}

class RecommendedMatchesTable extends StatelessWidget {
  const RecommendedMatchesTable({
    super.key,
    required this.groups,
    required this.prioritizedMatches,
    this.deprioritizedMatches = const {},
    this.onEditResult,
    this.emptyMessage = 'Keine offenen Partien.',
    this.dense = false,
  });

  final List<RecommendedMatchGroup> groups;
  final Set<GroupMatch> prioritizedMatches;
  final Set<GroupMatch> deprioritizedMatches;
  final ValueChanged<GroupMatch>? onEditResult;
  final String emptyMessage;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final visibleGroups = [
      for (final group in groups)
        if (group.matches.any(
              (match) => match.hasPlayers && !match.isResolved,
            ) ||
            group.playedMatches != null && group.totalMatches != null)
          group,
    ];
    if (visibleGroups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(emptyMessage),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final openGroupIndexes = [
          for (var index = 0; index < visibleGroups.length; index++)
            if (visibleGroups[index].matches.any(
              (match) => match.hasPlayers && !match.isResolved,
            ))
              index,
        ];
        final maxColumns = min(
          4,
          max(visibleGroups.length, openGroupIndexes.length * 2),
        );
        final columns = (constraints.maxWidth / 190).floor().clamp(
          1,
          maxColumns,
        );
        final spacing = 8.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        final columnCounts = List<int>.filled(visibleGroups.length, 1);
        for (var index = visibleGroups.length; index < columns; index++) {
          columnCounts[
            openGroupIndexes[(index - visibleGroups.length) %
                openGroupIndexes.length]
          ]++;
        }
        final displayColumns =
            <
              ({
                RecommendedMatchGroup group,
                List<GroupMatch> matches,
                int copyIndex,
              })
            >[];
        for (
          var groupIndex = 0;
          groupIndex < visibleGroups.length;
          groupIndex++
        ) {
          final group = visibleGroups[groupIndex];
          final matches = _orderedMatches(
            group,
            prioritizedMatches,
            deprioritizedMatches,
          );
          final copies = columnCounts[groupIndex];
          for (var copyIndex = 0; copyIndex < copies; copyIndex++) {
            final start = matches.length * copyIndex ~/ copies;
            final end = matches.length * (copyIndex + 1) ~/ copies;
            displayColumns.add((
              group: group,
              matches: matches.sublist(start, end),
              copyIndex: copyIndex,
            ));
          }
        }
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final column in displayColumns)
              SizedBox(
                width: width,
                child: _GroupTable(
                  group: column.group,
                  matches: column.matches,
                  copyIndex: column.copyIndex,
                  prioritizedMatches: prioritizedMatches,
                  onEditResult: onEditResult,
                  dense: dense,
                ),
              ),
          ],
        );
      },
    );
  }
}

List<GroupMatch> _orderedMatches(
  RecommendedMatchGroup group,
  Set<GroupMatch> prioritizedMatches,
  Set<GroupMatch> deprioritizedMatches,
) {
  final matches =
      [
        for (var index = 0; index < group.matches.length; index++)
          (match: group.matches[index], index: index),
      ]..sort((left, right) {
        final leftPriority = prioritizedMatches.contains(left.match);
        final rightPriority = prioritizedMatches.contains(right.match);
        if (leftPriority != rightPriority) return leftPriority ? -1 : 1;
        final leftDeprioritized = deprioritizedMatches.contains(left.match);
        final rightDeprioritized = deprioritizedMatches.contains(right.match);
        if (leftDeprioritized != rightDeprioritized) {
          return leftDeprioritized ? 1 : -1;
        }
        return left.index.compareTo(right.index);
      });
  return [
    for (final item in matches)
      if (item.match.hasPlayers && !item.match.isResolved) item.match,
  ];
}

class _GroupTable extends StatelessWidget {
  const _GroupTable({
    required this.group,
    required this.matches,
    required this.copyIndex,
    required this.prioritizedMatches,
    required this.onEditResult,
    required this.dense,
  });

  final RecommendedMatchGroup group;
  final List<GroupMatch> matches;
  final int copyIndex;
  final Set<GroupMatch> prioritizedMatches;
  final ValueChanged<GroupMatch>? onEditResult;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey(
        'recommended-group-${group.name}'
        '${copyIndex == 0 ? '' : '-$copyIndex'}',
      ),
      decoration: BoxDecoration(
        color: TournamentDisplayPalette.card,
        border: Border.all(color: TournamentDisplayPalette.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    group.name,
                    style: const TextStyle(
                      color: TournamentDisplayPalette.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (group.playedMatches != null && group.totalMatches != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '${group.playedMatches}/${group.totalMatches}',
                      style: const TextStyle(
                        color: TournamentDisplayPalette.mutedText,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (group.isDelayed)
                  const Tooltip(
                    message: 'Diese Gruppe liegt im Spielplan zurück',
                    child: Icon(
                      Icons.priority_high,
                      color: TournamentDisplayPalette.accent,
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
          for (final match in matches) ...[
            const Divider(height: 1, color: TournamentDisplayPalette.border),
            _MatchRow(
              match: match,
              isPrioritized: prioritizedMatches.contains(match),
              onEditResult: onEditResult,
              dense: dense,
            ),
          ],
        ],
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.match,
    required this.isPrioritized,
    required this.onEditResult,
    required this.dense,
  });

  final GroupMatch match;
  final bool isPrioritized;
  final ValueChanged<GroupMatch>? onEditResult;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final playerStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: TournamentDisplayPalette.text,
      fontWeight: FontWeight.w600,
    );

    return Padding(
      key: ValueKey(
        'recommended-match-${match.round}-'
        '${match.homePlayer?.profileId ?? match.homePlayer?.name}-'
        '${match.awayPlayer?.profileId ?? match.awayPlayer?.name}',
      ),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: dense ? 14 : 18,
            child: isPrioritized
                ? const Tooltip(
                    message: 'Priorisierte Partie',
                    child: Icon(
                      Icons.priority_high,
                      size: 18,
                      color: TournamentDisplayPalette.accent,
                    ),
                  )
                : null,
          ),
          Expanded(
            child: Text(
              match.homePlayer!.shortDisplayName,
              style: dense ? playerStyle?.copyWith(fontSize: 12) : playerStyle,
              maxLines: dense ? 1 : 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onEditResult != null)
            IconButton(
              tooltip: 'Ergebnis eintragen',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.edit_outlined, size: 17),
              color: TournamentDisplayPalette.accent,
              onPressed: () => onEditResult!(match),
            ),
          if (onEditResult == null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: dense ? 3 : 8),
              child: Text(
                '-',
                style: playerStyle?.copyWith(
                  color: TournamentDisplayPalette.mutedText,
                ),
              ),
            ),
          Expanded(
            child: Text(
              match.awayPlayer!.shortDisplayName,
              style: dense ? playerStyle?.copyWith(fontSize: 12) : playerStyle,
              maxLines: dense ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
