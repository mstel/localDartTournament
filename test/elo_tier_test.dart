import 'dart:io';

import 'package:dart_tournament_manager/features/rankings/domain/elo_tier.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/rankings/presentation/rankings_page.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'custom Elo tier bands persist with a ranking and classify ratings',
    () async {
      final directory = await Directory.systemTemp.createTemp('elo-tier-test-');
      addTearDown(() => directory.delete(recursive: true));
      final database = LocalAppDatabase(baseDirectory: directory);
      final ranking = LocalRanking(
        id: 'custom-tiers',
        name: 'Custom',
        enableTiers: true,
        tierBands: [
          EloTier.styled(name: 'Elite', minElo: 1500, index: 0),
          EloTier.styled(name: 'Club', minElo: 1000, index: 1),
          EloTier.styled(name: 'Entry', minElo: 0, index: 2),
        ],
      );

      await database.saveLocalRanking(ranking);
      final loaded = (await database.loadLocalRankings()).single;

      expect(
        loaded.effectiveTierBands.map((tier) => (tier.name, tier.minElo)),
        [('Elite', 1500), ('Club', 1000), ('Entry', 0)],
      );
      expect(
        EloTier.fromElo(1600, tiers: loaded.effectiveTierBands).name,
        'Elite',
      );
      expect(
        EloTier.fromElo(1200, tiers: loaded.effectiveTierBands).name,
        'Club',
      );
      expect(
        EloTier.fromElo(999, tiers: loaded.effectiveTierBands).name,
        'Entry',
      );
    },
  );

  test('legacy rankings retain the default tier bands', () {
    final ranking = LocalRanking.fromJson({'id': 'legacy', 'name': 'Legacy'});

    expect(ranking.tierBands, isNull);
    expect(ranking.effectiveTierBands.map((tier) => (tier.name, tier.minElo)), [
      ('Diamant', 1200),
      ('Platin', 1100),
      ('Gold', 1000),
      ('Silber', 900),
      ('Bronze', 0),
    ]);
  });

  testWidgets('ranking settings can rename, edit, and add Elo tiers', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'elo-tier-editor-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = LocalAppDatabase(baseDirectory: directory);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(home: RankingsPage(database: database)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField).first, 'Vereinsrangliste');
    final enableTiers = find.widgetWithText(
      SwitchListTile,
      'Auf- & Abstiegssystem (Elo-Tiers)',
    );
    await tester.ensureVisible(enableTiers);
    await tester.tap(enableTiers);
    await tester.pump(const Duration(milliseconds: 500));

    Finder tierField(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
    await tester.enterText(tierField('Tier 1'), 'Spitze');
    await tester.enterText(tierField('Ab Elo').first, '1300');
    final addTierButton = find.text('Tier hinzufügen');
    await tester.ensureVisible(addTierButton);
    await tester.tap(addTierButton);
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester.widget<TextField>(tierField('Tier 1')).controller!.text,
      'Neues Tier',
    );
    expect(
      tester.widget<TextField>(tierField('Tier 2')).controller!.text,
      'Spitze',
    );
    final eloBounds = tierField('Ab Elo')
        .evaluate()
        .map((element) => (element.widget as TextField).controller!.text)
        .toList();
    expect(eloBounds.take(2), ['1400', '1300']);
    await tester.tap(find.text('Abbrechen'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
