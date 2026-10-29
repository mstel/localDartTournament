import 'package:flutter/material.dart';

import '../../../../../shared/theme/tournament_display_palette.dart';
import '../../../../rankings/application/tournament_match_elo_service.dart';
import '../../../application/player_withdrawal_service.dart';
import '../../../domain/engines/group_standings_engine.dart';
import '../../../domain/engines/qualification_certainty.dart';
import '../../../domain/tournament_models.dart';
import '../../../../statistics/domain/best_performance.dart';

class RecentMatchResultCard extends StatelessWidget {
  const RecentMatchResultCard({
    super.key,
    required this.tournament,
    required this.match,
    required this.eloChanges,
    this.eloError,
  });

  final CreatedTournament tournament;
  final GroupMatch match;
  final List<TournamentMatchEloChange> eloChanges;
  final String? eloError;

  @override
  Widget build(BuildContext context) => Container(
    key:
        key ??
        ValueKey(
          'recent-result-${match.round}-'
          '${match.homePlayer?.profileId ?? match.homePlayer?.name}-'
          '${match.awayPlayer?.profileId ?? match.awayPlayer?.name}',
        ),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: TournamentDisplayPalette.card,
      border: Border.all(color: TournamentDisplayPalette.border.withAlpha(150)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _RecentPlayerLabel(
                tournament: tournament,
                match: match,
                player: match.homePlayer,
                textAlign: TextAlign.end,
              ),
            ),
            const SizedBox(width: 6),
            DecoratedBox(
              decoration: BoxDecoration(
                color: TournamentDisplayPalette.cardEmphasis,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: TournamentDisplayPalette.border),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Text(
                  '${match.homeScore ?? 0} : ${match.awayScore ?? 0}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: TournamentDisplayPalette.accent,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _RecentPlayerLabel(
                tournament: tournament,
                match: match,
                player: match.awayPlayer,
                textAlign: TextAlign.start,
              ),
            ),
          ],
        ),
        if (eloError != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              eloError!,
              style: const TextStyle(color: Color(0xFFFFCC80), fontSize: 11),
            ),
          )
        else if (eloChanges.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 5,
              runSpacing: 3,
              children: [
                for (final change in eloChanges)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: TournamentDisplayPalette.cardEmphasis,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: TournamentDisplayPalette.border.withAlpha(150),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${change.rankingName}: '),
                            _eloDeltaSpan(change.homeDelta),
                            const TextSpan(text: ' / '),
                            _eloDeltaSpan(change.awayDelta),
                            const TextSpan(text: ' Elo'),
                          ],
                        ),
                        style: const TextStyle(
                          color: TournamentDisplayPalette.mutedText,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (match.bestPerformances.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 3,
              children: [
                for (final performance in match.bestPerformances)
                  _RecentPerformanceBadge(performance: performance),
              ],
            ),
          ),
      ],
    ),
  );
}

class _RecentPlayerLabel extends StatelessWidget {
  const _RecentPlayerLabel({
    required this.tournament,
    required this.match,
    required this.player,
    required this.textAlign,
  });

  final CreatedTournament tournament;
  final GroupMatch match;
  final TournamentPlayer? player;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    if (player == null) {
      return const Text(
        '?',
        style: TextStyle(color: Colors.white70),
        textAlign: TextAlign.center,
      );
    }

    final isWinner = match.winner == player;
    final isLoser = match.loser == player;
    final status = _recentPlayerStatus(tournament, match, player!);
    final statusColor = status == 'Ausgeschieden'
        ? const Color(0xFFEF9A9A)
        : const Color(0xFF86EFAC);
    final alignment = textAlign == TextAlign.end
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        Text(
          player!.shortDisplayName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isWinner
                ? const Color(0xFF86EFAC)
                : isLoser
                ? const Color(0xFFEF9A9A)
                : Colors.white,
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
        ),
        if (status != null)
          Text(
            status,
            style: TextStyle(
              color: statusColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
          ),
      ],
    );
  }
}

String? _recentPlayerStatus(
  CreatedTournament tournament,
  GroupMatch match,
  TournamentPlayer player,
) {
  if (PlayerWithdrawalService.policy(tournament, player) != null) {
    return 'Ausgeschieden';
  }
  for (final stage in tournament.runStages) {
    if (stage is GroupTournamentRunStage) {
      final groupIndex = stage.groups.indexWhere(
        (group) => group.matches.contains(match),
      );
      if (groupIndex < 0) continue;
      final group = stage.groups[groupIndex];
      final standings = GroupStandingsEngine().calculate(
        group,
        stage.tieBreakers,
        tournament: tournament,
      );
      final place = standings.indexWhere(
        (standing) => standing.player == player,
      );
      if (place < 0) return null;
      final plan = stage.qualificationPlan;
      final fixedPlaces = plan == null
          ? 2
          : groupIndex < plan.fixedByGroup.length
          ? plan.fixedByGroup[groupIndex]
          : plan.fixedPerGroup;
      if (const QualificationCertainty().isCertain(
        standing: standings[place],
        place: place + 1,
        fixedPlaces: fixedPlaces,
        standings: standings,
        matches: group.matches,
        tieBreakers: stage.tieBreakers,
      )) {
        return 'Gesetzt';
      }
      final groupComplete = group.matches
          .where((item) => item.hasPlayers)
          .every((item) => item.isResolved);
      final eligibleForExtra =
          plan != null &&
          plan.extraCount > 0 &&
          plan.extraGroups.contains(groupIndex + 1) &&
          place + 1 == plan.extraRank;
      if (groupComplete && place + 1 > fixedPlaces && !eligibleForExtra) {
        return 'Ausgeschieden';
      }
      return null;
    }
    if (stage is KnockoutTournamentRunStage && stage.matches.contains(match)) {
      final playerKey = PlayerWithdrawalService.key(player);
      final losses = stage.matches
          .where(
            (item) =>
                item.hasResult &&
                item.loser != null &&
                PlayerWithdrawalService.key(item.loser!) == playerKey,
          )
          .length;
      if (losses >= stage.eliminationLossLimit) return 'Ausgeschieden';
      return null;
    }
  }
  return null;
}

class _RecentPerformanceBadge extends StatelessWidget {
  const _RecentPerformanceBadge({required this.performance});

  final BestPerformance performance;

  @override
  Widget build(BuildContext context) {
    final label = switch (performance.type) {
      BestPerformanceType.score170 => '170+',
      BestPerformanceType.score180 => '180er',
      BestPerformanceType.highFinish =>
        'HF ${performance.value?.toString() ?? ''}',
      BestPerformanceType.shortLeg =>
        'SL ${performance.value?.toString() ?? ''}',
    };
    final detail = [
      performance.playerName,
      performance.label,
      if (performance.value != null) '${performance.value}',
    ].where((part) => part.isNotEmpty).join(' · ');
    return Tooltip(
      message: detail,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TournamentDisplayPalette.cardEmphasis,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: TournamentDisplayPalette.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            label.trim(),
            style: const TextStyle(
              color: Color(0xFF70E0BA),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

TextSpan _eloDeltaSpan(int? delta) {
  final color = delta == null || delta == 0
      ? const Color(0xFFB0BEC5)
      : delta > 0
      ? const Color(0xFF86EFAC)
      : const Color(0xFFEF9A9A);
  return TextSpan(
    text: delta == null
        ? '–'
        : delta > 0
        ? '+$delta'
        : '$delta',
    style: TextStyle(color: color),
  );
}
