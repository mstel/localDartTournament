import 'package:dart_tournament_manager/features/challonge/application/challonge_tournament_conversion_service.dart';
import 'package:dart_tournament_manager/features/challonge/domain/challonge_tournament.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> challongeData() => {
  'id': 42,
  'name': 'Historischer Spieltag',
  'state': 'complete',
  'tournament_type': 'round robin',
  'created_at': '2026-04-04T12:00:00Z',
  'started_at': '2026-04-04T13:00:00Z',
  'completed_at': '2026-04-04T14:00:00Z',
  'full_challonge_url': 'https://challonge.com/spieltag42',
  'participants': [
    {'id': 1, 'name': 'Anna', 'final_rank': 1},
    {'id': 2, 'name': 'Ben', 'final_rank': 2},
    {'id': 3, 'name': 'Cem', 'final_rank': 3},
  ],
  'matches': [
    {
      'id': 10,
      'identifier': 'M1',
      'group_id': 'Gruppe A',
      'group_type': 'round robin',
      'round': 1,
      'state': 'complete',
      'player1_id': 1,
      'player2_id': 2,
      'winner_id': 1,
      'scores_csv': '2-1',
      'started_at': '2026-04-04T13:15:00Z',
      'completed_at': '2026-04-04T13:20:00Z',
    },
    {
      'id': 11,
      'identifier': 'M2',
      'group_id': 'Gruppe A',
      'group_type': 'round robin',
      'round': 1,
      'state': 'complete',
      'player1_id': 1,
      'player2_id': 3,
      'winner_id': 1,
      'scores_csv': '2-0',
      'started_at': '2026-04-04T13:00:00Z',
      'completed_at': '2026-04-04T13:05:00Z',
      'bestPerformances': [
        {'type': 'score180', 'playerName': 'Anna', 'playerProfileId': 'p1'},
      ],
    },
    {
      'id': 12,
      'identifier': 'M3',
      'group_id': 'Gruppe A',
      'group_type': 'round robin',
      'round': 1,
      'state': 'complete',
      'player1_id': 2,
      'player2_id': 3,
      'winner_id': 2,
      'scores_csv': '2-1',
      'started_at': '2026-04-04T13:30:00Z',
      'completed_at': '2026-04-04T13:35:00Z',
    },
  ],
};

CreatedTournament archivedTournament() {
  final source = ChallongeTournament(challongeData());
  return source.convert({'1': 'p1', '2': 'p2', '3': 'p3'});
}

