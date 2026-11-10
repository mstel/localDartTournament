import 'dart:async';

import 'package:flutter/material.dart';

import '../../../application/tournament_timing.dart';
import '../../../domain/tournament_models.dart';
import '../tournament_date_picker_field.dart';

class TournamentTimingPanel extends StatefulWidget {
  const TournamentTimingPanel({
    super.key,
    required this.tournament,
    this.onStart,
    this.onPauseToggle,
    this.onEditTimes,
    this.onResetClock,
    this.onChangeTournamentDate,
    this.onShiftMatchDates,
    this.allowManualStart = true,
    this.allowStartTimeEdit = false,
  });

  final CreatedTournament tournament;
  final Future<void> Function()? onStart;
  final Future<void> Function()? onPauseToggle;
  final Future<void> Function(DateTime? startedAt, DateTime? finishedAt)?
  onEditTimes;
  final Future<void> Function()? onResetClock;
  final ValueChanged<DateTime>? onChangeTournamentDate;
  final Future<int> Function(DateTime date)? onShiftMatchDates;
  final bool allowManualStart;
  final bool allowStartTimeEdit;

  @override
  State<TournamentTimingPanel> createState() => _TournamentTimingPanelState();
}

class _TournamentTimingPanelState extends State<TournamentTimingPanel> {
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _syncClockTimer();
  }

  @override
  void didUpdateWidget(covariant TournamentTimingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncClockTimer();
  }

  void _syncClockTimer() {
    final tournament = widget.tournament;
    final shouldRun =
        tournament.startedAt != null &&
        tournament.finishedAt == null &&
        !tournament.isClockPaused;
    if (shouldRun == (_timer != null)) return;
    _timer?.cancel();
    _timer = shouldRun
        ? Timer.periodic(const Duration(minutes: 1), (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _duration(int seconds) =>
      '${seconds ~/ 3600} h ${(seconds ~/ 60) % 60} min';

  String _time(DateTime date) {
    final local = date.toLocal();
    return '${local.day}.${local.month}. '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Future<DateTime?> _pickTimestamp(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Startdatum auswählen',
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Startuhrzeit auswählen',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _editStartTime() async {
    final current = widget.tournament.startedAt;
    if (widget.onEditTimes == null ||
        (current == null && !widget.allowStartTimeEdit)) {
      return;
    }
    final selected = await _pickTimestamp(current ?? DateTime.now());
    if (selected == null || !mounted) return;
    try {
      await widget.onEditTimes!(selected, widget.tournament.finishedAt);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Startzeitpunkt konnte nicht gespeichert werden.'),
          ),
        );
      }
    } finally {
      if (mounted) _syncClockTimer();
    }
  }

  Future<void> _resetClock() async {
    if (widget.onResetClock == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turnieruhr zurücksetzen?'),
        content: const Text(
          'Die Laufzeit wird ab 00:00 Uhr des eingestellten Turnierdatums '
          'berechnet. Wenn kein Turnierdatum festgelegt wurde, gilt heute. '
          'Ergebnisse und gemessene Matchzeiten bleiben erhalten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Uhr zurücksetzen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onResetClock!();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Turnieruhr konnte nicht zurückgesetzt werden. Bitte erneut versuchen.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        _syncClockTimer();
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _shiftMatchDates() async {
    final callback = widget.onShiftMatchDates;
    if (callback == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Begegnungsdaten verschieben?'),
        content: const Text(
          'Alle gespeicherten Start- und Endzeitpunkte der Begegnungen werden '
          'auf das ausgewählte Turnierdatum verschoben. Uhrzeiten und die '
          'chronologische Reihenfolge bleiben erhalten. An einer '
          'Sommerzeitgrenze kann sich die berechnete Matchdauer ändern. '
          'Turnieruhr und Turnierlog werden nicht verändert.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Begegnungsdaten verschieben'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final count = await callback(
        DateUtils.dateOnly(widget.tournament.effectiveDate.toLocal()),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count == 0
                  ? 'Die Begegnungsdaten liegen bereits auf diesem Datum.'
                  : 'Zeitstempel von $count Begegnungen wurden verschoben.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Begegnungsdaten konnten nicht verschoben werden.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tournament = widget.tournament;
    final hasMatchTimestamps = TournamentTiming.matches(
      tournament,
    ).any((match) => match.startedAt != null || match.finishedAt != null);
    final stats = TournamentTiming.snapshot(tournament, DateTime.now());
    final date = DateUtils.dateOnly(tournament.effectiveDate.toLocal());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Icon(
              Icons.timer_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            Text(
              'Uhr & Zeiteinstellungen',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.onChangeTournamentDate != null)
          TournamentDatePickerField(
            value: date,
            onChanged: widget.onChangeTournamentDate!,
          ),
        const SizedBox(height: 8),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            if (tournament.startedAt == null) ...[
              const Text(
                'Turnieruhr nicht gestartet',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if (widget.allowManualStart && widget.onStart != null)
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await widget.onStart!();
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Turnierstart konnte nicht gespeichert werden.',
                                  ),
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              _syncClockTimer();
                              setState(() => _busy = false);
                            }
                          }
                        },
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Turnieruhr starten'),
                ),
            ] else ...[
              Text(
                tournament.finishedAt != null
                    ? 'Abgeschlossen'
                    : tournament.isClockPaused
                    ? 'Pausiert'
                    : 'Läuft',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '${tournament.finishedAt == null ? 'Laufzeit' : 'Gesamtdauer'} '
                '${_duration(stats.elapsed.inSeconds)}',
              ),
              Text('Start: ${_time(tournament.startedAt!)}'),
              if (tournament.finishedAt != null)
                Text('Ende: ${_time(tournament.finishedAt!)}'),
              if (stats.forecast != null && tournament.finishedAt == null)
                Text('Voraussichtliches Ende: ${_time(stats.forecast!)}'),
              if (tournament.finishedAt == null && widget.onEditTimes != null)
                TextButton.icon(
                  onPressed: _busy ? null : _editStartTime,
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: const Text('Startzeitpunkt neu festlegen'),
                ),
              if (tournament.finishedAt == null && widget.onPauseToggle != null)
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await widget.onPauseToggle!();
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Uhr-Status konnte nicht gespeichert werden.',
                                  ),
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              _syncClockTimer();
                              setState(() => _busy = false);
                            }
                          }
                        },
                  icon: Icon(
                    tournament.isClockPaused
                        ? Icons.play_circle_outline
                        : Icons.pause_circle_outline,
                  ),
                  label: Text(
                    tournament.isClockPaused
                        ? 'Uhr fortsetzen'
                        : 'Uhr pausieren',
                  ),
                ),
              if (tournament.finishedAt == null && widget.onResetClock != null)
                TextButton.icon(
                  onPressed: _busy ? null : _resetClock,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Turnieruhr zurücksetzen'),
                ),
            ],
            if (hasMatchTimestamps && widget.onShiftMatchDates != null)
              TextButton.icon(
                onPressed: _busy ? null : _shiftMatchDates,
                icon: const Icon(Icons.event_repeat_outlined),
                label: const Text('Begegnungsdaten auf Turnierdatum setzen'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Das Turnierdatum ordnet das Turnier kalenderbezogen ein. '
          'Start- und Endzeit der Turnieruhr beschreiben den tatsächlichen '
          'Ablauf; das Enddatum wird beim Abschluss automatisch erfasst.',
        ),
      ],
    );
  }
}
