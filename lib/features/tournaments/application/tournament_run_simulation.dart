import 'dart:math' as math;

import '../../league/application/league_board_runtime.dart';
import '../domain/tournament_models.dart';
import '../domain/tournament_planning_parameters.dart';
import '../domain/tournament_format_planner.dart';
import 'order_of_play/order_of_play_controller.dart';
import 'tournament_simulation_runtime.dart';

enum TournamentSimulationMode { fixedStep, randomStep }

typedef TournamentSimulationRuntimeFactory =
    TournamentSimulationRuntime Function(CreatedTournament tournament);

class TournamentRunSimulation {
  TournamentRunSimulation({
    required CreatedTournament source,
    required TournamentPlanningParameters planningParameters,
    required int seed,
    required TournamentSimulationMode mode,
    required int minimumMinutes,
    required int maximumMinutes,
    required TournamentSimulationRuntimeFactory runtimeFactory,
    bool autoStartMatches = true,
  }) : _tournament = CreatedTournament.fromJson(source.toJson()),
       _planningParameters = planningParameters,
       _seed = seed,
       _mode = mode,
       _minimumMinutes = minimumMinutes,
       _maximumMinutes = maximumMinutes,
       _autoStartMatches = autoStartMatches,
       _runtimeFactory = runtimeFactory,
       _random = _SimulationRandom(seed) {
    if (minimumMinutes < 1 ||
        maximumMinutes < minimumMinutes ||
        maximumMinutes > 120) {
      throw ArgumentError('Ungültiger Bereich für die Spieldauer.');
    }
    if (_tournament.leagueMatch != null) {
      _leagueRuntime = LeagueBoardRuntime(_tournament)..installOn(_tournament);
    }
    _runtime = _runtimeFactory(_tournament);
    if (_tournament.runStages.isEmpty) {
      if (_tournament.stages.isEmpty) {
        throw StateError('Für dieses Turnier ist keine Simulation verfügbar.');
      }
      _tournament.runStages.add(
        _runtime.build(_tournament.stages.first, _tournament.players),
      );
    }
    _tournament
      ..activeStageIndex = _tournament.activeStageIndex.clamp(
        0,
        _tournament.runStages.length - 1,
      )
      ..startedAt = _origin
      ..finishedAt = null
      ..pausedAt = null
      ..totalPausedSeconds = 0
      ..completedStageIndexes.clear();
    _activateStage(_tournament.activeStageIndex);
    for (var index = 0; index < _tournament.runStages.length; index++) {
      for (final match in _runtime.matches(_tournament.runStages[index])) {
        if (match.hasResult || match.isAnnulled) continue;
        match
          ..boardNumber = null
          ..startedAt = null
          ..finishedAt = null
          ..startedPlayers = null;
      }
    }
    _leagueRuntime?.writeTo(_tournament);
    _appendLog('Simulation gestartet.');
    _initialSnapshot = _takeSnapshot();
  }

  static final DateTime _origin = DateTime.utc(2000, 1, 1);
  final TournamentPlanningParameters _planningParameters;
  final TournamentSimulationRuntimeFactory _runtimeFactory;
  final OrderOfPlayController _orderOfPlay = const OrderOfPlayController();
  final List<_SimulationSnapshot> _undoStack = [];
  final List<String> _eventLog = [];
  final Map<String, int> _durationByMatch = {};
  final Map<int, int> _boardAvailableAt = {};
  late final _SimulationSnapshot _initialSnapshot;
  late CreatedTournament _tournament;
  late TournamentSimulationRuntime _runtime;
  LeagueBoardRuntime? _leagueRuntime;
  _SimulationRandom _random;
  int _seed;
  TournamentSimulationMode _mode;
  int _minimumMinutes;
  int _maximumMinutes;
  int _elapsedSeconds = 0;
  bool _autoStartMatches;
  bool _isComplete = false;

  CreatedTournament get tournament => _tournament;
  int get seed => _seed;
  TournamentSimulationMode get mode => _mode;
  int get minimumMinutes => _minimumMinutes;
  int get maximumMinutes => _maximumMinutes;
  bool get isComplete => _isComplete;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get autoStartMatches => _autoStartMatches;
  List<String> get eventLog => List.unmodifiable(_eventLog);
  Duration get elapsed => Duration(seconds: _elapsedSeconds);
  int get stepCount => _allMatches().where((match) => match.isResolved).length;
  int get totalSteps =>
      math.max(stepCount, _orderOfPlay.entries(_tournament).length);

