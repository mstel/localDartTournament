import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../../../shared/theme/tournament_display_palette.dart';
import '../../../application/order_of_play/order_of_play_controller.dart';
import '../../../../rankings/application/tournament_match_elo_service.dart';
import '../../../../rankings/domain/local_elo_calculator.dart';
import '../../../application/tournament_flow_priority.dart';
import '../../../domain/tournament_flow_priority_settings.dart';
import '../../../application/tournament_director_snapshot.dart';
import '../../../application/tournament_timing.dart';
import '../../../application/tournament_audio_announcement_service.dart';
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
    this.directorModeEnabled = false,
    this.showBoardNumber,
    this.onStartOnBoard,
    this.onResetMatch,
    this.onOpenMatch,
    this.onStartClock,
    this.onPauseClock,
    this.onEditTimes,
    this.onResetClock,
    this.onChangeTournamentDate,
    this.onShiftMatchDates,
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
  final bool directorModeEnabled;
  final bool? showBoardNumber;
  final Future<void> Function(int board, {GroupMatch? match})? onStartOnBoard;
  final Future<void> Function(GroupMatch match)? onResetMatch;
  final ValueChanged<GroupMatch>? onOpenMatch;
  final Future<void> Function()? onStartClock;
  final Future<void> Function()? onPauseClock;
  final Future<void> Function(DateTime? startedAt, DateTime? finishedAt)?
  onEditTimes;
  final Future<void> Function()? onResetClock;
  final ValueChanged<DateTime>? onChangeTournamentDate;
  final Future<int> Function(DateTime date)? onShiftMatchDates;
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
  final _matchSearchController = TextEditingController();
  final _recentResultsController = ScrollController();
  bool _busy = false;
  String? _actionError;
  TournamentAudioAnnouncementService? _alertAudio;
  final Map<int, DateTime> _idleBoardSince = {};
  final Map<int, DateTime> _idleBoardLastAlert = {};
  Timer? _idleBoardTimer;
  List<String> _visibleNotices = const [];
  bool _hasObservedNotices = false;
  DateTime? _lastAlertAt;
  late Future<Map<String, List<TournamentMatchEloChange>>> _eloChanges;
  late String _eloInputFingerprint;

  TournamentAudioAnnouncementService get _audio =>
      _alertAudio ??= TournamentAudioAnnouncementService();

  TournamentFlowPrioritySettings get _prioritySettings {
    final settings = widget.tournament.tournamentSettings;
    return TournamentFlowPrioritySettings(
      playerMatchDeficitThreshold: settings.playerMatchDeficitThreshold,
      groupMatchDeficitThreshold: settings.groupMatchDeficitThreshold,
      usePercentageForGroups: settings.usePercentageForGroups,
    );
  }

  @override
  void initState() {
    super.initState();
    _refreshEloChanges();
    _idleBoardTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _checkIdleBoardSound(),
    );
  }

  @override
  void didUpdateWidget(covariant TournamentDirectorDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fingerprint = jsonEncode(widget.tournament.toJson());
    if (fingerprint != _eloInputFingerprint) {
      _refreshEloChanges(fingerprint: fingerprint);
    }
    if (oldWidget.tournament.id != widget.tournament.id ||
        oldWidget.activeStage != widget.activeStage) {
      _idleBoardSince.clear();
      _idleBoardLastAlert.clear();
      _visibleNotices = const [];
      _hasObservedNotices = false;
    }
  }

  String _displayGroupLabel(String? groupKey) {
    if (groupKey == null || groupKey.trim().isEmpty) return '';
    final cleaned = groupKey.trim();
    final separatorIndex = cleaned.indexOf(':');
    if (separatorIndex >= 0) {
      final prefix = cleaned.substring(0, separatorIndex).trim();
      if (prefix.isNotEmpty && int.tryParse(prefix) != null) {
        final remainder = cleaned.substring(separatorIndex + 1).trim();
        if (remainder.isNotEmpty) return remainder;
      }
    }
    return cleaned;
  }

  void _refreshEloChanges({String? fingerprint}) {
    _eloInputFingerprint =
        fingerprint ?? jsonEncode(widget.tournament.toJson());
    _eloChanges = TournamentMatchEloService().calculate(widget.tournament);
  }

  void _observeNotices(List<String> notices) {
    final previous = _visibleNotices.toSet();
    final current = notices.toSet();
    final newlyVisible = current.difference(previous);
    _visibleNotices = notices;
    if (!_hasObservedNotices) {
      _hasObservedNotices = true;
      return;
    }
    if (newlyVisible.isEmpty ||
        !widget.tournament.tournamentSettings.announceHintsAudibly) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.tournament.tournamentSettings.announceHintsAudibly &&
          newlyVisible.any(_visibleNotices.contains)) {
        _playAlert();
      }
    });
  }

  void _checkIdleBoardSound() {
    if (!mounted) return;
    final settings = widget.tournament.tournamentSettings;
    if (!widget.directorModeEnabled || !settings.idleBoardSoundEnabled) {
      _idleBoardSince.clear();
      _idleBoardLastAlert.clear();
      return;
    }
    final snapshot = TournamentDirectorSnapshot(
      widget.tournament,
      widget.activeStage,
    );
    final hasPlayableMatches = snapshot.ready.any(snapshot.canStart);
    final freeBoards = hasPlayableMatches
        ? snapshot.freeBoards.toSet()
        : <int>{};
    final now = DateTime.now();
    _idleBoardSince.removeWhere((board, _) => !freeBoards.contains(board));
    _idleBoardLastAlert.removeWhere((board, _) => !freeBoards.contains(board));
    for (final board in freeBoards) {
      final lastBoardMatch = snapshot.entries
          .map((entry) => entry.match)
          .where(
            (match) =>
                match.boardNumber == board &&
                match.finishedAt != null &&
                !match.isAnnulled,
          )
          .map((match) => match.finishedAt!)
          .fold<DateTime?>(null, (latest, finishedAt) {
            if (latest == null || finishedAt.isAfter(latest)) {
              return finishedAt;
            }
            return latest;
          });
      final tournamentStart = widget.tournament.startedAt ?? now;
      final inferredSince =
          lastBoardMatch != null && lastBoardMatch.isAfter(tournamentStart)
          ? lastBoardMatch
          : tournamentStart;
      _idleBoardSince.putIfAbsent(board, () => inferredSince);
    }
    final dueBoards = freeBoards.where((board) {
      final since = _idleBoardSince[board]!;
      final firstAlertAt = since.add(
        Duration(minutes: settings.idleBoardSoundStartMinutes),
      );
      final lastAlert = _idleBoardLastAlert[board];
      return lastAlert == null
          ? !now.isBefore(firstAlertAt)
          : now.difference(lastAlert) >=
                Duration(minutes: settings.idleBoardSoundRepeatMinutes);
    }).toList();
    if (dueBoards.isEmpty) return;
    for (final board in dueBoards) {
      _idleBoardLastAlert[board] = now;
      final elapsed = now.difference(_idleBoardSince[board]!);
      unawaited(
        _audio.speakGerman(
          '${widget.tournament.boardDisplayName(board)} seit '
          '${elapsed.inMinutes} Minuten frei',
        ),
      );
    }
  }

  void _playAlert() {
    final now = DateTime.now();
    if (_lastAlertAt != null &&
        now.difference(_lastAlertAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastAlertAt = now;
    unawaited(_audio.playAlert());
  }

  @override
  void dispose() {
    _idleBoardTimer?.cancel();
    final alertAudio = _alertAudio;
    if (alertAudio != null) unawaited(alertAudio.dispose());
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
  bool get _showBoardNumber =>
      widget.showBoardNumber ?? widget.directorModeEnabled;

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
    final assignment = snapshot.schedule.planned
        .where((assignment) => identical(assignment.entry.match, entry.match))
        .firstOrNull;
    return assignment != null && snapshot.freeBoards.contains(assignment.board)
        ? assignment.board
        : null;
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
    final choices = state.selectableForBoard(board);
    if (choices.isEmpty) return;

    final match = await showDialog<GroupMatch>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Partie für ${widget.tournament.boardDisplayName(board)} auswählen',
        ),
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
                  title: Text(entry.match.participantShortLabel),
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

  Widget _matchQueue(
    String title,
    List<PlayEntry> entries, {
    required String emptyMessage,
    bool showResult = false,
    int? maxColumns,
    Set<GroupMatch> prioritizedMatches = const {},
    Map<GroupMatch, int> plannedBoards = const {},
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
                  plannedBoard: plannedBoards[entry.match],
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
    final startOnBoard = widget.onStartOnBoard;

    return _box([
      Text(
        'Partien eines Teilnehmers finden',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('director-player-search'),
        controller: _matchSearchController,
        decoration: const InputDecoration(
          labelText: 'Teilnehmername suchen',
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
          const Text('Keine offene Partie mit diesem Teilnehmer gefunden.')
        else
          for (final entry in matches)
            Builder(
              builder: (context) {
                final running = state.schedule.running
                    .where(
                      (candidate) => identical(candidate.match, entry.match),
                    )
                    .firstOrNull;
                final assignment = state.schedule.planned
                    .where(
                      (candidate) =>
                          identical(candidate.entry.match, entry.match),
                    )
                    .firstOrNull;
                final canStart =
                    running == null &&
                    assignment != null &&
                    state.freeBoards.contains(assignment.board) &&
                    startOnBoard != null &&
                    widget.canOperate &&
                    !widget.tournament.completedStageIndexes.contains(
                      widget.activeStage,
                    ) &&
                    !entry.players.any(busyPlayers.contains);
                final status = running != null
                    ? 'Läuft auf ${running.match.boardNumber == null ? 'Board —' : widget.tournament.boardDisplayName(running.match.boardNumber!)}'
                    : canStart
                    ? 'Startbar · ${widget.tournament.boardDisplayName(assignment.board)}'
                    : assignment != null
                    ? 'Wartet auf ein freies Board oder die Phasenfreigabe'
                    : 'Wartet auf vorherige Ergebnisse';

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.match.participantShortLabel),
                  subtitle: Text(status),
                  trailing: canStart
                      ? FilledButton.tonal(
                          onPressed: () => _act(
                            () => startOnBoard(
                              assignment.board,
                              match: entry.match,
                            ),
                          ),
                          child: Text(
                            '${widget.tournament.boardDisplayName(assignment.board)} starten',
                          ),
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
        'director-match-log-${match.round}-${match.participantLabel}',
      ),
      tournament: widget.tournament,
      match: match,
      eloChanges: matchKey == null
          ? const <TournamentMatchEloChange>[]
          : changes?[matchKey] ?? const <TournamentMatchEloChange>[],
      eloError: eloError,
      showBoardNumber: _showBoardNumber,
      onTap: widget.onOpenMatch == null
          ? null
          : () => widget.onOpenMatch!(match),
    );
  }

  Widget _queueTile(
    PlayEntry entry, {
    required double width,
    required bool showResult,
    required bool isPriority,
    int? plannedBoard,
  }) {
    final match = entry.match;
    final startOnBoard = widget.onStartOnBoard;
    final quickStartBoard =
        widget.directorModeEnabled && !showResult && startOnBoard != null
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
                '${match.round}-${match.participantLabel}',
              ),
              tournament: widget.tournament,
              match: match,
              eloChanges: changes,
              eloError: snapshot.hasError
                  ? 'Ranglistenänderungen konnten nicht geladen werden.'
                  : null,
              showBoardNumber: _showBoardNumber,
              onTap: widget.onOpenMatch == null
                  ? null
                  : () => widget.onOpenMatch!(match),
            ),
          );
        },
      );
    }
    final theme = Theme.of(context);
    return Container(
      key: ValueKey(
        'director-match-tile-${showResult ? 'result' : 'next'}-'
        '${match.round}-${match.participantLabel}',
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
                      : _showBoardNumber
                      ? plannedBoard != null
                            ? widget.tournament.boardDisplayName(plannedBoard)
                            : match.boardNumber != null
                            ? widget.tournament.boardDisplayName(
                                match.boardNumber!,
                              )
                            : 'Wartet'
                      : 'Nächste Partie',
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
          Row(
            children: [
              Expanded(
                child: Text(
                  match.participantShortLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: TournamentDisplayPalette.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (quickStartBoard != null)
                Tooltip(
                  message:
                      'Partie auf ${widget.tournament.boardDisplayName(quickStartBoard)} starten',
                  child: IconButton.filledTonal(
                    tooltip:
                        'Partie auf ${widget.tournament.boardDisplayName(quickStartBoard)} starten',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: () => _act(
                      () => startOnBoard!(quickStartBoard, match: match),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                ),
            ],
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
    final directorPlan = activeStageEntries
        .where((entry) => entry.match.hasPlayers && !entry.match.isResolved)
        .toList();
    final pendingMatches = directorPlan.map((entry) => entry.match).toList();
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
    final boardAssignments = <int, List<BoardAssignment>>{
      for (var board = 1; board <= t.boardCount; board++)
        board: state.upcomingForBoard(board),
    };
    final boardCards = !widget.directorModeEnabled
        ? <Widget>[]
        : [
            for (var board = 1; board <= t.boardCount; board++)
              Builder(
                builder: (context) {
                  final running = state.runningOn(board);
                  final blocked = t.blockedBoards.contains(board);
                  final upcomingForBoard = boardAssignments[board]!;
                  final recommendation = state.recommendationForBoard(board);
                  final suggestion = recommendation?.next;
                  final alternative = recommendation?.alternative;
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
                  final assignedGroups =
                      <String>{
                            ?running?.groupKey,
                            for (final assignment in upcomingForBoard)
                              ?assignment.entry.groupKey,
                          }
                          .map(_displayGroupLabel)
                          .where((value) => value.isNotEmpty)
                          .toList()
                        ..sort();
                  return Container(
                    key: ValueKey('director-board-$board'),
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
                                widget.tournament.boardDisplayName(board),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          label,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (widget.tournament.directorSchedulingStrategy ==
                                'group' &&
                            assignedGroups.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              assignedGroups.join(' · '),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: TournamentDisplayPalette.mutedText,
                                  ),
                            ),
                          ),
                        if (running != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  running.match.participantShortLabel,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (widget.canOperate)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final resultButton =
                                            OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                minimumSize: const Size(0, 48),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                    ),
                                              ),
                                              onPressed: () => _act(
                                                () => widget.onResult(
                                                  running.match,
                                                ),
                                              ),
                                              icon: const Icon(
                                                Icons.edit_note_rounded,
                                              ),
                                              label: const Text(
                                                'Ergebnis erfassen',
                                              ),
                                            );
                                        final resetButton =
                                            widget.onResetMatch == null
                                            ? null
                                            : OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  minimumSize: const Size(
                                                    0,
                                                    48,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                      ),
                                                ),
                                                onPressed: () => _act(
                                                  () => widget.onResetMatch!(
                                                    running.match,
                                                  ),
                                                ),
                                                icon: const Icon(
                                                  Icons.refresh_rounded,
                                                ),
                                                label: const Text(
                                                  'Partie zurücksetzen',
                                                ),
                                              );
                                        if (resetButton != null &&
                                            constraints.maxWidth >= 300) {
                                          return Row(
                                            children: [
                                              Expanded(child: resultButton),
                                              const SizedBox(width: 8),
                                              Expanded(child: resetButton),
                                            ],
                                          );
                                        }
                                        return Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            resultButton,
                                            ?resetButton,
                                          ],
                                        );
                                      },
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
                          const SizedBox.shrink(),
                        if (!blocked && upcomingForBoard.isNotEmpty)
                          for (final assignment in upcomingForBoard)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    '${identical(assignment.entry.match, suggestion?.entry.match) ? 'Nächste Partie: ' : ''}${assignment.entry.match.participantShortLabel}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  if (widget.onStartOnBoard != null)
                                    Tooltip(
                                      message:
                                          'Partie auf ${t.boardDisplayName(board)} starten',
                                      child: FilledButton.tonalIcon(
                                        onPressed:
                                            widget.canOperate &&
                                                state.canStart(assignment.entry)
                                            ? () => _act(
                                                () => widget.onStartOnBoard!(
                                                  board,
                                                  match: assignment.entry.match,
                                                ),
                                              )
                                            : null,
                                        icon: const Icon(
                                          Icons.play_arrow_rounded,
                                          size: 18,
                                        ),
                                        label: Text(t.boardDisplayName(board)),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        if (!blocked && alternative != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Alternative: ${alternative.entry.match.participantShortLabel}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (widget.onStartOnBoard != null)
                                  Tooltip(
                                    message:
                                        'Alternative auf ${t.boardDisplayName(board)} starten',
                                    child: FilledButton.tonalIcon(
                                      onPressed:
                                          widget.canOperate &&
                                              state.canStart(alternative.entry)
                                          ? () => _act(
                                              () => widget.onStartOnBoard!(
                                                board,
                                                match: alternative.entry.match,
                                              ),
                                            )
                                          : null,
                                      icon: const Icon(
                                        Icons.play_arrow_rounded,
                                        size: 18,
                                      ),
                                      label: Text(
                                        '${t.boardDisplayName(board)} starten',
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (running == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (!blocked &&
                                    suggestion != null &&
                                    widget.onStartOnBoard != null &&
                                    widget.canOperate)
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _chooseMatchForBoard(board, state),
                                    icon: const Icon(Icons.swap_horiz_rounded),
                                    label: const Text('Partie wählen'),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      _act(() => widget.onBlock(board)),
                                  icon: Icon(
                                    blocked
                                        ? Icons.lock_open_rounded
                                        : Icons.lock_rounded,
                                  ),
                                  label: Text(
                                    blocked ? 'Freigeben' : 'Sperren',
                                  ),
                                ),
                              ],
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
    _observeNotices(flowNotices);

    final totalGames = active.length;
    final totalTournamentGames = state.entries
        .where((entry) => entry.match.hasPlayers)
        .length;

    final hasStageActions =
        widget.onCompleteStage != null ||
        widget.onFinishEarly != null ||
        (widget.onReopenPreviousStage != null &&
            widget.canReopenPreviousStage) ||
        (widget.onResetCurrentStage != null && widget.canResetCurrentStage);
    final Widget? stageActions = hasStageActions
        ? Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.onReopenPreviousStage != null &&
                  widget.canReopenPreviousStage)
                OutlinedButton.icon(
                  onPressed: widget.onReopenPreviousStage,
                  icon: const Icon(Icons.undo),
                  label: const Text('Vorherige Phase wieder öffnen'),
                ),
              if (widget.onResetCurrentStage != null &&
                  widget.canResetCurrentStage)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: widget.onResetCurrentStage,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Phase zurücksetzen'),
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
                        : 'Phase abschließen',
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
                  label: const Text('Vorschau nächste Phase'),
                ),
            ],
          )
        : null;
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
                'Übersicht',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
          ?stageActions,
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
      if (stage is KnockoutTournamentRunStage && stage.isKratzer) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final player in stage.participants)
              Builder(
                builder: (context) {
                  final lives = stage.livesRemainingFor(player);
                  return Chip(
                    avatar: Icon(
                      lives == 0
                          ? Icons.person_off_outlined
                          : Icons.favorite_outline,
                      size: 18,
                    ),
                    label: Text('${player.shortDisplayName} · $lives Leben'),
                  );
                },
              ),
          ],
        ),
      ],
      const SizedBox(height: 8),
      Wrap(
        spacing: 20,
        runSpacing: 12,
        children: [
          Text(
            '$completed/$totalGames Begegnungen in dieser Phase · '
            '$totalCompleted/$totalTournamentGames gesamt',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          _TournamentClockSummary(tournament: t),
        ],
      ),
      if (!widget.canOperate)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Start derzeit gesperrt: Phasenfreigabe oder Auslosung abwarten.',
          ),
        ),
    ]);

    final boardOverview = _box([
      Text('Boards', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = ((constraints.maxWidth + 8) / 220).floor().clamp(
            1,
            t.boardCount,
          );
          final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
          final cards = [
            for (var index = 0; index < boardCards.length; index++)
              SizedBox(width: width, child: boardCards[index]),
          ];
          return Wrap(spacing: 8, runSpacing: 8, children: cards);
        },
      ),
      if (widget.directorModeEnabled && stageActions != null) ...[
        const Divider(height: 28),
        stageActions,
      ],
    ]);
    final clock = _box([
      TournamentTimingPanel(
        tournament: t,
        onStart: widget.onStartClock,
        onPauseToggle: widget.onPauseClock,
        onEditTimes: widget.onEditTimes,
        onResetClock: widget.onResetClock,
        onChangeTournamentDate: widget.onChangeTournamentDate,
        onShiftMatchDates: widget.onShiftMatchDates,
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
      for (final notice in flowNotices)
        Container(
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
        ),
      if (waiting > 0)
        Text('$waiting Paarungen warten auf vorherige Ergebnisse.'),
      if (state.freeBoards.isEmpty &&
          state.schedule.running.isEmpty &&
          state.ready.isNotEmpty)
        const Text(
          'Alle Boards sind gesperrt. Ein Board freigeben, um fortzufahren.',
        ),
      const SizedBox(height: 8),
      if (!widget.directorModeEnabled &&
          active.isNotEmpty &&
          completed == active.length &&
          waiting == 0)
        const Text(
          'Phase fertig: Buttons oben zum Abschließen oder vorzeitigen Beenden nutzen.',
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
        if (!widget.directorModeEnabled) ...[
          status,
          const SizedBox(height: 12),
          clock,
          const SizedBox(height: 12),
        ],
        if (widget.directorModeEnabled) ...[
          boardOverview,
          const SizedBox(height: 12),
          _matchSearch(state),
          const SizedBox(height: 12),
          _matchQueue(
            'Spielplan',
            directorPlan,
            emptyMessage: 'Keine weiteren Paarungen in der aktiven Phase.',
            prioritizedMatches: flowPriority.prioritizedMatches,
            plannedBoards: {
              for (final assignment in upcoming)
                assignment.entry.match: assignment.board,
            },
          ),
        ] else ...[
          _matchQueue(
            'Empfohlene Partien',
            nextSix,
            emptyMessage: 'Keine weiteren Paarungen in der aktiven Phase.',
            prioritizedMatches: flowPriority.prioritizedMatches,
            plannedBoards: {
              for (final assignment in upcoming)
                assignment.entry.match: assignment.board,
            },
          ),
          const SizedBox(height: 12),
          _box([
            Text('Spielplan', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            RecommendedMatchesTable(
              groups: recommendedGroups,
              prioritizedMatches: flowPriority.prioritizedMatches,
              deprioritizedMatches: flowPriority.deprioritizedMatches,
              emptyMessage: 'Keine weiteren Paarungen in der aktiven Phase.',
              dense: true,
            ),
          ]),
        ],
        const SizedBox(height: 12),
        _matchQueue(
          'Letzte Ergebnisse',
          latestResults,
          emptyMessage: 'Noch keine Ergebnisse in dieser Phase.',
          showResult: true,
          maxColumns: 4,
        ),
      ],
    );
  }
}

class _TournamentClockSummary extends StatefulWidget {
  const _TournamentClockSummary({required this.tournament});

  final CreatedTournament tournament;

  @override
  State<_TournamentClockSummary> createState() =>
      _TournamentClockSummaryState();
}

class _TournamentClockSummaryState extends State<_TournamentClockSummary> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _TournamentClockSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  void _syncTimer() {
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

  @override
  Widget build(BuildContext context) {
    final tournament = widget.tournament;
    if (tournament.startedAt == null) {
      return const Text('Turnieruhr nicht gestartet');
    }
    final timing = TournamentTiming.snapshot(tournament, DateTime.now());
    final localStart = tournament.startedAt!.toLocal();
    final start =
        '${localStart.hour.toString().padLeft(2, '0')}:'
        '${localStart.minute.toString().padLeft(2, '0')} Uhr';
    return Wrap(
      spacing: 20,
      runSpacing: 12,
      children: [
        Text(
          'Laufzeit: ${timing.elapsed.inHours} h '
          '${timing.elapsed.inMinutes.remainder(60)} min · Start $start',
        ),
        if (timing.forecast != null)
          Text(
            'Prognose Ende: '
            '${timing.forecast!.toLocal().hour.toString().padLeft(2, '0')}:'
            '${timing.forecast!.toLocal().minute.toString().padLeft(2, '0')}',
          ),
      ],
    );
  }
}
