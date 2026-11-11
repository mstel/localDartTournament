import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/shared/widgets/adaptive_content.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/stage_controls.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Navigation and content at $size, text $scale', (
        tester,
      ) async {
        tester.view.reset();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        StageViewMode selected = StageViewMode.dashboard;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: Column(
                  children: [
                    StageViewModeSwitch(
                      selectedMode: selected,
                      onModeChanged: (mode) => setState(() => selected = mode),
                    ),
                    Expanded(
                      child: AdaptiveContentList(
                        children: [
                          AdaptiveTileLayout(
                            children: [
                              for (var i = 0; i < 8; i++)
                                Card(
                                  child: ListTile(
                                    title: Text('Bereich $i'),
                                    subtitle: const Text(
                                      'Lange Beschreibung einer Turnierverwaltung mit mehreren Funktionen.',
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const TextField(
                            decoration: InputDecoration(
                              labelText: 'Turniername',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (size.width < 840 * scale) {
          await tester.tap(find.byType(DropdownButtonFormField<StageViewMode>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Partien & Ergebnisse').last);
        } else {
          await tester.tap(find.text('Partien & Ergebnisse'));
        }
        await tester.pumpAndSettle();
        expect(selected, StageViewMode.results);
        await tester.scrollUntilVisible(
          find.byType(TextField),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(find.byType(TextField), 'Testturnier');
        expect(find.text('Testturnier'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
