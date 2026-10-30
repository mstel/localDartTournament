import 'package:flutter/material.dart';

import '../../../../../shared/theme/tournament_display_palette.dart';
import '../../../../rankings/application/tournament_match_elo_service.dart';
import '../../../application/player_withdrawal_service.dart';
import '../../../domain/engines/group_standings_engine.dart';
import '../../../domain/engines/qualification_certainty.dart';
import '../../../domain/tournament_models.dart';
import '../../../../statistics/domain/best_performance.dart';

class RecentMatchResultLogEntry extends StatelessWidget {
  const RecentMatchResultLogEntry({
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
  Widget build(BuildContext context) {
    final homePlayer = match.homePlayer;
    final awayPlayer = match.awayPlayer;
    final homeIsWinner = homePlayer != null && match.winner == homePlayer;
    final awayIsWinner = awayPlayer != null && match.winner == awayPlayer;
    final homeColor = homeIsWinner
        ? const Color(0xFF4ED9A4)
        : homePlayer != null && match.loser == homePlayer
        ? const Color(0xFFFF7777)
        : TournamentDisplayPalette.text;
    final awayColor = awayIsWinner
        ? const Color(0xFF4ED9A4)
        : awayPlayer != null && match.loser == awayPlayer
        ? const Color(0xFFFF7777)
        : TournamentDisplayPalette.text;
    final homeStatus = homePlayer == null
        ? null
        : _recentPlayerStatus(tournament, match, homePlayer);
    final awayStatus = awayPlayer == null
        ? null
        : _recentPlayerStatus(tournament, match, awayPlayer);
    final time = match.finishedAt?.toLocal();
    final resultDescription = homeIsWinner
        ? ' besiegte '
        : awayIsWinner
        ? ' unterlag '
        : ' spielte gegen ';

    return Padding(
      key:
          key ??
          ValueKey(
            'recent-result-${match.round}-'
            '${homePlayer?.profileId ?? homePlayer?.name}-'
            '${awayPlayer?.profileId ?? awayPlayer?.name}',
          ),
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: homePlayer?.name ?? '?',
                        style: TextStyle(
                          color: homeColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (homeStatus != null)
                        TextSpan(
                          text: ' ($homeStatus)',
                          style: const TextStyle(
                            color: TournamentDisplayPalette.mutedText,
                            fontSize: 10,
                          ),
                        ),
                      TextSpan(text: resultDescription),
                      TextSpan(
                        text: awayPlayer?.name ?? '?',
                        style: TextStyle(
                          color: awayColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (awayStatus != null)
                        TextSpan(
                          text: ' ($awayStatus)',
                          style: const TextStyle(
                            color: TournamentDisplayPalette.mutedText,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF123D2D),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: Text(
                    match.isAnnulled
                        ? 'annulliert'
                        : '${match.homeScore ?? 0}:${match.awayScore ?? 0}',
                    style: const TextStyle(
                      color: Color(0xFF4ED9A4),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (time != null) ...[
                const SizedBox(width: 10),
                Text(
                  '${time.hour.toString().padLeft(2, '0')}:'
                  '${time.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: TournamentDisplayPalette.mutedText,
                    fontSize: 11,
                  ),
                ),
              ],
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
          else
            for (final change in eloChanges)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: _eloRatingText(
                        change.homeDelta,
                        change.homeRatingBefore,
                        change.homeRatingAfter,
                        TextAlign.start,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${change.rankingName} · ${tournament.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: TournamentDisplayPalette.mutedText,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _eloRatingText(
                        change.awayDelta,
                        change.awayRatingBefore,
                        change.awayRatingAfter,
                        TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
          if (match.bestPerformances.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Wrap(
                spacing: 4,
                runSpacing: 2,
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

Widget _eloRatingText(int? delta, int? before, int? after, TextAlign align) {
  final color = delta == null || delta == 0
      ? const Color(0xFFB0BEC5)
      : delta > 0
      ? const Color(0xFF4ED9A4)
      : const Color(0xFFFF7777);
  final change = delta == null
      ? ''
      : delta > 0
      ? '+$delta'
      : '$delta';
  final rating = before != null && after != null ? ' ($before → $after)' : '';
  return Text(
    '$change Elo$rating',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: align,
    style: TextStyle(color: color, fontSize: 11),
  );
}
