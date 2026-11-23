import 'package:dart_tournament_manager/features/settings/data/general_defaults_storage.dart';
import 'package:dart_tournament_manager/features/settings/presentation/general_defaults_panel.dart';
import 'package:dart_tournament_manager/features/settings/presentation/settings_page.dart';
import 'package:dart_tournament_manager/features/league/presentation/league_match_page.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<bool> _scrollUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 8; i++) {
    if (finder.evaluate().isNotEmpty) return true;
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
  }
  return finder.evaluate().isNotEmpty;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('general defaults are versioned and validate stored board counts', () async {
    const storage = GeneralDefaultsStorage();
    expect((await storage.load()).defaultBoardCount, 4);
    await storage.save(const GeneralDefaults(defaultBoardCount: 6));
    expect(
      (await const GeneralDefaultsStorage().load()).defaultBoardCount,
      6,
    );

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('general_defaults'),
      '{"schemaVersion":1,"defaultBoardCount":6}',
    );

    await preferences.setString(
      'general_defaults',
      '{"schemaVersion":99,"defaultBoardCount":6}',
    );
    await expectLater(storage.load(), throwsFormatException);

    await preferences.setString(
      'general_defaults',
      '{"schemaVersion":1,"defaultBoardCount":0}',
    );
    await expectLater(storage.load(), throwsFormatException);
  });

  testWidgets('the general defaults panel edits the board count', (tester) async {
    const storage = GeneralDefaultsStorage();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: GeneralDefaultsPanel(storage: storage))),
    );
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('general-default-board-count'));
    expect(tester.widget<TextFormField>(field).controller?.text, '4');
    await tester.enterText(field, '7');
    await tester.tap(find.byKey(const ValueKey('general-defaults-save')));
    await tester.pumpAndSettle();

    expect((await storage.load()).defaultBoardCount, 7);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: GeneralDefaultsPanel(storage: storage))),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(field).controller?.text, '7');
  });

  testWidgets('settings has Standardwerte and Tools sections', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    final chips = find.byType(ChoiceChip);
    expect(chips, findsNWidgets(5));
    final labels = chips
        .evaluate()
        .map((element) => (element.widget as ChoiceChip).label as Text)
        .map((label) => label.data)
        .toList();
    expect(labels, ['Daten', 'Updates', 'Darstellung', 'Standardwerte', 'Tools']);
    expect(find.text('Sonstige Einstellungen'), findsNothing);

    await tester.tap(chips.at(3));
    await tester.pumpAndSettle();
    expect(find.text('Allgemein'), findsOneWidget);
    expect(find.text('PDF-Spielplan Einstellungen'), findsOneWidget);
    final general = tester.getTopLeft(find.text('Allgemein'));
    final pdf = tester.getTopLeft(find.text('PDF-Spielplan Einstellungen'));
    expect(general.dy, lessThan(pdf.dy));
    for (final title in [
      'Insights Standardwerte',
      'Turnierleitermodus',
      'Passende Turnierform finden',
    ]) {
      expect(
        await _scrollUntilFound(tester, find.text(title)),
        isTrue,
        reason: title,
      );
    }

    await tester.tap(find.byType(ChoiceChip).at(4));
    await tester.pumpAndSettle();
    expect(find.text('Auslosungsrad'), findsOneWidget);
    expect(find.text('Team Game'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the stored board count prefills all three creation paths', (
    tester,
  ) async {
    await const GeneralDefaultsStorage().save(
      const GeneralDefaults(defaultBoardCount: 6),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TournamentFormatPlannerDialog())),
    );
    await tester.pumpAndSettle();
    final plannerField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Anzahl Boards',
    );
    expect(tester.widget<TextField>(plannerField).controller?.text, '6');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      const MaterialApp(home: TournamentCreationPage(skipEntryChoices: true)),
    );
    await tester.pumpAndSettle();
    expect(
      await _scrollUntilFound(tester, find.textContaining('6 Boards')),
      isTrue,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const MaterialApp(home: LeagueMatchPage()));
    await tester.pumpAndSettle();
    final leagueBoards = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<int> &&
          widget.decoration.labelText == 'Boards',
    );
    expect(await _scrollUntilFound(tester, leagueBoards), isTrue);
    expect(
      tester.widget<DropdownButtonFormField<int>>(leagueBoards.first)
          .initialValue,
      6,
    );

    expect(tester.takeException(), isNull);
  });
}
