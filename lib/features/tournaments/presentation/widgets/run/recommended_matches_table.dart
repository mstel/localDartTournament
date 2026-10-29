import 'package:flutter/material.dart';

import '../../../../../shared/theme/tournament_display_palette.dart';
import '../../../domain/tournament_models.dart';

class RecommendedMatchGroup {
  const RecommendedMatchGroup({
    required this.name,
    required this.matches,
    this.isDelayed = false,
  });

  final String name;
  final List<GroupMatch> matches;
  final bool isDelayed;
}

class RecommendedMatchesTable extends StatelessWidget {
  const RecommendedMatchesTable({
    super.key,
    required this.groups,
    required this.prioritizedMatches,
    this.onEditResult,
    this.emptyMessage = 'Keine offenen Partien.',
  });

  final List<RecommendedMatchGroup> groups;
  final Set<GroupMatch> prioritizedMatches;
  final ValueChanged<GroupMatch>? onEditResult;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final visibleGroups = [
      for (final group in groups)
        if (group.matches.any((match) => match.hasPlayers && !match.isResolved))
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
        final columns = (constraints.maxWidth / 280).floor().clamp(1, 4);
        final spacing = 8.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final group in visibleGroups)
              SizedBox(
                width: width,
                child: _GroupTable(
                  group: group,
                  prioritizedMatches: prioritizedMatches,
                  onEditResult: onEditResult,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GroupTable extends StatelessWidget {
  const _GroupTable({
    required this.group,
    required this.prioritizedMatches,
    required this.onEditResult,
  });

  final RecommendedMatchGroup group;
  final Set<GroupMatch> prioritizedMatches;
  final ValueChanged<GroupMatch>? onEditResult;

  @override
  Widget build(BuildContext context) {
    final matches =
        [
          for (var index = 0; index < group.matches.length; index++)
            (match: group.matches[index], index: index),
        ]..sort((left, right) {
          final leftPriority = prioritizedMatches.contains(left.match);
          final rightPriority = prioritizedMatches.contains(right.match);
          if (leftPriority != rightPriority) return leftPriority ? -1 : 1;
          return left.index.compareTo(right.index);
        });

    return Container(
      key: ValueKey('recommended-group-${group.name}'),
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
          for (final item in matches)
            if (item.match.hasPlayers && !item.match.isResolved) ...[
              const Divider(height: 1, color: TournamentDisplayPalette.border),
              _MatchRow(
                match: item.match,
                isPrioritized: prioritizedMatches.contains(item.match),
                onEditResult: onEditResult,
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
  });

  final GroupMatch match;
  final bool isPrioritized;
  final ValueChanged<GroupMatch>? onEditResult;

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
            width: 18,
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
              style: playerStyle,
              maxLines: 2,
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
          Expanded(
            child: Text(
              match.awayPlayer!.shortDisplayName,
              style: playerStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
