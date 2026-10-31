import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../../../shared/theme/tournament_display_palette.dart';
import '../../../application/order_of_play/order_of_play_controller.dart';
import '../../../../rankings/application/tournament_match_elo_service.dart';
import '../../../../rankings/domain/local_elo_calculator.dart';
import '../../../application/tournament_flow_priority.dart';
import '../../../application/tournament_flow_priority_preferences.dart';
import '../../../domain/tournament_flow_priority_settings.dart';
import '../../../application/tournament_director_snapshot.dart';
import '../../../application/tournament_timing.dart';
import '../../../domain/tournament_models.dart';
import 'tournament_timing_panel.dart';
import 'tournament_second_screen_view.dart';
import 'recommended_matches_table.dart';
import 'recent_match_result_card.dart';

/// Embedded tournament controls for match scheduling and result entry.
class TournamentDirectorDashboard extends StatefulWidget {
  const TournamentDirectorDashboard({
    super.key,
    required this.tournament,
    required this.activeStage,
    required this.onChange,
    required this.onResult,
    required this.onBlock,
    this.onStartOnBoard,
    this.onMoveMatch,
    this.onStartClock,
    this.onPauseClock,
    this.onEditTimes,
    this.onResetClock,
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
  final Future<void> Function(int board, {GroupMatch? match})? onStartOnBoard;
  final Future<void> Function(GroupMatch match, int board)? onMoveMatch;
  final Future<void> Function()? onStartClock;
  final Future<void> Function()? onPauseClock;
  final Future<void> Function(DateTime? startedAt, DateTime? finishedAt)?
  onEditTimes;
  final Future<void> Function()? onResetClock;
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
  final _matchSearchController = TextEditingController();
  final _recentResultsController = ScrollController();
  bool _busy = false;
  String? _actionError;
  int _noticeIndex = 0;
  TournamentFlowPrioritySettings _prioritySettings =
      TournamentFlowPriority.defaultSettings;
  late Future<Map<String, List<TournamentMatchEloChange>>> _eloChanges;
  late String _eloInputFingerprint;

  @override
  void initState() {
    super.initState();
    _refreshEloChanges();
    unawaited(_loadPrioritySettings());
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) {
        setState(() => _noticeIndex++);
      }
    });
  }

  @override
  void didUpdateWidget(covariant TournamentDirectorDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fingerprint = jsonEncode(widget.tournament.toJson());
    if (fingerprint != _eloInputFingerprint) {
      _refreshEloChanges(fingerprint: fingerprint);
    }
  }

  void _refreshEloChanges({String? fingerprint}) {
    _eloInputFingerprint =
        fingerprint ?? jsonEncode(widget.tournament.toJson());
    _eloChanges = TournamentMatchEloService().calculate(widget.tournament);
  }

  Future<void> _loadPrioritySettings() async {
    try {
      final settings = await TournamentFlowPriorityPreferences().load();
      if (mounted) setState(() => _prioritySettings = settings);
    } catch (error) {
      if (mounted) {
        setState(
          () => _actionError =
              'Hinweiseinstellungen konnten nicht geladen werden: $error',
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _matchSearchController.dispose();
    _recentResultsController.dispose();
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

  int? _quickStartBoard(PlayEntry entry) {
    if (!widget.canOperate ||
        widget.tournament.completedStageIndexes.contains(widget.activeStage)) {
      return null;
    }
    final snapshot = TournamentDirectorSnapshot(
      widget.tournament,
      widget.activeStage,
    );
    if (!snapshot.schedule.planned.any(
      (assignment) => identical(assignment.entry.match, entry.match),
    )) {
      return null;
    }
    if (snapshot.schedule.running.any(
      (running) => running.players.any(entry.players.contains),
    )) {
      return null;
    }
    return snapshot.freeBoards.firstOrNull;
  }

  Future<void> _chooseMatchForBoard(
    int board,
    TournamentDirectorSnapshot state,
  ) async {
    final startOnBoard = widget.onStartOnBoard;
    if (startOnBoard == null ||
        !widget.canOperate ||
        widget.tournament.completedStageIndexes.contains(widget.activeStage)) {
      return;
    }
    final busyPlayers = {
      for (final running in state.schedule.running) ...running.players,
    };
    final choices = state.schedule.planned
        .where(
          (assignment) =>
              assignment.entry.stageIndex == widget.activeStage &&
              assignment.entry.match.hasPlayers &&
              !assignment.entry.match.isResolved &&
              !assignment.entry.players.any(busyPlayers.contains),
        )
        .toList();
    if (choices.isEmpty) return;

    final match = await showDialog<GroupMatch>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Partie für Board $board auswählen'),
        content: SizedBox(
          width: 440,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.65,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: choices.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final assignment = choices[index];
                final entry = assignment.entry;
                return ListTile(
                  title: Text(
                    '${entry.match.homePlayer?.shortDisplayName ?? 'Freilos'} - '
                    '${entry.match.awayPlayer?.shortDisplayName ?? 'Freilos'}',
                  ),
                  subtitle: Text(
                    '${entry.origin} · Warteschritt ${assignment.block + 1}',
                  ),
                  onTap: () => Navigator.of(context).pop(entry.match),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
    if (match == null || !mounted) return;
    await startOnBoard(board, match: match);
  }

  Future<void> _chooseBoardForRunningMatch(
    PlayEntry entry,
    TournamentDirectorSnapshot state,
  ) async {
    final moveMatch = widget.onMoveMatch;
    if (moveMatch == null || !widget.canOperate) return;
    final availableBoards = state.freeBoards;
    if (availableBoards.isEmpty) return;
    final board = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Laufende Partie verschieben'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${entry.match.homePlayer?.shortDisplayName ?? 'Freilos'} - '
              '${entry.match.awayPlayer?.shortDisplayName ?? 'Freilos'}',
            ),
            const SizedBox(height: 8),
            for (final board in availableBoards)
              ListTile(
                leading: const Icon(Icons.dashboard_outlined),
                title: Text('Auf Board $board verschieben'),
                onTap: () => Navigator.of(context).pop(board),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
    if (board == null || !mounted) return;
    await _act(() => moveMatch(entry.match, board));
  }

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
          if (showResult) {
            return FutureBuilder<Map<String, List<TournamentMatchEloChange>>>(
              future: _eloChanges,
              builder: (context, snapshot) => SizedBox(
                key: const ValueKey('director-recent-results-scroll'),
                height: 132,
                child: Scrollbar(
                  controller: _recentResultsController,
                  thumbVisibility: entries.length > 2,
                  child: ListView.separated(
                    controller: _recentResultsController,
                    padding: EdgeInsets.zero,
                    itemCount: entries.length,
                    separatorBuilder: (context, index) => const Divider(
                      height: 1,
                      color: TournamentDisplayPalette.border,
                    ),
                    itemBuilder: (context, index) => ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 66),
                      child: _recentMatchLogEntry(
                        entries[index].match,
                        snapshot.data,
                        eloError: snapshot.hasError
                            ? 'Ranglistenänderungen konnten nicht geladen werden.'
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
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

  Widget _matchSearch(TournamentDirectorSnapshot state) {
    final query = _matchSearchController.text.trim();
    final matches = query.isEmpty ? <PlayEntry>[] : state.search(query);
    final busyPlayers = {
      for (final running in state.schedule.running) ...running.players,
    };
    final freeBoard = state.freeBoards.firstOrNull;
    final startOnBoard = widget.onStartOnBoard;

    return _box([
      Text(
        'Partien eines Spielers finden',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('director-player-search'),
        controller: _matchSearchController,
        decoration: const InputDecoration(
          labelText: 'Spielername suchen',
          hintText: 'Name eingeben',
          prefixIcon: Icon(Icons.search),
          border: OutlineInputBorder(),
        ),
        textInputAction: TextInputAction.search,
        onChanged: (_) => setState(() {}),
      ),
      if (query.isNotEmpty) ...[
        const SizedBox(height: 8),
        if (matches.isEmpty)
          const Text('Keine offene Partie mit diesem Spieler gefunden.')
        else
          for (final entry in matches)
            Builder(
              builder: (context) {
                final running = state.schedule.running
                    .where(
                      (candidate) => identical(candidate.match, entry.match),
                    )
                    .firstOrNull;
                final isPlanned = state.schedule.planned.any(
                  (assignment) =>
                      identical(assignment.entry.match, entry.match),
                );
                final canStart =
                    running == null &&
                    isPlanned &&
                    freeBoard != null &&
                    startOnBoard != null &&
                    widget.canOperate &&
                    !widget.tournament.completedStageIndexes.contains(
                      widget.activeStage,
                    ) &&
                    !entry.players.any(busyPlayers.contains);
                final status = running != null
                    ? 'Läuft auf Board ${running.match.boardNumber ?? '—'}'
                    : canStart
                    ? 'Startbar · ${entry.origin}'
                    : isPlanned
                    ? 'Wartet auf ein freies Board oder die Etappenfreigabe'
                    : 'Wartet auf vorherige Ergebnisse';

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${entry.match.homePlayer?.shortDisplayName ?? 'Freilos'} - '
                    '${entry.match.awayPlayer?.shortDisplayName ?? 'Freilos'}',
                  ),
                  subtitle: Text(status),
                  trailing: canStart
                      ? FilledButton.tonal(
                          onPressed: () => _act(
                            () => startOnBoard(freeBoard, match: entry.match),
                          ),
                          child: const Text('Starten'),
                        )
                      : null,
                );
              },
            ),
      ],
    ]);
  }

  Widget _recentMatchLogEntry(
    GroupMatch match,
    Map<String, List<TournamentMatchEloChange>>? changes, {
    String? eloError,
  }) {
    final matchKey = const LocalEloCalculator().matchKey(
      widget.tournament,
      match,
    );
    return RecentMatchResultLogEntry(
      key: ValueKey(
        'director-match-log-${match.round}-${match.homePlayer?.name}-'
        '${match.awayPlayer?.name}',
      ),
      tournament: widget.tournament,
      match: match,
      eloChanges: matchKey == null
          ? const <TournamentMatchEloChange>[]
          : changes?[matchKey] ?? const <TournamentMatchEloChange>[],
      eloError: eloError,
    );
  }

  Widget _queueTile(
    PlayEntry entry, {
    required double width,
    required bool showResult,
    required bool isPriority,
  }) {
    final match = entry.match;
    final startOnBoard = widget.onStartOnBoard;
    final quickStartBoard = !showResult && startOnBoard != null
        ? _quickStartBoard(entry)
        : null;
    if (showResult) {
      return FutureBuilder<Map<String, List<TournamentMatchEloChange>>>(
        future: _eloChanges,
        builder: (context, snapshot) {
          final matchKey = const LocalEloCalculator().matchKey(
            widget.tournament,
            match,
          );
          final changes = matchKey == null
              ? const <TournamentMatchEloChange>[]
              : snapshot.data?[matchKey] ?? const <TournamentMatchEloChange>[];
          return SizedBox(
            width: width,
            child: RecentMatchResultLogEntry(
              key: ValueKey(
                'director-match-tile-result-'
                '${match.round}-${match.homePlayer?.name}-'
                '${match.awayPlayer?.name}',
              ),
              tournament: widget.tournament,
              match: match,
              eloChanges: changes,
              eloError: snapshot.hasError
                  ? 'Ranglistenänderungen konnten nicht geladen werden.'
                  : null,
            ),
          );
        },
      );
    }
    final theme = Theme.of(context);
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
          if (quickStartBoard != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.icon(
                onPressed: () =>
                    _act(() => startOnBoard!(quickStartBoard, match: match)),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Schnellstart'),
              ),
            ),
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
    final activeStageEntries = state.entries
        .where((entry) => entry.stageIndex == widget.activeStage)
        .toList();
    final active = activeStageEntries
        .where((entry) => entry.match.hasPlayers)
        .toList();
    final completed = activeStageEntries
        .where((entry) => entry.match.hasPlayers && entry.match.hasResult)
        .length;
    final totalCompleted = state.entries
        .where((entry) => entry.match.hasPlayers && entry.match.hasResult)
        .length;
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
    final pendingMatches = activeStageEntries
        .where((entry) => entry.match.hasPlayers && !entry.match.isResolved)
        .map((entry) => entry.match)
        .toList();
    final pendingOrder = {
      for (var index = 0; index < activeStageEntries.length; index++)
        activeStageEntries[index].match: index,
    };
    final pendingMatchSet = pendingMatches.toSet();
    final flowPriority = TournamentFlowPriority.forStage(
      t.runStages[widget.activeStage],
      settings: _prioritySettings,
    );
    pendingMatches.sort((a, b) {
      final aIsPriority = flowPriority.prioritizedMatches.contains(a);
      final bIsPriority = flowPriority.prioritizedMatches.contains(b);
      final priorityComparison = aIsPriority == bIsPriority
          ? 0
          : aIsPriority
          ? -1
          : 1;
      if (priorityComparison != 0) return priorityComparison;
      return pendingOrder[a]!.compareTo(pendingOrder[b]!);
    });
    final nextSix = upcoming
        .take(6)
        .map((assignment) => assignment.entry)
        .toList();
    final boardCards = [
      for (var board = 1; board <= t.boardCount; board++)
        Builder(
          builder: (context) {
            final running = state.runningOn(board);
            final blocked = t.blockedBoards.contains(board);
            final suggestion =
                widget.onStartOnBoard != null && widget.canOperate
                ? OrderOfPlayController().suggestForBoard(
                    t,
                    widget.activeStage,
                    board,
                  )
                : null;
            final label = running != null
                ? 'Läuft'
                : blocked
                ? 'Gesperrt'
                : suggestion != null
                ? 'Frei'
                : 'Reserve';
            final accent = running != null
                ? TournamentDisplayPalette.accent
                : blocked
                ? Theme.of(context).colorScheme.error
                : suggestion != null
                ? Colors.green.shade700
                : TournamentDisplayPalette.mutedText;
            return Container(
              width: 180,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: TournamentDisplayPalette.card,
                border: Border.all(
                  color: blocked
                      ? Theme.of(context).colorScheme.error.withAlpha(180)
                      : TournamentDisplayPalette.border,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        running != null
                            ? Icons.sports_score
                            : blocked
                            ? Icons.block
                            : Icons.dashboard_outlined,
                        size: 18,
                        color: accent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Board $board',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (running != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${running.match.homePlayer?.shortDisplayName ?? 'Freilos'} - '
                            '${running.match.awayPlayer?.shortDisplayName ?? 'Freilos'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (widget.onMoveMatch != null &&
                              widget.canOperate &&
                              state.freeBoards.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _chooseBoardForRunningMatch(running, state),
                                icon: const Icon(Icons.swap_horiz_rounded),
                                label: const Text('Board wechseln'),
                              ),
                            ),
                          if (widget.canOperate)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _act(() => widget.onResult(running.match)),
                                icon: const Icon(Icons.edit_note_rounded),
                                label: const Text('Ergebnis erfassen'),
                              ),
                            ),
                        ],
                      ),
                    )
                  else if (blocked)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Für manuellen Betrieb gesperrt.'),
                    )
                  else if (suggestion != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: FilledButton.icon(
                        onPressed: widget.onStartOnBoard == null
                            ? null
                            : () => _act(() => widget.onStartOnBoard!(board)),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Starten'),
                      ),
                    ),
                  if (running == null &&
                      !blocked &&
                      suggestion != null &&
                      widget.onStartOnBoard != null &&
                      widget.canOperate)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton.icon(
                        onPressed: () => _chooseMatchForBoard(board, state),
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: const Text('Partie wählen'),
                      ),
                    ),
                  if (running == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton.icon(
                        onPressed: () => _act(() => widget.onBlock(board)),
                        icon: Icon(
                          blocked
                              ? Icons.lock_open_rounded
                              : Icons.lock_rounded,
                        ),
                        label: Text(blocked ? 'Freigeben' : 'Sperren'),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
    ];
    final recommendedGroups = <RecommendedMatchGroup>[];
    final stage = t.runStages[widget.activeStage];
    if (stage is GroupTournamentRunStage) {
      for (final group in stage.groups) {
        recommendedGroups.add(
          RecommendedMatchGroup(
            name: group.name,
            matches: group.matches.where(pendingMatchSet.contains).toList(),
            isDelayed: flowPriority.delayedGroups.contains(group.name),
          ),
        );
      }
    } else {
      recommendedGroups.add(
        RecommendedMatchGroup(name: stage.name, matches: pendingMatches),
      );
    }
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
    final latestResults = recentResults;
    final flowNotices = flowPriority.notices;

    final totalGames = active.length;
    final totalTournamentGames = state.entries
        .where((entry) => entry.match.hasPlayers)
        .length;

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
            '$completed/$totalGames Spiele in dieser Etappe · '
            '$totalCompleted/$totalTournamentGames gesamt',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
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

    final boardOverview = _box([
      Text('Boards', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: boardCards),
    ]);
    final clock = _box([
      TournamentTimingPanel(
        tournament: t,
        onStart: widget.onStartClock,
        onPauseToggle: widget.onPauseClock,
        onEditTimes: widget.onEditTimes,
        onResetClock: widget.onResetClock,
        allowManualStart: widget.onStartClock != null,
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
        clock,
        const SizedBox(height: 12),
        boardOverview,
        const SizedBox(height: 12),
        _matchSearch(state),
        const SizedBox(height: 12),
        _box([
          Text('Spielplan', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          RecommendedMatchesTable(
            groups: recommendedGroups,
            prioritizedMatches: flowPriority.prioritizedMatches,
            deprioritizedMatches: flowPriority.deprioritizedMatches,
            emptyMessage: 'Keine weiteren Paarungen in der aktiven Etappe.',
            dense: true,
          ),
        ]),
        const SizedBox(height: 12),
        _matchQueue(
          'Schnellstart · nächste Partien',
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
      ],
    );
  }
}
