import 'package:dart_tournament_manager/features/tournaments/domain/set_result_validation.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('best-of-three legs end at two and reject unreachable scores', () {
    const format = TournamentGameFormat(bestOfLegs: 3);

    expect(isValidLegResult(format, homeLegs: 2, awayLegs: 0), isTrue);
    expect(isValidLegResult(format, homeLegs: 2, awayLegs: 1), isTrue);
    expect(isValidLegResult(format, homeLegs: 3, awayLegs: 0), isFalse);
    expect(isValidLegResult(format, homeLegs: 1, awayLegs: 1), isFalse);
  });

  test('best-of-five legs end at three and reject scores over the limit', () {
    const format = TournamentGameFormat(bestOfLegs: 5);

    expect(isValidLegResult(format, homeLegs: 3, awayLegs: 2), isTrue);
    expect(isValidLegResult(format, homeLegs: 4, awayLegs: 0), isFalse);
  });
}
