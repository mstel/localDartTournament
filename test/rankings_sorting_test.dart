import 'dart:io';

import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/rankings/presentation/rankings_page.dart';
import 'package:dart_tournament_manager/features/rankings/application/ranking_order.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/shared/persistence/storage_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ranking sort modes and custom order are easy to change', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('ranking_sorting_widget_test_'),
    ))!;
    addTearDown(() => tester.runAsync(() => directory.delete(recursive: true)));
    final database = LocalAppDatabase(baseDirectory: directory);

    await tester.runAsync(() async {
      await database.saveLocalRanking(
        const LocalRanking(
          id: 'ranking-2026',
          name: 'Unzenberg 2026',
          validFromYear: 2026,
        ),
      );
      await database.saveLocalRanking(
        const LocalRanking(
          id: 'ranking-2024',
          name: 'Unzenberg 2024',
          validFromYear: 2024,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: RankingsPage(database: database)),
      );
      await StorageAccess.run(() async {});
    });
    await _pumpRankingPage(tester);
    expect(
      tester.getTopLeft(find.text('Unzenberg 2024')).dy,
      lessThan(tester.getTopLeft(find.text('Unzenberg 2026')).dy),
    );

    await _chooseSortMode(tester, 'Startjahr absteigend');
    expect(
      tester.getTopLeft(find.text('Unzenberg 2026')).dy,
      lessThan(tester.getTopLeft(find.text('Unzenberg 2024')).dy),
    );

    await _chooseSortMode(tester, 'Benutzerdefiniert');
    expect(
      tester.getTopLeft(find.text('Unzenberg 2026')).dy,
      lessThan(tester.getTopLeft(find.text('Unzenberg 2024')).dy),
    );
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Nach unten verschieben').first);
      await StorageAccess.run(() async {});
    });
    await tester.pump(const Duration(milliseconds: 300));

    final reopened = (await tester.runAsync(
      () => LocalAppDatabase(baseDirectory: directory).loadLocalRankings(),
    ))!;
    expect(reopened.map((ranking) => ranking.id), [
      'ranking-2024',
      'ranking-2026',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom reordering controls fit on a phone at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('ranking_sorting_mobile_test_'),
    ))!;
    addTearDown(() => tester.runAsync(() => directory.delete(recursive: true)));
    final database = LocalAppDatabase(baseDirectory: directory);
    await tester.runAsync(() async {
      await database.saveLocalRanking(
        const LocalRanking(id: 'one', name: 'Rangliste Eins'),
      );
      await database.saveLocalRanking(
        const LocalRanking(id: 'two', name: 'Rangliste Zwei'),
      );

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: RankingsPage(database: database),
        ),
      );
      await StorageAccess.run(() async {});
    });
    await tester.pump(const Duration(milliseconds: 300));
    await _chooseSortMode(tester, 'Benutzerdefiniert');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _chooseSortMode(WidgetTester tester, String label) async {
  final field = find.byType(DropdownButtonFormField<RankingSortMode>);
  await tester.ensureVisible(field);
  await tester.pump();
  await tester.tap(field);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text(label).last);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpRankingPage(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
