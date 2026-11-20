import 'package:dart_tournament_manager/features/tournaments/application/group_end_review_service.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/second_screen_dialog_requests.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/tournament_second_screen_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CreatedTournament _tiedGroupTournament({
  QualificationPlan plan = const QualificationPlan(
    totalQualifiers: 1,
    fixedPerGroup: 1,
    extraCount: 0,
    extraRank: 0,
    eligibleGroupSize: null,
    extraGroups: [],
    fixedByGroup: [1],
  ),
}) {
  final a = TournamentPlayer.generated(1).copyWith(name: 'A');
  final b = TournamentPlayer.generated(2).copyWith(name: 'B');
  final group = TournamentGroup(
    name: 'Gruppe A',
    playType: 'round_robin',
    players: [a, b],
    matches: [
      GroupMatch(
        homePlayer: a,
        awayPlayer: b,
        round: 1,
        homeLegs: 1,
        awayLegs: 1,
      ),
    ],
  );
  return CreatedTournament(
    name: 'Gleichstand',
    players: [a, b],
    stages: const [
      TournamentStage(name: 'Gruppenphase', type: 'groups', groupSizes: [2]),
      TournamentStage(name: 'KO', type: 'single_knockout'),
    ],
    runStages: [
      GroupTournamentRunStage(
        name: 'Gruppenphase',
        groupPlayType: 'round_robin',
        groups: [group],
        qualificationPlan: plan,
        tieBreakers: defaultGroupTieBreakers,
      ),
      KnockoutTournamentRunStage(
        name: 'KO',
        rounds: [
          [GroupMatch(round: 1)],
        ],
      ),
    ],
  );
}

class _RecordingStorage extends TournamentStorage {
  _RecordingStorage(this.tournaments);

  final List<CreatedTournament> tournaments;
  int saveCount = 0;

  @override
  Future<void> saveTournament(CreatedTournament tournament) async {
    saveCount++;
    tournament.updatedAt = DateTime.now();
  }
}