void main() {
  test(
    'converts an archive into a completed native historical tournament',
    () async {
      final archived = archivedTournament();

      final converted = await ChallongeTournamentConversionService().convert(
        archived,
      );

      expect(converted.id, archived.id);
      expect(converted.name, 'Historischer Spieltag');
      expect(converted.finishedAt, DateTime.parse('2026-04-04T14:00:00Z'));
      expect(converted.completedStageIndexes, {0});
      expect(converted.importedArchive!.usesNativeLogic, isTrue);
      expect(converted.runStages.single, isA<GroupTournamentRunStage>());
      final group =
          (converted.runStages.single as GroupTournamentRunStage).groups.single;
      expect(group.name, 'Gruppe A');
      expect(group.players.map((player) => player.profileId), [
        'p1',
        'p2',
        'p3',
      ]);
      expect(group.matches.map((match) => match.startedAt!.minute), [
        0,
        15,
        30,
      ]);
      expect(group.matches.first.bestPerformances.single.playerProfileId, 'p1');
    },
  );

  test(
    'uses Challonge seeds to preserve knockout paths when matches are unordered',
    () async {
      Map<String, dynamic> match(
        int id,
        int round,
        int home,
        int away,
        int homeSeed,
        int awaySeed,
      ) => {
        'id': id,
        'identifier': 'M$id',
        'round': round,
        'state': 'complete',
        'player1_id': home,
        'player2_id': away,
        'player1_seed': homeSeed,
        'player2_seed': awaySeed,
        'winner_id': home,
        'scores_csv': '2-0',
        'started_at': '2026-04-04T13:00:00Z',
        'completed_at': '2026-04-04T13:05:00Z',
      };

      final data = {
        'id': 43,
        'name': 'Unsortierter KO-Baum',
        'state': 'complete',
        'tournament_type': 'single elimination',
        'created_at': '2026-04-04T12:00:00Z',
        'started_at': '2026-04-04T13:00:00Z',
        'completed_at': '2026-04-04T14:00:00Z',
        'full_challonge_url': 'https://challonge.com/unsortierterbaum',
        'participants': [
          for (var seed = 1; seed <= 8; seed++)
            {'id': seed, 'name': 'Spieler $seed', 'final_rank': seed},
        ],
        // The second-round paths require [1 vs 8, 4 vs 5] and [2 vs 7,
        // 3 vs 6]. Challonge may return first-round rows in another order.
        'matches': [
          match(11, 1, 1, 8, 1, 8),
          match(12, 1, 2, 7, 2, 7),
          match(13, 1, 3, 6, 3, 6),
          match(14, 1, 4, 5, 4, 5),
          match(21, 2, 1, 4, 1, 4),
          match(22, 2, 2, 3, 2, 3),
          match(31, 3, 1, 2, 1, 2),
        ],
      };
      final archived = ChallongeTournament(
        data,
      ).convert({for (var seed = 1; seed <= 8; seed++) '$seed': 'p$seed'});

      final converted = await ChallongeTournamentConversionService().convert(
        archived,
      );

      final stage = converted.runStages.single as KnockoutTournamentRunStage;
      expect(converted.completedStageIndexes, {0});
      expect(stage.rounds[1], hasLength(2));
      expect(
        stage.rounds[1].map((m) => {m.homePlayer!.name, m.awayPlayer!.name}),
        [
          {'Spieler 1', 'Spieler 4'},
          {'Spieler 2', 'Spieler 3'},
        ],
      );
      expect(stage.rounds.last.single.winner?.name, 'Spieler 1');
    },
  );

  test(
    'converts incomplete assignments while preserving local opponents',
    () async {
      final original = archivedTournament();
      final archive = original.toJson()
        ..['players'] = [
          const TournamentPlayer(
            profileId: 'p1',
            name: 'Anna',
            isGenerated: false,
          ).toJson(),
          const TournamentPlayer(
            profileId: 'p2',
            name: 'Ben',
            isGenerated: false,
          ).toJson(),
          const TournamentPlayer(name: 'Cem', isGenerated: false).toJson(),
        ];
      final imported = Map<String, dynamic>.from(
        archive['importedArchive'] as Map,
      );
      imported['participants'] = [
        for (final participant in imported['participants'] as List)
          if (participant['id'] == '3')
            {
              ...Map<String, dynamic>.from(participant as Map),
              'profileId': null,
            }
          else
            participant,
      ];
      archive['importedArchive'] = imported;
      var fetched = false;
      final service = ChallongeTournamentConversionService(
        fetch: (_) async {
          fetched = true;
          return ChallongeTournament(challongeData());
        },
      );

      final converted = await service.convert(
        CreatedTournament.fromJson(archive),
      );

      expect(converted.runStages.single, isA<GroupTournamentRunStage>());
      final group =
          (converted.runStages.single as GroupTournamentRunStage).groups.single;
      expect(group.players.map((player) => player.profileId), [
        'p1',
        'p2',
        null,
      ]);
      expect(group.matches, hasLength(3));
      expect(fetched, isFalse);
    },
  );

  test(
    'refreshes incomplete archive data and retains locally edited highlights',
    () async {
      final original = archivedTournament();
      final originalArchive = original.importedArchive!;
      final incompleteMatches = [
        for (final match in originalArchive.matches)
          if (match['id'] == 10)
            {...match, 'state': 'pending'}
          else if (match['id'] == 11)
            {
              ...match,
              'bestPerformances': [
                {
                  'type': 'score180',
                  'playerName': 'Anna',
                  'playerProfileId': 'p1',
                },
              ],
            }
          else
            match,
      ];
      final data = original.toJson()
        ..['importedArchive'] = originalArchive
            .copyWithMatches(incompleteMatches)
            .toJson();
      final incomplete = CreatedTournament.fromJson(data);
      String? requestedUrl;
      final converted = await ChallongeTournamentConversionService(
        fetch: (url) async {
          requestedUrl = url;
          return ChallongeTournament(challongeData());
        },
      ).convert(incomplete);

      expect(requestedUrl, 'https://challonge.com/spieltag42');
      expect(converted.id, original.id);
      expect(converted.name, original.name);
      expect(converted.runStages.single, isA<GroupTournamentRunStage>());
      final group =
          (converted.runStages.single as GroupTournamentRunStage).groups.single;
      expect(group.matches, hasLength(3));
      expect(group.matches.first.bestPerformances.single.playerName, 'Anna');
    },
  );

  test(
    'refreshes numeric group ids to recover Challonge group names',
    () async {
      final matches = challongeData()['matches'] as List;
      final data = challongeData()
        ..['matches'] = [
          for (final match in matches)
            {...Map<String, dynamic>.from(match as Map), 'group_id': 12345},
        ];
      final archived = ChallongeTournament(
        data,
      ).convert({'1': 'p1', '2': 'p2', '3': 'p3'});

      final converted = await ChallongeTournamentConversionService(
        fetch: (_) async => ChallongeTournament(challongeData()),
      ).convert(archived);

      final group =
          (converted.runStages.single as GroupTournamentRunStage).groups.single;
      expect(group.name, 'Gruppe A');
      expect(converted.importedArchive!.nativeValidation!['issues'], isEmpty);
    },
  );

  test('retains cached group ids and reports a blocked name refresh', () async {
    final matches = challongeData()['matches'] as List;
    final data = challongeData()
      ..['matches'] = [
        for (final match in matches)
          {...Map<String, dynamic>.from(match as Map), 'group_id': 12345},
      ];
    final archived = ChallongeTournament(
      data,
    ).convert({'1': 'p1', '2': 'p2', '3': 'p3'});

    final converted = await ChallongeTournamentConversionService(
      fetch: (_) async => throw const FormatException('HTTP 403'),
    ).convert(archived);

    final group =
        (converted.runStages.single as GroupTournamentRunStage).groups.single;
    expect(group.name, '12345');
    expect(
      converted.importedArchive!.nativeValidation!['status'],
      'differences',
    );
    expect(
      converted.importedArchive!.nativeValidation!['issues'],
      contains(
        contains(
          'Gruppennamen konnten nicht erneut von Challonge geladen werden',
        ),
      ),
    );
  });
}
