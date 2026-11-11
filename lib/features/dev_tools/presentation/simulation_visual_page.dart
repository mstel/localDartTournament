import '../../tournaments/domain/knockout_round_names.dart';
import 'simulation_graph.dart';
import 'package:flutter/material.dart';
import '../domain/tournament_simulation_engine.dart';

class SimulationVisualPage extends StatelessWidget {
  const SimulationVisualPage({super.key, required this.report});
  final TournamentSimulationReport report;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: report.stageReports.length,
    child: Scaffold(
      appBar: AppBar(
        title: Text(report.scenarioName),
        bottom: TabBar(
          isScrollable: true,
          tabs: [
            for (final stage in report.stageReports) Tab(text: stage.name),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          for (final stage in report.stageReports)
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${stage.inputCount} Teilnehmer → ${stage.outputCount} weiter · ${stage.matchCount} Matches',
                  style: Theme.of(context).textTheme.titleLarge,
                ),

                if (stage.lossLimit > 1)
                  Text(
                    stage.finalEndsTournament
                        ? '${stage.lossLimit == 2 ? 'Doppel-KO' : 'Triple-KO'} · Ein großes Finale entscheidet'
                        : 'Kratzer-Modus · ${stage.lossLimit} Leben',
                  ),
                const Text('N. = Niederlagen vor dem Spiel · S = Sets'),
                for (final table in stage.groupTables.entries) ...[
                  const SizedBox(height: 20),
                  Text(
                    table.key,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: [
                        for (final title in [
                          '#',
                          'Teilnehmer',
                          'Sp',
                          'S',
                          'U',
                          'N',
                          'Legs',
                          'Diff',
                          'Pkt',
                        ])
                          DataColumn(label: Text(title)),
                      ],
                      rows: [
                        for (var i = 0; i < table.value.length; i++)
                          DataRow(
                            cells: [
                              for (final value in [
                                i + 1,
                                table.value[i].player.name,
                                table.value[i].played,
                                table.value[i].wins,
                                table.value[i].draws,
                                table.value[i].losses,
                                '${table.value[i].legsFor}:${table.value[i].legsAgainst}',
                                table.value[i].legDifference,
                                table.value[i].points,
                              ])
                                DataCell(Text('$value')),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
                if (stage.matchRecords.any((r) => !r.isRoundBased)) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Turnierbaum',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text(
                    'Verschieben und zoomen. Grün: Sieger weiter · Orange: Verlierer weiter. Die Verbindungen zeigen den tatsächlichen Verlauf der Simulation.',
                  ),
                  const SizedBox(height: 12),
                  SimulationGraph(
                    records: stage.matchRecords
                        .where((r) => !r.isRoundBased)
                        .toList(),
                  ),
                ],
                const SizedBox(height: 20),
                ExpansionTile(
                  title: const Text('Alle gespielten Matches'),
                  children: [
                    for (final record in stage.matchRecords)
                      ListTile(
                        title: Text(
                          '${record.match.homePlayer?.name ?? 'Freilos'}  ${record.match.hasResult ? record.match.scoreLabel : '-:-'}  ${record.match.awayPlayer?.name ?? 'Freilos'}',
                        ),
                        subtitle: Text(
                          'Spiel ${record.number} · ${record.bracket} · ${record.isRoundBased ? 'Runde ${record.match.round % 1000}' : knockoutMatchName(record.match, stage.matchRecords.where((r) => r.bracket == record.bracket).map((r) => r.match))}',
                        ),
                      ),
                  ],
                ),
              ],
            ),
        ],
      ),
    ),
  );
}
