import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show TournamentFormatPlannerDialog;
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_format_planner.dart';

void main() {
  const planner = TournamentFormatPlanner();
  TournamentPlanningRequest request(int? target, {int minimum = 1}) =>
      TournamentPlanningRequest(
        players: 12,
        boards: 3,
        minimumMatchesPerPlayer: minimum,
        minimumMinutes: 1,
        maximumMinutes: 2,
        targetMinutes: target,
        x01Selection: '501',
        checkoutType: 'double_out',
      );

  testWidgets('planner accepts any final format as the initial preference', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TournamentFormatPlannerDialog(initialPreferredFinalStage: null),
      ),
    );

    final preference = tester.widget<DropdownButtonFormField<String?>>(
      find.byKey(
        const ValueKey('planner-preferred-final-stage'),
        skipOffstage: false,
      ),
    );
    expect(preference.initialValue, isNull);
  });

  test('target replaces window and sorts by absolute distance', () {
    for (final target in [90, 180, 300]) {
      final results = planner.suggestFormats(request(target));
      expect(results, isNotEmpty);
      final distances = results
          .map((s) => (s.estimatedMinutes - target).abs())
          .toList();
      expect(distances, orderedEquals([...distances]..sort()));
      expect(results.every((s) => !s.isClosestAlternative), isTrue);
      expect(results.first.estimatedMinutes, greaterThan(2));
    }
  });

  test('target preserves minimum games when feasible', () {
    final results = planner.suggestFormats(request(180, minimum: 5));
    expect(results, isNotEmpty);
    expect(results.every((s) => s.minimumMatchesPerPlayer >= 5), isTrue);
  });

  test('window fallback is unchanged; invalid targets are rejected', () {
    expect(
      planner
          .suggestFormats(request(null))
          .every((s) => s.isClosestAlternative),
      isTrue,
    );
    expect(planner.suggestFormats(request(0)), isEmpty);
    expect(planner.suggestFormats(request(-1)), isEmpty);
  });

  testWidgets('planner pre-fills an adjusted tournament target duration', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TournamentFormatPlannerDialog(
          initialPlayerCount: 7,
          initialBoardCount: 3,
          initialTargetMinutes: 150,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('planner-min-duration')), findsOneWidget);
    expect(find.byKey(const ValueKey('planner-max-duration')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('planner-target-duration')),
      findsOneWidget,
    );
    expect(find.textContaining('2 Std. 30 Min.'), findsOneWidget);
    expect(find.text('2 Std. 00 Min.'), findsOneWidget);
    expect(find.text('4 Std. 00 Min.'), findsOneWidget);
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields[0].controller!.text, '7');
    expect(fields[1].controller!.text, '3');
    expect(tester.takeException(), isNull);
  });

  testWidgets('best/worst case resets an active target duration', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TournamentFormatPlannerDialog(
          initialPlayerCount: 7,
          initialTargetMinutes: 150,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('planner-best-worst-case')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('planner-best-worst-case')),
          )
          .value,
      isTrue,
    );
    expect(find.textContaining('3 Std. 00 Min.'), findsOneWidget);
    expect(find.textContaining('2 Std. 00 Min.'), findsOneWidget);
    expect(find.textContaining('4 Std. 00 Min.'), findsOneWidget);
  });
}