  void setAutoStartMatches(bool value) {
    if (_autoStartMatches == value) return;
    _autoStartMatches = value;
    _appendLog(
      value
          ? 'Automatischer Start der Partien aktiviert.'
          : 'Partien werden nur noch manuell gestartet.',
    );
  }

  void updateOptions({
    required int seed,
    required TournamentSimulationMode mode,
    required int minimumMinutes,
    required int maximumMinutes,
  }) {
    if (_undoStack.isNotEmpty || stepCount > 0) {
      throw StateError(
        'Simulationsparameter sind nach dem ersten Schritt fixiert.',
      );
    }
    if (minimumMinutes < 1 ||
        maximumMinutes < minimumMinutes ||
        maximumMinutes > 120) {
      throw ArgumentError('Ungültiger Bereich für die Spieldauer.');
    }
    _seed = seed;
    _mode = mode;
    _minimumMinutes = minimumMinutes;
    _maximumMinutes = maximumMinutes;
    _random = _SimulationRandom(seed);
  }

  bool nextStep() {
    if (_isComplete) return false;
    final snapshot = _takeSnapshot();
    _undoStack.add(snapshot);
    try {
      _prepareCurrentStage();
      if (_isComplete) return true;

      _startAvailableMatches();
      var schedule = _currentSchedule();
      if (schedule.running.isEmpty) {
        final nextBoardTime = _boardAvailableAt.values
            .where((time) => time > _elapsedSeconds)
            .fold<int?>(
              null,
              (next, time) => next == null || time < next ? time : next,
            );
        if (nextBoardTime != null) {
          _elapsedSeconds = nextBoardTime;
          _appendLog('Board-Leerstand beendet.');
          if (_autoStartMatches) {
            _startAvailableMatches();
            schedule = _currentSchedule();
          } else {
            return true;
          }
        }
      }
      if (schedule.running.isEmpty) {
        if (_isComplete) return true;
        if (!_autoStartMatches) {
          _undoStack.removeLast();
          _appendLog(
            'Keine laufende Partie. Bitte eine Partie manuell starten.',
          );
          return false;
        }
        throw StateError('Die Simulation kann keine nächste Partie starten.');
      }

      final finishTimes = <GroupMatch, int>{};
      for (final entry in schedule.running) {
        final key = _keyForMatch(entry.match);
        final duration = _durationByMatch[key];
        if (duration == null) {
          throw StateError(
            'Für eine laufende Partie fehlt die Simulationsdauer.',
          );
        }
        finishTimes[entry.match] =
            entry.match.startedAt!.difference(_origin).inSeconds + duration;
      }
      final nextFinish = finishTimes.values.reduce((a, b) => a < b ? a : b);
      _elapsedSeconds = math.max(_elapsedSeconds, nextFinish);
      final finishedAt = _simulationTime;
      for (final entry in schedule.running) {
        if (finishTimes[entry.match] != nextFinish) continue;
        _recordResult(entry.match, entry.stageIndex);
        entry.match.finishedAt = finishedAt;
        _appendLog(
          'Partie beendet: ${entry.match.participantShortLabel}'
          '${entry.match.boardNumber == null ? '' : ' auf ${_tournament.boardDisplayName(entry.match.boardNumber!)}'}.',
        );
        final board = entry.match.boardNumber;
        if (board != null) {
          _boardAvailableAt[board] =
              _elapsedSeconds + _planningParameters.boardIdleMinutes * 60;
        }
      }
      _prepareCurrentStage();
      _leagueRuntime?.writeTo(_tournament);
      if (!_isComplete) _startAvailableMatches();
      _appendLog('Simulationsschritt abgeschlossen.');
      return true;
    } catch (_) {
      _restoreSnapshot(snapshot);
      _undoStack.removeLast();
      rethrow;
    }
  }

