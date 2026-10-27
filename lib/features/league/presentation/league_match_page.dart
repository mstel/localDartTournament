import 'dart:math' show min;

import '../../../shared/widgets/sport_settings_section.dart';
import 'package:flutter/material.dart';
import '../../tournaments/application/tournament_timing.dart';
import '../../tournaments/presentation/widgets/run/tournament_timing_panel.dart';
import '../../tournaments/application/order_of_play/order_of_play_controller.dart';
import '../application/league_board_runtime.dart';
import '../application/league_duration_estimator.dart';
import 'league_overview.dart';
import 'league_player_picker.dart';
import '../../tournaments/data/app_database.dart';
import '../../../shared/widgets/adaptive_content.dart';
import '../../tournaments/data/tournament_storage.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../domain/league_match.dart';
import '../../settings/data/planning_settings_storage.dart';
import '../../tournaments/domain/tournament_planning_parameters.dart';
import 'league_pairing_dialog.dart';
import '../../statistics/domain/tournament_player_statistics.dart';
import '../../statistics/presentation/tournament_statistics_view.dart';

class LeagueMatchPage extends StatefulWidget {
  const LeagueMatchPage({
    super.key,
    this.tournament,
    this.storage,
    this.database,
  });
  final LocalAppDatabase? database;
  final CreatedTournament? tournament;
  final TournamentStorage? storage;
  @override
  State<LeagueMatchPage> createState() => _LeagueMatchPageState();
}

