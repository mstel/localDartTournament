import '../../domain/tournament_models.dart';

/// Dart Swiss: 3/1/0, Buchholz, leg difference, legs won, initial seed.
/// Future rounds contain empty slots and cannot be scheduled before the barrier.
class SwissEngine {
  // Keeping at least half the complete graph available guarantees another
  // perfect matching (an odd field includes a virtual bye opponent).
  static int maximumRounds(int players) => (players + 1) ~/ 2;

  static int buchholz(
    TournamentGroup group,
    TournamentPlayer player,
    List<PlayerStanding> table,
  ) {
    final points = {for (final row in table) row.player: row.points};
    return group.matches
        .where(
          (m) =>
              m.hasPlayers &&
              m.hasResult &&
              !m.isAnnulled &&
              (m.homePlayer == player || m.awayPlayer == player),
        )
        .fold(
          0,
          (sum, m) =>
              sum +
              (points[m.homePlayer == player ? m.awayPlayer : m.homePlayer] ??
                  0),
        );
  }

  static List<GroupMatch> build(List<TournamentPlayer> players, int rounds) {
    if (players.length < 3 ||
        rounds < 1 ||
        rounds > maximumRounds(players.length)) {
      throw ArgumentError(
        'Swiss benötigt mindestens 3 Teilnehmer und höchstens ${maximumRounds(players.length)} Runden.',
      );
    }
    final group = TournamentGroup(
      name: 'Swiss',
      playType: 'swiss',
      players: players,
      matches: [
        for (var r = 1; r <= rounds; r++)
          for (var i = 0; i < (players.length + 1) ~/ 2; i++)
            GroupMatch(round: r, label: 'Swiss · Runde $r'),
      ],
    );
    advance(group);
    return group.matches;
  }

  static List<PlayerStanding> standings(
    TournamentGroup group, {
    int? beforeRound,
  }) {
    final rows = {for (final p in group.players) p: PlayerStanding(p)};
    final games = group.matches.where(
      (m) => beforeRound == null || m.round < beforeRound,
    );
    for (final m in games) {
      if (m.isAnnulled || m.withdrawalIgnored) continue;
      if (!m.hasPlayers) {
        if (m.allowsBye && m.winner != null) rows[m.winner]?.points += 3;
        continue;
      }
      if (!m.hasResult) continue;
      for (final home in [true, false]) {
        final p = home ? m.homePlayer! : m.awayPlayer!;
        final row = rows[p]!;
        row.played++;
        row.legsFor += home ? m.homeLegs! : m.awayLegs!;
        row.legsAgainst += home ? m.awayLegs! : m.homeLegs!;
        if (m.winner == null) {
          row.draws++;
          row.points++;
        } else if (m.winner == p) {
          row.wins++;
          row.points += 3;
        } else {
          row.losses++;
        }
      }
    }
    int buchholz(TournamentPlayer p) => games
        .where(
          (m) =>
              m.countsForStatistics &&
              !m.isAnnulled &&
              (m.homePlayer == p || m.awayPlayer == p),
        )
        .fold(
          0,
          (sum, m) =>
              sum +
              (rows[m.homePlayer == p ? m.awayPlayer : m.homePlayer]?.points ??
                  0),
        );
    final sorted = rows.values.toList()
      ..sort((a, b) {
        for (final cmp in [
          b.points.compareTo(a.points),
          buchholz(b.player).compareTo(buchholz(a.player)),
          b.legDifference.compareTo(a.legDifference),
          b.legsFor.compareTo(a.legsFor),
        ]) {
          if (cmp != 0) return cmp;
        }
        return group.players
            .indexOf(a.player)
            .compareTo(group.players.indexOf(b.player));
      });
    return sorted;
  }

  static void advance(TournamentGroup group) {
    final rounds = group.matches.map((m) => m.round).toSet().toList()..sort();
    for (final r in rounds) {
      final slots = group.matches.where((m) => m.round == r).toList();
      if (slots.every((m) => m.homePlayer != null)) {
        if (slots.any((m) => !m.isResolved)) return;
        continue;
      }
      final previous = group.matches.where((m) => m.round < r).toList();
      if (previous.any((m) => !m.isResolved)) return;
      final table = standings(group, beforeRound: r);
      final ranked = table.map((s) => s.player).toList();
      final points = {for (final s in table) s.player: s.points};
      bool met(TournamentPlayer a, TournamentPlayer b) => previous.any(
        (m) =>
            (m.homePlayer == a && m.awayPlayer == b) ||
            (m.homePlayer == b && m.awayPlayer == a),
      );
      final byes = previous
          .where((m) => m.allowsBye && !m.hasPlayers)
          .map((m) => m.winner)
          .toSet();
      var attempts = 0;
      List<(TournamentPlayer, TournamentPlayer)>? pair(
        List<TournamentPlayer> remaining,
      ) {
        if (remaining.isEmpty) return [];
        if (++attempts > 100000) return null;
        final a = remaining.first;
        final opponents = remaining.skip(1).where((b) => !met(a, b)).toList()
          ..sort((b, c) {
            final cmp = (points[a]! - points[b]!).abs().compareTo(
              (points[a]! - points[c]!).abs(),
            );
            return cmp != 0
                ? cmp
                : ranked.indexOf(b).compareTo(ranked.indexOf(c));
          });
        for (final b in opponents) {
          final rest = pair(remaining.where((p) => p != a && p != b).toList());
          if (rest != null) return [(a, b), ...rest];
        }
        return null;
      }

      List<(TournamentPlayer, TournamentPlayer)>? pairs;
      TournamentPlayer? bye;
      for (final candidate in <TournamentPlayer?>[
        if (ranked.length.isEven)
          null
        else
          ...ranked.reversed.where((p) => !byes.contains(p)),
      ]) {
        attempts = 0;
        pairs = pair(ranked.where((p) => p != candidate).toList());
        if (pairs != null) {
          bye = candidate;
          break;
        }
      }
      if (pairs == null) {
        throw StateError('Swiss: Keine Paarung ohne Wiederholung möglich.');
      }
      for (var i = 0; i < pairs.length; i++) {
        slots[i].homePlayer = pairs[i].$1;
        slots[i].awayPlayer = pairs[i].$2;
      }
      if (bye != null) {
        final index = group.matches.indexOf(slots.last);
        group.matches[index] = GroupMatch(
          round: r,
          label: 'Swiss · Runde $r · Freilos',
          homePlayer: bye,
          allowsBye: true,
        );
      }
      return;
    }
  }

  /// An edited earlier result invalidates every dependent later pairing.
  static void invalidateAfter(TournamentGroup group, int round) {
    for (var i = 0; i < group.matches.length; i++) {
      final old = group.matches[i];
      if (old.round > round) {
        group.matches[i] = GroupMatch(
          round: old.round,
          label: 'Swiss · Runde ${old.round}',
        );
      }
    }
  }
}
