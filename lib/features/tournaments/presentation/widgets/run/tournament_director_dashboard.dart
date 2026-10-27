import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../../shared/theme/tournament_display_palette.dart';
import '../../../application/tournament_flow_priority.dart';
import '../../../application/tournament_director_snapshot.dart';
import '../../../application/tournament_timing.dart';
import '../../../domain/tournament_models.dart';
import '../../../domain/engines/board_scheduling_engine.dart';
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
    this.onReopenPreviousStage,
    this.canReopenPreviousStage = false,
    this.onResetCurrentStage,
    this.canResetCurrentStage = false,
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
  final VoidCallback? onReopenPreviousStage;
  final bool canReopenPreviousStage;
  final VoidCallback? onResetCurrentStage;
  final bool canResetCurrentStage;
  @override
  State<TournamentDirectorDashboard> createState() =>
      _TournamentDirectorDashboardState();
}

class _TournamentDirectorDashboardState
    extends State<TournamentDirectorDashboard> {
  Timer? _timer;
  bool _busy = false;
  String? _actionError;
  int _noticeIndex = 0;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) {
        setState(() => _noticeIndex++);
      }
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

  bool _hasNextKnockoutStage(CreatedTournament tournament) {
    if (widget.activeStage < 0 ||
        widget.activeStage >= tournament.runStages.length ||
        tournament.runStages[widget.activeStage]
            is KnockoutTournamentRunStage) {
      return false;
    }
    return tournament.runStages
        .skip(widget.activeStage + 1)
        .any((stage) => stage is KnockoutTournamentRunStage);
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

  Widget _matchQueue(
    String title,
    List<PlayEntry> entries, {
    required String emptyMessage,
    bool showResult = false,
    int? maxColumns,
    Set<GroupMatch> prioritizedMatches = const {},
  }) => _box([
    Text(title, style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    if (entries.isEmpty)
      Text(emptyMessage)
    else
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = maxColumns == null
              ? constraints.maxWidth >= 1100
                    ? 6
                    : constraints.maxWidth >= 700
                    ? 3
                    : 1
              : ((constraints.maxWidth + 8) / 228).floor().clamp(1, maxColumns);
          final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in entries)
                _queueTile(
                  entry,
                  width: width,
                  showResult: showResult,
                  isPriority: prioritizedMatches.contains(entry.match),
                ),
            ],
          );
        },
      ),
  ]);

  Widget _queueTile(
    PlayEntry entry, {
    required double width,
    required bool showResult,
    required bool isPriority,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final match = entry.match;
    return Container(
      key: ValueKey(
        'director-match-tile-${showResult ? 'result' : 'next'}-'
        '${match.round}-${match.homePlayer?.name}-${match.awayPlayer?.name}',
      ),
      width: width,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isPriority
            ? TournamentDisplayPalette.cardEmphasis
            : TournamentDisplayPalette.card,
        border: Border.all(
          color: isPriority
              ? TournamentDisplayPalette.accent.withAlpha(180)
              : TournamentDisplayPalette.border.withAlpha(150),
          width: isPriority ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                showResult ? Icons.check_circle_outline : Icons.sports_score,
                size: 18,
                color: TournamentDisplayPalette.mutedText,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  showResult
                      ? entry.origin
                      : 'Etappe ${entry.stageIndex + 1}'
                            '${match.boardNumber == null ? '' : ' · Board ${match.boardNumber}'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: TournamentDisplayPalette.mutedText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isPriority)
                Tooltip(
                  message: 'Priorisierte Partie',
                  child: Text(
                    '!',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: TournamentDisplayPalette.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${match.homePlayer?.shortDisplayName ?? 'Freilos'} - '
            '${match.awayPlayer?.shortDisplayName ?? 'Freilos'}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: TournamentDisplayPalette.text,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (showResult) ...[
            const SizedBox(height: 4),
            Text(
              '${match.homeLegs ?? 0}:${match.awayLegs ?? 0}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: TournamentDisplayPalette.text,
              ),
            ),
            for (final performance in match.bestPerformances.take(2))
              Text(
                '${performance.playerName} · ${performance.label}'
                '${performance.value == null ? '' : ' ${performance.value}'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ],
      ),
    );
  }

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
    final upcoming = state.schedule.planned
        .where(
          (assignment) =>
              assignment.entry.stageIndex == widget.activeStage &&
              assignment.entry.match.hasPlayers,
        )
        .toList();
    final flowPriority = TournamentFlowPriority.forStage(
      t.runStages[widget.activeStage],
    );
    upcoming.sort((a, b) {
      final aIsPriority = flowPriority.prioritizedMatches.contains(
        a.entry.match,
      );
      final bIsPriority = flowPriority.prioritizedMatches.contains(
        b.entry.match,
      );
      final priorityComparison = aIsPriority == bIsPriority
          ? 0
          : aIsPriority
          ? -1
          : 1;
      if (priorityComparison != 0) return priorityComparison;
      return a.block.compareTo(b.block);
    });
    final nextSix = upcoming
        .take(6)
        .map((assignment) => assignment.entry)
        .toList();
    final resultEntryOrder = {
      for (var index = 0; index < state.entries.length; index++)
        state.entries[index].match: index,
    };
    final recentResults =
        state.entries
            .where(
              (entry) =>
                  entry.stageIndex == widget.activeStage &&
                  entry.match.hasPlayers &&
                  entry.match.hasResult,
            )
            .toList()
          ..sort((a, b) {
            final aTime =
                a.match.finishedAt ??
                a.match.startedAt ??
                t.startedAt ??
                t.createdAt;
            final bTime =
                b.match.finishedAt ??
                b.match.startedAt ??
                t.startedAt ??
                t.createdAt;
            final timeComparison = bTime.compareTo(aTime);
            if (timeComparison != 0) return timeComparison;
            return (resultEntryOrder[b.match] ?? 0).compareTo(
              resultEntryOrder[a.match] ?? 0,
            );
          });
    final latestResults = recentResults.take(4).toList();
    final bestPerformances = [
      for (final entry in recentResults) ...entry.match.bestPerformances,
    ];
    final flowNotices = flowPriority.notices;

    final totalGames = active.length;
    final progressPct = totalGames > 0
        ? ((completed / totalGames) * 100).round()
        : 0;

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
          if (widget.onCompleteStage != null ||
              widget.onFinishEarly != null ||
              (widget.onReopenPreviousStage != null &&
                  widget.canReopenPreviousStage) ||
              (widget.onResetCurrentStage != null &&
                  widget.canResetCurrentStage))
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.onReopenPreviousStage != null &&
                    widget.canReopenPreviousStage)
                  OutlinedButton.icon(
                    onPressed: widget.onReopenPreviousStage,
                    icon: const Icon(Icons.undo),
                    label: const Text('Vorherige Etappe wieder öffnen'),
                  ),
                if (widget.onResetCurrentStage != null &&
                    widget.canResetCurrentStage)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: widget.onResetCurrentStage,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Etappe zurücksetzen'),
                  ),
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
                if (_hasNextKnockoutStage(t))
                  OutlinedButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => Dialog.fullscreen(
                        child: TournamentSecondScreenView(
                          tournament: t,
                          isStandaloneWindow: true,
                          showNextStagePreviewInitially: true,
                          onClose: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.account_tree_outlined),
                    label: const Text('Vorschau nächste Etappe'),
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
          Text(
            t.startedAt == null
                ? 'Turnieruhr nicht gestartet'
                : 'Laufzeit: ${_duration(timing.elapsed)} · Start ${_timeOfDay(t.startedAt!)}',
          ),
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
      if (flowNotices.isNotEmpty)
        Builder(
          builder: (context) {
            final notice = flowNotices[_noticeIndex % flowNotices.length];
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: TournamentDisplayPalette.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: TournamentDisplayPalette.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.priority_high,
                    color: TournamentDisplayPalette.accent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      notice,
                      style: TextStyle(
                        color: TournamentDisplayPalette.text,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        notices,
        const SizedBox(height: 12),
        status,
        const SizedBox(height: 12),
        _matchQueue(
          'Empfohlene Partien',
          nextSix,
          emptyMessage: 'Keine weiteren Paarungen in der aktiven Etappe.',
          prioritizedMatches: flowPriority.prioritizedMatches,
        ),
        const SizedBox(height: 12),
        _matchQueue(
          'Letzte Ergebnisse',
          latestResults,
          emptyMessage: 'Noch keine Ergebnisse in dieser Etappe.',
          showResult: true,
          maxColumns: 4,
        ),
        if (bestPerformances.isNotEmpty) ...[
          const SizedBox(height: 12),
          _box([
            Text(
              'Bestleistungen',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final performance in bestPerformances)
                  Chip(
                    avatar: const Icon(Icons.military_tech_outlined, size: 18),
                    label: Text(
                      '${performance.playerName} · ${performance.label}'
                      '${performance.value == null ? '' : ' ${performance.value}'}',
                    ),
                  ),
              ],
            ),
          ]),
        ],
      ],
    );
  }
}