  List<int> availableBoardsFor(GroupMatch match) {
    final stageIndex = _tournament.activeStageIndex;
    if (_isComplete ||
        stageIndex < 0 ||
        stageIndex >= _tournament.runStages.length) {
      return const [];
    }
    final schedule = _currentSchedule();
    final entry = schedule.planned
        .where((assignment) => identical(assignment.entry.match, match))
        .map((assignment) => assignment.entry)
        .firstOrNull;
    if (entry == null ||
        schedule.running.any(
          (running) => running.players.any(entry.players.contains),
        )) {
      return const [];
    }
    final runningBoards = {
      for (final running in schedule.running) ?running.match.boardNumber,
    };
    final available = [
      for (var board = 1; board <= _tournament.boardCount; board++)
        if (!_tournament.blockedBoards.contains(board) &&
            !runningBoards.contains(board) &&
            (_boardAvailableAt[board] ?? 0) <= _elapsedSeconds)
          board,
    ];
    final recommendedBoard = schedule.planned
        .where((assignment) => identical(assignment.entry.match, match))
        .map((assignment) => assignment.board)
        .firstOrNull;
    if (recommendedBoard != null && available.remove(recommendedBoard)) {
      available.insert(0, recommendedBoard);
    }
    return available;
  }

  bool startMatch(GroupMatch match, int board) {
    final availableBoards = availableBoardsFor(match);
    if (!availableBoards.contains(board)) return false;
    final stageIndex = _tournament.activeStageIndex;
    final snapshot = _takeSnapshot();
    _undoStack.add(snapshot);
    try {
      if (!_orderOfPlay.start(
        _tournament,
        stageIndex,
        match,
        board,
        startedAt: _simulationTime,
      )) {
        _undoStack.removeLast();
        return false;
      }
      _durationByMatch[_keyForMatch(match)] = _matchDurationSeconds(
        stageIndex,
        match,
      );
      _appendLog(
        'Partie manuell gestartet: ${match.participantShortLabel} auf '
        '${_tournament.boardDisplayName(board)}.',
      );
      return true;
    } catch (_) {
      _restoreSnapshot(snapshot);
      _undoStack.removeLast();
      rethrow;
    }
  }

  void reset() {
    final autoStartMatches = _autoStartMatches;
    _undoStack.clear();
    _restoreSnapshot(_initialSnapshot);
    _autoStartMatches = autoStartMatches;
    _appendLog('Simulation zurückgesetzt.');
  }

  bool undoLastStep() {
    if (_undoStack.isEmpty) return false;
    _restoreSnapshot(_undoStack.removeLast());
    _appendLog('Letzter Simulationsschritt rückgängig gemacht.');
    return true;
  }

  void _prepareCurrentStage() {
    var transitions = 0;
    while (!_isComplete) {
      final stageIndex = _tournament.activeStageIndex;
      if (stageIndex < 0 || stageIndex >= _tournament.stages.length) {
        _isComplete = true;
        _tournament.finishedAt = _simulationTime;
        return;
      }
      if (stageIndex >= _tournament.runStages.length) {
        final previous = _tournament.runStages[stageIndex - 1];
        final nextStage = _runtime.build(
          _tournament.stages[stageIndex],
          _runtime.qualifiers(previous),
        );
        _tournament.runStages.add(nextStage);
      }
      final stage = _tournament.runStages[stageIndex];
      _activateStage(stageIndex);
      _runtime.advance(now: _simulationTime);
      if (_runtime.hasOpen(stage)) return;

      _tournament.completedStageIndexes.add(stageIndex);
      if (stageIndex == _tournament.stages.length - 1) {
        _isComplete = true;
        _tournament.finishedAt = _simulationTime;
        _leagueRuntime?.writeTo(_tournament);
        return;
      }
      final nextIndex = stageIndex + 1;
      final nextStage = _runtime.build(
        _tournament.stages[nextIndex],
        _runtime.qualifiers(stage),
      );
      if (_tournament.runStages.length > nextIndex) {
        _tournament.runStages[nextIndex] = nextStage;
        _tournament.runStages.removeRange(
          nextIndex + 1,
          _tournament.runStages.length,
        );
      } else {
        _tournament.runStages.add(nextStage);
      }
      _tournament.activeStageIndex = nextIndex;
      _appendLog('Phase gestartet: ${_tournament.stages[nextIndex].name}.');
      if (++transitions > _tournament.stages.length) {
        throw StateError('Die Phasenfolge ist in der Simulation blockiert.');
      }
    }
  }

