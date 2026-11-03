import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/tournament_date_picker_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('date picker exposes the selected date and allows changing it', (
    tester,
  ) async {
    DateTime? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentDatePickerField(
            value: DateTime(2020, 4, 17),
            onChanged: (value) => changed = value,
          ),
        ),
      ),
    );

    expect(find.byType(TournamentDatePickerField), findsOneWidget);
    await tester.tap(find.byIcon(Icons.calendar_today_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(changed, DateTime(2020, 4, 20));
  });
}
