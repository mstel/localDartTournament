import 'package:dart_tournament_manager/features/statistics/domain/best_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/best_performance_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('records a text description for a Bullseye finish', (
    tester,
  ) async {
    List<BestPerformance> changed = const [];
    final match = GroupMatch(
      homePlayer: TournamentPlayer(
        profileId: 'player-1',
        name: 'Spieler Eins',
        isGenerated: false,
      ),
      awayPlayer: TournamentPlayer(
        profileId: 'player-2',
        name: 'Spieler Zwei',
        isGenerated: false,
      ),
      round: 1,
    );
    for (final size in [
      const Size(360, 800),
      const Size(800, 600),
      const Size(1440, 900),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: const TextScaler.linear(2),
          ),
          child: MaterialApp(
            home: Scaffold(
              body: BestPerformanceEditor(
                key: ValueKey(size),
                match: match,
                initial: const [],
                onChanged: (performances) => changed = performances,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('180+'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bullseye Finish').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Bullseye innen');
      await tester.tap(find.text('Bestleistung hinzufügen'));
      await tester.pumpAndSettle();

      expect(changed, hasLength(1));
      expect(changed.single.type, BestPerformanceType.bullseyeFinish);
      expect(changed.single.details, 'Bullseye innen');
      expect(
        find.text('Spieler Eins: Bullseye Finish · Bullseye innen'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }

    addTearDown(tester.view.reset);
  });
}
