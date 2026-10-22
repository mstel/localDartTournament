import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_tournament_manager/features/rankings/application/tournament_ranking_changes_service.dart';
import 'package:dart_tournament_manager/features/rankings/domain/elo_tier.dart';
import 'package:dart_tournament_manager/features/rankings/domain/elo_tier.dart'
    show EloTier;
import 'package:dart_tournament_manager/features/statistics/domain/best_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_completion_image_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'generates a portrait tournament-completion image with all sections',
    () async {
      final bytes = await const TournamentCompletionImageGenerator()
          .generatePortraitPng(
            data: TournamentCompletionImageData(
              tournamentName: 'Vereinscup',
              tournamentType: 'Gruppenphase + KO',
              participantCount: 8,
              matchCount: 14,
              legCount: 41,
              averageLegsPerMatch: 2.9,
              durationSummary: 'Erwartet: 2:00–3:00',
              podium: const [
                TournamentCompletionPodiumEntry(
                  place: 1,
                  playerName: 'Alex Sieger',
                  wins: 5,
                  losses: 0,
                  legsFor: 12,
                  legsAgainst: 3,
                ),
              ],
              rankingChanges: [
                TournamentRankingPlayerChange(
                  playerProfileId: 'alex',
                  playerName: 'Alex Sieger',
                  delta: 24,
                  ratingBefore: 1000,
                  ratingAfter: 1024,
                  tierBefore: EloTier.values.first,
                  tierAfter: EloTier.values.last,
                  enableTiers: true,
                  rankingName: 'Vereinswertung',
                  rankingPositionBefore: 3,
                  rankingPositionAfter: 1,
                ),
              ],
              bestPerformances: const [
                BestPerformance(
                  type: BestPerformanceType.score180,
                  playerName: 'Alex Sieger',
                ),
              ],
            ),
          );
      final data = ByteData.sublistView(bytes);

      expect(bytes.sublist(0, 8), [
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]);
      expect(data.getUint32(16, Endian.big), 1080);
      expect(data.getUint32(20, Endian.big), greaterThan(1000));

      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      expect(rgba.getUint8(0), 0x0D);
      expect(rgba.getUint8(1), 0x13);
      expect(rgba.getUint8(2), 0x18);
      image.dispose();
      codec.dispose();
    },
  );
}
