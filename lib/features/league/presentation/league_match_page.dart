import 'dart:math' show max, min;

import '../../../shared/widgets/sport_settings_section.dart';
import 'package:flutter/material.dart';
import '../../tournaments/application/tournament_timing.dart';
import '../../tournaments/presentation/widgets/run/tournament_timing_panel.dart';
import '../../tournaments/presentation/widgets/tournament_date_picker_field.dart';
import '../../tournaments/application/order_of_play/order_of_play_controller.dart';
import '../application/league_board_runtime.dart';
import '../application/league_duration_estimator.dart';
import 'league_overview.dart';
import 'league_game_format_setup.dart';
import 'league_player_picker.dart';
import '../../tournaments/data/app_database.dart';
import '../../../shared/widgets/adaptive_content.dart';
import '../../tournaments/data/tournament_storage.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../domain/league_match.dart';
import '../../settings/data/planning_settings_storage.dart';
import '../../tournaments/domain/tournament_planning_parameters.dart';
import 'league_pairing_dialog.dart';
import 'league_team_dialogs.dart';
import '../../statistics/domain/tournament_player_statistics.dart';
import '../../statistics/presentation/tournament_statistics_view.dart';

class LeagueMatchPage extends StatefulWidget {
  const LeagueMatchPage({
    super.key,
    this.tournament,
    this.storage,
    this.database,
    this.onCreated,
    this.editConfigurationOnly = false,
  });
  final LocalAppDatabase? database;
  final CreatedTournament? tournament;
  final TournamentStorage? storage;
  final ValueChanged<CreatedTournament>? onCreated;
  final bool editConfigurationOnly;
  @override
  State<LeagueMatchPage> createState() => _LeagueMatchPageState();
}

class LeagueSubstitutionDialog extends StatefulWidget {
  const LeagueSubstitutionDialog({
    super.key,
    required this.league,
    required this.teamSide,
    required this.teamName,
  });

  final LeagueMatch league;
  final int teamSide;
  final String teamName;

  @override
  State<LeagueSubstitutionDialog> createState() =>
      _LeagueSubstitutionDialogState();
}

class _LeagueSubstitutionDialogState extends State<LeagueSubstitutionDialog> {
  int? _outPlayer;
  int? _inPlayer;

  List<String> get _roster => widget.teamSide == 0
      ? widget.league.homePlayers
      : widget.league.awayPlayers;

  bool _wasSubstitutedOut(int player) => widget.league.substitutions.any(
    (event) =>
        event.teamSide == widget.teamSide && event.outPlayerIndex == player,
  );

  String _status(int player, Set<int> active) {
    if (active.contains(player)) return 'Aktiv';
    if (_wasSubstitutedOut(player)) return 'Ausgewechselt';
    return 'Ersatzspieler';
  }

  Color _statusColor(BuildContext context, String status) {
    if (status == 'Aktiv') return Theme.of(context).colorScheme.primary;
    if (status == 'Ersatzspieler') return Colors.orange.shade800;
    return Theme.of(context).colorScheme.error;
  }

  Widget _playerTile(
    BuildContext context,
    int player,
    Set<int> active, {
    required bool lineup,
  }) {
    final status = _status(player, active);
    final canSelect =
        lineup || widget.league.allowReentry || !_wasSubstitutedOut(player);
    final selected = lineup ? _outPlayer == player : _inPlayer == player;
    final content = ListTile(
      dense: true,
      selected: selected,
      title: Text(_roster[player]),
      subtitle: status == 'Ausgewechselt' && widget.league.allowReentry
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Ausgewechselt',
                style: TextStyle(color: Colors.white),
              ),
            )
          : Text(
              status == 'Ersatzspieler' ? 'Ersatzbank' : status,
              style: TextStyle(color: _statusColor(context, status)),
            ),
      trailing: selected
          ? const Icon(Icons.check_circle_outline)
          : const Icon(Icons.drag_indicator),
      onTap: canSelect
          ? () => setState(() {
              if (lineup) {
                _outPlayer = player;
              } else {
                _inPlayer = player;
              }
            })
          : null,
    );
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => lineup
          ? !active.contains(details.data) &&
                (widget.league.allowReentry ||
                    !_wasSubstitutedOut(details.data))
          : active.contains(details.data),
      onAcceptWithDetails: (details) => setState(() {
        if (lineup) {
          _inPlayer = details.data;
        } else {
          _outPlayer = details.data;
        }
      }),
      builder: (context, candidates, rejected) {
        final tile = Card(
          color: candidates.isEmpty
              ? null
              : Theme.of(context).colorScheme.secondaryContainer,
          child: content,
        );
        if (!canSelect) return tile;
        return Draggable<int>(
          data: player,
          feedback: Material(
            elevation: 4,
            child: Chip(label: Text(_roster[player])),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: tile),
          child: tile,
        );
      },
    );
  }

  Widget _playerList(
    BuildContext context,
    String title,
    List<int> players,
    Set<int> active, {
    required bool lineup,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final player in players)
            _playerTile(context, player, active, lineup: lineup),
          if (players.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Keine Teilnehmer in diesem Bereich.'),
            ),
        ],
      ),
    ),
  );

  Future<void> _confirmSubstitution() async {
    final outPlayer = _outPlayer;
    final inPlayer = _inPlayer;
    if (outPlayer == null || inPlayer == null) return;
    final remaining = widget.league.substitutionsRemaining(widget.teamSide) - 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Auswechseln bestätigen?'),
        content: Text(
          'Ihre Mannschaft hat danach noch $remaining Auswechselungen. '
          '${widget.league.allowReentry ? 'Bereits ausgewechselte Teilnehmer dürfen wieder eingewechselt werden.' : 'Ausgewechselte Teilnehmer können nicht erneut eingewechselt werden.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Nein'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ja, auswechseln'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop((outPlayer, inPlayer));
    }
  }

  @override
  Widget build(BuildContext context) {
    final league = widget.league;
    final active = league.activePlayers(widget.teamSide).toSet();
    final reserves = league.reservePlayers(widget.teamSide);
    final width = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      title: Text('Auswechselungen · ${widget.teamName}'),
      content: SizedBox(
        width: width > 900 ? 760 : width * 0.9,
        child: SingleChildScrollView(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final lineup = _playerList(
                context,
                'Aktuelle Aufstellung',
                active.toList()..sort(),
                active,
                lineup: true,
              );
              final bench = _playerList(
                context,
                'Ersatzbank',
                reserves,
                active,
                lineup: false,
              );
              return constraints.maxWidth > 560
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: lineup),
                        const Icon(Icons.swap_horiz, size: 32),
                        Expanded(child: bench),
                      ],
                    )
                  : Column(children: [lineup, bench]);
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _outPlayer == null || _inPlayer == null
              ? null
              : _confirmSubstitution,
          child: const Text('Auswechseln'),
        ),
      ],
    );
  }
}

