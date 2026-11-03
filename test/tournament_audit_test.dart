import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'support/tournament_simulation_engine.dart';
import 'support/tournament_simulation_scenarios.dart';
import 'support/tournament_simulation_report_log.dart';

void main() {
  test('audits every tournament scenario with reproducible strength orders', () {
    final runs = <Map<String, dynamic>>[];
    final failures = <String>[];
    for (final scenario in tournamentDevelopmentScenarios) {
      for (final seed in <int?>[null, 7, 42]) {
        final label =
            '${scenario.name} · ${seed == null ? 'Standard' : 'Seed $seed'}';
        try {
          final report = TournamentSimulationEngine().run(scenario, seed: seed);
          if (report.finalPlayers.length != scenario.stages.last.qualifiers) {
            throw StateError('Falsche Anzahl Weiterkommender');
          }
          if (report.finalPlayers.map((p) => p.name).toSet().length !=
              report.finalPlayers.length) {
            throw StateError('Doppelte Weiterkommende');
          }
          for (final stage in report.stageReports) {
            if (stage.outputCount < 1 || stage.outputCount > stage.inputCount) {
              throw StateError('Unplausible Teilnehmerzahl');
            }
            for (final match in stage.matches) {
              if (!match.isResolved) {
                throw StateError('Unaufgelöstes Match in ${stage.name}');
              }
              if (match.isKratzer) {
                if (match.players.map((player) => player.name).toSet().length !=
                    match.players.length) {
                  throw StateError('Spieler spielt gegen sich selbst');
                }
              } else if (match.hasPlayers &&
                  match.homePlayer!.name == match.awayPlayer!.name) {
                throw StateError('Spieler spielt gegen sich selbst');
              }
            }
          }
          runs.add({
            'name': label,
            'passed': true,
            'matches': report.totalMatches,
            'winners': report.finalPlayers.map((p) => p.name).toList(),
            'detail': formatTournamentSimulationLog([report]),
          });
        } catch (error, stack) {
          failures.add('$label: $error');
          runs.add({
            'name': label,
            'passed': false,
            'error': '$error',
            'detail': '$error\n$stack',
          });
        }
      }
    }
    final directory = Directory('build/tournament_audit')
      ..createSync(recursive: true);
    File('${directory.path}/simulation.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'generatedAt': DateTime.now().toIso8601String(),
        'runs': runs,
        'failures': failures,
      }),
    );
    final escape = const HtmlEscape().convert;
    final html =
        StringBuffer(
            '''<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Turnierkontrolle</title>
<style>body{font:16px system-ui;max-width:1200px;margin:40px auto;padding:0 20px;background:#f3f7f5;color:#173c31}details{background:white;border:1px solid #ccdcd4;border-radius:10px;padding:16px;margin:12px 0}summary{cursor:pointer;font-weight:600}pre{white-space:pre-wrap;overflow-wrap:anywhere;font:13px monospace}.bad{border:2px solid #bd3333}input{padding:12px;width:90%;font:inherit}a{color:#006846}</style>
<h1>Turnierkontrolle</h1><p><a href="index.html">Gesamtergebnis und Prüfprotokolle</a></p>
''',
          )
          ..writeln(
            '<p>${runs.length} Durchläufe · ${failures.length} Fehler · ${escape(DateTime.now().toString())}</p>',
          )
          ..writeln(
            '<p>Jeder Modus wird mit Standard-Reihenfolge und zwei festen Zufalls-Seeds durchgespielt. Ergebnisse folgen einer reproduzierbaren Spielstärke-Reihenfolge (2:1). Aufbau, Freilose, Ergebnisweitergabe und Qualifikation laufen über dieselben Methoden wie im normalen Turnier. Nur die Ergebnisse werden simuliert. Kein vollständiger automatisierter UI-Durchlauf.</p>',
          )
          ..writeln(
            '<input id="filter" placeholder="Szenario suchen …" aria-label="Szenarien filtern">',
          );
    for (final run in runs) {
      html.writeln(
        '<details class="${run['passed'] == true ? '' : 'bad'}"><summary>${run['passed'] == true ? 'OK' : 'FEHLER'} · ${escape(run['name'] as String)}</summary>',
      );
      if (run['passed'] == true) {
        html.writeln(
          '<p>${run['matches']} Matches · Finale Weiterkommende: ${escape((run['winners'] as List).join(', '))}</p>',
        );
      }
      html.writeln('<pre>${escape(run['detail'] as String)}</pre></details>');
    }
    html.writeln(
      '''<script>document.querySelector('#filter').addEventListener('input',e=>{for(const d of document.querySelectorAll('details'))d.hidden=!d.querySelector('summary').textContent.toLowerCase().includes(e.target.value.toLowerCase())})</script></html>''',
    );
    File(
      '${directory.path}/simulation.html',
    ).writeAsStringSync(html.toString());
    expect(
      failures,
      isEmpty,
      reason: 'Details: build/tournament_audit/simulation.html',
    );
  });
}
