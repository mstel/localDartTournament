import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/app/app_theme.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/group_stage_run_section.dart';

void main() {
  testWidgets(
    'mobile group selection survives resize and hides finished matches',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.reset);
      final anna = TournamentPlayer.generated(1);
      final ben = TournamentPlayer.generated(2);
      final finished = GroupMatch(homePlayer: anna, awayPlayer: ben, round: 2)
        ..homeLegs = 3
        ..awayLegs = 1;
      final stage = GroupTournamentRunStage(
        name: 'Gruppenphase',
        groupPlayType: 'round_robin',
        qualificationPlan: null,
        tieBreakers: defaultGroupTieBreakers,
        groups: [
          for (final name in ['Gruppe A', 'Gruppe B'])
            TournamentGroup(
              name: name,
              playType: 'round_robin',
              players: [anna, ben],
              matches: [
                GroupMatch(homePlayer: anna, awayPlayer: ben, round: 1),
                finished,
              ],
            ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDartTournamentTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: GroupStageRunSection(
                stage: stage,
                standingsFor: (_, _) => [],
                onEditResult: (_) {},
                canEditResults: true,
                miniKnockoutBracketBuilder: (_, _, _, _) => const SizedBox(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Offene Spiele'), findsOneWidget);
      expect(find.text('Runde 1'), findsOneWidget);
      expect(find.text('Runde 2').hitTestable(), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gruppe B').last);
      await tester.pumpAndSettle();
      for (final size in [const Size(1440, 900), const Size(360, 800)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(
        tester
            .widget<DropdownButtonFormField<int>>(
              find.byType(DropdownButtonFormField<int>),
            )
            .initialValue,
        1,
      );
      await tester.scrollUntilVisible(
        find.text('Abgeschlossene Spiele (1)'),
        150,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('Abgeschlossene Spiele (1)')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abgeschlossene Spiele (1)'));
      await tester.pumpAndSettle();
      expect(find.text('3:1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
