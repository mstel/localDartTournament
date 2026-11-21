import 'package:flutter/material.dart';

import '../domain/team_game_state.dart';

/// Große Anzeige für den Zweitmonitor.
///
/// Es gibt bewusst keine Punkt- oder Score-Anzeige: Scolia übernimmt die
/// Punkteeingabe, dieses Widget zeigt ausschließlich den am Zug befindlichen
/// Spieler beziehungsweise das Ergebnis. Die Animation läuft nur einmal kurz
/// beim Spielerwechsel, nicht dauerhaft.
class TeamGameDisplayView extends StatelessWidget {
  const TeamGameDisplayView({
    super.key,
    required this.state,
    this.onClose,
  });

  final TeamGameState? state;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: const Color(0xFF071A17),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: _buildContent(state, textTheme),
                ),
              ),
            ),
            if (onClose != null)
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  key: const ValueKey('team-game-display-close'),
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                  color: Colors.white70,
                  tooltip: 'Zweitmonitoransicht schließen',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(TeamGameState? state, TextTheme textTheme) {
    if (state == null || !state.hasPlayers) {
      return Semantics(
        liveRegion: true,
        child: Column(
          key: const ValueKey('team-game-display-waiting'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_outlined, size: 72, color: Colors.white38),
            const SizedBox(height: 24),
            Text(
              'Team Game bereit',
              textAlign: TextAlign.center,
              style: textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Namen und Mannschaften bitte am Hauptmonitor eingeben.',
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (state.isFinished && state.winningTeamName != null) {
      return Semantics(
        liveRegion: true,
        child: Column(
          key: const ValueKey('team-game-display-result'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_outlined,
                size: 72, color: Colors.amber.shade300),
            const SizedBox(height: 24),
            Text(
              'Team ${state.winningTeamName} hat gewonnen',
              key: const ValueKey('team-game-display-winner'),
              textAlign: TextAlign.center,
              style: textTheme.displaySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    final turn = state.currentTurn!;
    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            state.status == TeamGameStatus.setup
                ? 'TEAM GAME · VORSCHAU'
                : 'TEAM GAME',
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(
              color: Colors.tealAccent.shade200,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 550),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final scale = Tween<double>(begin: 0.92, end: 1.0)
                  .animate(animation);
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: scale, child: child),
              );
            },
            child: _buildTurn(turn, textTheme),
          ),
        ],
      ),
    );
  }

  Widget _buildTurn(TeamGameTurn turn, TextTheme textTheme) {
    return LayoutBuilder(
      key: ValueKey(turn.identity),
      builder: (context, constraints) {
        final shortest = constraints.constrainWidth(
          constraints.maxWidth < constraints.maxHeight
              ? constraints.maxWidth
              : constraints.maxHeight,
        );
        final fontSize = (shortest / 9).clamp(38.0, 148.0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              turn.teamName,
              key: const ValueKey('team-game-display-team'),
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Text(
              turn.player,
              key: const ValueKey('team-game-display-player'),
              textAlign: TextAlign.center,
              style: textTheme.displayLarge?.copyWith(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'ist am Zug',
              textAlign: TextAlign.center,
              style: textTheme.headlineMedium?.copyWith(
                color: Colors.tealAccent.shade200,
              ),
            ),
          ],
        );
      },
    );
  }
}
