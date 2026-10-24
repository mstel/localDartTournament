import 'package:dart_tournament_manager/features/tournaments/application/tournament_duration_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats actual and estimated tournament duration consistently', () {
    expect(
      TournamentDurationRange.actualDurationLabel(
        const Duration(hours: 2, minutes: 34),
      ),
      'Tatsächliche Turnierdauer: 2h 34m',
    );
    expect(
      TournamentDurationRange.estimatedDurationLabel(
        minimumMinutes: 176,
        maximumMinutes: 264,
      ),
      'Geschätzte Turnierdauer: 3h 40m (2h 56m–4h 24m)',
    );
  });
}
