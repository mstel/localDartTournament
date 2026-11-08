import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/group_positions_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const clipboardText =
      'Gruppen: 2\n\nGruppe A:\nSpieler 3\nSpieler 4\n\nGruppe B:\nSpieler 1\nSpieler 2';

  GroupTournamentRunStage fixture() => GroupTournamentRunStage(
    name: 'Gruppen',
    groupPlayType: 'round_robin',
    qualificationPlan: null,
    tieBreakers: const [],
    groups: [
      for (var groupIndex = 0; groupIndex < 2; groupIndex++)
        TournamentGroup(
          name: 'Gruppe ${String.fromCharCode(65 + groupIndex)}',
          playType: 'round_robin',
          players: [
            for (var index = 0; index < 2; index++)
              TournamentPlayer(
                name: 'Spieler ${groupIndex * 2 + index + 1}',
                isGenerated: false,
              ),
          ],
          matches: const [],
        ),
    ],
  );

  Future<void> setClipboard(WidgetTester tester, String value) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') return {'text': value};
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  Future<void> tapApply(WidgetTester tester) async {
    final applyButton = find.text('Übernehmen');
    await tester.ensureVisible(applyButton);
    await tester.pumpAndSettle();
    await tester.tap(applyButton);
    await tester.pumpAndSettle();
  }

  testWidgets('loads ELO ratings only when strength allocation is requested', (
    tester,
  ) async {
    var ratingLoads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => GroupPositionsDialog(
                  stage: fixture(),
                  loadRatings: () async {
                    ratingLoads++;
                    return const {'spieler 1': 1200};
                  },
                ),
              ),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    expect(ratingLoads, 0);

    await tester.tap(
      find.byWidgetPredicate((widget) => widget is DropdownButtonFormField),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stärke ausgeglichen verteilen').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Neu einteilen'));
    await tester.pumpAndSettle();

    expect(ratingLoads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps edits open until confirmation at large text sizes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    final stage = GroupTournamentRunStage(
      name: 'Gruppen',
      groupPlayType: 'round_robin',
      qualificationPlan: null,
      tieBreakers: const [],
      groups: [
        for (var groupIndex = 0; groupIndex < 2; groupIndex++)
          TournamentGroup(
            name: 'Gruppe ${String.fromCharCode(65 + groupIndex)}',
            playType: 'round_robin',
            players: [
              for (var index = 0; index < 16; index++)
                TournamentPlayer(
                  name: 'Spieler ${groupIndex * 16 + index + 1}',
                  isGenerated: false,
                ),
            ],
            matches: const [],
          ),
      ],
    );
    GroupPositionsResult? result;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<GroupPositionsResult>(
                  context: context,
                  builder: (_) => GroupPositionsDialog(stage: stage),
                );
              },
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    expect(find.text('Gruppe A'), findsOneWidget);
    expect(find.text('Gruppe B'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Spieler 1'));
    await tester.tap(find.text('Spieler 17'));
    await tester.pumpAndSettle();

    expect(find.text('Gruppen neu einteilen'), findsOneWidget);
    expect(result, isNull);
    expect(find.text('Spieler 17'), findsOneWidget);
    expect(find.text('Spieler 1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tapApply(tester);

    expect(result!.assignments, hasLength(2));
    expect(result!.assignments[0].first.name, 'Spieler 17');
    expect(result!.assignments[1].first.name, 'Spieler 1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('supports drag-and-drop between groups', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    final stage = GroupTournamentRunStage(
      name: 'Gruppen',
      groupPlayType: 'round_robin',
      qualificationPlan: null,
      tieBreakers: const [],
      groups: [
        for (var groupIndex = 0; groupIndex < 2; groupIndex++)
          TournamentGroup(
            name: 'Gruppe ${String.fromCharCode(65 + groupIndex)}',
            playType: 'round_robin',
            players: [
              for (var index = 0; index < 4; index++)
                TournamentPlayer(
                  name: 'Spieler ${groupIndex * 4 + index + 1}',
                  isGenerated: false,
                ),
            ],
            matches: const [],
          ),
      ],
    );
    GroupPositionsResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<GroupPositionsResult>(
                  context: context,
                  builder: (_) => GroupPositionsDialog(stage: stage),
                );
              },
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();

    final source = tester.getCenter(find.text('Spieler 1'));
    final target = tester.getCenter(find.text('Spieler 5'));
    final gesture = await tester.startGesture(source);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(target);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.text('Gruppen neu einteilen'), findsOneWidget);
    await tapApply(tester);
    expect(result!.assignments[0].first.name, 'Spieler 5');
    expect(result!.assignments[1].first.name, 'Spieler 1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('imports a matching assignment without changing the stage yet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await setClipboard(tester, clipboardText);
    final stage = fixture();
    GroupPositionsResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<GroupPositionsResult>(
                  context: context,
                  builder: (_) => GroupPositionsDialog(stage: stage),
                );
              },
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zuweisung aus Zwischenablage übernehmen'));
    await tester.pumpAndSettle();

    expect(find.text('Spieler 3'), findsOneWidget);
    expect(stage.groups.first.players.first.name, 'Spieler 1');
    expect(result, isNull);

    await tapApply(tester);
    expect(result!.assignments.first.first.name, 'Spieler 3');
    expect(result!.assignments.last.first.name, 'Spieler 1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejects a mismatched assignment without changing groups', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await setClipboard(tester, 'Gruppen: 1\n\nGruppe A:\nFremder Spieler');
    final stage = fixture();
    GroupPositionsResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<GroupPositionsResult>(
                  context: context,
                  builder: (_) => GroupPositionsDialog(stage: stage),
                );
              },
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zuweisung aus Zwischenablage übernehmen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('enthält 1 Gruppen'), findsOneWidget);
    expect(stage.groups.first.players.first.name, 'Spieler 1');
    expect(result, isNull);
    expect(tester.takeException(), isNull);

    await tapApply(tester);
    expect(result!.assignments.first.first.name, 'Spieler 1');
    expect(result!.assignments.last.last.name, 'Spieler 4');
  });

  testWidgets('asks whether matching catalog names are profiles or locals', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await setClipboard(
      tester,
      'Gruppen: 2\n\nGruppe A:\nAda\nBert\n\nGruppe B:\nCem\nDora',
    );
    final stage = GroupTournamentRunStage(
      name: 'Gruppen',
      groupPlayType: 'round_robin',
      qualificationPlan: null,
      tieBreakers: const [],
      groups: [
        for (final names in [
          ['Ada', 'Bert'],
          ['Cem', 'Dora'],
        ])
          TournamentGroup(
            name: 'Gruppe',
            playType: 'round_robin',
            players: [
              for (final name in names)
                TournamentPlayer(name: name, isGenerated: false),
            ],
            matches: const [],
          ),
      ],
    );
    GroupPositionsResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<GroupPositionsResult>(
                  context: context,
                  builder: (_) => GroupPositionsDialog(
                    stage: stage,
                    loadCatalogProfiles: () async => [
                      PlayerProfile(
                        id: 'ada-profile',
                        displayName: 'Ada',
                        country: '',
                        city: '',
                        dartsSetupJson: '',
                        createdAt: DateTime(2026),
                        isActive: true,
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zuweisung aus Zwischenablage übernehmen'));
    await tester.pumpAndSettle();
    expect(
      find.text('Spieler aus dem Spielerkatalog verwenden'),
      findsOneWidget,
    );
    await tester.tap(find.text('Spieler aus dem Spielerkatalog verwenden'));
    await tester.pumpAndSettle();
    expect(find.text('Spieler 3'), findsNothing);
    expect(tester.takeException(), isNull);

    await tapApply(tester);
    expect(result!.playerReplacements.values.first.profileId, 'ada-profile');
  });

  for (final size in [const Size(360, 800), const Size(800, 600)]) {
    testWidgets('group editor adapts to $size with large text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<GroupPositionsResult>(
                  context: context,
                  builder: (_) => GroupPositionsDialog(stage: fixture()),
                ),
                child: const Text('Öffnen'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Öffnen'));
      await tester.pumpAndSettle();

      expect(
        find.text('Zuweisung aus Zwischenablage übernehmen'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
