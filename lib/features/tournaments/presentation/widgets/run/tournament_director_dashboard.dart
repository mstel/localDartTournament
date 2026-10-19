import 'dart:async';
import 'package:flutter/material.dart';
import '../../../application/tournament_director_snapshot.dart';
import '../../../application/tournament_timing.dart';
import '../../../domain/tournament_models.dart';
import 'tournament_second_screen_view.dart';

/// Embedded tournament controls for match scheduling and result entry.
class TournamentDirectorDashboard extends StatefulWidget {
  const TournamentDirectorDashboard({
    super.key,
    required this.tournament,
    required this.activeStage,
    required this.onChange,
    required this.onResult,
    required this.onBlock,
    this.saveError,
    this.canOperate = true,
    this.onCompleteStage,
    this.onFinishEarly,
    this.canCompleteStage = false,
    this.isLastStage = false,
  });
  final CreatedTournament tournament;
  final int activeStage;
  final Future<void> Function() onChange;
  final Future<void> Function(GroupMatch) onResult;
  final Future<void> Function(int) onBlock;
  final String? saveError;
  final bool canOperate;
  final VoidCallback? onCompleteStage;
  final VoidCallback? onFinishEarly;
  final bool canCompleteStage;
  final bool isLastStage;
  @override
  State<TournamentDirectorDashboard> createState() =>
      _TournamentDirectorDashboardState();
}

