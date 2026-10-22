import 'package:dart_tournament_manager/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('group setup offers each supported allocation mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> reveal(Finder target) async {
      for (
        var attempt = 0;
        attempt < 8 && target.hitTestable().evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await tester.pumpAndSettle();
      }
    }

    await tester.pumpWidget(const DartTournamentApp());
    await tester.tap(find.text('Turnier erstellen'));
    await tester.pumpAndSettle();
    final create = find.text('Normales- oder Ranglistenturnier erstellen');
    await reveal(create);
    await tester.tap(create);
    await tester.pumpAndSettle();

    final workflow = find.text('2 · Turnierablauf');
    await reveal(workflow);
    await tester.tap(workflow);
    await tester.pumpAndSettle();
    await reveal(find.byKey(const ValueKey('group-count-field')));
    final groupOptions = find.text('Gruppenoptionen');
    await reveal(groupOptions);
    final allocation = find.byKey(const ValueKey('group-player-allocation'));
    await reveal(allocation);
    await tester.tap(allocation);
    await tester.pumpAndSettle();

    expect(find.text('Wertungsstufen bündeln'), findsWidgets);
    expect(find.text('Stärken gleichmäßig verteilen'), findsWidgets);
    expect(find.textContaining('Zufällig verteilen'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