List<(int, int)> _validScores(LeagueMatch league) {
  final format = league.gameFormat;
  final target = format.bestOfSets > 1
      ? format.bestOfSets ~/ 2 + 1
      : format.bestOfLegs ~/ 2 + 1;
  return [
    for (var score = 0; score < target; score++) (target, score),
    for (var score = 0; score < target; score++) (score, target),
    if (format.allowsDraws) (format.bestOfLegs ~/ 2, format.bestOfLegs ~/ 2),
  ];
}

class _LeagueMatchPageState extends State<LeagueMatchPage> {
  final _form = GlobalKey<FormState>();
  final _rosterSections = List.generate(
    2,
    (_) => GlobalKey<SportSettingsSectionState>(),
  );
  final _name = TextEditingController(text: 'Ligaspiel');
  final _starterCountInput = TextEditingController(text: '4');
  final _singlesPerPlayerInput = TextEditingController(text: '4');
  final _doublesCountInput = TextEditingController(text: '2');
  final _teams = [
    TextEditingController(text: 'Heim'),
    TextEditingController(text: 'Gast'),
  ];
  final _rosters = List.generate(
    2,
    (team) => List.generate(
      6,
      (i) => TextEditingController(
        text: '${team == 0 ? 'Heim' : 'Gast'} ${i + 1}',
      ),
    ),
  );
  late final _storage = widget.storage ?? TournamentStorage();
  late CreatedTournament? _tournament = widget.tournament;
  bool _busy = false;
  DateTime _tournamentDate = DateUtils.dateOnly(DateTime.now());
  String? _error;
  final _profiles = <String, TournamentPlayer>{};