class _LeagueMatchPageState extends State<LeagueMatchPage> {
  final _form = GlobalKey<FormState>();
  final _rosterSections = List.generate(
    2,
    (_) => GlobalKey<SportSettingsSectionState>(),
  );
  final _name = TextEditingController(text: 'Ligaspiel');
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
                            ? 'Spieler ${i + 1}'
                            : 'Ersatzspieler ${i - 3}'
                      : 'Spieler ${i + 1}'} · ${_rosters[team][i].text}',
                ),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _rosters[team].length),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Neuen Spielerplatz hinzufügen'),
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
            'Dieser Spieler ist bereits in einer Mannschaft vorgesehen.',
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
  int _singlesPerPlayer = 2;
  int _doublesCount = 2;
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
        _singlesPerPlayer = 4;
        _doublesCount = 2;
      } else {
        _singlesPerPlayer = 2;
        _doublesCount = min(_doublesCount, _rosters.first.length ~/ 2);
      }
    });
  }

  Future<void> _removeLastPlayer(int team) async {
    if (_busy || _rosters[team].length <= 1) return;
    final slot = _rosters[team].length - 1;
    final key = '$team:$slot';
    setState(() {
      _profiles.remove(key);
      _rosters[team].removeLast().dispose();
      _singlesPerPlayer = min(_singlesPerPlayer, _rosters[0].length);
      _doublesCount = min(_doublesCount, _rosters[0].length ~/ 2);
      _error = null;
    });
  }

  int? _estimatedAdjustedMinutes() {
    if (_rosters[0].length != _rosters[1].length || _rosters[0].isEmpty) {
      return null;
    }
    try {
      final names = [
        for (var team = 0; team < 2; team++)
          [
            for (var i = 0; i < _rosters[team].length; i++)
              _rosters[team][i].text.trim().isEmpty
                  ? 'Spieler ${i + 1}'
                  : _rosters[team][i].text.trim(),
          ],
      ];
      final league = LeagueMatch.adjusted(
        homeTeam: _teams[0].text,
        awayTeam: _teams[1].text,
        homePlayers: names[0],
        awayPlayers: names[1],
        singlesPerPlayer: _singlesPerPlayer,
        doublesCount: _doublesCount,
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
        title: const Text('Spiel auf Board starten'),
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
            'Board oder Spieler sind bereits in einem laufenden Spiel.',
      );
      return;
    }
    runtime.writeTo(next);
    await _save(next);
  }

  @override
  void initState() {
    super.initState();
    _loadPlanningParameters();
  }

  @override
  void dispose() {
    for (final c in [_name, ..._teams, ..._rosters.expand((r) => r)]) {
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
        _rosters[0].length != _rosters[1].length) {
      setState(
        () => _error =
            'Für den angepassten Spielplan müssen beide Teams gleich viele Spieler haben.',
      );
      return;
    }
    final playerLimit = _variant == LeagueMatchVariant.traditional ? 6 : null;
    final homePlayers = _rosters[0]
        .take(playerLimit ?? _rosters[0].length)
        .map((c) => c.text)
        .toList();
    final awayPlayers = _rosters[1]
        .take(playerLimit ?? _rosters[1].length)
        .map((c) => c.text)
        .toList();
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
            singlesPerPlayer: _singlesPerPlayer,
            doublesCount: _doublesCount,
          );
    await _save(
      CreatedTournament(
        name: _name.text.trim(),
        players: [
          for (var team = 0; team < 2; team++)
            for (var slot = 0; slot < homePlayers.length; slot++)
              _profiles['$team:$slot'] ??
                  TournamentPlayer(
                    name: _rosters[team][slot].text.trim(),
                    isGenerated: false,
                  ),
        ],
        stages: [],
        runStages: [],
        leagueMatch: league,
        boardCount: _boards,
      ),
    );
  }

  Future<void> _result(int index) async {
    final result = await showDialog<(int?, int?)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ergebnis · Best of 5'),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final score in [
                (3, 0),
                (3, 1),
                (3, 2),
                (0, 3),
                (1, 3),
                (2, 3),
              ])
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
    next.leagueMatch!.games[index].score(result.$1, result.$2);
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
                ? '${_tournament!.leagueMatch!.games.length} Begegnungen · 501 Single In / Double Out · Best of 5 Legs'
                : '18 Begegnungen · 501 Single In / Double Out · Best of 5 Legs',
          ),
          const SizedBox(height: 12),
          if (_tournament == null)
            Text(
              _variant == LeagueMatchVariant.traditional
                  ? 'Traditioneller Spielplan mit 16 Einzeln und 2 Doppeln. Pro Team vier Spieler und zwei Ersatzspieler erfassen.'
                  : 'Im angepassten Spielplan werden Einzel gleichmäßig auf alle Spieler verteilt. Doppelpartner kommen je Team nur einmal zum Einsatz.',
            ),
          const SizedBox(height: 16),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_tournament == null) _setup(context) else ..._games(context),
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
          decoration: const InputDecoration(
            labelText: 'Name des Ligaspiels',
            hintText: 'Zum Beispiel: Vereinsliga · 3. Spieltag',
          ),
          validator: _required,
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
            summary: 'Begegnungen und voraussichtliche Dauer planen',
            icon: Icons.tune,
            children: [
              DropdownButtonFormField<int>(
                key: ValueKey(
                  'singles-per-player-$_singlesPerPlayer-${_rosters[0].length}',
                ),
                initialValue: _singlesPerPlayer,
                decoration: const InputDecoration(
                  labelText: 'Einzel je Spieler',
                ),
                items: [
                  for (var count = 1; count <= _rosters[0].length; count++)
                    DropdownMenuItem(value: count, child: Text('$count')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _singlesPerPlayer = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey(
                  'doubles-count-$_doublesCount-${_rosters[0].length}',
                ),
                initialValue: _doublesCount,
                decoration: const InputDecoration(
                  labelText: 'Doppel je Mannschaft',
                ),
                items: [
                  for (var count = 0; count <= _rosters[0].length ~/ 2; count++)
                    DropdownMenuItem(value: count, child: Text('$count')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _doublesCount = value);
                },
              ),
              const SizedBox(height: 8),
              _boardControls(),
              Builder(
                builder: (context) {
                  final duration = _estimatedAdjustedMinutes();
                  final teamsMatch = _rosters[0].length == _rosters[1].length;
                  final matches =
                      _rosters[0].length * _singlesPerPlayer + _doublesCount;
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.schedule_outlined),
                      title: Text(
                        teamsMatch
                            ? '$matches Begegnungen'
                            : 'Teamgrößen angleichen',
                      ),
                      subtitle: Text(
                        duration == null
                            ? 'Dauer wird berechnet, sobald beide Teams gleich viele Spieler haben.'
                            : 'Voraussichtliche Dauer: ${_formatDuration(duration)} · Best of 5 · $_boards ${_boards == 1 ? 'Board' : 'Boards'}',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
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
                    '${_teams[team].text} · ${_rosters[team].length} Spielerplätze',
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
                          label: const Text('Lokalen Spieler hinzufügen'),
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
                            tooltip: 'Spieler aus dem Katalog auswählen',
                            onPressed: _busy
                                ? null
                                : () => _selectPlayer(team, i),
                            icon: const Icon(Icons.person_add_alt),
                          ),
                          labelText: _variant == LeagueMatchVariant.traditional
                              ? i < 4
                                    ? 'Spieler ${i + 1}'
                                    : 'Ersatzspieler ${i - 3}'
                              : 'Spieler ${i + 1}',
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (_variant == LeagueMatchVariant.adjusted)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _rosters[team].add(TextEditingController());
                                  _error = null;
                                }),
                          icon: const Icon(Icons.person_add),
                          label: const Text('Spieler hinzufügen'),
                        ),
                        TextButton.icon(
                          onPressed: _busy || _rosters[team].length <= 1
                              ? null
                              : () => _removeLastPlayer(team),
                          icon: const Icon(Icons.person_remove_outlined),
                          label: const Text('Letzten Spieler entfernen'),
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
          child: const Text('Ligaspiel anlegen'),
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

  Widget _boardControls() {
    final count = _tournament?.boardCount ?? _boards;
    final running =
        _tournament?.leagueMatch?.games.any(
          (g) => !g.complete && g.runtime?['startedAt'] != null,
        ) ??
        false;
    Future<void> change(int value) async {
      if (_tournament == null) {
        setState(() => _boards = value);
        return;
      }
      final next = CreatedTournament.fromJson(_tournament!.toJson())
        ..boardCount = value;
      await _save(next);
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        Text('$count Boards'),
        IconButton(
          tooltip: 'Weniger Boards',
          onPressed: _busy || running || count <= 1
              ? null
              : () => change(count - 1),
          icon: const Icon(Icons.remove),
        ),
        IconButton(
          tooltip: 'Mehr Boards',
          onPressed: _busy || running || count >= 64
              ? null
              : () => change(count + 1),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

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
                tooltip: 'Spiel nach oben',
                onPressed: _busy || i == 0 ? null : () => _move(i, -1),
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: 'Spiel nach unten',
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
