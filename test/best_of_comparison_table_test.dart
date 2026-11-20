import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/best_of_comparison_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TournamentGroup _group(
  String name,
  List<TournamentPlayer> players, {
  List<GroupMatch> matches = const [],
}) => TournamentGroup(
  name: name,
  playType: 'round_robin',
  players: players,
  matches: matches,
);

PlayerStanding _standing(
  TournamentPlayer player, {
  required int points,
  required int legsFor,
  required int legsAgainst,
}) => PlayerStanding(player)
  ..points = points
  ..legsFor = legsFor
  ..legsAgainst = legsAgainst
  ..played = 3
  ..wins = 1;

({
  GroupTournamentRunStage stage,
  Map<TournamentGroup, List<PlayerStanding>> standings,
})
_fixture({bool complete = true}) {
  final anna = TournamentPlayer(name: 'Anna', isGenerated: true);
  final berta = TournamentPlayer(name: 'Berta', isGenerated: true);
  final chris = TournamentPlayer(name: 'Chris', isGenerated: true);
  final dora = TournamentPlayer(name: 'Dora', isGenerated: true);
  final groupA = _group(
    'Gruppe A',
    [anna, berta],
    matches: complete
        ? const []
        : [GroupMatch(round: 1, homePlayer: anna, awayPlayer: berta)],
  );
  final groupB = _group(
    'Gruppe B',
    [chris, dora],
    matches: complete
        ? const []
        : [GroupMatch(round: 1, homePlayer: chris, awayPlayer: dora)],
  );
  final plan = QualificationPlan(
    totalQualifiers: 3,
    fixedPerGroup: 1,
    extraCount: 1,
    extraRank: 2,
    eligibleGroupSize: 2,
    extraGroups: const [1, 2],
    fixedByGroup: const [1, 1],
  );
  return (
    stage: GroupTournamentRunStage(
      name: 'Gruppenphase',
      groupPlayType: 'round_robin',
      groups: [groupA, groupB],
      qualificationPlan: plan,
      tieBreakers: const ['points', 'legDifference'],
    ),
    standings: {
      groupA: [
        _standing(anna, points: 12, legsFor: 12, legsAgainst: 6),
        _standing(berta, points: 8, legsFor: 10, legsAgainst: 9),
      ],
      groupB: [
        _standing(chris, points: 11, legsFor: 11, legsAgainst: 7),
        _standing(dora, points: 6, legsFor: 8, legsAgainst: 10),
      ],
    },
  );
}

Widget _wrap(Widget child, Brightness brightness) => MaterialApp(
  theme: ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF1565C0),
      brightness: brightness,
    ),
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

ColorScheme _scheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(DataTable))).colorScheme;

void main() {
  test('Gruppenkopf zeigt Spielstand und Weiterkommensregel', () {
    final fixture = _fixture();
    expect(groupMatchProgressLabel(fixture.stage.groups.first), '0/0');
    expect(
      groupAdvancementLabel(fixture.stage.qualificationPlan, 1),
      'Top 1 & bester 2. Platz',
    );
    expect(groupAdvancementLabel(null, 1), 'Top 2 weiter');

    final incomplete = _fixture(complete: false);
    expect(groupMatchProgressLabel(incomplete.stage.groups.first), '0/1');
  });

  testWidgets('showt dunkelgrüne Zeilen mit lesbarem Text im Lichtthema', (
    tester,
  ) async {
    final fixture = _fixture();
    await tester.pumpWidget(
      _wrap(
        BestOfComparisonTable(
          stage: fixture.stage,
          standingsByGroup: fixture.standings,
        ),
        Brightness.light,
      ),
    );

    final table = tester.widget<DataTable>(find.byType(DataTable));
    final scheme = _scheme(tester);
    expect(table.headingRowColor!.resolve({}), scheme.surfaceContainerHighest);
    expect(table.headingTextStyle!.color, scheme.onSurface);
    expect(table.dataTextStyle!.color, scheme.onSurface);
    expect(table.rows.first.color!.resolve({}), const Color(0xFF0B6B45));
    expect(table.dataRowMinHeight, 48);
    expect(tester.widget<Text>(find.text('Berta')).style?.color, Colors.white);
    // Nicht weiterkommende Kandidaten behalten den normalen Oberflächentext.
    expect(table.rows.last.color!.resolve({}), isNull);
    expect(tester.widget<Text>(find.text('Dora')).style, isNull);
  });

  testWidgets('showt dunkle Zeilen mit hellem Text im Dunkelthema', (
    tester,
  ) async {
    final fixture = _fixture();
    await tester.pumpWidget(
      _wrap(
        BestOfComparisonTable(
          stage: fixture.stage,
          standingsByGroup: fixture.standings,
        ),
        Brightness.dark,
      ),
    );

    final table = tester.widget<DataTable>(find.byType(DataTable));
    final scheme = _scheme(tester);
    expect(table.headingRowColor!.resolve({}), scheme.surfaceContainerHighest);
    expect(table.headingTextStyle!.color, scheme.onSurface);
    expect(table.dataTextStyle!.color, scheme.onSurface);
    expect(table.rows.first.color!.resolve({}), const Color(0xFF144D34));
    expect(
      tester.widget<Text>(find.text('Berta')).style?.color,
      const Color(0xFF86EFAC),
    );
  });

  testWidgets('offene Vergleiche nutzen kontrastreiche Farben', (tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final fixture = _fixture(complete: false);
      await tester.pumpWidget(
        _wrap(
          BestOfComparisonTable(
            stage: fixture.stage,
            standingsByGroup: fixture.standings,
          ),
          brightness,
        ),
      );
      // Der Theme-Wechsel von MaterialApp wird animiert.
      await tester.pump(const Duration(milliseconds: 300));
      final table = tester.widget<DataTable>(find.byType(DataTable));
      final rowColor = table.rows.first.color!.resolve({});
      final textColor = tester.widget<Text>(find.text('Berta')).style?.color;
      expect(_scheme(tester).brightness, brightness);
      if (brightness == Brightness.light) {
        expect(rowColor, const Color(0xFFD6F5E3));
        expect(textColor, const Color(0xFF064E3B));
      } else {
        expect(rowColor, const Color(0xFF163828));
        expect(textColor, const Color(0xFFA7F3D0));
      }
      for (final row in table.rows) {
        expect(row.color!.resolve({}), isNot(const Color(0xFFC8F7DC)));
      }
    }
  });
}