void main() {
  group('GroupEndReviewService', () {
    test('acks are keyed by stage and result fingerprint', () {
      final tournament = _tiedGroupTournament();
      final stage = tournament.runStages.first as GroupTournamentRunStage;

      expect(
        GroupEndReviewService.isAcknowledged(tournament, 0, stage),
        isFalse,
      );
      GroupEndReviewService.acknowledge(tournament, 0, stage);
      expect(
        GroupEndReviewService.isAcknowledged(tournament, 0, stage),
        isTrue,
      );
      expect(
        GroupEndReviewService.isAcknowledged(tournament, 1, stage),
        isFalse,
      );

      final changed = _tiedGroupTournament();
      final changedStage = changed.runStages.first as GroupTournamentRunStage;
      changedStage.groups.first.matches.first.homeLegs = 2;
      expect(
        GroupEndReviewService.key(0, stage) ==
            GroupEndReviewService.key(0, changedStage),
        isFalse,
      );
      expect(
        GroupEndReviewService.isAcknowledged(changed, 0, changedStage),
        isFalse,
      );
    });

    test('detects ties and extra-place comparisons only when relevant', () {
      final tournament = _tiedGroupTournament();
      final stage = tournament.runStages.first as GroupTournamentRunStage;
      expect(
        GroupEndReviewService.hasTieOrComparison(tournament, stage),
        isTrue,
      );

      final resolved = _tiedGroupTournament();
      final resolvedStage = resolved.runStages.first as GroupTournamentRunStage;
      resolvedStage.groups.first.matches.first
        ..homeLegs = 2
        ..awayLegs = 0;
      expect(
        GroupEndReviewService.hasTieOrComparison(resolved, resolvedStage),
        isFalse,
      );

      final comparison = _tiedGroupTournament(
        plan: const QualificationPlan(
          totalQualifiers: 1,
          fixedPerGroup: 0,
          extraCount: 1,
          extraRank: 1,
          eligibleGroupSize: null,
          extraGroups: [1],
          fixedByGroup: [0],
        ),
      );
      final comparisonStage =
          comparison.runStages.first as GroupTournamentRunStage;
      comparisonStage.groups.first.matches.first
        ..homeLegs = 2
        ..awayLegs = 0;
      expect(
        GroupEndReviewService.hasTieOrComparison(comparison, comparisonStage),
        isTrue,
      );
    });

    test('acknowledgement round-trips through JSON', () {
      final tournament = _tiedGroupTournament();
      final stage = tournament.runStages.first as GroupTournamentRunStage;
      GroupEndReviewService.acknowledge(tournament, 0, stage);
      final restored = CreatedTournament.fromJson(tournament.toJson());
      expect(
        GroupEndReviewService.isAcknowledged(
          restored,
          0,
          restored.runStages.first as GroupTournamentRunStage,
        ),
        isTrue,
      );
    });

    test('clearing acknowledgements makes the review appear again', () {
      final tournament = _tiedGroupTournament();
      final stage = tournament.runStages.first as GroupTournamentRunStage;
      GroupEndReviewService.acknowledge(tournament, 0, stage);
      tournament.acknowledgedGroupEndReviews.add('stage:1|later-stage');
      final restored = CreatedTournament.fromJson(tournament.toJson());

      GroupEndReviewService.clearAcknowledgementsFrom(restored, 0);

      expect(restored.acknowledgedGroupEndReviews, {'stage:1|later-stage'});
      expect(
        GroupEndReviewService.isAcknowledged(
          restored,
          0,
          restored.runStages.first as GroupTournamentRunStage,
        ),
        isFalse,
      );
    });
  });

  group('SecondScreenGroupEndReviewRequest', () {
    test('hide keeps identity and round-trips through tournament JSON', () {
      final tournament = _tiedGroupTournament();
      final stage = tournament.runStages.first as GroupTournamentRunStage;
      final request = SecondScreenGroupEndReviewRequest.create(
        stageIndex: 0,
        reviewKey: GroupEndReviewService.key(0, stage),
      );
      tournament.secondScreenGroupEndReview = request;

      final hidden = request.hide();
      expect(hidden.id, request.id);
      expect(hidden.reviewKey, request.reviewKey);
      expect(hidden.visible, isFalse);

      tournament.secondScreenGroupEndReview = hidden;
      final restored = CreatedTournament.fromJson(tournament.toJson());
      expect(restored.secondScreenGroupEndReview, isNotNull);
      expect(restored.secondScreenGroupEndReview!.id, request.id);
      expect(restored.secondScreenGroupEndReview!.visible, isFalse);
      expect(
        restored.secondScreenGroupEndReview!.reviewKey,
        GroupEndReviewService.key(
          0,
          restored.runStages.first as GroupTournamentRunStage,
        ),
      );
    });
  });

  testWidgets('second monitor shows and persists the group end review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tournament = _tiedGroupTournament();
    final storage = _RecordingStorage([tournament]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            storage: storage,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('group-end-review-dialog')),
      findsOneWidget,
    );
    expect(find.textContaining('Gruppenphase beendet'), findsOneWidget);
    expect(find.textContaining('Matchpunkte: Sieg = 3 Punkte'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('group-end-review-acknowledge')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('group-end-review-dialog')), findsNothing);
    expect(storage.saveCount, 1);
    expect(tournament.acknowledgedGroupEndReviews, isNotEmpty);
    expect(
      GroupEndReviewService.isAcknowledged(
        tournament,
        0,
        tournament.runStages.first as GroupTournamentRunStage,
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'second monitor closes the review after main window acknowledgement',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tournament = _tiedGroupTournament();

      Widget buildView(CreatedTournament current) => MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: current,
            isStandaloneWindow: true,
            storage: _RecordingStorage([current]),
          ),
        ),
      );

      await tester.pumpWidget(buildView(tournament));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('group-end-review-dialog')),
        findsOneWidget,
      );

      // Das Hauptfenster bestätigt und speichert; der Monitor liest das Turnier
      // beim nächsten Poll als neue Instanz ein.
      GroupEndReviewService.acknowledge(
        tournament,
        0,
        tournament.runStages.first as GroupTournamentRunStage,
      );
      tournament.updatedAt = DateTime.now();
      final acknowledged = CreatedTournament.fromJson(tournament.toJson());

      await tester.pumpWidget(buildView(acknowledged));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('group-end-review-dialog')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'second monitor shows request dialog and cancel aborts without ack',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tournament = _tiedGroupTournament();
      final stage = tournament.runStages.first as GroupTournamentRunStage;
      tournament.secondScreenGroupEndReview =
          SecondScreenGroupEndReviewRequest.create(
            stageIndex: 0,
            reviewKey: GroupEndReviewService.key(0, stage),
          );
      final storage = _RecordingStorage([tournament]);

      Widget buildView(CreatedTournament current) => MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: current,
            isStandaloneWindow: true,
            storage: storage,
          ),
        ),
      );

      await tester.pumpWidget(buildView(tournament));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('group-end-review-dialog')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('group-end-review-cancel')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('group-end-review-dialog')),
        findsNothing,
      );
      expect(tournament.secondScreenGroupEndReview!.visible, isFalse);
      expect(tournament.acknowledgedGroupEndReviews, isEmpty);
      expect(storage.saveCount, 1);

      // Der verdeckte Request bleibt auch nach einem Reopen verschwunden.
      final reopened = CreatedTournament.fromJson(tournament.toJson());
      await tester.pumpWidget(buildView(reopened));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('group-end-review-dialog')),
        findsNothing,
      );

      // Ein echter neuer Abschluss erzeugt eine neue ID und zeigt den Dialog.
      final nextRequest = SecondScreenGroupEndReviewRequest.create(
        stageIndex: 0,
        reviewKey: GroupEndReviewService.key(0, stage),
      );
      final next = CreatedTournament.fromJson(tournament.toJson())
        ..secondScreenGroupEndReview = nextRequest;
      await tester.pumpWidget(buildView(next));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('group-end-review-dialog')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('second monitor acknowledges request and hides it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tournament = _tiedGroupTournament();
    final stage = tournament.runStages.first as GroupTournamentRunStage;
    final request = SecondScreenGroupEndReviewRequest.create(
      stageIndex: 0,
      reviewKey: GroupEndReviewService.key(0, stage),
    );
    tournament.secondScreenGroupEndReview = request;
    final storage = _RecordingStorage([tournament]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSecondScreenView(
            tournament: tournament,
            isStandaloneWindow: true,
            storage: storage,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('group-end-review-acknowledge')),
    );
    await tester.pumpAndSettle();

    expect(GroupEndReviewService.isAcknowledged(tournament, 0, stage), isTrue);
    expect(tournament.secondScreenGroupEndReview!.visible, isFalse);
    expect(storage.saveCount, 1);
    expect(tester.takeException(), isNull);
  });
}
