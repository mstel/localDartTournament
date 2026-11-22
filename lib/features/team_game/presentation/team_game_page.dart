import 'package:flutter/material.dart';

import '../../../shared/widgets/adaptive_content.dart';
import '../application/team_game_display_launcher.dart';
import '../data/team_game_signal_repository.dart';
import '../domain/team_game_state.dart';
import 'team_game_display_view.dart';
import 'team_game_run_page.dart';
import 'team_roster_editor.dart';

/// Setup für den casual Team-Game-Modus: zwei Mannschaftsnamen und deren
/// Spieler. Punkte werden nicht erfasst, sondern über Scolia eingetragen.
class TeamGamePage extends StatefulWidget {
  const TeamGamePage({
    super.key,
    TeamGameSignalRepository? repository,
    TeamGameDisplayLauncher? displayLauncher,
    TeamGameState? initialState,
  }) : _repository = repository,
       _displayLauncher = displayLauncher,
       _initialState = initialState;

  final TeamGameSignalRepository? _repository;
  final TeamGameDisplayLauncher? _displayLauncher;
  final TeamGameState? _initialState;

  @override
  State<TeamGamePage> createState() => _TeamGamePageState();
}

class _TeamGamePageState extends State<TeamGamePage> {
  late final TeamGameSignalRepository _repository;
  late final TeamGameDisplayLauncher _displayLauncher;

  late final List<TextEditingController> _teamNames;
  late final List<List<TextEditingController>> _players;

  @override
  void initState() {
    super.initState();
    _repository = widget._repository ?? TeamGameSignalRepository();
    _displayLauncher =
        widget._displayLauncher ?? ProcessTeamGameDisplayLauncher();

    final initial = widget._initialState;
    _teamNames = [
      TextEditingController(text: initial?.home.teamName ?? 'Heim'),
      TextEditingController(text: initial?.away.teamName ?? 'Gast'),
    ];
    _players = [
      _controllersFor(initial?.home.players),
      _controllersFor(initial?.away.players),
    ];
  }

  List<TextEditingController> _controllersFor(List<String>? players) {
    final names = players == null || players.isEmpty
        ? const <String>['']
        : players;
    return names.map((name) => TextEditingController(text: name)).toList();
  }

  @override
  void dispose() {
    for (final controller in _teamNames) {
      controller.dispose();
    }
    for (final team in _players) {
      for (final controller in team) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  void _addPlayer(int team) => setState(() {
    _players[team].add(TextEditingController());
  });

  void _removePlayer(int team, int index) => setState(() {
    if (_players[team].length <= 1) {
      _players[team][index].clear();
      return;
    }
    _players[team].removeAt(index).dispose();
  });

  String? _validate() {
    if (_teamNames[0].text.trim().isEmpty ||
        _teamNames[1].text.trim().isEmpty) {
      return 'Bitte beide Mannschaftsnamen eingeben.';
    }
    if (_players[0].every((c) => c.text.trim().isEmpty) ||
        _players[1].every((c) => c.text.trim().isEmpty)) {
      return 'Bitte mindestens einen Spieler je Mannschaft eingeben.';
    }
    return null;
  }

  TeamGameState _buildState() {
    final initial = widget._initialState;
    if (initial != null) {
      return initial.withRoster(
        homeTeam: _teamNames[0].text,
        homePlayers: _players[0].map((c) => c.text).toList(),
        awayTeam: _teamNames[1].text,
        awayPlayers: _players[1].map((c) => c.text).toList(),
      );
    }
    return TeamGameState.create(
      homeTeam: _teamNames[0].text,
      homePlayers: _players[0].map((c) => c.text).toList(),
      awayTeam: _teamNames[1].text,
      awayPlayers: _players[1].map((c) => c.text).toList(),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(key: const ValueKey('team-game-validation'), content: Text(message)),
    );
  }

  Future<void> _openDisplay() async {
    final error = _validate();
    if (error != null) {
      _showError(error);
      return;
    }
    final state = _buildState();
    await _repository.save(state);
    final opened = await _displayLauncher.open();
    if (!mounted) return;
    if (opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zweitmonitoransicht geöffnet.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: TeamGameDisplayView(
          state: state,
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
  }

  Future<void> _startGame() async {
    final error = _validate();
    if (error != null) {
      _showError(error);
      return;
    }
    final state = _buildState().started();
    await _repository.save(state);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TeamGameRunPage(
          initialState: state,
          repository: _repository,
        ),
      ),
    );
  }

  Future<void> _saveAndReturn() async {
    final error = _validate();
    if (error != null) {
      _showError(error);
      return;
    }
    await _repository.save(_buildState());
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget._initialState != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Namen bearbeiten' : 'Team Game'),
      ),
      body: AdaptiveContentList(
        children: [
          Text(
            'Team Game',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Ein Leg 1001 Double out. Die Punkteingabe erfolgt über Scolia; '
            'hier werden nur die Mannschaften und die Reihenfolge der Spieler '
            'verwaltet.',
          ),
          const SizedBox(height: 16),
          AdaptiveTileLayout(
            minTileWidth: 330,
            children: [
              TeamRosterEditor(
                side: 'home',
                title: 'Heimteam',
                icon: Icons.home_outlined,
                teamNameController: _teamNames[0],
                playerControllers: _players[0],
                onAddPlayer: () => _addPlayer(0),
                onRemovePlayer: (index) => _removePlayer(0, index),
              ),
              TeamRosterEditor(
                side: 'away',
                title: 'Gastteam',
                icon: Icons.sports_outlined,
                teamNameController: _teamNames[1],
                playerControllers: _players[1],
                onAddPlayer: () => _addPlayer(1),
                onRemovePlayer: (index) => _removePlayer(1, index),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Reihenfolge: Heim 1, Gast 1, Heim 2, Gast 2, ... Das Heimteam '
            'beginnt. Jedes Team rotiert durch sein eigenes Kader; nach dem '
            'letzten Spieler geht es beim ersten Spieler dieses Teams weiter. '
            'Die Anzahl der Wechsel ist nicht vorgegeben.',
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 680;
              final openButton = OutlinedButton.icon(
                key: const ValueKey('team-game-open-display'),
                onPressed: _openDisplay,
                icon: const Icon(Icons.tv_outlined),
                label: const Text('Zweitmonitor ansicht öffnen'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              );
              final primaryButton = editing
                  ? FilledButton.icon(
                      key: const ValueKey('team-game-save-setup'),
                      onPressed: _saveAndReturn,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Namen speichern'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    )
                  : FilledButton.icon(
                      key: const ValueKey('team-game-start'),
                      onPressed: _startGame,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Team Game Starten'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    );
              if (wide) {
                return Row(
                  children: [
                    Expanded(child: openButton),
                    const SizedBox(width: 12),
                    Expanded(child: primaryButton),
                  ],
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  openButton,
                  const SizedBox(height: 12),
                  primaryButton,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
