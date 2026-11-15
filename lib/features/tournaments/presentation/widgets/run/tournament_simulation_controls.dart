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
    required this.autoStartMatches,
    required this.onAutoStartMatchesChanged,
    required this.optionsEnabled,
    required this.completedSteps,
    required this.totalSteps,
    required this.elapsed,
    required this.canUndo,
    required this.isComplete,
    required this.eventLog,
    required this.onNextStep,
    required this.onUndo,
    required this.onStop,
    required this.onReset,
  });

  final TournamentSimulationMode mode;
  final ValueChanged<TournamentSimulationMode> onModeChanged;
  final TextEditingController seedController;
  final TextEditingController minimumMinutesController;
  final TextEditingController maximumMinutesController;
  final bool autoStartMatches;
  final ValueChanged<bool> onAutoStartMatchesChanged;
  final bool optionsEnabled;
  final int completedSteps;
  final int totalSteps;
  final Duration elapsed;
  final bool canUndo;
  final bool isComplete;
  final List<String> eventLog;
  final VoidCallback onNextStep;
  final VoidCallback onUndo;
  final VoidCallback onStop;
  final VoidCallback onReset;

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

  Widget _controls(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
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
                  return SizedBox(width: constraints.maxWidth, child: field);
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
      SwitchListTile(
        key: const ValueKey('simulation-auto-start-toggle'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Partien automatisch auf aktiv stellen'),
        value: autoStartMatches,
        onChanged: onAutoStartMatchesChanged,
      ),
      const SizedBox(height: 8),
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
            onPressed: onStop,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Simulation beenden'),
          ),
          OutlinedButton.icon(
            key: const ValueKey('simulation-reset-button'),
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Simulation zurücksetzen'),
          ),
          OutlinedButton.icon(
            onPressed: canUndo ? onUndo : null,
            icon: const Icon(Icons.undo),
            label: const Text('Letzter Schritt rückgängig'),
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
  );

  Widget _simulationLog(BuildContext context) {
    final theme = Theme.of(context);
    final visibleCount = eventLog.length.clamp(0, 100);
    return Container(
      key: const ValueKey('tournament-simulation-log'),
      height: 320,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.article_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Simulations-Log',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text('$visibleCount'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: visibleCount == 0
                ? const Center(child: Text('Noch keine Ereignisse.'))
                : ListView.separated(
                    reverse: false,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: visibleCount,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 12, endIndent: 12),
                    itemBuilder: (context, index) {
                      final entry = eventLog[eventLog.length - index - 1];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          index == 0
                              ? Icons.fiber_manual_record
                              : Icons.circle_outlined,
                          size: index == 0 ? 14 : 12,
                          color: index == 0
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline,
                        ),
                        title: Text(entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Card(
    key: const ValueKey('tournament-simulation-controls'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final controls = _controls(context);
          final log = _simulationLog(context);
          if (constraints.maxWidth >= 850) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: controls),
                const SizedBox(width: 16),
                Expanded(child: log),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [controls, const SizedBox(height: 12), log],
          );
        },
      ),
    ),
  );
}
