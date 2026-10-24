import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/challonge/data/challonge_public_reader.dart';
import 'package:dart_tournament_manager/features/challonge/application/challonge_native_import.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

// Public bracket fields observed on DCUH202637, 2026-10-08. Images and account metadata omitted.
void main() {
  test(
    'real two-stage public bracket preserves 25 games, aliases and separate ranks',
    () async {
      const names = [
        'Marvin_S',
        'Burkhard_H',
        'Michael_Le',
        'Jan_Wa',
        'Andre_Wi',
        'Mike_Ro',
        'Max_Re',
      ];
      const games = [
        [1, 6, 0, 2],
        [2, 5, 2, 1],
        [3, 4, 2, 0],
        [5, 3, 2, 0],
        [6, 2, 2, 0],
        [0, 1, 2, 0],
        [2, 0, 1, 2],
        [3, 6, 1, 2],
        [4, 5, 0, 2],
        [6, 4, 1, 2],
        [0, 3, 1, 2],
        [1, 2, 2, 0],
        [3, 1, 2, 0],
        [4, 0, 0, 2],
        [5, 6, 1, 2],
        [0, 5, 1, 2],
        [1, 4, 0, 2],
        [2, 3, 1, 2],
        [4, 2, 2, 0],
        [5, 1, 2, 0],
        [6, 0, 1, 2],
      ];
      Map<String, dynamic> match(
        int id,
        int round,
        int p1,
        int p2,
        int a,
        int b, {
        bool finals = false,
      }) {
        const ids = {0: 305765821, 3: 305765841, 5: 305766435, 6: 305766614};
        int pid(int n) => finals ? ids[n]! : 48672952 + n;
        return {
          'id': id,
          'round': round,
          'state': 'complete',
          'player1': {'id': pid(p1), 'display_name': names[p1]},
          'player2': {'id': pid(p2), 'display_name': names[p2]},
          'games': [
            [a, b],
          ],
          'winner_id': pid(a > b ? p1 : p2),
          'loser_id': pid(a > b ? p2 : p1),
        };
      }

      final third = match(474126961, 0, 5, 0, 2, 1, finals: true);
      final store = {
        'tournament': {
          'id': 18563162,
          'state': 'complete',
          'tournament_type': 'single elimination',
          'is_team': false,
          'split_participants': false,
          'participants_per_match': 2,
        },
        'matches_by_round': {
          '1': [
            match(474126958, 1, 5, 3, 0, 2, finals: true),
            match(474126959, 1, 0, 6, 0, 2, finals: true),
          ],
          '2': [match(474126960, 2, 3, 6, 1, 2, finals: true)],
        },
        'third_place_match': third,
        'consolation_matches': [third],
        'groups': [
          {
            'name': 'Gruppe A',
            'matches_by_round': {
              '1': [
                for (var i = 0; i < games.length; i++)
                  match(
                    474112733 + i,
                    i ~/ 3 + 1,
                    games[i][0],
                    games[i][1],
                    games[i][2],
                    games[i][3],
                  ),
              ],
            },
            'scorecard_html':
                '<table><tbody>${[5, 0, 6, 3, 4, 2, 1].indexed.map((e) => '<tr><td>${e.$1 + 1}</td><td class="participant"><span class="label">Erweitert</span><a>${names[e.$2]}</a></td></tr>').join()}</tbody></table>',
          },
        ],
      };
      final source =
          '''<html><meta property="og:title" content="Vereinsheim Unzenberg 2026 - 37. Spieltag - Challonge"><div class="start-time">September 30, 2026 bei 6:30 PM CEST</div><a href="/de/DCUH202637/standings">Rangliste</a><script>window._initialStoreState['TournamentStore'] = ${jsonEncode(store)};</script></html>''';
      final standings =
          '<table class="standings"><tbody>${[6, 3, 5, 0].indexed.map((e) => '<tr><td class="rank">${e.$1 + 1}</td><td class="display_name"><strong>${names[e.$2]}</strong></td></tr>').join()}</tbody></table>';
      final reader = ChallongePublicReader(
        readDocument: (uri) async =>
            uri.path.endsWith('/standings') ? standings : source,
      );
      final tournament = await reader.tournament(
        'https://challonge.com/de/DCUH202637',
      );
      expect(tournament.participants.length, 7);
      expect(tournament.matches.length, 25);
      expect(
        tournament.participants.where((p) => p['final_rank'] != null).length,
        4,
      );
      expect(
        tournament.participants.singleWhere(
          (p) => p['name'] == 'Andre_Wi',
        )['final_rank'],
        isNull,
      );
      final archive = tournament.convert({
        for (final p in tournament.participants)
          '${p['id']}': 'member-${p['id']}',
      }).importedArchive!;
      expect(
        archive.participants.singleWhere(
          (p) => p['name'] == 'Mike_Ro',
        )['groupPlacements'],
        [
          {'group': 'Gruppe A', 'rank': 1},
        ],
      );
      expect(tournament.data['started_at'], '2026-09-30T16:30:00.000Z');
      expect(tournament.data['completed_at'], isNull);
      final native = ChallongeNativeImport.convert(
        tournament.convert({
          for (final p in tournament.participants)
            '${p['id']}': 'member-${p['id']}',
        }),
      );
      expect(native.runStages, hasLength(2));
      expect(native.activeStageIndex, 1);
      expect(native.completedStageIndexes, {0, 1});
      expect(native.runStages.first, isA<GroupTournamentRunStage>());
      expect(native.runStages.last, isA<KnockoutTournamentRunStage>());
      final ko = native.runStages.last as KnockoutTournamentRunStage;
      expect(
        ko.rounds.expand((r) => r).where((m) => m.hasResult),
        hasLength(3),
      );
      expect(ko.placementMatches.where((m) => m.hasResult), hasLength(1));
      expect(
        native.importedArchive!.nativeValidation!['issues'],
        [
          'Gruppe A: Jan_Wa berechnet Platz 2, Challonge Platz 4.',
          'Gruppe A: Marvin_S berechnet Platz 3, Challonge Platz 2.',
          'Gruppe A: Max_Re berechnet Platz 4, Challonge Platz 3.',
          'Gruppe A: Burkhard_H berechnet Platz 6, Challonge Platz 7.',
          'Gruppe A: Michael_Le berechnet Platz 7, Challonge Platz 6.',
        ],
      );
      expect(
        CreatedTournament.fromJson(
          native.toJson(),
        ).importedArchive!.usesNativeLogic,
        isTrue,
      );
    },
  );
}
