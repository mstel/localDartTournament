import '../../features/tournaments/domain/tournament_models.dart';

/// ErgebnisString immer aus Sicht des Siegers: `Sieger:Verlierer`.
///
/// Bei Unentschieden, annullierten oder noch offenen Partien bleibt die
/// Reihenfolge Heim:Gast erhalten.
String winnerFirstScore(GroupMatch match) {
  final home = match.homeScore ?? 0;
  final away = match.awayScore ?? 0;
  final winner = match.winner;
  if (winner != null && winner == match.awayPlayer) {
    return '$away:$home';
  }
  return '$home:$away';
}
