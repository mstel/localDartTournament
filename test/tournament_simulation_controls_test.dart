import 'package:dart_tournament_manager/features/tournaments/application/tournament_run_simulation.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/tournament_simulation_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (width, height, textScale) in [
    (360.0, 800.0, 1.0),
    (800.0, 600.0, 1.0),
    (1440.0, 900.0, 1.0),
    (800.0, 600.0, 2.0),
    (1440.0, 900.0, 2.0),
    (360.0, 800.0, 2.0),
  ]) {
    testWidgets(
      'simulation controls fit ${width.toInt()}x${height.toInt()} at ${textScale}x text',
      (tester) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final seed = TextEditingController(text: '42');
        final minimum = TextEditingController(text: '4');
        final maximum = TextEditingController(text: '15');
        addTearDown(seed.dispose);
        addTearDown(minimum.dispose);
        addTearDown(maximum.dispose);

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: ListView(
                children: [
                  TournamentSimulationControls(
                    mode: TournamentSimulationMode.randomStep,
                    onModeChanged: (_) {},
                    seedController: seed,
                    minimumMinutesController: minimum,
                    maximumMinutesController: maximum,
                    autoStartMatches: true,
                    onAutoStartMatchesChanged: (_) {},
                    optionsEnabled: true,
                    completedSteps: 12,
                    totalSteps: 80,
                    elapsed: const Duration(minutes: 5, seconds: 15),
                    canUndo: true,
                    isComplete: false,
                    eventLog: const ['00:00 · Simulation gestartet.'],
                    onNextStep: () {},
                    onUndo: () {},
                    onStop: () {},
                    onReset: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Simulationsschritt 12 / 80 · Simulationszeit 05:15'),
          findsOneWidget,
        );
        expect(find.text('Nächster Schritt'), findsOneWidget);
        expect(
          find.text('Partien automatisch auf aktiv stellen'),
          findsOneWidget,
        );
        expect(find.text('Simulations-Log'), findsOneWidget);
        expect(find.text('Simulation zurücksetzen'), findsOneWidget);
        final logContainer = tester.widget<Container>(
          find.byKey(const ValueKey('tournament-simulation-log')),
        );
        expect(
          (logContainer.decoration! as BoxDecoration).color,
          Theme.of(
            tester.element(
              find.byKey(const ValueKey('tournament-simulation-log')),
            ),
          ).colorScheme.surface,
        );
        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const ValueKey('simulation-auto-start-toggle')),
              )
              .value,
          isTrue,
        );
        if (width >= 1440) {
          expect(
            tester.getRect(find.text('Turniersimulation')).center.dx,
            lessThan(tester.getRect(find.text('Simulations-Log')).center.dx),
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('automatic start toggle and reset invoke their callbacks', (
    tester,
  ) async {
    var autoStart = true;
    var resets = 0;
    final seed = TextEditingController(text: '42');
    final minimum = TextEditingController(text: '4');
    final maximum = TextEditingController(text: '15');
    addTearDown(seed.dispose);
    addTearDown(minimum.dispose);
    addTearDown(maximum.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              TournamentSimulationControls(
                mode: TournamentSimulationMode.fixedStep,
                onModeChanged: (_) {},
                seedController: seed,
                minimumMinutesController: minimum,
                maximumMinutesController: maximum,
                autoStartMatches: autoStart,
                onAutoStartMatchesChanged: (value) => autoStart = value,
                optionsEnabled: true,
                completedSteps: 0,
                totalSteps: 2,
                elapsed: Duration.zero,
                canUndo: false,
                isComplete: false,
                eventLog: const ['00:00 · Simulation gestartet.'],
                onNextStep: () {},
                onUndo: () {},
                onStop: () {},
                onReset: () => resets++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final autoStartToggle = find.byKey(
      const ValueKey('simulation-auto-start-toggle'),
    );
    await tester.ensureVisible(autoStartToggle);
    await tester.tap(autoStartToggle);
    await tester.pumpAndSettle();
    expect(autoStart, isFalse);
    final resetButton = find.byKey(const ValueKey('simulation-reset-button'));
    await tester.ensureVisible(resetButton);
    await tester.tap(resetButton);
    expect(resets, 1);
    expect(tester.takeException(), isNull);
  });
}
