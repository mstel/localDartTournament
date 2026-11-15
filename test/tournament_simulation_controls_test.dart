import 'package:dart_tournament_manager/features/tournaments/application/tournament_run_simulation.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/tournament_simulation_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (width, height, textScale) in [
    (360.0, 800.0, 1.0),
    (800.0, 600.0, 1.0),
    (1440.0, 900.0, 1.0),
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
                    optionsEnabled: true,
                    completedSteps: 12,
                    totalSteps: 80,
                    elapsed: const Duration(minutes: 5, seconds: 15),
                    canUndo: true,
                    isComplete: false,
                    onNextStep: () {},
                    onUndo: () {},
                    onStop: () {},
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
        expect(tester.takeException(), isNull);
      },
    );
  }
}
