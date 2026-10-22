import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_export.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

void main() {
  test('exports a versioned tournament document with complete source data', () {
    final tournament = CreatedTournament(
      name: 'Vereinsturnier',
      players: [TournamentPlayer(name: 'Anna Beispiel', isGenerated: false)],
      stages: const [],
      runStages: const [],
    );

    final decoded = jsonDecode(TournamentExport.encode(tournament));

    expect(decoded['format'], 'dart-tournament-export');
    expect(decoded['schemaVersion'], TournamentExport.schemaVersion);
    expect(decoded['tournament']['name'], 'Vereinsturnier');
    expect(decoded['tournament']['players'].single['name'], 'Anna Beispiel');
  });

  test(
    'exports a standalone responsive HTML document without embedding markup',
    () {
      final tournament = CreatedTournament(
        name: '</script><b>Vereinsturnier</b>',
        players: [TournamentPlayer(name: 'Anna Beispiel', isGenerated: false)],
        stages: const [],
        runStages: const [],
      );

      final html = TournamentExport.html(tournament);

      expect(html, contains('<meta name="viewport"'));
      expect(html, contains('max-width:1100px'));
      expect(html, contains(r'\u003c/script>'));
      expect(html, contains('Begegnungen und Ergebnisse'));
      expect(html, contains('Drucken / Als PDF speichern'));
      expect(html, contains('Bestleistungen'));
    },
  );

  test('HTML export includes result summary, podium and ranking movement', () {
    final tournament = CreatedTournament(
      name: 'Vereinsturnier',
      players: [TournamentPlayer(name: 'Anna Beispiel', isGenerated: false)],
      stages: const [],
      runStages: const [],
    );

    final html = TournamentExport.html(
      tournament,
      resultSummary: {
        'participantCount': 8,
        'matchCount': 12,
        'legCount': 51,
        'averageLegsPerMatch': 4.25,
        'actualDurationSeconds': 15600,
        'expectedMinimumMinutes': 200,
        'expectedMaximumMinutes': 300,
        'podium': [
          {
            'name': 'Anna Beispiel',
            'wins': 5,
            'losses': 0,
            'legsFor': 15,
            'legsAgainst': 4,
          },
        ],
      },
      rankingChanges: [
        {
          'rankingName': 'Vereinsrangliste',
          'playerName': 'Anna Beispiel',
          'delta': 21,
          'ratingBefore': 800,
          'ratingAfter': 821,
          'tierChange': true,
          'tierBefore': 'Bronze',
          'tierAfter': 'Silber',
        },
      ],
    );

    expect(html, contains('"participantCount":8'));
    expect(html, contains('expectedMinimumMinutes'));
    expect(html, contains('rankingChanges'));
    expect(html, contains('ratingBefore'));
    expect(html, contains('Drucken / Als PDF speichern'));
  });
}