class _TournamentDirectorDashboardState
    extends State<TournamentDirectorDashboard> {
  Timer? _timer;
  bool _busy = false;
  String? _actionError;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _actionError =
              'Aktion fehlgeschlagen. Verbindung und Berechtigung prüfen und erneut versuchen.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _box(List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
  Widget _button(
    String label,
    VoidCallback? action, {
    IconData icon = Icons.arrow_forward,
  }) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
    onPressed: _busy ? null : action,
    icon: Icon(icon),
    label: Text(label),
  );
  String _duration(Duration d) =>
      '${d.inHours} h ${d.inMinutes.remainder(60)} min';
  String _clock(DateTime t) =>
      '${t.toLocal().hour.toString().padLeft(2, '0')}:${t.toLocal().minute.toString().padLeft(2, '0')}';
  String _timeOfDay(DateTime t) =>
      '${t.toLocal().hour.toString().padLeft(2, '0')}:${t.toLocal().minute.toString().padLeft(2, '0')} Uhr';

  @override
  Widget build(BuildContext context) => _build(context);

  Widget _build(BuildContext context) {
    final t = widget.tournament;
    final state = TournamentDirectorSnapshot(t, widget.activeStage);
    final now = DateTime.now();
    final timing = TournamentTiming.snapshot(t, now);
    final active = state.entries
        .where((e) => e.stageIndex == widget.activeStage && e.match.hasPlayers)
        .toList();
    final completed = active.where((e) => e.match.isResolved).length;
    final waiting = state.schedule.waiting
        .where((e) => e.stageIndex == widget.activeStage && !e.match.isResolved)
        .length;
    // Prüfe auf Ungleichgewicht der absolvierten Spiele pro Spieler in Gruppen
    final List<String> flowNotices = [];
    if (t.runStages[widget.activeStage] is GroupTournamentRunStage) {
      final groupStage =
          t.runStages[widget.activeStage] as GroupTournamentRunStage;
      final groupProgress = [
        for (final group in groupStage.groups)
          if (group.matches.any((match) => match.hasPlayers))
            group.matches.where((match) => match.hasResult).length /
                group.matches.where((match) => match.hasPlayers).length,
      ];
      if (groupProgress.length > 1) {
        final spread =
            (groupProgress.reduce((a, b) => a > b ? a : b) -
                groupProgress.reduce((a, b) => a < b ? a : b)) *
            100;
        if (spread >= 25) {
          flowNotices.add(
            'Die Gruppen liegen beim Spielfortschritt ${spread.round()} Prozentpunkte auseinander. '
            'Offene Partien der zurückliegenden Gruppen sollten bevorzugt angesetzt werden.',
          );
        }
      }
      for (final group in groupStage.groups) {
        if (group.players.length >= 3) {
          final playedMap = <TournamentPlayer, int>{};
          for (final p in group.players) {
            playedMap[p] = group.matches
                .where(
                  (m) =>
                      m.hasPlayers &&
                      m.hasResult &&
                      (m.homePlayer == p || m.awayPlayer == p),
                )
                .length;
          }
          final sortedPlayers = group.players.toList()
            ..sort((a, b) => (playedMap[b] ?? 0).compareTo(playedMap[a] ?? 0));
          if (sortedPlayers.length >= 2) {
            final most = sortedPlayers.first;
            final least = sortedPlayers.last;
            final diff = (playedMap[most] ?? 0) - (playedMap[least] ?? 0);
            if (diff >= 2 && (playedMap[least] ?? 0) < group.matches.length) {
              flowNotices.add(
                'In ${group.name} hat ${most.name} bereits ${playedMap[most]} Partien absolviert, '
                'während ${least.name} erst ${playedMap[least]} Partien gespielt hat. '
                'Offene Partien von ${least.name} sollten priorisiert werden, um den Turnierfluss nicht zu blockieren.',
              );
            }
          }
        }
      }
    }

    final totalGames = active.length;
    final progressPct = totalGames > 0
        ? ((completed / totalGames) * 100).round()
        : 0;

    final heroBoard = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TournamentSecondScreenView(tournament: t),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => Dialog.fullscreen(
                child: TournamentSecondScreenView(
                  tournament: t,
                  isStandaloneWindow: true,
                ),
              ),
            ),
            child: const Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Icon(Icons.open_in_new, size: 18),
                Text('2. Bildschirm (TV-Vollbild) öffnen'),
              ],
            ),
          ),
        ),
      ],
    );

    final status = _box([
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dashboard',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text('Aktive Etappe: ${t.runStages[widget.activeStage].name}'),
            ],
          ),
          if (widget.onCompleteStage != null || widget.onFinishEarly != null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.onFinishEarly != null)
                  OutlinedButton.icon(
                    onPressed: !widget.canCompleteStage
                        ? widget.onFinishEarly
                        : null,
                    icon: const Icon(Icons.block_outlined),
                    label: const Text('Vorzeitig beenden'),
                  ),
                if (widget.onCompleteStage != null)
                  FilledButton.icon(
                    onPressed: widget.canCompleteStage
                        ? widget.onCompleteStage
                        : null,
                    icon: Icon(
                      widget.isLastStage
                          ? Icons.check_circle_outline
                          : Icons.arrow_forward,
                    ),
                    label: Text(
                      widget.isLastStage
                          ? 'Turnier abschließen'
                          : 'Etappe abschließen',
                    ),
                  ),
              ],
            ),
        ],
      ),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: totalGames > 0
              ? (completed / totalGames).clamp(0.0, 1.0)
              : 0.0,
          minHeight: 8,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 20,
        runSpacing: 12,
        children: [
          Text(
            '$completed von $totalGames Spielen fertig ($progressPct%)',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text('${active.length - completed} offen'),
          Text('${state.schedule.running.length} laufen gerade'),
          Text('${state.freeBoards.length} Boards frei'),
          Text(
            t.startedAt == null
                ? 'Turnieruhr nicht gestartet'
                : 'Laufzeit: ${_duration(timing.elapsed)} · Start ${_timeOfDay(t.startedAt!)}',
          ),
          Text('Uhrzeit: ${_timeOfDay(now)}'),
          if (timing.forecast != null)
            Text('Prognose Ende: ${_clock(timing.forecast!)}'),
        ],
      ),
      if (!widget.canOperate)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Spielstart derzeit gesperrt: Etappenfreigabe oder Auslosung abwarten.',
          ),
        ),
    ]);

    final notices = _box([
      Text(
        'Hinweise & Empfehlungen',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (widget.saveError != null) ...[
        Text(
          widget.saveError!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        _button(
          'Speichern erneut versuchen',
          () => _act(widget.onChange),
          icon: Icons.save_outlined,
        ),
      ],
      if (_actionError != null) Text(_actionError!),
      for (final notice in flowNotices)
        Builder(
          builder: (context) {
            final colors = Theme.of(context).colorScheme;
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.tertiaryContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.tertiary),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.priority_high,
                    color: colors.onTertiaryContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      notice,
                      style: TextStyle(
                        color: colors.onTertiaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      if (waiting > 0)
        Text('$waiting Paarungen warten auf vorherige Ergebnisse.'),
      if (state.freeBoards.isEmpty &&
          state.schedule.running.isEmpty &&
          state.ready.isNotEmpty)
        const Text(
          'Alle Boards sind gesperrt. Ein Board freigeben, um fortzufahren.',
        ),
      if (active.isNotEmpty && completed == active.length && waiting == 0)
        const Text(
          'Etappe fertig: Buttons oben zum Abschließen oder vorzeitigen Beenden nutzen.',
        ),
      if (widget.saveError == null &&
          _actionError == null &&
          waiting == 0 &&
          flowNotices.isEmpty &&
          !(state.freeBoards.isEmpty && state.ready.isNotEmpty) &&
          !(active.isNotEmpty && completed == active.length))
        const Text(
          'Keine akuten Probleme erkannt. Der Turnierbetrieb läuft flüssig.',
        ),
    ]);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 1000 &&
            MediaQuery.textScalerOf(context).scale(16) <= 24;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.saveError != null) ...[
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.saveError!,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Speichern erneut versuchen'),
                        onPressed: () => _act(widget.onChange),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            heroBoard,
            const SizedBox(height: 12),
            notices,
            const SizedBox(height: 12),
            status,
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [], // Boards and games UI removed for refactor
              )
            else
              const SizedBox.shrink(),
          ],
        );
      },
    );
  }
}
