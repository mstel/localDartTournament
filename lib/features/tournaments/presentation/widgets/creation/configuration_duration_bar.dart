import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../application/configuration_duration_estimator.dart';
import '../../../domain/tournament_models.dart';
import '../../../domain/tournament_planning_parameters.dart';
import '../../../../settings/data/planning_settings_storage.dart';

class ConfigurationDurationBar extends StatefulWidget {
  const ConfigurationDurationBar({
    super.key,
    required this.stages,
    required this.boards,
    required this.onBoardsChanged,
    this.editing = false,
    this.parameters,
  });
  final List<TournamentStage> stages;
  final int boards;
  final ValueChanged<int> onBoardsChanged;
  final bool editing;
  final TournamentPlanningParameters? parameters;

  @override
  State<ConfigurationDurationBar> createState() =>
      _ConfigurationDurationBarState();
}

class _ConfigurationDurationBarState extends State<ConfigurationDurationBar> {
  Timer? _timer;
  String? _signature;
  int? _minutes;
  ConfigurationEstimate? _estimate;
  bool _loading = true;
  String? _error;
  TournamentPlanningParameters? _parameters;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _parameters = widget.parameters ?? await PlanningSettingsStorage().load();
      if (mounted) _schedule();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Zeiteinstellungen konnten nicht geladen werden.';
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant ConfigurationDurationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    if (_parameters == null) return;
    final signature =
        '${widget.boards}:${jsonEncode(widget.stages.map((s) => s.toJson()).toList())}';
    if (signature == _signature) return;
    _signature = signature;
    _timer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });
    _timer = Timer(const Duration(milliseconds: 250), () {
      try {
        final estimate = const ConfigurationDurationEstimator().preview(
          widget.stages,
          widget.boards,
          _parameters!,
        );
        if (mounted) {
          setState(() {
            _estimate = estimate;
            _minutes = estimate?.minutes;
            _loading = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Konfiguration für eine Schätzung noch unvollständig.';
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Geschätzte Gesamtdauer',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _loading
                ? 'Wird berechnet …'
                : _error ??
                      (_minutes == null
                          ? 'Bitte eine vollständige Etappe konfigurieren.'
                          : _minutes! < 60
                          ? 'ca. ${_minutes!} min'
                          : 'ca. ${_minutes! ~/ 60} h ${_minutes! % 60} min'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (!_loading && _error == null && _estimate != null) ...[
            Text(
              '${_estimate!.variableMatches ? 'ca. ' : ''}${_estimate!.totalMatches} Spiele insgesamt',
            ),
            Text(
              'Garantiert mindestens ${_estimate!.minimumMatches} Spiele je Teilnehmer',
            ),
            Text(
              'Zusätzliche Pausen- und Leerstandszeit: '
              'ca. ${_estimate!.waitMinutes.ceil()} min '
              '(Leerstand ${_parameters!.boardIdleMinutes} min je Boardwechsel).',
            ),
            const Text(
              'Matches, nicht einzelne Legs. Freilose zählen nicht als Spiel. Spätere Etappen zählen zur Mindestzahl nur, wenn alle Teilnehmer sie erreichen. Zusätzliche Entscheidungsspiele sind nicht enthalten.',
            ),
            if (_estimate!.variableMatches)
              const Text(
                'Die Gesamtzahl hängt vom Turnierverlauf ab; angezeigt wird die Simulation der Zeitvorschau.',
              ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${widget.boards} Boards'),
              IconButton(
                tooltip: 'Ein Board weniger',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: widget.boards > 1
                    ? () => widget.onBoardsChanged(widget.boards - 1)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              IconButton(
                tooltip: 'Ein Board mehr',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: widget.boards < 64
                    ? () => widget.onBoardsChanged(widget.boards + 1)
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          Text(
            widget.editing
                ? 'Vorschau inklusive der aktuell bearbeiteten Etappe.'
                : 'Berechnet für die hinzugefügten Etappen.',
          ),
          const Text(
            'Die Schätzung addiert die durchschnittliche Matchdauer je Zeitblock. '
            'Gleichzeitig spielbare Matches teilen sich einen Block; der Board-Leerstand '
            'wird nur zwischen belegten Blöcken berücksichtigt. Abhängige KO- und '
            'Swiss-Runden werden nacheinander eingeplant. Ergebnisse, Entscheidungsspiele '
            'und zusätzliche Pausen können die Dauer verändern.',
          ),
        ],
      ),
    ),
  );
}
