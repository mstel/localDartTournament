import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/creation/stage_setup_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('explains each tie-breaker at $size and large text', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: GroupTieBreakerSetup(
                tieBreakers: defaultGroupTieBreakers,
                onMoveTieBreaker: (_, _) async {},
              ),
            ),
          ),
        ),
      );

      final tooltips = find.ancestor(
        of: find.byIcon(Icons.info_outline),
        matching: find.byType(Tooltip),
      );
      expect(tooltips, findsNWidgets(defaultGroupTieBreakers.length));
      final messages = tooltips
          .evaluate()
          .map((element) => (element.widget as Tooltip).message)
          .toList();
      expect(messages, hasLength(4));
      expect(messages[0], contains('Matchpunkte'));
      expect(
        messages[0],
        contains('Sieg = 3 Punkte, Unentschieden = 1 Punkt, Niederlage = 0'),
      );
      expect(messages[0], contains('nicht die Anzahl einzelner Legs'));
      expect(messages[1], contains('Direkter Vergleich'));
      expect(messages[1], contains('Matchpunkte aus den direkten Duellen'));
      expect(messages[2], contains('Leg-Differenz'));
      expect(
        messages[2],
        contains('gewonnenen Legs minus Summe der verlorenen Legs'),
      );
      expect(messages[2], contains('Die höhere Differenz gewinnt'));
      expect(messages[3], contains('Gewonnene Legs'));
      expect(find.text('Matchpunkte'), findsOneWidget);
      expect(
        tester.getSize(tooltips.first).shortestSide,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
