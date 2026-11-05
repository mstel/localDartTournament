import 'package:dart_tournament_manager/features/statistics/presentation/monthly_statistics_import_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in const [Size(360, 800), Size(800, 600), Size(1440, 900)]) {
    testWidgets('monthly import page lays out at $size with large text', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: const TextScaler.linear(2),
          ),
          child: const MaterialApp(home: MonthlyStatisticsImportPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Monatsstatistiken importieren'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
