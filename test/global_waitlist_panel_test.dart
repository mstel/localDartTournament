import 'package:dart_tournament_manager/features/tournaments/application/order_of_play/order_of_play_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_director_snapshot.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/global_waitlist_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CreatedTournament _tournament() {
  final players = [for (var i = 1; i <= 18; i++) TournamentPlayer.generated(i)];
  final groups = [
    for (var groupIndex = 0; groupIndex < 3; groupIndex++)
      TournamentGroup(
        name: 'Gruppe ${String.fromCharCode(65 + groupIndex)}',
        playType: 'round_robin',
        players: players.skip(groupIndex * 6).take(6).toList(),
        matches: [
          for (var home = groupIndex * 6; home < groupIndex * 6 + 6; home++)
            for (var away = home + 1; away < groupIndex * 6 + 6; away++)
              GroupMatch(
                homePlayer: players[home],
                awayPlayer: players[away],
                round: 1,
              ),
        ],
      ),
  ];
  final tournament =
      CreatedTournament(
          id: 'global-waitlist-panel-test',
          name: 'Warteliste',
          players: players,
          stages: const [],
          boardCount: 3,
          runStages: [
            GroupTournamentRunStage(
              name: 'Gruppenphase',
              groupPlayType: 'round_robin',
              qualificationPlan: null,
              tieBreakers: defaultGroupTieBreakers,
              groups: groups,
            ),
          ],
        )
        ..directorModeEnabled = true
        ..directorSchedulingStrategy = 'global'
        ..directorPlayOrderMode = 'dynamic';
  _initialize(tournament);
  return tournament;
}

void _initialize(CreatedTournament tournament) {
  const controller = OrderOfPlayController();
  final snapshot = TournamentDirectorSnapshot(tournament, 0);
  controller.initializeGlobalWaitlist(
    tournament,
    0,
    allEntries: snapshot.entries,
    schedule: snapshot.schedule,
    isPreviewable: snapshot.isPreviewableMatch,
  );
}

class _WaitlistHarness extends StatefulWidget {
  const _WaitlistHarness({required this.tournament});

  final CreatedTournament tournament;

  @override
  State<_WaitlistHarness> createState() => _WaitlistHarnessState();
}

class _WaitlistHarnessState extends State<_WaitlistHarness> {
  void _changeFixedCount(int count) {
    setState(() {
      widget.tournament.directorGlobalWaitlist.fixedCount = count;
      _initialize(widget.tournament);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: GlobalWaitlistPanel(
        snapshot: TournamentDirectorSnapshot(widget.tournament, 0),
        onFixedCountChanged: _changeFixedCount,
      ),
    ),
  );
}

void main() {
  testWidgets('fixed preview dropdown accepts odd counts and expands rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tournament = _tournament();

    await tester.pumpWidget(
      MaterialApp(home: _WaitlistHarness(tournament: tournament)),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('global-waitlist-entry-3')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('global-waitlist-entry-4')), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7 Begegnungen').last);
    await tester.pumpAndSettle();

    expect(tournament.directorGlobalWaitlist.fixedCount, 7);
    expect(tournament.directorGlobalWaitlist.fixedKeys(0), hasLength(7));
    expect(
      find.byKey(const ValueKey('global-waitlist-entry-7')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('global-waitlist-entry-6')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
