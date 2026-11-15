import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/tournament_run_simulation.dart';

class TournamentSimulationControls extends StatelessWidget {
  const TournamentSimulationControls({
    super.key,
    required this.mode,
    required this.onModeChanged,
    required this.seedController,
    required this.minimumMinutesController,
    required this.maximumMinutesController,
    required this.optionsEnabled,
    required this.completedSteps,
    required this.totalSteps,
    required this.elapsed,
    required this.canUndo,
    required this.isComplete,
    required this.onNextStep,
    required this.onUndo,
    required this.onStop,
  });

  final TournamentSimulationMode mode;
  final ValueChanged<TournamentSimulationMode> onModeChanged;
  final TextEditingController seedController;
  final TextEditingController minimumMinutesController;
  final TextEditingController maximumMinutesController;
  final bool optionsEnabled;
  final int completedSteps;
  final int totalSteps;
  final Duration elapsed;
  final bool canUndo;
  final bool isComplete;
  final VoidCallback onNextStep;
  final VoidCallback onUndo;
  final VoidCallback onStop;

  String _elapsedLabel(Duration value) {
    final minutes = value.inMinutes;
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    final seconds = value.inSeconds % 60;
    return hours == 0
        ? '${remainder.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
        : '${hours.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }

  Widget _numberField({
    required String label,
    required TextEditingController controller,
    required bool allowNegative,
  }) => SizedBox(
    width: 150,
    child: TextField(
      controller: controller,
      enabled: optionsEnabled,
      keyboardType: const TextInputType.numberWithOptions(
        signed: true,
        decimal: false,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          allowNegative ? RegExp(r'^-?\d*') : RegExp(r'^\d*'),
        ),
      ],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Card(
    key: const ValueKey('tournament-simulation-controls'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                'Turniersimulation',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Chip(
                avatar: Icon(Icons.science_outlined, size: 18),
                label: Text('Simulation aktiv'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Simulationsschritt $completedSteps / $totalSteps · '
            'Simulationszeit ${_elapsedLabel(elapsed)}',
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: totalSteps == 0
                ? null
                : (completedSteps / totalSteps).clamp(0, 1).toDouble(),
          ),
          const SizedBox(height: 16),
          Text('Simulationsart', style: Theme.of(context).textTheme.titleSmall),
          RadioGroup<TournamentSimulationMode>(
            groupValue: mode,
            onChanged: (value) {
              if (value != null && optionsEnabled) onModeChanged(value);
            },
            child: Column(
              children: [
                RadioListTile<TournamentSimulationMode>(
                  contentPadding: EdgeInsets.zero,
                  enabled: optionsEnabled,
                  value: TournamentSimulationMode.fixedStep,
                  title: const Text('Fixe Schrittsimulation'),
                ),
                RadioListTile<TournamentSimulationMode>(
                  contentPadding: EdgeInsets.zero,
                  enabled: optionsEnabled,
                  value: TournamentSimulationMode.randomStep,
                  title: const Text('Zufällige Schrittsimulation'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            mode == TournamentSimulationMode.fixedStep
                ? 'Standardzeiten aus den Turniereinstellungen; '
                      'Board-Leerstand wird berücksichtigt.'
                : 'Jede Partie erhält beim Start eine reproduzierbare Dauer.',
          ),
          if (mode == TournamentSimulationMode.randomStep) ...[
            const SizedBox(height: 12),
            Text(
              'Spieldauer pro Partie',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 12,
                runSpacing: 12,
                children:
                    [
                      _numberField(
                        label: 'Von (Minuten)',
                        controller: minimumMinutesController,
                        allowNegative: false,
                      ),
                      _numberField(
                        label: 'Bis (Minuten)',
                        controller: maximumMinutesController,
                        allowNegative: false,
                      ),
                      _numberField(
                        label: 'Zufalls-Seed',
                        controller: seedController,
                        allowNegative: true,
                      ),
                    ].map((field) {
                      if (constraints.maxWidth >= 500) return field;
                      return SizedBox(
                        width: constraints.maxWidth,
                        child: field,
                      );
                    }).toList(),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            _numberField(
              label: 'Zufalls-Seed',
              controller: seedController,
              allowNegative: true,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: isComplete ? null : onNextStep,
                icon: const Icon(Icons.skip_next),
                label: Text(
                  isComplete ? 'Simulation abgeschlossen' : 'Nächster Schritt',
                ),
              ),
              OutlinedButton.icon(
                onPressed: canUndo ? onUndo : null,
                icon: const Icon(Icons.undo),
                label: const Text('Letzter Schritt rückgängig'),
              ),
              OutlinedButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Simulation beenden'),
              ),
            ],
          ),
          if (!optionsEnabled)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Simulationsart, Seed und Spieldauer sind nach dem ersten Schritt fixiert.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    ),
  );
}
