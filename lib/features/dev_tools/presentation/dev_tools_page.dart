import 'package:dart_tournament_manager/shared/widgets/adaptive_content.dart';
import 'dart:math';
import '../domain/random_tournament_simulations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/development_simulation_runner.dart';
import '../domain/tournament_simulation_engine.dart';
import 'simulation_visual_page.dart';

class DevToolsPage extends StatefulWidget {
  const DevToolsPage({super.key});
  @override
  State<DevToolsPage> createState() => _DevToolsPageState();
}

class _DevToolsPageState extends State<DevToolsPage> {
  bool _running = false;
  bool _randomMode = false;
  final _seed = TextEditingController();
  final _count = TextEditingController(text: '20');
  int? _lastSeed;
  @override
  void dispose() {
    _seed.dispose();
    _count.dispose();
    super.dispose();
  }

  String? _error;
  String _filter = '';
  List<Map<String, Object>>? _results;

  Future<void> _run() async {
    final count = int.tryParse(_count.text);
    final seedText = _seed.text.trim();
    final seed = seedText.isEmpty
        ? Random.secure().nextInt(0x7fffffff)
        : int.tryParse(seedText);
    if (_randomMode &&
        (count == null ||
            count < 1 ||
            count > 100 ||
            seed == null ||
            seed < 0 ||
            seed > 0x7fffffff)) {
      setState(
        () => _error =
            'Bitte 1–100 Turniere und einen Seed von 0 bis 2147483647 eingeben (oder Seed leer lassen).',
      );
      return;
    }
    setState(() {
      _running = true;
      _error = null;
      _results = null;
      _lastSeed = _randomMode ? seed : null;
    });
    try {
      final results = _randomMode
          ? await compute(
              runRandomSimulations,
              RandomSimulationRequest(seed: seed!, count: count!),
            )
          : await compute(runDevelopmentSimulations, false);
      if (mounted) setState(() => _results = results);
    } catch (error) {
      if (mounted) setState(() => _error = 'Testlauf fehlgeschlagen: $error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final failures = results?.where((r) => r['passed'] == false).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Dev Tools')),
      body: AdaptiveContentList(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Turnierformen durchspielen',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            _randomMode
                ? 'Zufallsturniere mit 2–32 Teilnehmern und bis zu drei Phasen. Seed leer lassen für neue Turniere oder einen Seed zur Wiederholung eingeben. Gespeicherte Turniere werden nicht verändert.'
                : 'Alle hinterlegten Szenarien werden mit drei reproduzierbaren Ergebnisverläufen geprüft. Die Berichte enthalten Matches, Ergebnisse und Teilnehmer. Gespeicherte Turniere werden nicht verändert.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Der Tester verwendet die produktive Turnierlogik für Aufbau, Freilose, Weitergabe, Tabellen und Weiterkommen. Nur die Ergebnisse werden simuliert. Flutter-Analyse und weitere Regressionstests laufen über den externen Turniertester.',
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            key: const ValueKey('dev-random-mode'),
            title: const Text('Zufallsmodus'),
            subtitle: const Text(
              'Neue Turnieraufbauten, Spielformate und zufällige Matchausgänge.',
            ),
            value: _randomMode,
            onChanged: _running
                ? null
                : (value) => setState(() {
                    _randomMode = value;
                  }),
          ),
          if (_randomMode) ...[
            TextField(
              key: const ValueKey('dev-random-count'),
              controller: _count,
              enabled: !_running,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Anzahl Zufallsturniere (1–100)',
              ),
            ),
            TextField(
              key: const ValueKey('dev-random-seed'),
              controller: _seed,
              enabled: !_running,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Seed zum Wiederholen (optional)',
                helperText:
                    'Leer: bei jedem Start neu. Für einen einzelnen Fehler dessen Seed und Anzahl 1 verwenden.',
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_lastSeed != null)
            SelectableText('Letzter Zufallslauf: Start-Seed $_lastSeed'),
          FilledButton.icon(
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.science_outlined),
            label: Text(
              _running
                  ? 'Simulation läuft …'
                  : (_randomMode
                        ? 'Zufallsturniere testen'
                        : 'Turnierformen testen'),
            ),
          ),
          if (_running)
            const Padding(
              padding: EdgeInsets.all(20),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(_error!),
            ),
          if (results != null) ...[
            const SizedBox(height: 20),
            Text(
              '${results.length} Durchläufe · ${results.length - failures} bestanden · $failures Fehler',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: results
                        .map(
                          (r) =>
                              '${r['passed'] == true ? 'OK' : 'FEHLER'} · ${r['name']}\n${r['detail']}',
                        )
                        .join('\n\n'),
                  ),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Kontrollbericht kopiert.')),
                );
              },
              icon: const Icon(Icons.copy_all),
              label: const Text('Gesamten Bericht kopieren'),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Szenarien filtern',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) =>
                  setState(() => _filter = value.toLowerCase()),
            ),
            const SizedBox(height: 12),
            if (!results.any(
              (r) => (r['name'] as String).toLowerCase().contains(_filter),
            ))
              const Text('Keine passenden Szenarien.'),
            for (final result in results.where(
              (r) => (r['name'] as String).toLowerCase().contains(_filter),
            ))
              Card(
                child: ExpansionTile(
                  key: ValueKey(result['name']),
                  leading: Icon(
                    result['passed'] == true
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    color: result['passed'] == true
                        ? Colors.green
                        : Theme.of(context).colorScheme.error,
                  ),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result['type'] as String? ?? 'Turniersimulation',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(result['name'] as String),
                    ],
                  ),
                  subtitle: Text(
                    result['passed'] == true
                        ? '${result['matches']} Matches · ${result['draws'] ?? 0} Unentschieden · bestanden'
                        : 'Fehler – Details öffnen',
                  ),
                  children: [
                    if (result['report']
                        case final TournamentSimulationReport report)
                      FilledButton.icon(
                        icon: const Icon(Icons.account_tree_outlined),
                        label: const Text('Turnierbaum und Tabellen öffnen'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                SimulationVisualPage(report: report),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          result['detail'] as String,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
