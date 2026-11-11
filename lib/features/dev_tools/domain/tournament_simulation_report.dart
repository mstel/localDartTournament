import '../../tournaments/domain/knockout_round_names.dart';
import 'tournament_simulation_engine.dart';

String formatTournamentSimulationLog(List<TournamentSimulationReport> reports) {
  final buffer = StringBuffer()
    ..writeln('Turnier-Simulationslog')
    ..writeln('=====================')
    ..writeln('Szenarien: ${reports.length}')
    ..writeln('');

  for (final report in reports) {
    _writeScenario(buffer, report);
  }

  return buffer.toString();
}

void _writeScenario(StringBuffer buffer, TournamentSimulationReport report) {
  buffer
    ..writeln('Szenario: ${report.scenarioName}')
    ..writeln('Begegnungen gesamt: ${report.totalMatches}')
    ..writeln(
      'Finale Teilnehmer: '
      '${report.finalPlayers.map((player) => player.name).join(', ')}',
    )
    ..writeln('');

  for (var index = 0; index < report.stageReports.length; index++) {
    _writeStage(buffer, index + 1, report.stageReports[index]);
  }

  buffer
    ..writeln('------------------------------------------------------------')
    ..writeln('');
}

void _writeStage(
  StringBuffer buffer,
  int stageNumber,
  SimulationStageReport stage,
) {
  buffer.writeln(
    'Phase $stageNumber: ${stage.name} '
    '(${stage.inputCount} rein -> ${stage.outputCount} weiter, '
    '${stage.matchCount} Begegnungen)',
  );

  if (stage.matches.isEmpty) {
    buffer.writeln('  Keine Begegnungen in dieser Phase.');
    buffer.writeln('');
    return;
  }

  final brackets = <String, List<SimulationMatchRecord>>{};
  for (final record in stage.matchRecords) {
    brackets.putIfAbsent(record.bracket, () => []).add(record);
  }

  for (final bracket in brackets.keys) {
    buffer.writeln('  $bracket');
    final rounds = <int, List<SimulationMatchRecord>>{};
    for (final record in brackets[bracket]!) {
      rounds.putIfAbsent(record.match.round, () => []).add(record);
    }

    final orderedRounds = rounds.keys.toList()..sort();
    for (final round in orderedRounds) {
      buffer.writeln(
        '    ${rounds[round]!.first.isRoundBased ? _roundLabel(round) : knockoutMatchName(rounds[round]!.first.match, brackets[bracket]!.map((r) => r.match))}',
      );
      for (final record in rounds[round]!) {
        buffer.writeln('      ${_recordLine(record)}');
      }
    }
  }

  buffer.writeln('');
}

String _roundLabel(int round) {
  if (round >= 1000) {
    final groupNumber = round ~/ 1000 + 1;
    final groupRound = round % 1000;
    return 'Gruppe $groupNumber - Runde $groupRound';
  }
  return 'Runde $round';
}

String _recordLine(SimulationMatchRecord record) {
  final match = record.match;
  final home = match.homePlayer?.name ?? 'Freilos';
  final away = match.awayPlayer?.name ?? 'Freilos';
  final score = match.hasResult
      ? match.scoreLabel
      : match.winner != null
      ? 'Freilos'
      : 'offen';
  final winner = match.winner?.name;
  final winnerText = winner == null ? '' : ' -> Sieger: $winner';
  final label = match.label == null ? '' : ' [${match.label}]';
  return 'Spiel ${record.number}: $home vs $away ($score)$winnerText$label '
      '| Quellen: ${record.homeSource} vs ${record.awaySource}';
}
