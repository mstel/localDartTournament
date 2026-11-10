import '../tournament_models.dart';

typedef PlacementSource = ({GroupMatch match, bool loser});
typedef PlacementInputs = ({PlacementSource home, PlacementSource away});

/// Selective classification trees for each cohort eliminated from the main KO.
/// Only paths required to determine the selected pairs of places are built.
class PlacementEngine {
  static Map<GroupMatch, PlacementInputs> plan(
    List<List<GroupMatch>> rounds,
    Iterable<int> places, {
    List<GroupMatch> existing = const [],
  }) {
    final selected = places.toSet();
    final stored = {for (final m in existing) m.placementKey: m};
    final edges = <GroupMatch, PlacementInputs>{};
    void branch(
      List<PlacementSource> inputs,
      int start,
      String key,
      int depth,
    ) => _branch(inputs, start, key, depth, selected, stored, edges);
    for (var i = 0; i < rounds.length; i++) {
      final round = rounds[i];
      if (round.length >= 2) {
        branch(
          round.map((m) => (match: m, loser: true)).toList(),
          round.length + 1,
          'R$i',
          0,
        );
      }
    }
    return edges;
  }

  static Map<GroupMatch, PlacementInputs> planDoubleElimination(
    List<List<GroupMatch>> rounds,
    Iterable<int> places, {
    List<GroupMatch> existing = const [],
  }) {
    final selected = places.toSet();
    final stored = {for (final match in existing) match.placementKey: match};
    final edges = <GroupMatch, PlacementInputs>{};
    final matchGroups = <int, List<GroupMatch>>{};
    for (final match in rounds.expand((round) => round)) {
      final label = match.label;
      if (label == null || !label.startsWith('Losers Runde ')) continue;
      final number = int.tryParse(label.substring('Losers Runde '.length));
      if (number != null) matchGroups.putIfAbsent(number, () => []).add(match);
    }
    final roundsByNumber = matchGroups.keys.toList()..sort();
    for (var index = 0; index < roundsByNumber.length; index++) {
      final number = roundsByNumber[index];
      final cohort = matchGroups[number]!;
      final laterEliminations = roundsByNumber
          .skip(index + 1)
          .fold<int>(0, (total, later) => total + matchGroups[later]!.length);
      final firstPlace = 3 + laterEliminations;
      _branch(
        cohort.map((match) => (match: match, loser: true)).toList(),
        firstPlace,
        'double/L$number',
        0,
        selected,
        stored,
        edges,
      );
    }
    return edges;
  }

  static Map<GroupMatch, PlacementInputs> planTripleElimination(
    List<List<GroupMatch>> rounds,
    Iterable<int> places, {
    required int lossLimit,
    List<GroupMatch> existing = const [],
  }) {
    if (lossLimit < 3) {
      throw ArgumentError.value(lossLimit, 'lossLimit');
    }
    final selected = places.toSet();
    final stored = {for (final match in existing) match.placementKey: match};
    final edges = <GroupMatch, PlacementInputs>{};
    final eliminationPrefix = '${lossLimit - 1} Niederlagen Runde ';
    final cohorts = <({int round, List<GroupMatch> matches})>[];
    for (var index = 0; index < rounds.length; index++) {
      final matches = rounds[index]
          .where((match) => match.label?.startsWith(eliminationPrefix) ?? false)
          .toList();
      if (matches.isNotEmpty) cohorts.add((round: index, matches: matches));
    }
    for (var index = 0; index < cohorts.length; index++) {
      final cohort = cohorts[index];
      final laterEliminations = cohorts
          .skip(index + 1)
          .fold<int>(0, (total, later) => total + later.matches.length);
      _branch(
        cohort.matches.map((match) => (match: match, loser: true)).toList(),
        3 + laterEliminations,
        'triple/L$lossLimit/R${cohort.round}',
        0,
        selected,
        stored,
        edges,
      );
    }
    return edges;
  }

  static List<GroupMatch> build(
    List<List<GroupMatch>> rounds,
    Iterable<int> places,
  ) => plan(rounds, places).keys.toList();

  static List<GroupMatch> buildDoubleElimination(
    List<List<GroupMatch>> rounds,
    Iterable<int> places,
  ) => planDoubleElimination(rounds, places).keys.toList();

  static List<GroupMatch> buildTripleElimination(
    List<List<GroupMatch>> rounds,
    Iterable<int> places, {
    required int lossLimit,
  }) =>
      planTripleElimination(rounds, places, lossLimit: lossLimit).keys.toList();

