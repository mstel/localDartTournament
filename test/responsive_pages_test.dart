import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show HomePage;

void main() {
  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('Hauptmenü bleibt bei $size und großer Schrift bedienbar', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const HomePage(),
        ),
      );
      await tester.pumpAndSettle();

      if (size.width < 1100) {
        await tester.tap(find.byTooltip('Bereich wechseln'));
        await tester.pumpAndSettle();
      }

      for (final label in [
        'Turniere',
        'Spieler',
        'Statistiken',
        'Ranglisten',
      ]) {
        expect(find.text(label), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
