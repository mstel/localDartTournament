import 'package:dart_tournament_manager/features/achievements/presentation/achievement_target_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fits mobile, tablet and desktop at large text scale', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [
      const Size(360, 800),
      const Size(800, 600),
      const Size(1440, 900),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const ValueKey('open-responsive-dialog'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AchievementTargetDialog(targets: {}),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-responsive-dialog')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Viewport $size');
      await tester.tap(find.text('Standard wiederherstellen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wiederherstellen'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('saves adjusted thresholds and can restore defaults', (
    tester,
  ) async {
    Map<String, double>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Builder(
              builder: (dialogContext) => TextButton(
                key: const ValueKey('open-dialog'),
                onPressed: () async {
                  result = await showDialog<Map<String, double>>(
                    context: dialogContext,
                    builder: (_) => const AchievementTargetDialog(targets: {}),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-dialog')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turniererfolge'));
    await tester.pumpAndSettle();
    final targetField = find.byKey(
      const ValueKey('achievement-target-tournament_participation_5'),
    );
    await tester.enterText(targetField, '20');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(result, {'tournament_participation_5': 20});

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('open-dialog'),
              onPressed: () async {
                result = await showDialog<Map<String, double>>(
                  context: context,
                  builder: (_) => const AchievementTargetDialog(
                    targets: {'tournament_participation_5': 20},
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    result = null;
    await tester.tap(find.byKey(const ValueKey('open-dialog')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Standard wiederherstellen'));
    await tester.pumpAndSettle();
    expect(find.text('Standardwerte wiederherstellen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.text('Achievement-Werte anpassen'), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.text('Standard wiederherstellen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wiederherstellen'));
    await tester.pumpAndSettle();
    expect(result, isEmpty);
  });

  testWidgets('updates helper description when an achievement target changes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('open-dialog'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AchievementTargetDialog(targets: {}),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-dialog')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spielbetrieb'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('achievement-target-legs_won_10'));
    await tester.enterText(field, '9');
    await tester.pumpAndSettle();

    expect(find.text('Gewinne insgesamt 9 Legs.'), findsOneWidget);
  });
}
