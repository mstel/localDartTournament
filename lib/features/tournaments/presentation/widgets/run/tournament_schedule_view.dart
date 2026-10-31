import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/knockout_round_names.dart';
import '../../../domain/tournament_models.dart';

class TournamentScheduleView extends StatelessWidget {
  const TournamentScheduleView({
    super.key,
    required this.tournament,
    this.onEditResult,
  });

  final CreatedTournament tournament;
  final ValueChanged<GroupMatch>? onEditResult;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${tournament.name} · Vollständiger Spielplan'),
      leading: IconButton(
        tooltip: 'Zurück',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (
            var stageIndex = 0;
            stageIndex < tournament.runStages.length;
            stageIndex++
          )
            _stageTable(context, tournament.runStages[stageIndex], stageIndex),
        ],
      ),
    ),
  );

  Widget _stageTable(
    BuildContext context,
    TournamentRunStage stage,
    int stageIndex,
  ) {
    final stageSettings = stageIndex < tournament.stages.length
        ? tournament.stages[stageIndex]
        : null;
    final rows = <_ScheduleRow>[];
    if (stage is GroupTournamentRunStage) {
      for (final group in stage.groups) {
        final seen = <GroupMatch>{};
        for (final match in [
          ...group.matches,
          ...group.knockoutRounds.expand((round) => round),
          ...group.placementMatches,
        ]) {
          if (seen.add(match)) {
            rows.add(
              _ScheduleRow(
                round: group.playType == 'mini_knockout'
                    ? (match.isDecider
                          ? 'Entscheidung'
                          : 'Runde ${match.round}')
                    : 'Gruppe ${group.name} · Runde ${match.round}',
                match: match,
              ),
            );
          }
        }
      }
    } else if (stage is KnockoutTournamentRunStage) {
      for (var roundIndex = 0; roundIndex < stage.rounds.length; roundIndex++) {
        for (final match in stage.rounds[roundIndex]) {
          rows.add(
            _ScheduleRow(
              round: stage.eliminationLossLimit == 1
                  ? knockoutRoundName(roundIndex, stage.rounds.length)
                  : 'Runde ${roundIndex + 1}',
              match: match,
            ),
          );
        }
      }
      for (final match in stage.placementMatches) {
        rows.add(_ScheduleRow(round: 'Platzierung', match: match));
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '${stageIndex + 1}. ${stage.name}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (stage is KnockoutTournamentRunStage)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (stageSettings != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _knockoutSeedingHint(stageSettings),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => Dialog.fullscreen(
                          child: _KnockoutTreePage(
                            stage: stage,
                            stageSettings: stageSettings,
                            onEditResult: onEditResult,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.account_tree_outlined),
                      label: const Text('K.-o.-Baum im Vollbild öffnen'),
                    ),
                  ),
                ],
              ),
            ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Für diese Etappe sind keine Paarungen vorhanden.'),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  const DataColumn(label: Text('Runde / Gruppe')),
                  const DataColumn(label: Text('Spieler 1')),
                  const DataColumn(label: Text('Ergebnis')),
                  const DataColumn(label: Text('Spieler 2')),
                  const DataColumn(label: Text('Status')),
                  const DataColumn(label: Text('Zusammenfassung')),
                  const DataColumn(label: Text('Board')),
                  if (onEditResult != null)
                    const DataColumn(label: Text('Aktion')),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      cells: [
                        DataCell(Text(row.round)),
                        DataCell(Text(row.match.homePlayer?.name ?? 'Offen')),
                        DataCell(
                          Text(
                            row.match.hasResult ? row.match.scoreLabel : '–',
                          ),
                        ),
                        DataCell(Text(row.match.awayPlayer?.name ?? 'Offen')),
                        DataCell(
                          Text(
                            row.match.isAnnulled
                                ? 'Annulliert'
                                : row.match.hasResult
                                ? 'Beendet'
                                : row.match.allowsBye && row.match.hasPlayers
                                ? 'Freilos'
                                : row.match.hasPlayers
                                ? 'Offen'
                                : 'Paarung offen',
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 220,
                            child: Text(
                              _matchSummary(
                                row.match,
                                knockoutStage:
                                    stage is KnockoutTournamentRunStage
                                    ? stage
                                    : null,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(row.match.boardNumber?.toString() ?? '–'),
                        ),
                        if (onEditResult != null)
                          DataCell(
                            IconButton(
                              tooltip: 'Ergebnis bearbeiten',
                              onPressed: row.match.hasPlayers
                                  ? () => onEditResult!(row.match)
                                  : null,
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ScheduleRow {
  const _ScheduleRow({required this.round, required this.match});

  final String round;
  final GroupMatch match;
}

class _KnockoutTreePage extends StatelessWidget {
  const _KnockoutTreePage({
    required this.stage,
    this.stageSettings,
    this.onEditResult,
  });

  final KnockoutTournamentRunStage stage;
  final TournamentStage? stageSettings;
  final ValueChanged<GroupMatch>? onEditResult;

  static const _cardWidth = 250.0;
  static const _cardHeight = 104.0;
  static const _roundGap = 48.0;
  static const _verticalGap = 20.0;
  static const _headerHeight = 48.0;

  @override
  Widget build(BuildContext context) {
    final rounds = stage.rounds;
    return Scaffold(
      appBar: AppBar(
        title: Text('${stage.name} · K.-o.-Baum'),
        leading: IconButton(
          tooltip: 'Zurück zum Spielplan',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (stageSettings != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  _knockoutSeedingHint(stageSettings!),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Expanded(
              child: rounds.isEmpty
                  ? const Center(
                      child: Text('Für diese Etappe gibt es keinen Baum.'),
                    )
                  : _buildTree(context, rounds),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTree(BuildContext context, List<List<GroupMatch>> rounds) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final cardHeight = math.max(_cardHeight, 120 * scale);
    final boardHeight = math.max(
      MediaQuery.sizeOf(context).height - 100,
      _headerHeight + rounds.first.length * (cardHeight + _verticalGap),
    );
    final boardWidth =
        rounds.length * _cardWidth + (rounds.length - 1) * _roundGap;
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: boardWidth,
          height: boardHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _KnockoutTreeConnectorPainter(
                    roundCounts: [for (final round in rounds) round.length],
                    cardWidth: _cardWidth,
                    roundGap: _roundGap,
                    cardHeight: cardHeight,
                    headerHeight: _headerHeight,
                    verticalGap: _verticalGap,
                  ),
                ),
              ),
              for (var roundIndex = 0; roundIndex < rounds.length; roundIndex++)
                Positioned(
                  left: roundIndex * (_cardWidth + _roundGap),
                  top: 0,
                  width: _cardWidth,
                  height: boardHeight,
                  child: Stack(
                    children: [
                      Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: Text(
                          stage.eliminationLossLimit == 1
                              ? knockoutRoundName(roundIndex, rounds.length)
                              : 'Runde ${roundIndex + 1}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      for (
                        var matchIndex = 0;
                        matchIndex < rounds[roundIndex].length;
                        matchIndex++
                      )
                        Positioned(
                          top: _matchTop(roundIndex, matchIndex, cardHeight),
                          width: _cardWidth,
                          height: cardHeight,
                          child: _matchCard(
                            context,
                            rounds[roundIndex][matchIndex],
                            roundIndex,
                            matchIndex,
                            rounds.length,
                            onEditResult,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  double _matchTop(int roundIndex, int matchIndex, double cardHeight) {
    final slotHeight =
        (cardHeight + _verticalGap) * math.pow(2, roundIndex).toDouble();
    return _headerHeight +
        matchIndex * slotHeight +
        (slotHeight - cardHeight) / 2;
  }

  Widget _matchCard(
    BuildContext context,
    GroupMatch match,
    int roundIndex,
    int matchIndex,
    int roundCount,
    ValueChanged<GroupMatch>? onEditResult,
  ) {
    final theme = Theme.of(context);
    final winner = match.winner;
    String playerLabel(TournamentPlayer? player, bool home) {
      if (player != null) return player.name;
      if (roundIndex == 0) return match.allowsBye ? 'Freilos' : 'Offen';
      return 'Gewinner Spiel ${matchIndex * 2 + (home ? 1 : 2)}';
    }

    Widget playerRow(String name, TournamentPlayer? player, int? score) => Row(
      children: [
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: player != null && player == winner
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
        ),
        if (score != null) Text('$score'),
      ],
    );

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            playerRow(
              playerLabel(match.homePlayer, true),
              match.homePlayer,
              match.homeScore,
            ),
            const Divider(height: 12),
            playerRow(
              playerLabel(match.awayPlayer, false),
              match.awayPlayer,
              match.awayScore,
            ),
            if (roundIndex == roundCount - 1 &&
                match.isDecider &&
                match.label != null)
              Text(match.label!, style: theme.textTheme.bodySmall),
            if (match.hasResult || (match.allowsBye && match.winner != null))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _matchSummary(match, knockoutStage: stage),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            if (onEditResult != null)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Ergebnis bearbeiten',
                  onPressed: match.hasPlayers
                      ? () => onEditResult(match)
                      : null,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _knockoutSeedingHint(TournamentStage stage) {
  final seeding = stage.knockoutSeedingMode == 'random'
      ? stage.knockoutDrawOnStart
            ? 'Zufallsauslosung beim Turnierstart'
            : 'Zufallsauslosung'
      : 'Cross-Setzung nach Gruppenplatzierungen';
  final byeText = stage.knockoutByeCount == 0
      ? ''
      : stage.lossLimit >= 3
      ? ' · ${stage.knockoutByeCount} Teilnehmer automatisch gesetzt'
      : ' · ${stage.knockoutByeCount} Freilose';
  return 'Setzung: $seeding$byeText.';
}

String _matchSummary(
  GroupMatch match, {
  KnockoutTournamentRunStage? knockoutStage,
}) {
  if (match.isAnnulled) return 'Spiel annulliert.';
  if (match.allowsBye && match.winner != null) {
    return 'Freilos: ${match.winner!.name} kommt weiter.';
  }
  if (!match.hasResult) {
    return match.hasPlayers
        ? 'Ergebnis steht noch aus.'
        : 'Paarung noch offen.';
  }

  final winner = match.winner;
  if (winner == null) return 'Unentschieden: kein Sieger.';
  final isPlacementMatch =
      knockoutStage?.placementMatches.contains(match) ?? false;
  final summary = StringBuffer(
    isPlacementMatch
        ? 'Platzierung entschieden: ${winner.name}'
        : 'Sieger: ${winner.name}',
  );
  if (knockoutStage != null && !isPlacementMatch) {
    final loser = match.loser;
    if (loser != null) {
      final losses = knockoutStage.matches
          .where((playedMatch) => playedMatch.loser == loser)
          .length;
      if (losses >= knockoutStage.eliminationLossLimit) {
        summary.write(' · ${loser.name} ausgeschieden');
      } else {
        final remainingLives = knockoutStage.eliminationLossLimit - losses;
        summary.write(' · ${loser.name}: noch $remainingLives Leben');
      }
    }
  }
  if (match.bestPerformances.isNotEmpty) {
    final performance = match.bestPerformances.first;
    summary
      ..write(' · ${performance.playerName}: ${performance.label}')
      ..write(performance.value == null ? '' : ' ${performance.value}');
  }
  return summary.toString();
}

class _KnockoutTreeConnectorPainter extends CustomPainter {
  const _KnockoutTreeConnectorPainter({
    required this.roundCounts,
    required this.cardWidth,
    required this.roundGap,
    required this.cardHeight,
    required this.headerHeight,
    required this.verticalGap,
  });

  final List<int> roundCounts;
  final double cardWidth;
  final double roundGap;
  final double cardHeight;
  final double headerHeight;
  final double verticalGap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blueGrey
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (var round = 0; round < roundCounts.length - 1; round++) {
      for (var nextMatch = 0; nextMatch < roundCounts[round + 1]; nextMatch++) {
        final nextCenter = _top(round + 1, nextMatch) + cardHeight / 2;
        for (var sourceOffset = 0; sourceOffset < 2; sourceOffset++) {
          final sourceMatch = nextMatch * 2 + sourceOffset;
          if (sourceMatch >= roundCounts[round]) continue;
          final sourceCenter = _top(round, sourceMatch) + cardHeight / 2;
          final startX = round * (cardWidth + roundGap) + cardWidth;
          final branchX = startX + roundGap / 2;
          final endX = (round + 1) * (cardWidth + roundGap) - roundGap / 2;
          final path = Path()
            ..moveTo(startX, sourceCenter)
            ..lineTo(branchX, sourceCenter)
            ..lineTo(branchX, nextCenter)
            ..lineTo(endX, nextCenter);
          canvas.drawPath(path, paint);
        }
      }
    }
  }

  double _top(int roundIndex, int matchIndex) {
    final slotHeight =
        (cardHeight + verticalGap) * math.pow(2, roundIndex).toDouble();
    return headerHeight +
        matchIndex * slotHeight +
        (slotHeight - cardHeight) / 2;
  }

  @override
  bool shouldRepaint(_KnockoutTreeConnectorPainter oldDelegate) =>
      oldDelegate.roundCounts != roundCounts ||
      oldDelegate.cardWidth != cardWidth ||
      oldDelegate.roundGap != roundGap ||
      oldDelegate.cardHeight != cardHeight ||
      oldDelegate.headerHeight != headerHeight ||
      oldDelegate.verticalGap != verticalGap;
}
