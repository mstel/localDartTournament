import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart';

void main() {
  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('optional group phase at $size with large text', (
      tester,
    ) async {
      Future<void> reveal(Finder target) async {
        for (
          var attempt = 0;
          attempt < 20;
          attempt++
        ) {
          final scrollable = find
              .ancestor(of: target, matching: find.byType(Scrollable))
              .first;
          final position = tester.state<ScrollableState>(scrollable).position;
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          if (target.hitTestable().evaluate().isNotEmpty) break;
          position.jumpTo(
            (position.pixels + 120).clamp(0, position.maxScrollExtent),
          );
          await tester.pumpAndSettle();
        }
        final scrollable = find
            .ancestor(of: target, matching: find.byType(Scrollable))
            .first;
        final position = tester.state<ScrollableState>(scrollable).position;
        expect(
          target.hitTestable(),
          findsOneWidget,
          reason:
              'Target rect ${tester.getRect(target)}; scroll ${position.pixels}/${position.maxScrollExtent}, viewport ${position.viewportDimension}.',
        );
      }

      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(body: TournamentFormatPlannerDialog()),
        ),
      );
      await tester.ensureVisible(find.text('Turnierformen'));
      await tester.tap(find.text('Turnierformen'));
      await tester.pumpAndSettle();
      final option = find.byKey(const ValueKey('planner-require-groups'));
      final mode = find.byKey(
        const ValueKey('planner-mode-groups:round_robin'),
      );
      expect(mode, findsOneWidget);
      await reveal(mode);
      expect(tester.widget<CheckboxListTile>(mode).value, isTrue);
      await tester.tap(mode.hitTestable());
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(mode).value, isFalse);
      final section = find.text('Aufbau & Gruppen');
      await reveal(section);
      await tester.tap(section.hitTestable());
      await tester.pumpAndSettle();
      await reveal(option);
      expect(tester.widget<SwitchListTile>(option).value, isFalse);
      await tester.tap(option.hitTestable());
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(option).value, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
