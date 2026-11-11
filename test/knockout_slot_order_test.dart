import 'package:dart_tournament_manager/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('random knockout slots stay stable across form rebuilds', (
    tester,
  ) async {
    await tester.pumpWidget(const DartTournamentApp());
    await tester.tap(find.text('Turnier erstellen'));
    await tester.pumpAndSettle();

    final normal = find.text('Normales- oder Ranglistenturnier erstellen');
    if (normal.evaluate().isNotEmpty) {
      await tester.tap(normal);
      await tester.pumpAndSettle();
    }

    await tester.enterText(find.widgetWithText(TextField, 'Anzahl'), '8');
    final scrollable = find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first;
    final generatePlayers = find.text('Teilnehmer erzeugen');
    await tester.scrollUntilVisible(
      generatePlayers,
      400,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(generatePlayers);
    await tester.pumpAndSettle();

    final workflow = find.text('2 · Turnierstruktur');
    await tester.scrollUntilVisible(workflow, 400, scrollable: scrollable);
    await tester.pumpAndSettle();
    if (find.byKey(const ValueKey('stage-type-field')).evaluate().isEmpty) {
      await tester.tap(workflow);
      await tester.pumpAndSettle();
    }

    final stageType = find.byKey(const ValueKey('stage-type-field'));
    await tester.scrollUntilVisible(stageType, 400, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(stageType);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Doppel-KO').last);
    await tester.pumpAndSettle();

    List<String?> previewPlayers() {
      final preview = find.byKey(const ValueKey('knockout-preview'));
      return tester
          .widgetList<Text>(
            find.descendant(of: preview, matching: find.byType(Text)),
          )
          .map((text) => text.data)
          .where((text) => text != null && text.startsWith('Platz '))
          .toList();
    }

    final firstOrder = previewPlayers();
    expect(firstOrder, hasLength(8));

    final finalToggle = find.byKey(const ValueKey('final-ends-tournament'));
    await tester.ensureVisible(finalToggle);
    await tester.tap(finalToggle);
    await tester.pumpAndSettle();

    expect(previewPlayers(), firstOrder);
  });
}
