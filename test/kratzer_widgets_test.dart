import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/main.dart';

void main() {
  testWidgets(
    'creation configures Kratzer board size without draw or bracket controls',
    (tester) async {
      await tester.pumpWidget(const DartTournamentApp());
      await tester.tap(find.text('Turnier erstellen'));
      await tester.pumpAndSettle();
      final normal = find.text('Normales- oder Ranglistenturnier erstellen');
      if (normal.evaluate().isNotEmpty) {
        await tester.ensureVisible(normal);
        await tester.tap(normal);
        await tester.pumpAndSettle();
      }
      final workflow = find.text('2 · Turnierstruktur');
      for (
        var attempt = 0;
        attempt < 8 && workflow.hitTestable().evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.widgetWithText(TextField, 'Anzahl'), '4');
      final generatePlayers = find.text('Teilnehmer erzeugen');
      for (
        var attempt = 0;
        attempt < 8 && generatePlayers.hitTestable().evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Teilnehmer erzeugen'));
      await tester.pumpAndSettle();
      for (
        var attempt = 0;
        attempt < 8 && workflow.hitTestable().evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      await tester.tap(workflow);
      await tester.pumpAndSettle();
      final type = find.byKey(const ValueKey('stage-type-field'));
      for (
        var attempt = 0;
        attempt < 12 && type.hitTestable().evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(type);
      await tester.pumpAndSettle();
      await tester.tap(type.hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Doppel-KO').last);
      await tester.pumpAndSettle();
      expect(find.text('Auslosungsrad beim Turnierstart'), findsNothing);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('final-ends-tournament')),
            )
            .value,
        isTrue,
      );
      final finalEndsToggle = find.byKey(
        const ValueKey('final-ends-tournament'),
      );
      for (
        var attempt = 0;
        attempt < 8 && finalEndsToggle.hitTestable().evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      await tester.tap(finalEndsToggle.hitTestable());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('kratzer-lives-3')), findsNothing);
      for (
        var attempt = 0;
        attempt < 8 && type.hitTestable().evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(ListView).last, const Offset(0, 300));
        await tester.pumpAndSettle();
      }
      await tester.tap(type.hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kratzer-Modus').last);
      await tester.pumpAndSettle();
      final lives = find.byKey(const ValueKey('kratzer-lives-3'));
      for (
        var attempt = 0;
        attempt < 8 && lives.hitTestable().evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      await tester.tap(lives);
      await tester.pumpAndSettle();
      await tester.tap(find.text('5 Leben').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('kratzer-lives-5')), findsOneWidget);
      final distribution = find.byKey(
        const ValueKey('kratzer-board-distribution-balanced'),
      );
      await tester.ensureVisible(distribution);
      expect(distribution, findsOneWidget);
      await tester.tap(distribution);
      await tester.pumpAndSettle();
      await tester.tap(find.text('4 Teilnehmer').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('kratzer-board-distribution-4')),
        findsOneWidget,
      );
      final sameScratches = find.byKey(
        const ValueKey('kratzer-prefer-same-scratches'),
      );
      await tester.ensureVisible(sameScratches);
      await tester.tap(sameScratches);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(sameScratches).value, isTrue);
      final playUntilElimination = find.byKey(
        const ValueKey('kratzer-play-until-elimination'),
      );
      await tester.ensureVisible(playUntilElimination);
      await tester.tap(playUntilElimination);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(playUntilElimination).value, isTrue);
      final specialRules = find.byKey(const ValueKey('kratzer-special-rules'));
      await tester.ensureVisible(specialRules);
      await tester.tap(specialRules);
      await tester.pumpAndSettle();
      final bonus180 = find.byKey(const ValueKey('kratzer-bonus-life-180'));
      await tester.ensureVisible(bonus180);
      await tester.tap(bonus180);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(bonus180).value, isTrue);
      final bonusHighFinish = find.byKey(
        const ValueKey('kratzer-bonus-life-high-finish'),
      );
      await tester.ensureVisible(bonusHighFinish);
      await tester.tap(bonusHighFinish);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(bonusHighFinish).value, isTrue);
      expect(
        find.byKey(const ValueKey('kratzer-handicaps-enabled')),
        findsOneWidget,
      );
      final startScratches = find.byKey(
        const ValueKey('kratzer-starting-scratches'),
      );
      await tester.ensureVisible(startScratches);
      await tester.tap(startScratches);
      await tester.pumpAndSettle();
      final firstPlayerScratches = find.byKey(
        const ValueKey('kratzer-start-scratches-0'),
      );
      await tester.ensureVisible(firstPlayerScratches);
      await tester.tap(firstPlayerScratches);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 Kratzer').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<int>>(firstPlayerScratches)
            .initialValue,
        2,
      );
      expect(find.text('Auslosungsrad beim Turnierstart'), findsNothing);
      expect(find.text('4 Weiter'), findsNothing);
      expect(find.text('4er Feld'), findsNothing);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final size in [
        const Size(360, 800),
        const Size(800, 600),
        const Size(1440, 900),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('kratzer-board-distribution-4')),
        );
        expect(
          find.byKey(const ValueKey('kratzer-board-distribution-4')),
          findsOneWidget,
          reason: 'Kratzer-Auswahl bei $size',
        );
        await tester.ensureVisible(startScratches);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
