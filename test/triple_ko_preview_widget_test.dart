import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/creation/triple_ko_preview_sections.dart';

void main() {
  const sizes = [Size(360, 800), Size(800, 600), Size(1440, 900)];

  testWidgets(
    'Triple KO preview starts compact and expands every bracket phase',
    (tester) async {
      tester.view.physicalSize = sizes.first;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_previewApp(size: sizes.first));

      expect(find.byType(ExpansionTile), findsNWidgets(3));
      expect(find.textContaining('Begegnungen'), findsNWidgets(3));
      expect(find.text('Teilnehmer 1'), findsNothing);

      for (var index = 0; index < 3; index++) {
        final phase = find.byKey(ValueKey('triple-preview-loss-level-$index'));
        await tester.ensureVisible(phase);
        await tester.tap(phase);
        await tester.pumpAndSettle();

        expect(find.text('Teilnehmer ${index + 1}'), findsOneWidget);
        await tester.tap(phase);
        await tester.pumpAndSettle();
      }

      expect(find.text('Teilnehmer 1'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Triple KO preview fits common viewports with large text', (
    tester,
  ) async {
    addTearDown(tester.view.reset);

    for (final size in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(_previewApp(size: size, textScale: 2));
      expect(find.byType(ExpansionTile), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    }
  });
}

Widget _previewApp({required Size size, double textScale = 1}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          child: TripleKoPreviewSections(
            phases: [
              for (var index = 0; index < 3; index++)
                TripleKoPreviewPhase(
                  title: [
                    'Winners Bracket',
                    '1 Niederlage',
                    '2 Niederlagen',
                  ][index],
                  roundCount: 3 - index,
                  encounterCount: 7 - index * 2,
                  child: Text('Teilnehmer ${index + 1}'),
                ),
            ],
            finalChild: const Text('Finale'),
          ),
        ),
      ),
    ),
  );
}