  Future<void> _addRosterPlayer(int team) async {
    final slot = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('${_teams[team].text}: Aufstellungsplatz wählen'),
        children: [
          for (var i = 0; i < _rosters[team].length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${_variant == LeagueMatchVariant.traditional
                      ? i < 4
                            ? 'Teilnehmer ${i + 1}'
                            : 'Ersatzspieler ${i - 3}'
                      : 'Teilnehmer ${i + 1}'} · ${_rosters[team][i].text}',
                ),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _rosters[team].length),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Neuen Teilnehmerplatz hinzufügen'),
            ),
          ),
        ],
      ),
    );
    if (!mounted || slot == null) return;
    final newSlot = slot == _rosters[team].length;
    if (newSlot) setState(() => _rosters[team].add(TextEditingController()));
    await _selectPlayer(team, slot);
    if (mounted && newSlot && !_profiles.containsKey('$team:$slot')) {
      setState(() => _rosters[team].removeLast().dispose());
    }
  }

  Future<void> _selectPlayer(int team, int slot) async {
    final key = '$team:$slot';
    final choice = await showDialog<LeaguePlayerChoice>(
      context: context,
      builder: (_) => LeaguePlayerPicker(database: widget.database),
    );
    if (!mounted || choice == null) return;
    if (_profiles.entries.any(
      (e) => e.key != key && e.value.profileId == choice.player.profileId,
    )) {
      setState(
        () => _error =
            'Dieser Teilnehmer ist bereits in einer Mannschaft vorgesehen.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    setState(() {
      _profiles[key] = choice.player;
      _rosters[team][slot].text = choice.player.name;
      _busy = false;
      _error = null;
    });
  }

  int _boards = 1;
  LeagueMatchVariant _variant = LeagueMatchVariant.traditional;
  TournamentGameFormat _gameFormat = const TournamentGameFormat(bestOfLegs: 5);
  int _singlesPerPlayer = 4;
  int _doublesCount = 2;
  int _starterCount = 4;
  int _maxReservePlayers = 2;
  int _substitutionLimit = 2;
  bool _allowReentry = false;
  TournamentPlanningParameters _planningParameters =
      const TournamentPlanningParameters();

  Future<void> _loadPlanningParameters() async {
    try {
      final parameters = await PlanningSettingsStorage().load();
      if (mounted) setState(() => _planningParameters = parameters);
    } catch (_) {
      // Fall back to the same planning defaults used by the duration engine.
    }
  }

  void _setVariant(LeagueMatchVariant variant) {
    setState(() {
      final oldDefaultName = _variant == LeagueMatchVariant.adjusted
          ? 'Angepasstes Liga-/Freundschaftsspiel'
          : 'Ligaspiel';
      if (_name.text == oldDefaultName) {
        _name.text = variant == LeagueMatchVariant.adjusted
            ? 'Angepasstes Liga-/Freundschaftsspiel'
            : 'Ligaspiel';
      }
      _variant = variant;
      if (variant == LeagueMatchVariant.traditional) {
        for (var team = 0; team < _rosters.length; team++) {
          final roster = _rosters[team];
          while (roster.length > 6) {
            roster.removeLast().dispose();
          }
          while (roster.length < 6) {
            roster.add(
              TextEditingController(
                text: '${_teams[team].text} ${roster.length + 1}',
              ),
            );
          }
        }
        _starterCount = 4;
        _maxReservePlayers = 4;
        _substitutionLimit = 4;
        _allowReentry = false;
        _singlesPerPlayer = 4;
        _doublesCount = 2;
      } else {
        _starterCount = 4;
        _maxReservePlayers = max(
          0,
          max(_rosters[0].length - 4, _rosters[1].length - 4),
        );
        _substitutionLimit = 2;
        _allowReentry = false;
        _singlesPerPlayer = 4;
        _doublesCount = min(_doublesCount, _starterCount ~/ 2);
        for (var team = 0; team < _rosters.length; team++) {
          while (_rosters[team].length > _starterCount + _maxReservePlayers) {
            _rosters[team].removeLast().dispose();
          }
        }
      }
      _starterCountInput.text = '$_starterCount';
      _singlesPerPlayerInput.text = '$_singlesPerPlayer';
      _doublesCountInput.text = '$_doublesCount';
    });
  }

  Future<void> _removeLastPlayer(int team) async {
    if (_busy ||
        _rosters[team].length <=
            (_variant == LeagueMatchVariant.traditional ? 4 : _starterCount)) {
      return;
    }
    final slot = _rosters[team].length - 1;
    final key = '$team:$slot';
    setState(() {
      _profiles.remove(key);
      _rosters[team].removeLast().dispose();
      _singlesPerPlayer = min(_singlesPerPlayer, _rosters[0].length);
      _starterCount = min(
        _starterCount,
        min(_rosters[0].length, _rosters[1].length),
      );
      _maxReservePlayers = max(
        0,
        max(
          _rosters[0].length - _starterCount,
          _rosters[1].length - _starterCount,
        ),
      );
      _substitutionLimit = min(_substitutionLimit, _maxReservePlayers);
      _doublesCount = min(_doublesCount, _starterCount ~/ 2);
      _starterCountInput.text = '$_starterCount';
      _singlesPerPlayerInput.text = '$_singlesPerPlayer';
      _doublesCountInput.text = '$_doublesCount';
      _error = null;
    });
  }

  int? _estimatedAdjustedMinutes() {
    if (_rosters[0].length < _starterCount ||
        _rosters[1].length < _starterCount) {
      return null;
    }
    try {
      final names = [
        for (var team = 0; team < 2; team++)
          [
            for (var i = 0; i < _rosters[team].length; i++)
              _rosters[team][i].text.trim().isEmpty
                  ? 'Teilnehmer ${i + 1}'
                  : _rosters[team][i].text.trim(),
          ],
      ];
      final league = LeagueMatch.adjusted(
        homeTeam: _teams[0].text,
        awayTeam: _teams[1].text,
        homePlayers: names[0],
        awayPlayers: names[1],
        starterCount: _starterCount,
        maxReservePlayers: _maxReservePlayers,
        substitutionLimit: _substitutionLimit,
        allowReentry: _allowReentry,
        singlesPerPlayer: _singlesPerPlayer,
        doublesCount: _doublesCount,
        gameFormat: _gameFormat,
      );
      return const LeagueDurationEstimator()
          .estimate(
            league: league,
            boards: _boards,
            parameters: _planningParameters,
          )
          .minutes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _startGame(int index) async {
    var next = CreatedTournament.fromJson(_tournament!.toJson());
    var runtime = LeagueBoardRuntime(next);
    final board = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Begegnung auf Board starten'),
        children: [
          for (var b = 1; b <= next.boardCount; b++)
            SimpleDialogOption(
              onPressed:
                  runtime.schedule.running.any((e) => e.match.boardNumber == b)
                  ? null
                  : () => Navigator.pop(context, b),
              child: Text('Board $b'),
            ),
        ],
      ),
    );
    if (!mounted || board == null) return;
    next = CreatedTournament.fromJson(_tournament!.toJson());
    runtime = LeagueBoardRuntime(next);
    if (!const OrderOfPlayController().start(
      runtime.tournament,
      0,
      runtime.matches[index],
      board,
    )) {
      setState(
        () => _error =
            'Board oder Teilnehmer sind bereits in einer laufenden Begegnung.',
      );
      return;
    }
    runtime.writeTo(next);
    await _save(next);
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.tournament;
    final league = existing?.leagueMatch;
    if (widget.editConfigurationOnly && existing != null && league != null) {
      _name.text = existing.name;
      _tournamentDate = DateUtils.dateOnly(existing.effectiveDate.toLocal());
      _boards = existing.boardCount;
      _variant = league.variant;
      _gameFormat = league.gameFormat;
      _teams[0].text = league.homeTeam;
      _teams[1].text = league.awayTeam;
      _starterCount = league.starterCount;
      _maxReservePlayers = league.maxReservePlayers;
      _substitutionLimit = league.substitutionLimit;
      _allowReentry = league.allowReentry;
      _singlesPerPlayer = league.singlesPerPlayer;
      _doublesCount = league.doublesCount;
      _starterCountInput.text = '$_starterCount';
      _singlesPerPlayerInput.text = '$_singlesPerPlayer';
      _doublesCountInput.text = '$_doublesCount';
      for (var team = 0; team < 2; team++) {
        final roster = team == 0 ? league.homePlayers : league.awayPlayers;
        while (_rosters[team].length > roster.length) {
          _rosters[team].removeLast().dispose();
        }
        while (_rosters[team].length < roster.length) {
          _rosters[team].add(TextEditingController());
        }
        for (var index = 0; index < roster.length; index++) {
          _rosters[team][index].text = roster[index];
          final offset = team == 0 ? 0 : league.homePlayers.length;
          if (offset + index < existing.players.length) {
            _profiles['$team:$index'] = existing.players[offset + index];
          }
        }
      }
    }
    _loadPlanningParameters();
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _starterCountInput,
      _singlesPerPlayerInput,
      _doublesCountInput,
      ..._teams,
      ..._rosters.expand((r) => r),
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(
    CreatedTournament next, {
    bool rethrowError = false,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await TournamentTiming.prepare(next, parameters: _planningParameters);
      await _storage.saveTournament(next);
      if (mounted) setState(() => _tournament = next);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Speichern fehlgeschlagen. Bitte erneut versuchen.',
        );
      }
      if (rethrowError) rethrow;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeTournamentDate(DateTime date) async {
    final tournament = _tournament;
    if (tournament == null) return;
    final previous = tournament.tournamentDate;
    final normalized = DateTime(date.year, date.month, date.day);
    if (previous != null &&
        previous.year == normalized.year &&
        previous.month == normalized.month &&
        previous.day == normalized.day) {
      return;
    }
    tournament.tournamentDate = normalized;
    tournament.addActivity(
      'tournament_date_changed',
      'Turnierdatum geändert: ${MaterialLocalizations.of(context).formatMediumDate(normalized)}',
    );
    try {
      await _save(tournament, rethrowError: true);
    } catch (_) {
      tournament
        ..tournamentDate = previous
        ..activityLog.removeLast();
    }
  }

  Future<void> _create() async {
    if (_busy) return;
    if (!_form.currentState!.validate()) {
      for (final section in _rosterSections) {
        section.currentState?.expand();
      }
      return;
    }
    if (!_form.currentState!.validate()) return;
    if (_variant == LeagueMatchVariant.adjusted &&
        (_starterCount > _rosters[0].length ||
            _starterCount > _rosters[1].length)) {
      setState(() => _error = 'Beide Teams benötigen alle Stammspieler.');
      return;
    }
    final homePlayers = _rosters[0].map((c) => c.text.trim()).toList();
    final awayPlayers = _rosters[1].map((c) => c.text.trim()).toList();
    final league = _variant == LeagueMatchVariant.traditional
        ? LeagueMatch.rhl(
            homeTeam: _teams[0].text,
            awayTeam: _teams[1].text,
            homePlayers: homePlayers,
            awayPlayers: awayPlayers,
          )
        : LeagueMatch.adjusted(
            homeTeam: _teams[0].text,
            awayTeam: _teams[1].text,
            homePlayers: homePlayers,
            awayPlayers: awayPlayers,
            starterCount: _starterCount,
            maxReservePlayers: _maxReservePlayers,
            substitutionLimit: _substitutionLimit,
            allowReentry: _allowReentry,
            singlesPerPlayer: _singlesPerPlayer,
            doublesCount: _doublesCount,
            gameFormat: _gameFormat,
          );
    final players = [
      for (var team = 0; team < 2; team++)
        for (
          var slot = 0;
          slot < (team == 0 ? homePlayers.length : awayPlayers.length);
          slot++
        )
          _profiles['$team:$slot'] ??
              TournamentPlayer(
                name: _rosters[team][slot].text.trim(),
                isGenerated: false,
              ),
    ];
    final existing = widget.editConfigurationOnly ? widget.tournament : null;
    if (existing?.leagueMatch?.games.any((game) => game.complete) ?? false) {
      setState(
        () => _error =
            'Die Einstellungen sind erst nach dem Annullieren aller Ergebnisse bearbeitbar.',
      );
      return;
    }
    final tournament = existing == null
        ? CreatedTournament(
            name: _name.text.trim(),
            players: players,
            stages: [],
            runStages: [],
            leagueMatch: league,
            boardCount: _boards,
            tournamentDate: _tournamentDate,
          )
        : CreatedTournament.fromJson({
            ...existing.toJson(),
            'name': _name.text.trim(),
            'players': players.map((player) => player.toJson()).toList(),
            'stages': const [],
            'runStages': const [],
            'leagueMatch': league.toJson(),
            'boardCount': _boards,
          });
    await _save(tournament);
    if (mounted && _tournament != null) {
      if (existing != null) {
        Navigator.of(context).pop(_tournament);
        return;
      }
      widget.onCreated?.call(_tournament!);
    }
  }

  Future<void> _result(int index) async {
    final result = await showDialog<(int?, int?)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Ergebnis · ${_tournament!.leagueMatch!.gameFormat.label}'),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final score in _validScores(_tournament!.leagueMatch!))
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, score),
                  child: Text('${score.$1}:${score.$2}'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, (null, null)),
            child: const Text('Ergebnis entfernen'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    final next = CreatedTournament.fromJson(_tournament!.toJson());
    next.leagueMatch!.games[index].score(
      result.$1,
      result.$2,
      format: next.leagueMatch!.gameFormat,
    );
    if (result.$1 != null && result.$2 != null) {
      next.addActivity(
        'result_entered',
        'Ergebnis eingetragen · Begegnung ${index + 1} · ${result.$1}:${result.$2}',
      );
    }
    final runtime = LeagueBoardRuntime(next);
    const OrderOfPlayController().resultRecorded(runtime.matches[index]);
    runtime.writeTo(next);
    await _save(next);
  }

  Future<void> _pairing(int index) async {
    final next = CreatedTournament.fromJson(_tournament!.toJson());
    final league = next.leagueMatch!;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => LeaguePairingDialog(league: league, index: index),
    );
    if (changed == true && mounted) await _save(next);
  }

  Future<void> _move(int index, int delta) async {
    final next = CreatedTournament.fromJson(_tournament!.toJson());
    final games = next.leagueMatch!.games;
    games.insert(index + delta, games.removeAt(index));
    await _save(next);
  }

  Future<void> _substitutePlayers(int teamSide) async {
    final tournament = _tournament;
    if (tournament == null || _busy) return;
    final league = tournament.leagueMatch!;
    if (league.substitutionsRemaining(teamSide) < 1) {
      setState(
        () => _error =
            'Für dieses Team sind keine Auswechselungen mehr verfügbar.',
      );
      return;
    }
    final choice = await showDialog<(int, int)>(
      context: context,
      builder: (context) => LeagueSubstitutionDialog(
        league: league,
        teamSide: teamSide,
        teamName: teamSide == 0 ? league.homeTeam : league.awayTeam,
      ),
    );
    if (choice == null || !mounted) return;
    final next = CreatedTournament.fromJson(tournament.toJson());
    try {
      next.leagueMatch!.substitute(
        teamSide: teamSide,
        outPlayerIndex: choice.$1,
        inPlayerIndex: choice.$2,
      );
      final homeSide = teamSide == 0;
      final teamName = homeSide
          ? next.leagueMatch!.homeTeam
          : next.leagueMatch!.awayTeam;
      final roster = homeSide
          ? next.leagueMatch!.homePlayers
          : next.leagueMatch!.awayPlayers;
      next.addActivity(
        'substitution',
        '$teamName hat ${roster[choice.$1]} ausgewechselt und '
            '${roster[choice.$2]} eingewechselt',
      );
      await _save(next, rethrowError: true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Auswechselung fehlgeschlagen: $error');
      }
    }
  }

  Future<void> _showTeamRoster(int teamSide) async {
    final league = _tournament?.leagueMatch;
    if (league == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) =>
          LeagueRosterDialog(league: league, teamSide: teamSide),
    );
  }

  Future<void> _assignDoublePartners(int teamSide) async {
    final tournament = _tournament;
    if (tournament == null || _busy) return;
    final assignments = await showDialog<Map<int, List<int>>>(
      context: context,
      builder: (context) => LeagueTeamPairingsDialog(
        league: tournament.leagueMatch!,
        teamSide: teamSide,
      ),
    );
    if (assignments == null || !mounted) return;
    final next = CreatedTournament.fromJson(tournament.toJson());
    final league = next.leagueMatch!;
    for (final entry in assignments.entries) {
      final game = league.games[entry.key];
      if (teamSide == 0) {
        game.home = entry.value;
      } else {
        game.away = entry.value;
      }
    }
    try {
      await _save(next, rethrowError: true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Doppelaufstellung fehlgeschlagen: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _content(context);
  }

  Widget _content(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          '${_tournament == null ? 'Neues Ligaspiel' : _tournament!.name} '
          '(${(_tournament?.leagueMatch?.variant ?? _variant) == LeagueMatchVariant.adjusted ? 'Angepasstes Ligaspiel/Freundschaftsspiel' : 'Traditionelles Ligaspiel'})',
        ),
      ),
      body: AdaptiveContentList(
        children: [
          Text(
            _tournament?.leagueMatch?.variant == LeagueMatchVariant.adjusted
                ? '${_tournament!.leagueMatch!.games.length} Begegnungen · ${_tournament!.leagueMatch!.gameFormat.label}'
                : '18 Begegnungen · 501 Single In / Double Out · Best of 5 Legs',
          ),
          const SizedBox(height: 12),
          if (_tournament == null)
            Text(
              _variant == LeagueMatchVariant.traditional
                  ? 'Traditioneller Spielplan mit 16 Einzeln und 2 Doppeln. Je Team vier Stammspieler sowie bis zu vier Ersatzspieler erfassen.'
                  : 'Der angepasste Spielplan wird mit der festgelegten Anzahl Stammspieler erstellt; zusätzliche Kaderspieler bleiben Ersatzspieler.',
            ),
          const SizedBox(height: 16),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_tournament != null) ...[
            TournamentDatePickerField(
              value: DateUtils.dateOnly(_tournament!.effectiveDate.toLocal()),
              onChanged: _changeTournamentDate,
            ),
            const SizedBox(height: 12),
          ],
          if (_tournament == null || widget.editConfigurationOnly)
            _setup(context)
          else
            ..._games(context),
        ],
      ),
    ),
  );

  Widget _setup(BuildContext context) => Form(
    key: _form,
    child: Column(
      children: [
        TextFormField(
          key: const ValueKey('league-name'),
          controller: _name,
          maxLength: 200,
          decoration: InputDecoration(
            labelText: _variant == LeagueMatchVariant.adjusted
                ? 'Name des angepassten Liga-/Freundschaftsspiels'
                : 'Name des Ligaspiels',
            hintText: _variant == LeagueMatchVariant.adjusted
                ? 'Zum Beispiel: Freundschaftsspiel · Dartclub'
                : 'Zum Beispiel: Vereinsliga · 3. Spieltag',
          ),
          validator: _required,
        ),
        const SizedBox(height: 12),
        TournamentDatePickerField(
          value: _tournamentDate,
          onChanged: (date) => setState(() => _tournamentDate = date),
        ),
        const SizedBox(height: 16),
        SegmentedButton<LeagueMatchVariant>(
          segments: const [
            ButtonSegment(
              value: LeagueMatchVariant.traditional,
              label: Text('Traditionell'),
              icon: Icon(Icons.format_list_numbered),
            ),
            ButtonSegment(
              value: LeagueMatchVariant.adjusted,
              label: Text('Angepasst'),
              icon: Icon(Icons.tune),
            ),
          ],
          selected: {_variant},
          onSelectionChanged: (selection) => _setVariant(selection.single),
        ),
        if (_variant == LeagueMatchVariant.adjusted) ...[
          const SizedBox(height: 16),
          SportSettingsSection(
            title: 'Angepasster Spielplan',
            summary: 'Kader, Begegnungen und Dauer festlegen',
            icon: Icons.tune,
            children: [
              AdaptiveTileLayout(
                minTileWidth: 180,
                children: [
                  TextFormField(
                    key: const ValueKey('league-starter-count'),
                    controller: _starterCountInput,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Stammspieler je Team',
                    ),
                    validator: (value) {
                      final count = int.tryParse(value ?? '');
                      if (count == null ||
                          count < 1 ||
                          count > min(_rosters[0].length, _rosters[1].length)) {
                        return 'Zwischen 1 und ${min(_rosters[0].length, _rosters[1].length)} eingeben.';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      final count = int.tryParse(value);
                      if (count == null || count < 1) return;
                      setState(() {
                        _starterCount = count;
                        _maxReservePlayers = max(
                          0,
                          max(
                            _rosters[0].length - count,
                            _rosters[1].length - count,
                          ),
                        );
                        _doublesCount = min(_doublesCount, count ~/ 2);
                        _doublesCountInput.text = '$_doublesCount';
                        _substitutionLimit = min(
                          _substitutionLimit,
                          _maxReservePlayers,
                        );
                      });
                    },
                  ),
                  TextFormField(
                    controller: _singlesPerPlayerInput,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Einzel je Teilnehmer',
                    ),
                    validator: (value) {
                      final count = int.tryParse(value ?? '');
                      return count == null || count < 1
                          ? 'Mindestens 1 Einzel eingeben.'
                          : null;
                    },
                    onChanged: (value) {
                      final count = int.tryParse(value);
                      if (count != null && count > 0) {
                        setState(() => _singlesPerPlayer = count);
                      }
                    },
                  ),
                  TextFormField(
                    controller: _doublesCountInput,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Doppel je Mannschaft',
                    ),
                    validator: (value) {
                      final count = int.tryParse(value ?? '');
                      return count == null ||
                              count < 0 ||
                              count > _starterCount ~/ 2
                          ? 'Zwischen 0 und ${_starterCount ~/ 2} eingeben.'
                          : null;
                    },
                    onChanged: (value) {
                      final count = int.tryParse(value);
                      if (count != null && count >= 0) {
                        setState(() => _doublesCount = count);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LeagueGameFormatSetup(
                value: _gameFormat,
                onChanged: (format) => setState(() => _gameFormat = format),
                additionalSettings: [
                  DropdownButtonFormField<int>(
                    key: ValueKey('league-create-boards-$_boards'),
                    initialValue: _boards,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Boards'),
                    items: [
                      for (var count = 1; count <= 64; count++)
                        DropdownMenuItem(value: count, child: Text('$count')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _boards = value);
                    },
                  ),
                  DropdownButtonFormField<int>(
                    key: ValueKey(
                      'substitution-limit-$_substitutionLimit-$_maxReservePlayers',
                    ),
                    initialValue: _substitutionLimit.clamp(
                      0,
                      _maxReservePlayers,
                    ),
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Auswechselungen je Team',
                    ),
                    items: [
                      for (var count = 0; count <= _maxReservePlayers; count++)
                        DropdownMenuItem(value: count, child: Text('$count')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _substitutionLimit = value);
                      }
                    },
                  ),
                  DropdownButtonFormField<bool>(
                    key: ValueKey('league-reentry-$_allowReentry'),
                    initialValue: _allowReentry,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Erneut einwechseln',
                    ),
                    items: const [
                      DropdownMenuItem(value: false, child: Text('Nein')),
                      DropdownMenuItem(value: true, child: Text('Ja')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _allowReentry = value);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final duration = _estimatedAdjustedMinutes();
                  final matches =
                      _starterCount * _singlesPerPlayer + _doublesCount;
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.schedule_outlined),
                      title: Text(
                        '$matches Begegnungen · $_starterCount Stammspieler je Team',
                      ),
                      subtitle: Text(
                        duration == null
                            ? 'Dauer wird berechnet, sobald beide Teams genügend Stammspieler haben.'
                            : 'Voraussichtliche Dauer: ${_formatDuration(duration)} · ${_gameFormat.lengthLabel} · $_boards ${_boards == 1 ? 'Board' : 'Boards'}',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 12),
          _boardSetupField(),
        ],
        AdaptiveTileLayout(
          children: [
            for (var team = 0; team < 2; team++)
              SportSettingsSection(
                key: _rosterSections[team],
                title: team == 0
                    ? 'Heimteam & Aufstellung'
                    : 'Gastteam & Aufstellung',
                summary:
                    '${_teams[team].text} · ${_rosters[team].length} Teilnehmerplätze',
                icon: Icons.groups_outlined,
                children: [
                  TextFormField(
                    controller: _teams[team],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: team == 0
                          ? 'Heimmannschaft'
                          : 'Gastmannschaft',
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_variant == LeagueMatchVariant.adjusted) ...[
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _addRosterPlayer(team),
                          icon: const Icon(Icons.person_add),
                          label: const Text('Lokalen Teilnehmer hinzufügen'),
                        ),
                      ],
                    ],
                  ),
                  for (var i = 0; i < _rosters[team].length; i++)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextFormField(
                        controller: _rosters[team][i],
                        onChanged: (_) =>
                            setState(() => _profiles.remove('$team:$i')),
                        validator: _required,
                        decoration: InputDecoration(
                          suffixIcon: IconButton(
                            tooltip: 'Teilnehmer aus dem Katalog auswählen',
                            onPressed: _busy
                                ? null
                                : () => _selectPlayer(team, i),
                            icon: const Icon(Icons.person_add_alt),
                          ),
                          labelText: _variant == LeagueMatchVariant.traditional
                              ? i < 4
                                    ? 'Teilnehmer ${i + 1}'
                                    : 'Ersatzspieler ${i - 3}'
                              : 'Teilnehmer ${i + 1}',
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed:
                            _busy ||
                                _rosters[team].length >=
                                    (_variant == LeagueMatchVariant.traditional
                                        ? 8
                                        : 16)
                            ? null
                            : () => setState(() {
                                final next = _rosters[team].length + 1;
                                _rosters[team].add(
                                  TextEditingController(
                                    text: '${_teams[team].text} $next',
                                  ),
                                );
                                if (_variant == LeagueMatchVariant.adjusted) {
                                  _maxReservePlayers = max(
                                    _maxReservePlayers,
                                    max(
                                      0,
                                      max(
                                        _rosters[0].length - _starterCount,
                                        _rosters[1].length - _starterCount,
                                      ),
                                    ),
                                  );
                                  _substitutionLimit = min(
                                    _substitutionLimit,
                                    _maxReservePlayers,
                                  );
                                }
                                _error = null;
                              }),
                        icon: const Icon(Icons.person_add),
                        label: const Text(
                          'Teilnehmer / Ersatzspieler hinzufügen',
                        ),
                      ),
                      TextButton.icon(
                        onPressed:
                            _busy ||
                                _rosters[team].length <=
                                    (_variant == LeagueMatchVariant.traditional
                                        ? 4
                                        : _starterCount)
                            ? null
                            : () => _removeLastPlayer(team),
                        icon: const Icon(Icons.person_remove_outlined),
                        label: const Text('Letzten Teilnehmer entfernen'),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _create,
          child: Text(
            widget.editConfigurationOnly
                ? 'Einstellungen speichern'
                : _variant == LeagueMatchVariant.adjusted
                ? 'Angepasstes Liga-/Freundschaftsspiel anlegen'
                : 'Ligaspiel anlegen',
          ),
        ),
      ],
    ),
  );

  String? _required(String? text) =>
      text == null || text.trim().isEmpty ? 'Bitte Namen eingeben.' : null;

  String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    if (hours == 0) return '$remaining Minuten';
    if (remaining == 0) return '$hours Stunden';
    return '$hours Std. $remaining Min.';
  }

  Widget _boardSetupField() => DropdownButtonFormField<int>(
    key: ValueKey('traditional-board-count-$_boards'),
    initialValue: _boards,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Boards'),
    items: [
      for (var count = 1; count <= 64; count++)
        DropdownMenuItem(value: count, child: Text('$count')),
    ],
    onChanged: (value) {
      if (value != null) setState(() => _boards = value);
    },
  );

  List<Widget> _games(BuildContext context) {
    final league = _tournament!.leagueMatch!;
    return [
      TournamentTimingPanel(
        tournament: _tournament!,
        onStart: () async {
          final next = CreatedTournament.fromJson(_tournament!.toJson());
          next.startedAt ??= DateTime.now();
          await _save(next, rethrowError: true);
        },
      ),
      LeagueOverview(league: league),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.bar_chart),
          label: const Text('Statistik'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                appBar: AppBar(title: const Text('Ligastatistik')),
                body: TournamentStatisticsView(
                  rows: const TournamentStatisticsCalculator().calculate([
                    _tournament!,
                  ]),
                  description: 'Einzelstatistik aus gespeicherten Ergebnissen.',
                ),
              ),
            ),
          ),
        ),
      ),
      const Text(
        'Jedes gewonnene Match zählt einen Mannschaftspunkt. Bei Gleichstand endet das Ligaspiel unentschieden.',
      ),
      for (var teamSide = 0; teamSide < 2; teamSide++)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _busy ? null : () => _showTeamRoster(teamSide),
                    icon: const Icon(Icons.groups_outlined),
                    label: Text(
                      teamSide == 0 ? league.homeTeam : league.awayTeam,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(
                      '${league.substitutionsRemaining(teamSide)} Auswechselungen verfügbar',
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _substitutePlayers(teamSide),
                      icon: const Icon(Icons.swap_horiz),
                      label: Text(
                        teamSide == 0
                            ? 'Auswechselungen Heimteam'
                            : 'Auswechselungen Gastteam',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _assignDoublePartners(teamSide),
                      icon: const Icon(Icons.group_add_outlined),
                      label: Text(
                        teamSide == 0
                            ? 'Doppelpartner zuweisen Heimteam'
                            : 'Doppelpartner zuweisen Gastteam',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      for (var i = 0; i < league.games.length; i++)
        LeagueFixtureCard(
          league: league,
          index: i,
          boardLabel: league.games[i].runtime?['boardNumber'] == null
              ? null
              : 'Board ${league.games[i].runtime!['boardNumber']}',
          actions: [
            if (!league.games[i].complete &&
                league.games[i].runtime?['startedAt'] == null)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _startGame(i),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Starten'),
              ),
            OutlinedButton(
              key: ValueKey('league-result-$i'),
              onPressed: _busy ? null : () => _result(i),
              child: const Text('Ergebnis'),
            ),
            if (league.variant == LeagueMatchVariant.traditional &&
                !league.games[i].complete &&
                league.games[i].runtime?['startedAt'] == null)
              OutlinedButton(
                onPressed: _busy ? null : () => _pairing(i),
                child: const Text('Aufstellung'),
              ),
            if (league.games.every(
              (g) => !g.complete && g.runtime?['startedAt'] == null,
            )) ...[
              IconButton(
                tooltip: 'Begegnung nach oben',
                onPressed: _busy || i == 0 ? null : () => _move(i, -1),
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: 'Begegnung nach unten',
                onPressed: _busy || i == league.games.length - 1
                    ? null
                    : () => _move(i, 1),
                icon: const Icon(Icons.arrow_downward),
              ),
            ],
          ],
        ),
    ];
  }
}