  void _startAvailableMatches() {
    if (!_autoStartMatches) return;
    var attempts = 0;
    while (!_isComplete && attempts++ <= _tournament.boardCount) {
      final stageIndex = _tournament.activeStageIndex;
      final unavailableBoards = {
        for (final entry in _boardAvailableAt.entries)
          if (entry.value > _elapsedSeconds) entry.key,
      };
      final schedule = _orderOfPlay.plan(
        _tournament,
        stageIndex,
        additionalBlockedBoards: unavailableBoards,
      );
      var startedCount = 0;
      for (final assignment in schedule.planned.where(
        (assignment) => assignment.block == 0,
      )) {
        final match = assignment.entry.match;
        final startTime = _simulationTime;
        if (!_orderOfPlay.start(
          _tournament,
          stageIndex,
          match,
          assignment.board,
          startedAt: startTime,
        )) {
          continue;
        }
        _durationByMatch[_keyForMatch(match)] = _matchDurationSeconds(
          assignment.entry.stageIndex,
          match,
        );
        _appendLog(
          'Partie automatisch gestartet: ${match.participantShortLabel} auf '
          '${_tournament.boardDisplayName(assignment.board)}.',
        );
        startedCount++;
      }
      if (startedCount > 0 || schedule.running.isNotEmpty) return;
      final nextBoardTime = _boardAvailableAt.values
          .where((time) => time > _elapsedSeconds)
          .fold<int?>(
            null,
            (next, time) => next == null || time < next ? time : next,
          );
      if (nextBoardTime == null) return;
      _elapsedSeconds = nextBoardTime;
    }
  }

  BoardSchedule _currentSchedule() {
    final unavailableBoards = {
      for (final entry in _boardAvailableAt.entries)
        if (entry.value > _elapsedSeconds) entry.key,
    };
    return _orderOfPlay.plan(
      _tournament,
      _tournament.activeStageIndex,
      additionalBlockedBoards: unavailableBoards,
    );
  }

  int _matchDurationSeconds(int stageIndex, GroupMatch match) {
    if (_mode == TournamentSimulationMode.randomStep) {
      return (_minimumMinutes +
              _random.nextInt(_maximumMinutes - _minimumMinutes + 1)) *
          60;
    }
    final format =
        _tournament.leagueMatch?.gameFormat ??
        _tournament.stages[stageIndex].gameFormat;
    final minutes = TournamentFormatPlanner(
      parameters: _planningParameters,
    ).estimatedMatchMinutes(format);
    return math.max(1, (minutes * 60).round()).toInt();
  }

  void _recordResult(GroupMatch match, int stageIndex) {
    if (match.isKratzer) {
      final eligible = match.scratchEligiblePlayers.isEmpty
          ? match.players
          : match.scratchEligiblePlayers;
      if (eligible.isEmpty) {
        throw StateError('Für ein Kratzer-Match fehlen Teilnehmer.');
      }
      match.scratchedPlayer = eligible[_random.nextInt(eligible.length)];
      return;
    }
    final format =
        _tournament.leagueMatch?.gameFormat ??
        _tournament.stages[stageIndex].gameFormat;
    final homeWins = _random.nextInt(2) == 0;
    final isGroupStage =
        _tournament.runStages[stageIndex] is GroupTournamentRunStage;
    if (format.allowsDraws &&
        isGroupStage &&
        !match.isDecider &&
        _random.nextInt(3) == 0) {
      final drawScore = format.bestOfLegs ~/ 2;
      match
        ..homeLegs = drawScore
        ..awayLegs = drawScore
        ..homeSets = null
        ..awaySets = null;
      return;
    }
    final legsToWin = format.bestOfLegs ~/ 2 + 1;
    if (format.bestOfSets > 1) {
      final setsToWin = format.bestOfSets ~/ 2 + 1;
      final setsLost = _random.nextInt(setsToWin);
      final homeSets = homeWins ? setsToWin : setsLost;
      final awaySets = homeWins ? setsLost : setsToWin;
      match
        ..homeSets = homeSets
        ..awaySets = awaySets
        ..homeLegs =
            homeSets * legsToWin + _extraLegsForSets(awaySets, legsToWin)
        ..awayLegs =
            awaySets * legsToWin + _extraLegsForSets(homeSets, legsToWin);
      return;
    }
    final maximumLost = format.allowsDraws && !match.isDecider
        ? (legsToWin - 2).clamp(0, legsToWin - 1)
        : legsToWin - 1;
    final lostLegs = _random.nextInt(maximumLost + 1);
    match
      ..homeLegs = homeWins ? legsToWin : lostLegs
      ..awayLegs = homeWins ? lostLegs : legsToWin
      ..homeSets = null
      ..awaySets = null;
  }

