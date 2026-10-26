import '../../tournaments/domain/imported_tournament_archive.dart';
import '../../tournaments/domain/tournament_models.dart';

class ChallongeTournament {
  ChallongeTournament(Map<String, dynamic> data)
    : data = Map.unmodifiable(data) {
    if (data['id'] == null || data['state'] != 'complete') {
      throw const FormatException(
        'Nur abgeschlossene Challonge-Turniere importieren.',
      );
    }
    if (data['teams'] == true) {
      throw const FormatException(
        'Teamturniere benötigen eine individuelle Mitgliederzuordnung und werden noch nicht unterstützt.',
      );
    }
    if (DateTime.tryParse('${data['created_at'] ?? ''}') == null ||
        (data['public_dates'] != true &&
            DateTime.tryParse('${data['completed_at'] ?? ''}') == null)) {
      throw const FormatException(
        'Erstellungs- oder Abschlussdatum fehlt im Challonge-Export.',
      );
    }
    if (data['participants'] is! List || data['matches'] is! List) {
      throw const FormatException(
        'Teilnehmer und Spiele fehlen. Vollständigen JSON-Export verwenden.',
      );
    }
    final ids = participants.map((p) => '${p['id']}').toSet();
    if (participants.isEmpty ||
        ids.length != participants.length ||
        participants.any(
          (p) => p['id'] == null || name(p).isEmpty || name(p).length > 80,
        ) ||
        (data['participants_count'] != null &&
            data['participants_count'] != participants.length)) {
      throw const FormatException(
        'Unvollständige oder ungültige Teilnehmerliste.',
      );
    }
    if (participants.map((p) => normalizedName(name(p))).toSet().length !=
        participants.length) {
      throw const FormatException(
        'Gleichnamige Teilnehmer bitte zuerst in Challonge eindeutig benennen.',
      );
    }
    for (final p in participants) {
      final rank = p['final_rank'];
      if (rank != null && (rank is! int || rank < 1)) {
        throw const FormatException('Ungültige Challonge-Platzierung.');
      }
      for (final alias in (p['group_player_ids'] as List? ?? const [])) {
        if ('${p['id']}' != '$alias' && !ids.add('$alias')) {
          throw const FormatException('Mehrdeutige Gruppen-Teilnehmerkennung.');
        }
      }
    }
    final matchIds = <String>{};
    for (final m in matches) {
      if (m['id'] == null || !matchIds.add('${m['id']}')) {
        throw const FormatException('Ungültige oder doppelte Spielkennung.');
      }
      for (final key in ['player1_id', 'player2_id', 'winner_id', 'loser_id']) {
        if (m[key] != null && !ids.contains('${m[key]}')) {
          throw const FormatException(
            'Spiel verweist auf einen fehlenden Teilnehmer.',
          );
        }
      }
    }
  }
  final Map<String, dynamic> data;
  String get id => '${data['id']}';
  String get title => data['name'] as String? ?? 'Challonge-Turnier';
  List<Map<String, dynamic>> get participants =>
      unwrap(data['participants'] as List, 'participant');
  List<Map<String, dynamic>> get matches =>
      unwrap(data['matches'] as List, 'match');
  static List<Map<String, dynamic>> unwrap(List items, String key) =>
      items.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        return Map<String, dynamic>.from((map[key] ?? map) as Map);
      }).toList();
  static String name(Map<String, dynamic> p) =>
      (p['name'] as String? ?? '').trim();
  static String normalizedName(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  String get tournamentId => 'challonge:local:${Uri.encodeComponent(id)}';

  CreatedTournament convert(
    Map<String, String> profiles, {
    bool countsForRanking = false,
    List<String> rankingIds = const [],
    bool allowUnlinkedPlayers = false,
  }) {
    if (countsForRanking && rankingIds.isEmpty) {
      throw const FormatException(
        'Für die Elo-Wertung mindestens eine Rangliste auswählen.',
      );
    }
    final players = {
      for (final p in participants)
        '${p['id']}': TournamentPlayer(
          profileId: profiles['${p['id']}'],
          name: name(p),
          isGenerated: false,
        ),
    };
    final linkedProfileIds = players.values
        .map((p) => p.profileId)
        .whereType<String>()
        .toList();
    if ((!allowUnlinkedPlayers && players.values.any((p) => p.profileId == null)) ||
        linkedProfileIds.toSet().length != linkedProfileIds.length) {
      throw ArgumentError(
        'Jeder zugewiesene Teilnehmer muss einem eindeutigen Spieler entsprechen.',
      );
    }
    final results = <GroupMatch>[];
    final referencedPlayers = {
      ...players,
      for (final p in participants)
        for (final alias in (p['group_player_ids'] as List? ?? const []))
          '$alias': players['${p['id']}']!,
    };
    // Only an unambiguous integer score is a leg result. Multi-score matches,
    // walkovers and scores without a result stay faithfully in the archive.
    final statisticalMatches = matches.indexed.toList()
      ..sort((a, b) {
        final stage = (a.$2['group_id'] == null ? 1 : 0).compareTo(
          b.$2['group_id'] == null ? 1 : 0,
        );
        return stage != 0 ? stage : a.$1.compareTo(b.$1);
      });
    for (final indexedMatch in statisticalMatches) {
      final m = indexedMatch.$2;
      final score = RegExp(
        r'^(\d+)-(\d+)$',
      ).firstMatch('${m['scores_csv'] ?? ''}'.trim());
      if (score == null ||
          m['state'] != 'complete' ||
          m['player1_id'] == null ||
          m['player2_id'] == null) {
        continue;
      }
      final home = int.parse(score[1]!), away = int.parse(score[2]!);
      final expectedWinner = home > away
          ? m['player1_id']
          : home < away
          ? m['player2_id']
          : null;
      if ('${expectedWinner ?? ''}' != '${m['winner_id'] ?? ''}') continue;
      results.add(
        GroupMatch(
          homePlayer: referencedPlayers['${m['player1_id']}'],
          awayPlayer: referencedPlayers['${m['player2_id']}'],
          round: (m['round'] as int? ?? 1).abs(),
          homeLegs: home,
          awayLegs: away,
          label: 'Challonge ${m['identifier'] ?? m['id']}',
          startedAt: DateTime.tryParse('${m['started_at'] ?? ''}'),
          finishedAt: DateTime.tryParse('${m['completed_at'] ?? ''}'),
        ),
      );
    }
    final archive = ImportedTournamentArchive(
      sourceId: id,
      url: '${data['full_challonge_url'] ?? ''}',
      mode: '${data['tournament_type'] ?? ''}',
      participants: [
        for (final p in participants)
          {
            'id': '${p['id']}',
            'name': name(p),
            'profileId': profiles['${p['id']}'],
            'finalRank': p['final_rank'],
            'groupPlayerIds': p['group_player_ids'] ?? const [],
            'groupPlacements': p['group_placements'] ?? const [],
          },
      ],
      matches: [
        for (final m in matches)
          {
            for (final key in [
              'id',
              'identifier',
              'round',
              'state',
              'player1_id',
              'player2_id',
              'winner_id',
              'loser_id',
              'scores_csv',
              'started_at',
              'completed_at',
              'group_id',
              'group_type',
              'player1_seed',
              'player2_seed',
            ])
              key: m[key],
          },
      ],
    );
    return CreatedTournament(
      id: 'challonge:local:${Uri.encodeComponent(id)}',
      name: title,
      players: players.values.toList(),
      createdAt: DateTime.tryParse('${data['created_at'] ?? ''}'),
      startedAt: DateTime.tryParse('${data['started_at'] ?? ''}'),
      finishedAt: DateTime.tryParse('${data['completed_at'] ?? ''}') ??
          DateTime.tryParse('${data['started_at'] ?? ''}') ??
          DateTime.tryParse('${data['created_at'] ?? ''}'),
      countsForRanking: countsForRanking,
      rankingIds: countsForRanking
          ? rankingIds.toSet().toList()
          : const [],
      importedArchive: archive,
      stages: const [TournamentStage(name: 'Challonge-Archiv', type: 'groups')],
      runStages: [
        GroupTournamentRunStage(
          name: 'Challonge-Archiv',
          groupPlayType: 'round_robin',
          groups: [
            TournamentGroup(
              name: 'Archivierte Ergebnisse',
              playType: 'round_robin',
              players: players.values.toList(),
              matches: results,
            ),
          ],
          qualificationPlan: null,
          tieBreakers: const [],
        ),
      ],
      completedStageIndexes: {0},
    );
  }
}