  static Map<GroupMatch, PlacementInputs> sources(
    List<List<GroupMatch>> rounds,
    List<GroupMatch> matches,
  ) => plan(
    rounds,
    matches.map((m) => m.placementRank).whereType<int>(),
    existing: matches,
  );

  static Map<GroupMatch, PlacementInputs> doubleEliminationSources(
    List<List<GroupMatch>> rounds,
    List<GroupMatch> matches,
  ) => planDoubleElimination(
    rounds,
    matches.map((match) => match.placementRank).whereType<int>(),
    existing: matches,
  );

  static Map<GroupMatch, PlacementInputs> tripleEliminationSources(
    List<List<GroupMatch>> rounds,
    List<GroupMatch> matches, {
    required int lossLimit,
  }) => planTripleElimination(
    rounds,
    matches.map((match) => match.placementRank).whereType<int>(),
    lossLimit: lossLimit,
    existing: matches,
  );

  static void advance(List<List<GroupMatch>> rounds, List<GroupMatch> matches) {
    _advance(sources(rounds, matches));
  }

  static void advanceDoubleElimination(
    List<List<GroupMatch>> rounds,
    List<GroupMatch> matches,
  ) {
    _advance(doubleEliminationSources(rounds, matches));
  }

  static void advanceTripleElimination(
    List<List<GroupMatch>> rounds,
    List<GroupMatch> matches, {
    required int lossLimit,
  }) {
    _advance(tripleEliminationSources(rounds, matches, lossLimit: lossLimit));
  }

  static void _advance(Map<GroupMatch, PlacementInputs> sources) {
    final ready = <GroupMatch, bool>{};
    for (final e in sources.entries) {
      bool known(PlacementSource s) => ready[s.match] ?? s.match.isResolved;
      TournamentPlayer? player(PlacementSource s) =>
          s.loser ? s.match.loser : s.match.winner;
      final inputsReady = known(e.value.home) && known(e.value.away);
      final home = inputsReady ? player(e.value.home) : null;
      final away = inputsReady ? player(e.value.away) : null;
      final m = e.key;
      if (m.homePlayer != home || m.awayPlayer != away) {
        m.homeLegs = m.awayLegs = m.homeSets = m.awaySets = null;
        m.isAnnulled = false;
        m.boardNumber = null;
        m.startedAt = m.finishedAt = null;
        m.startedPlayers = null;
      }
      m.homePlayer = home;
      m.awayPlayer = away;
      ready[m] = inputsReady && (m.isResolved || !m.hasPlayers);
    }
  }

  static void _branch(
    List<PlacementSource> inputs,
    int start,
    String key,
    int depth,
    Set<int> selected,
    Map<String?, GroupMatch> stored,
    Map<GroupMatch, PlacementInputs> edges,
  ) {
    if (inputs.length < 2 ||
        !selected.any(
          (place) => place >= start && place < start + inputs.length,
        )) {
      return;
    }
    final matches = <GroupMatch>[];
    for (var i = 0; i < inputs.length; i += 2) {
      final id = '$key/$i';
      final terminal = inputs.length == 2;
      final match =
          stored[id] ??
          GroupMatch(
            round: 100 + depth,
            allowsBye: true,
            placementKey: id,
            placementRank: terminal ? start : null,
            label: terminal
                ? 'Spiel um Platz $start'
                : 'Plätze $start–${start + inputs.length - 1} · Spiel ${i ~/ 2 + 1}',
          );
      edges[match] = (home: inputs[i], away: inputs[i + 1]);
      matches.add(match);
    }
    if (inputs.length > 2) {
      _branch(
        matches.map((match) => (match: match, loser: false)).toList(),
        start,
        '$key/W',
        depth + 1,
        selected,
        stored,
        edges,
      );
      _branch(
        matches.map((match) => (match: match, loser: true)).toList(),
        start + inputs.length ~/ 2,
        '$key/L',
        depth + 1,
        selected,
        stored,
        edges,
      );
    }
  }

  static List<TournamentPlayer> applyRanking(
    List<TournamentPlayer> ranking,
    List<GroupMatch> placements,
  ) {
    final assigned = <int, TournamentPlayer>{};
    for (final m in placements) {
      if (m.placementRank == null || !m.isResolved) continue;
      if (m.winner != null) assigned[m.placementRank! - 1] = m.winner!;
      if (m.loser != null) assigned[m.placementRank!] = m.loser!;
    }
    final remaining = ranking
        .where((p) => !assigned.values.contains(p))
        .iterator;
    return [
      for (var i = 0; i < ranking.length; i++)
        if (assigned.containsKey(i))
          assigned[i]!
        else if (remaining.moveNext())
          remaining.current,
    ];
  }
}
