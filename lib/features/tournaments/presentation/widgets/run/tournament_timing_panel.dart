import 'dart:async';
import 'package:flutter/material.dart';
import '../../../domain/tournament_models.dart';
import '../../../application/tournament_timing.dart';

class TournamentTimingPanel extends StatefulWidget {
  const TournamentTimingPanel({
    super.key,
    required this.tournament,
    this.onStart,
    this.onPauseToggle,
    this.onEditTimes,
    this.onResetClock,
    this.allowManualStart = true,
    this.allowStartTimeEdit = false,
    this.allowEndTimeEdit = false,
  });
  final CreatedTournament tournament;
  final Future<void> Function()? onStart;
  final Future<void> Function()? onPauseToggle;
  final Future<void> Function(DateTime? startedAt, DateTime? finishedAt)?
  onEditTimes;
  final Future<void> Function()? onResetClock;
  final bool allowManualStart;
  final bool allowStartTimeEdit;
  final bool allowEndTimeEdit;
  @override
  State<TournamentTimingPanel> createState() => _TournamentTimingPanelState();
}

class _TournamentTimingPanelState extends State<TournamentTimingPanel> {
  Timer? _timer;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    if (widget.tournament.finishedAt == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String duration(int seconds) =>
      '${seconds ~/ 3600} h ${(seconds ~/ 60) % 60} min';
  String time(DateTime date) {
    final d = date.toLocal();
    return '${d.day}.${d.month}. ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String matchDuration(num seconds) =>
      '${seconds ~/ 60} min ${seconds.round() % 60} s';

  Future<DateTime?> _pickTimestamp(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Datum auswählen',
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Uhrzeit auswählen',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _editTimestamp({required bool start}) async {
    final current = start
        ? widget.tournament.startedAt
        : widget.tournament.finishedAt;
    if (widget.onEditTimes == null ||
        (current == null &&
            (start && !widget.allowStartTimeEdit ||
                !start && !widget.allowEndTimeEdit))) {
      return;
    }
    final selected = await _pickTimestamp(current ?? DateTime.now());
    if (selected == null || !mounted) return;
    final nextStart = start ? selected : widget.tournament.startedAt;
    final nextEnd = start ? widget.tournament.finishedAt : selected;
    if (nextStart != null && nextEnd != null && nextEnd.isBefore(nextStart)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Die Endzeit muss nach der Startzeit liegen.'),
        ),
      );
      return;
    }
    try {
      await widget.onEditTimes!(nextStart, nextEnd);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Zeitpunkt konnte nicht gespeichert werden.'),
          ),
        );
      }
    }
  }

  Future<void> _resetClock() async {
    if (widget.onResetClock == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turnieruhr zurücksetzen?'),
        content: const Text(
          'Die Laufzeit wird auf null gesetzt und die Uhr startet ab jetzt neu. '
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tournament;
    final stats = TournamentTiming.snapshot(t, DateTime.now());
    final deadline = t.startedAt == null || t.plannedMinutes == null
        ? null
        : t.startedAt!.add(Duration(minutes: t.plannedMinutes!));
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
              'Turnieruhr',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Wrap(
              alignment: WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                if (t.startedAt == null) ...[
                  const Text(
                    'Nicht gestartet',
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
                                        'Turnierstart konnte nicht gespeichert werden. Bitte erneut versuchen.',
                                      ),
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            },
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Turnieruhr starten'),
                    ),
                ] else ...[
                  Text(
                    t.finishedAt != null
                        ? 'Abgeschlossen'
                        : t.isClockPaused
                        ? 'Pausiert'
                        : 'Läuft',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${t.finishedAt == null ? 'Laufzeit' : 'Gesamtdauer'} ${duration(stats.elapsed.inSeconds)}',
                  ),
                  Text('Start: ${time(t.startedAt!)}'),
                  if (t.finishedAt != null)
                    Text('Ende: ${time(t.finishedAt!)}'),
                  if (stats.forecast != null && t.finishedAt == null)
                    Text('Voraussichtliches Ende: ${time(stats.forecast!)}'),
                  if (stats.expectedCompleted != null)
                    Text(
                      '${stats.completed} Spiele fertig · ${stats.expectedCompleted} laut Zeitplan',
                    ),
                  if (t.finishedAt == null && widget.onPauseToggle != null)
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
                                        'Uhr-Status konnte nicht gespeichert werden. Bitte erneut versuchen.',
                                      ),
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            },
                      icon: Icon(
                        t.isClockPaused
                            ? Icons.play_circle_outline
                            : Icons.pause_circle_outline,
                      ),
                      label: Text(
                        t.isClockPaused ? 'Uhr fortsetzen' : 'Uhr pausieren',
                      ),
                    ),
                  if (t.finishedAt == null && widget.onEditTimes != null)
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _editTimestamp(start: true),
                      icon: const Icon(Icons.edit_calendar_outlined),
                      label: const Text('Startzeitpunkt neu festlegen'),
                    ),
                  if (t.finishedAt == null && widget.onResetClock != null)
                    TextButton.icon(
                      onPressed: _busy ? null : _resetClock,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Turnieruhr zurücksetzen'),
                    ),
                ],
                TextButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Zeitplan und Matchdauer'),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.startedAt == null
                                  ? 'Start: noch nicht erfasst'
                                  : 'Start: ${time(t.startedAt!)}',
                            ),
                            if (t.finishedAt != null || widget.allowEndTimeEdit)
                              Text(
                                t.finishedAt == null
                                    ? 'Ende: noch nicht erfasst'
                                    : 'Ende: ${time(t.finishedAt!)}',
                              ),
                            if (widget.onEditTimes != null) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  if (t.startedAt != null ||
                                      widget.allowStartTimeEdit)
                                    TextButton.icon(
                                      onPressed: () =>
                                          _editTimestamp(start: true),
                                      icon: const Icon(
                                        Icons.edit_calendar_outlined,
                                      ),
                                      label: const Text('Startzeit anpassen'),
                                    ),
                                  if (t.finishedAt != null)
                                    TextButton.icon(
                                      onPressed: () =>
                                          _editTimestamp(start: false),
                                      icon: const Icon(
                                        Icons.edit_calendar_outlined,
                                      ),
                                      label: const Text('Endzeit anpassen'),
                                    ),
                                ],
                              ),
                            ],
                            if (deadline != null)
                              Text('Geplantes Ende: ${time(deadline)}'),
                            if (stats.forecast != null && stats.completed > 0)
                              Text(
                                'Voraussichtliches Ende: ${time(stats.forecast!)}',
                              ),
                            if (stats.expectedCompleted != null)
                              Text(
                                '${stats.completed} Spiele fertig · ${stats.expectedCompleted} laut Zeitplan',
                              ),
                            Text(
                              t.plannedMatchEndSeconds.isEmpty
                                  ? 'Sollvergleich bei älteren Turnieren: gleichmäßige Verteilung über die geplante Dauer.'
                                  : 'Sollvergleich: ursprünglicher Spielplan mit parallelen Boards und aufeinanderfolgenden Etappen. Freilose zählen nicht als Spiele.',
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${stats.matchSeconds.length} Matches mit gemessener Dauer',
                            ),
                            if (stats.averageSeconds != null) ...[
                              Text(
                                'Durchschnitt: ${matchDuration(stats.averageSeconds!)}',
                              ),
                              Text(
                                'Kürzestes Match: ${matchDuration(stats.matchSeconds.first)}',
                              ),
                              Text(
                                'Längstes Match: ${matchDuration(stats.matchSeconds.last)}',
                              ),
                            ],
                            Text(
                              '${stats.unmeasured} Ergebnisse ohne vollständige Zeitmessung',
                            ),
                            if (stats.matchSeconds.isNotEmpty)
                              ExpansionTile(
                                title: const Text('Gemessene Matches'),
                                children: [
                                  for (final match
                                      in TournamentTiming.matches(t).where(
                                        (m) =>
                                            m.hasPlayers &&
                                            !m.isAnnulled &&
                                            m.hasResult &&
                                            m.startedAt != null &&
                                            m.finishedAt != null &&
                                            !m.finishedAt!.isBefore(
                                              m.startedAt!,
                                            ),
                                      ))
                                    ListTile(
                                      title: Text(
                                        '${match.homePlayer!.name} – ${match.awayPlayer!.name}',
                                      ),
                                      subtitle: Text(
                                        matchDuration(
                                          match.finishedAt!
                                              .difference(match.startedAt!)
                                              .inSeconds,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            const SizedBox(height: 12),
                            const Text(
                              'Die Uhr startet rückwirkend mit dem ersten gespeicherten Ergebnis oder manuell über „Turnieruhr starten“. Die automatische Startzeit berücksichtigt die geschätzte Matchdauer und den Board-Leerstand. Die Prognose ist die geplante Dauer ab Startzeit; nach Abschluss wird die tatsächliche Endzeit angezeigt.',
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Schließen'),
                        ),
                      ],
                    ),
                  ),
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('Zeitstatistik'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