  int _extraLegsForSets(int sets, int legsToWin) => List.generate(
    sets,
    (_) => _random.nextInt(legsToWin),
  ).fold<int>(0, (total, value) => total + value);

  DateTime get _simulationTime =>
      _origin.add(Duration(seconds: _elapsedSeconds));

  List<GroupMatch> _allMatches() => [
    for (final stage in _tournament.runStages) ..._runtime.matches(stage),
  ];

  String _keyForMatch(GroupMatch match) {
    for (
      var stageIndex = 0;
      stageIndex < _tournament.runStages.length;
      stageIndex++
    ) {
      final matches = _runtime.matches(_tournament.runStages[stageIndex]);
      for (var matchIndex = 0; matchIndex < matches.length; matchIndex++) {
        if (identical(matches[matchIndex], match)) {
          return '$stageIndex:$matchIndex';
        }
      }
    }
    throw StateError('Simulationspartie ist keiner Turnierphase zugeordnet.');
  }

  void _activateStage(int index) {
    _runtime.activate(index);
    _tournament.activeStageIndex = index;
  }

  _SimulationSnapshot _takeSnapshot() => _SimulationSnapshot(
    tournament: _tournament.toJson(),
    elapsedSeconds: _elapsedSeconds,
    randomState: _random.state,
    boardAvailableAt: Map<int, int>.from(_boardAvailableAt),
    durationByMatch: Map<String, int>.from(_durationByMatch),
    eventLog: List<String>.from(_eventLog),
    isComplete: _isComplete,
  );

  void _appendLog(String event) {
    final minutes = _elapsedSeconds ~/ 60;
    final hours = minutes ~/ 60;
    final time = hours > 0
        ? '${hours.toString().padLeft(2, '0')}:'
              '${(minutes % 60).toString().padLeft(2, '0')}'
        : '${minutes.toString().padLeft(2, '0')}:'
              '${(_elapsedSeconds % 60).toString().padLeft(2, '0')}';
    _eventLog.add('$time · $event');
  }

  void _restoreSnapshot(_SimulationSnapshot snapshot) {
    _tournament = CreatedTournament.fromJson(snapshot.tournament);
    _elapsedSeconds = snapshot.elapsedSeconds;
    _random = _SimulationRandom(_seed)..state = snapshot.randomState;
    _boardAvailableAt
      ..clear()
      ..addAll(snapshot.boardAvailableAt);
    _durationByMatch
      ..clear()
      ..addAll(snapshot.durationByMatch);
    _eventLog
      ..clear()
      ..addAll(snapshot.eventLog);
    _isComplete = snapshot.isComplete;
    if (_tournament.leagueMatch == null) {
      _leagueRuntime = null;
    } else {
      _leagueRuntime = LeagueBoardRuntime(_tournament)..installOn(_tournament);
    }
    _runtime = _runtimeFactory(_tournament);
    _activateStage(_tournament.activeStageIndex);
  }
}

class _SimulationSnapshot {
  const _SimulationSnapshot({
    required this.tournament,
    required this.elapsedSeconds,
    required this.randomState,
    required this.boardAvailableAt,
    required this.durationByMatch,
    required this.eventLog,
    required this.isComplete,
  });

  final Map<String, dynamic> tournament;
  final int elapsedSeconds;
  final int randomState;
  final Map<int, int> boardAvailableAt;
  final Map<String, int> durationByMatch;
  final List<String> eventLog;
  final bool isComplete;
}

class _SimulationRandom {
  _SimulationRandom(int seed) : state = seed & 0xFFFFFFFF {
    if (state == 0) state = 0x6D2B79F5;
  }

  int state;

  int nextInt(int maximum) {
    if (maximum < 1) throw ArgumentError.value(maximum, 'maximum');
    var value = state;
    value ^= (value << 13) & 0xFFFFFFFF;
    value ^= value >> 17;
    value ^= (value << 5) & 0xFFFFFFFF;
    state = value & 0xFFFFFFFF;
    return state % maximum;
  }
}
