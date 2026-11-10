import '../../statistics/domain/best_performance.dart';
import '../domain/player_withdrawal.dart';
import '../domain/tournament_models.dart';
import 'order_of_play/order_of_play_controller.dart';

class PlayerWithdrawalService {
  const PlayerWithdrawalService();
  static String key(TournamentPlayer p) => p.profileId ?? p.name;
  static PlayerWithdrawal? policy(CreatedTournament t, TournamentPlayer p) =>
      t.withdrawals.where((w) => w.playerKey == key(p)).firstOrNull;

  bool canRestore(PlayerWithdrawal withdrawal, int activeStageIndex) =>
      withdrawal.stageIndex == activeStageIndex;

  bool remove(
    CreatedTournament tournament,
    PlayerWithdrawal withdrawal, {
    required bool annulResults,
  }) {
    if (!tournament.withdrawals.remove(withdrawal)) return false;
    if (annulResults) {
      reconcile(tournament);
      return true;
    }

    final timestamp = withdrawal.createdAt.toUtc().toIso8601String();
    for (final entry in const OrderOfPlayController().entries(tournament)) {
      final match = entry.match;
      if (match.withdrawalSignature?.split('|').contains(timestamp) != true) {
        continue;
      }
      match
        ..withdrawalSignature = null
        ..withdrawalHadResult = false
        ..withdrawalSnapshot = null;
    }
    return true;
  }

  /// Idempotent: generated later-round matches receive the same durable rule.
  bool reconcile(CreatedTournament t) {
    var changed = false;
    for (final entry in const OrderOfPlayController().entries(t)) {
      final m = entry.match;
      if (!m.hasPlayers) continue;
      final home = policy(t, m.homePlayer!);
      final away = policy(t, m.awayPlayer!);
      final signature =
          '${key(m.homePlayer!)}|${key(m.awayPlayer!)}|${home?.createdAt.toUtc().toIso8601String()}|${away?.createdAt.toUtc().toIso8601String()}';
      if (m.withdrawalSignature != null && m.withdrawalSignature != signature) {
        final snapshot = m.withdrawalSnapshot;
        if (snapshot != null) {
          _restoreMatch(m, snapshot);
        } else if (!m.withdrawalHadResult) {
          m.homeLegs = null;
          m.awayLegs = null;
          m.homeSets = null;
          m.awaySets = null;
          m.isAnnulled = false;
        }
        m.withdrawalSignature = null;
        m.withdrawalIgnored = false;
        m.withdrawalHadResult = false;
        m.withdrawalSnapshot = null;
        changed = true;
      }
      if (home == null && away == null) continue;
      if (m.withdrawalSignature == signature) continue;
      final rules = [?home, ?away];
      if (m.hasResult && !rules.any((r) => r.retroactive)) continue;
      final ignore = rules.any((r) => r.ignore);
      final wasPlayed = m.hasResult;
      m.withdrawalSignature = signature;
      m.withdrawalIgnored = ignore;
      m.withdrawalHadResult = wasPlayed;
      m.withdrawalSnapshot = _snapshotMatch(m);
      // Keep actual past results for optional opponent Elo, but exclude them
      // from the tournament table when the director selected ignore-all.
      if (!(ignore && wasPlayed)) {
        final format = t.stages[entry.stageIndex].gameFormat;
        final legs = format.bestOfLegs ~/ 2 + 1;
        final sets = format.bestOfSets ~/ 2 + 1;
        final homeWins = home == null;
        m.homeLegs = homeWins ? legs * (format.bestOfSets > 1 ? sets : 1) : 0;
        m.awayLegs = away == null
            ? legs * (format.bestOfSets > 1 ? sets : 1)
            : 0;
        m.homeSets = format.bestOfSets > 1 ? (homeWins ? sets : 0) : null;
        m.awaySets = format.bestOfSets > 1 ? (away == null ? sets : 0) : null;
        m.isAnnulled = home != null && away != null;
        m.finishedAt = rules
            .map((r) => r.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
      }
      m.boardNumber = null;
      m.startedAt = null;
      m.startedPlayers = null;
      changed = true;
    }
    return changed;
  }

  Map<String, dynamic> _snapshotMatch(GroupMatch match) => {
    'homeLegs': match.homeLegs,
    'awayLegs': match.awayLegs,
    'homeSets': match.homeSets,
    'awaySets': match.awaySets,
    'isAnnulled': match.isAnnulled,
    'boardNumber': match.boardNumber,
    'startedAt': match.startedAt?.toUtc().toIso8601String(),
    'finishedAt': match.finishedAt?.toUtc().toIso8601String(),
    'startedPlayers': match.startedPlayers,
    'scratchedPlayer': match.scratchedPlayer?.toJson(),
    'scratchEligiblePlayers': match.scratchEligiblePlayers
        .map((player) => player.toJson())
        .toList(),
    'bestPerformances': match.bestPerformances
        .map((performance) => performance.toJson())
        .toList(),
    'achievementNotifications': match.achievementNotifications
        .map((notice) => notice.toJson())
        .toList(),
    'kratzerBonusLives': match.kratzerBonusLives
        .map((bonus) => bonus.toJson())
        .toList(),
  };

  void _restoreMatch(GroupMatch match, Map<String, dynamic> snapshot) {
    match
      ..homeLegs = snapshot['homeLegs'] as int?
      ..awayLegs = snapshot['awayLegs'] as int?
      ..homeSets = snapshot['homeSets'] as int?
      ..awaySets = snapshot['awaySets'] as int?
      ..isAnnulled = snapshot['isAnnulled'] as bool? ?? false
      ..boardNumber = snapshot['boardNumber'] as int?
      ..startedAt = _date(snapshot['startedAt'])
      ..finishedAt = _date(snapshot['finishedAt'])
      ..startedPlayers = snapshot['startedPlayers'] as String?
      ..scratchedPlayer = _player(snapshot['scratchedPlayer'])
      ..scratchEligiblePlayers = _players(snapshot['scratchEligiblePlayers'])
      ..bestPerformances = _objects(
        snapshot['bestPerformances'],
      ).map(BestPerformance.fromJson).toList()
      ..achievementNotifications = _objects(
        snapshot['achievementNotifications'],
      ).map(TournamentAchievementNotice.fromJson).toList()
      ..kratzerBonusLives = _objects(
        snapshot['kratzerBonusLives'],
      ).map(KratzerBonusLife.fromJson).toList();
  }

  DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  TournamentPlayer? _player(Object? value) => value is Map
      ? TournamentPlayer.fromJson(Map<String, dynamic>.from(value))
      : null;

  List<TournamentPlayer> _players(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map(
              (player) =>
                  TournamentPlayer.fromJson(Map<String, dynamic>.from(player)),
            )
            .toList()
      : [];

  List<Map<String, dynamic>> _objects(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
      : [];
}
