import 'dart:async';

import 'package:flutter/material.dart';

import '../application/team_game_display_launcher.dart';
import '../data/team_game_signal_repository.dart';
import '../domain/team_game_state.dart';
import 'team_game_display_view.dart';
import 'team_game_page.dart';

/// Hauptmonitor während eines laufenden Team Games.
///
/// Bewusst ohne Punkteingabe: Scolia übernimmt das Leg. Diese Seite steuert
/// nur die Reihenfolge der Spieler und Siegerwahl.
class TeamGameRunPage extends StatefulWidget {
  const TeamGameRunPage({
    super.key,
    required this.initialState,
    TeamGameSignalRepository? repository,
    TeamGameDisplayLauncher? displayLauncher,
  }) : _repository = repository,
       _displayLauncher = displayLauncher;

  final TeamGameState initialState;
  final TeamGameSignalRepository? _repository;
  final TeamGameDisplayLauncher? _displayLauncher;

  @override
  State<TeamGameRunPage> createState() => _TeamGameRunPageState();
}

class _TeamGameRunPageState extends State<TeamGameRunPage> {
  late final TeamGameSignalRepository _repository;
  late final TeamGameDisplayLauncher _displayLauncher;
  late TeamGameState _state;
  bool _busy = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _repository = widget._repository ?? TeamGameSignalRepository();
    _displayLauncher =
        widget._displayLauncher ?? ProcessTeamGameDisplayLauncher();
    _state = widget.initialState;
  }

  Future<void> _persist(TeamGameState next) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _repository.save(next);
      if (mounted) setState(() => _state = next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            key: ValueKey('team-game-save-error'),
            content: Text('Der Zustand konnte nicht gespeichert werden.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _next() {
    if (!_state.canGoNext) return Future<void>.value();
    return _persist(_state.next());
  }

  Future<void> _back() {
    if (!_state.canGoBack) return Future<void>.value();
    return _persist(_state.previous());
  }

  Future<void> _end() async {
    if (_busy || _state.isFinished) return;
    final winner = await showDialog<TeamGameWinner>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('team-game-winner-dialog'),
        title: const Text('Spiel beenden'),
        content: const Text('Welche Mannschaft hat gewonnen?'),
        actions: [
          TextButton(
            key: const ValueKey('team-game-winner-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton.tonal(
            key: const ValueKey('team-game-winner-home'),
            onPressed: () => Navigator.of(dialogContext).pop(TeamGameWinner.home),
            child: Text('${_state.home.teamName} gewinnt'),
          ),
          FilledButton.tonal(
            key: const ValueKey('team-game-winner-away'),
            onPressed: () => Navigator.of(dialogContext).pop(TeamGameWinner.away),
            child: Text('${_state.away.teamName} gewinnt'),
          ),
        ],
      ),
    );
    if (winner != null) await _persist(_state.finished(winner));
  }

  /// Der Zweitmonitor bleibt auch während eines laufenden Spiels erreichbar.
  /// Er liest den aktuellen Zustand aus der Signaturdatei und zeigt daher
  /// unmittelbar den laufenden Spieler an.
  Future<void> _openDisplay() async {
    try {
      await _repository.save(_state);
    } catch (_) {
      // Der Zweitmonitor kann auch mit dem zuletzt gespeicherten Zustand
      // geöffnet werden; eine fehlgeschlagene Speicherung blockiert nicht.
    }
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
          state: _state,
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
  }

  /// Öffnet die Namenseinstellungen, ohne den laufenden Spielstand
  /// zurückzusetzen. Nach dem Speichern wird der geänderte Zustand wieder
  /// geladen, damit die Anzeige sofort aktualisiert wird.
  Future<void> _editNames() async {
    if (_busy) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TeamGamePage(
          repository: _repository,
          displayLauncher: _displayLauncher,
          initialState: _state,
        ),
      ),
    );
    if (!mounted) return;
    try {
      final saved = await _repository.load();
      if (saved != null && mounted) setState(() => _state = saved);
    } catch (_) {
      // Bei einem Lesefehler bleibt der letzte lokale Zustand bestehen.
    }
  }

  Future<void> _confirmLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('team-game-leave-dialog'),
        title: const Text('Spiel verlassen'),
        content: const Text('Sind sie sicher ?'),
        actions: [
          TextButton(
            key: const ValueKey('team-game-leave-no'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Nein'),
          ),
          FilledButton(
            key: const ValueKey('team-game-leave-yes'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Ja'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _leave();
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    try {
      await _repository.save(_state.prepared());
    } catch (_) {
      // Beim Verlassen darf eine fehlgeschlagene Speicherung die Navigation
      // nicht blockieren.
    }
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_confirmLeave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Team Game'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildStatus(constraints.maxWidth),
                        const SizedBox(height: 28),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _buildButton(
                              key: const ValueKey('team-game-run-next'),
                              label: 'Nächster Spieler',
                              icon: Icons.skip_next,
                              filled: true,
                              onPressed: _state.canGoNext && !_busy
                                  ? _next
                                  : null,
                            ),
                            _buildButton(
                              key: const ValueKey('team-game-run-end'),
                              label: 'Spiel Beenden',
                              icon: Icons.flag_outlined,
                              filled: true,
                              destructive: true,
                              onPressed:
                                  !_state.isFinished && !_busy ? _end : null,
                            ),
                            _buildButton(
                              key: const ValueKey('team-game-run-back'),
                              label: 'Rückgängig',
                              icon: Icons.undo_outlined,
                              filled: false,
                              onPressed: _state.canGoBack && !_busy
                                  ? _back
                                  : null,
                            ),
                            _buildButton(
                              key: const ValueKey('team-game-run-leave'),
                              label: 'Spiel verlassen',
                              icon: Icons.exit_to_app_outlined,
                              filled: false,
                              onPressed: _confirmLeave,
                            ),
                            _buildButton(
                              key: const ValueKey('team-game-run-open-display'),
                              label: 'Zweitmonitor ansicht öffnen',
                              icon: Icons.tv_outlined,
                              filled: false,
                              onPressed: _busy ? null : _openDisplay,
                            ),
                            _buildButton(
                              key: const ValueKey('team-game-run-edit-names'),
                              label: 'Namen bearbeiten',
                              icon: Icons.edit_outlined,
                              filled: false,
                              onPressed: _busy ? null : _editNames,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStatus(double availableWidth) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final finishedName = _state.winningTeamName;

    if (_state.isFinished && finishedName != null) {
      final fontSize = (availableWidth / 18).clamp(30.0, 86.0);
      return Semantics(
        liveRegion: true,
        child: Container(
          key: const ValueKey('team-game-run-finished'),
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events_outlined,
                  size: 64, color: scheme.primary),
              const SizedBox(height: 16),
              Text(
                'Team $finishedName hat gewonnen',
                key: const ValueKey('team-game-run-winner'),
                textAlign: TextAlign.center,
                style: textTheme.headlineMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final turn = _state.currentTurn;
    if (turn == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'Keine Spieler eingetragen.',
          key: const ValueKey('team-game-run-empty'),
          textAlign: TextAlign.center,
          style: textTheme.titleLarge,
        ),
      );
    }

    final fontSize = (availableWidth / 12).clamp(36.0, 112.0);
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('team-game-run-current'),
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'TEAM GAME · AM ZUG',
              style: textTheme.titleMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              turn.teamName,
              key: const ValueKey('team-game-run-team'),
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              turn.player,
              key: const ValueKey('team-game-run-player'),
              textAlign: TextAlign.center,
              style: textTheme.displayMedium?.copyWith(
                color: scheme.onSurface,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ist am Zug',
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton({
    required Key key,
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback? onPressed,
    bool destructive = false,
  }) {
    final style = filled
        ? FilledButton.styleFrom(
            minimumSize: const Size(220, 56),
            backgroundColor:
                destructive ? Theme.of(context).colorScheme.error : null,
            foregroundColor:
                destructive ? Theme.of(context).colorScheme.onError : null,
          )
        : OutlinedButton.styleFrom(
            minimumSize: const Size(220, 56),
          );
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon),
        const SizedBox(width: 10),
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
    if (filled) {
      return FilledButton(key: key, onPressed: onPressed, style: style, child: child);
    }
    return OutlinedButton(
      key: key,
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }
}
