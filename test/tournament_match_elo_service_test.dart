import 'dart:io';

import 'package:dart_tournament_manager/features/rankings/application/local_ranking_elo_service.dart';
import 'package:dart_tournament_manager/features/rankings/application/tournament_match_elo_service.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'returns persisted-ranking Elo deltas for tournament result matches',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tournament_match_elo_test_',
      );
      addTearDown(() => directory.delete(recursive: true));

      final database = LocalAppDatabase(baseDirectory: directory);
      final homeProfile = await database.createPlayerProfile(
        displayName: 'Anna Home',
      );
      final awayProfile = await database.createPlayerProfile(
        displayName: 'Ben Away',
      );
      const ranking = LocalRanking(id: 'elo', name: 'Vereinsrangliste');
      await database.saveLocalRanking(ranking);
      await database.setRankingPlayers(ranking.id, [
        homeProfile.id,
        awayProfile.id,
      ]);

      final home = TournamentPlayer(
        name: homeProfile.displayName,
        profileId: homeProfile.id,
        isGenerated: false,
      );
      final away = TournamentPlayer(
        name: awayProfile.displayName,
        profileId: awayProfile.id,
        isGenerated: false,
      );
      final match = GroupMatch(homePlayer: home, awayPlayer: away, round: 1)
        ..homeLegs = 1
        ..awayLegs = 0;
      final tournament = CreatedTournament(
        name: 'Testturnier',
        players: [home, away],
        stages: const [],
        runStages: [
          KnockoutTournamentRunStage(
            name: 'Finale',
            rounds: [
              [match],
            ],
          ),
        ],
        rankingIds: [ranking.id],
        startedAt: DateTime(2026, 1, 1),
      );
      final storage = TournamentStorage(
        file: File(
          '${directory.path}${Platform.pathSeparator}tournaments.json',
        ),
      );
      await storage.saveTournament(tournament);

      final changes = await TournamentMatchEloService(
        database: database,
        tournamentStorage: storage,
      ).calculate(tournament);
      final matchChanges = changes.values.single;

      expect(matchChanges, hasLength(1));
      expect(matchChanges.single.homeDelta, greaterThan(0));
      expect(matchChanges.single.awayDelta, lessThan(0));
      expect(matchChanges.single.homeRatingBefore, isNotNull);
      expect(matchChanges.single.homeRatingAfter, isNotNull);
      expect(
        matchChanges.single.homeRatingAfter! -
            matchChanges.single.homeRatingBefore!,
        matchChanges.single.homeDelta,
      );
      expect(matchChanges.single.awayRatingBefore, isNotNull);
      expect(matchChanges.single.awayRatingAfter, isNotNull);
      expect(
        matchChanges.single.awayRatingAfter! -
            matchChanges.single.awayRatingBefore!,
        matchChanges.single.awayDelta,
      );
    },
  );

  test(
    'includes local opponents at a temporary 1000 Elo when enabled',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tournament_match_local_elo_test_',
      );
      addTearDown(() => directory.delete(recursive: true));

      final database = LocalAppDatabase(baseDirectory: directory);
      final homeProfile = await database.createPlayerProfile(
        displayName: 'Anna Home',
      );
      const ranking = LocalRanking(
        id: 'elo',
        name: 'Vereinsrangliste',
        countUnassignedPlayers: true,
      );
      await database.saveLocalRanking(ranking);
      await database.setRankingPlayers(ranking.id, [homeProfile.id]);

      final home = TournamentPlayer(
        name: homeProfile.displayName,
        profileId: homeProfile.id,
        isGenerated: false,
      );
      const guest = TournamentPlayer(name: 'Gast', isGenerated: false);
      final match = GroupMatch(homePlayer: guest, awayPlayer: home, round: 1)
        ..homeLegs = 2
        ..awayLegs = 0;
      final tournament = CreatedTournament(
        name: 'Testturnier',
        players: [home, guest],
        stages: const [],
        runStages: [
          KnockoutTournamentRunStage(
            name: 'Finale',
            rounds: [
              [match],
            ],
          ),
        ],
        rankingIds: [ranking.id],
        startedAt: DateTime(2026, 1, 1),
      );
      final storage = TournamentStorage(
        file: File(
          '${directory.path}${Platform.pathSeparator}tournaments.json',
        ),
      );
      await storage.saveTournament(tournament);

      final changes = await TournamentMatchEloService(
        database: database,
        tournamentStorage: storage,
      ).calculate(tournament);
      final guestChange = changes.values.single.single;

      expect(guestChange.homeDelta, greaterThan(0));
      expect(guestChange.awayDelta, lessThan(0));
      expect(guestChange.homeRatingBefore, 1000);
      expect(guestChange.homeRatingAfter, 1000 + guestChange.homeDelta!);
    },
  );

  test(
    'uses the what-if replay for players below the participation threshold',
    () async {
      LocalRankingEloService.clearCache();
      final directory = await Directory.systemTemp.createTemp(
        'tournament_match_hypothetical_elo_test_',
      );
      addTearDown(() => directory.delete(recursive: true));

      final database = LocalAppDatabase(baseDirectory: directory);
      final eligibleProfile = await database.createPlayerProfile(
        displayName: 'Anna eligible',
      );
      final hypotheticalProfile = await database.createPlayerProfile(
        displayName: 'Ben hypothetical',
      );
      final secondEligibleProfile = await database.createPlayerProfile(
        displayName: 'Chris eligible',
      );
      const ranking = LocalRanking(
        id: 'threshold-elo',
        name: 'Rangliste mit Schwelle',
        requireMinimumParticipations: true,
        minimumParticipations: 2,
      );
      await database.saveLocalRanking(ranking);
      await database.setRankingPlayers(ranking.id, [
        eligibleProfile.id,
        hypotheticalProfile.id,
        secondEligibleProfile.id,
      ]);

      TournamentPlayer player(profile) => TournamentPlayer(
        name: profile.displayName,
        profileId: profile.id,
        isGenerated: false,
      );
      final eligible = player(eligibleProfile);
      final hypothetical = player(hypotheticalProfile);
      final secondEligible = player(secondEligibleProfile);

      final firstMatch =
          GroupMatch(homePlayer: eligible, awayPlayer: secondEligible, round: 1)
            ..homeLegs = 1
            ..awayLegs = 0;
      final first = CreatedTournament(
        name: 'Vorlauf',
        players: [eligible, secondEligible],
        stages: const [],
        runStages: [
          KnockoutTournamentRunStage(
            name: 'Finale',
            rounds: [
              [firstMatch],
            ],
          ),
        ],
        rankingIds: [ranking.id],
        startedAt: DateTime(2026, 1, 1),
      );
      final secondMatch =
          GroupMatch(homePlayer: eligible, awayPlayer: secondEligible, round: 1)
            ..homeLegs = 1
            ..awayLegs = 0;
      final second = CreatedTournament(
        name: 'Vorlauf 2',
        players: [eligible, secondEligible],
        stages: const [],
        runStages: [
          KnockoutTournamentRunStage(
            name: 'Finale',
            rounds: [
              [secondMatch],
            ],
          ),
        ],
        rankingIds: [ranking.id],
        startedAt: DateTime(2026, 1, 15),
      );
      final targetMatch =
          GroupMatch(homePlayer: hypothetical, awayPlayer: eligible, round: 1)
            ..homeLegs = 1
            ..awayLegs = 0;
      final target = CreatedTournament(
        name: 'Zielturnier',
        players: [hypothetical, eligible],
        stages: const [],
        runStages: [
          KnockoutTournamentRunStage(
            name: 'Finale',
            rounds: [
              [targetMatch],
            ],
          ),
        ],
        rankingIds: [ranking.id],
        startedAt: DateTime(2026, 2, 1),
      );
      final storage = TournamentStorage(
        file: File(
          '${directory.path}${Platform.pathSeparator}tournaments.json',
        ),
      );
      await storage.saveTournament(first);
      await storage.saveTournament(second);
      await storage.saveTournament(target);

      final changes = await TournamentMatchEloService(
        database: database,
        tournamentStorage: storage,
      ).calculate(target);
      final change = changes.values.single.single;

      expect(change.homeHypothetical, isTrue);
      // Auch der qualifizierte Gegner erhält hier nur hypothetische Punkte,
      // weil beide Werte aus dem What-if-Replay stammen.
      expect(change.awayHypothetical, isTrue);
      expect(change.homeDelta, greaterThan(0));
      expect(change.homeRatingBefore, isNotNull);
      expect(change.homeRatingAfter, isNotNull);
      expect(change.homeRatingAfter, isNot(ranking.startRating));
      expect(
        change.homeRatingAfter! - change.homeRatingBefore!,
        change.homeDelta,
      );

      expect(change.awayDelta, lessThan(0));
      expect(change.awayRatingBefore, greaterThan(ranking.startRating));
      expect(
        change.awayRatingAfter! - change.awayRatingBefore!,
        change.awayDelta,
      );
    },
  );
}
