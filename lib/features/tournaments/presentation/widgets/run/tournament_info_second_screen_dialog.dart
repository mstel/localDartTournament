import 'package:flutter/material.dart';

import '../../../../../shared/widgets/adaptive_content.dart';
import '../../../application/tournament_info_summary.dart';
import '../../../application/tournament_timing.dart';
import '../../../domain/tournament_models.dart';

/// Kompakte Turnierinfo-Ansicht für den Zweitmonitor.
class TournamentInfoSecondScreenDialog extends StatelessWidget {
  const TournamentInfoSecondScreenDialog({super.key, required this.tournament});

  final CreatedTournament tournament;

  static Future<void> show({
    required BuildContext context,
    required CreatedTournament tournament,
    VoidCallback? onClosed,
  }) {
    final future = showDialog<void>(
      context: context,
      builder: (context) =>
          TournamentInfoSecondScreenDialog(tournament: tournament),
    );
    return onClosed == null ? future : future.whenComplete(onClosed);
  }

  static String _dateLabel(CreatedTournament tournament) {
    final date = tournament.tournamentDate ?? tournament.startedAt;
    if (date == null) return 'Datum offen';
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}.${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matchCount = TournamentTiming.scheduledMatches(tournament).length;
    final durationMinutes =
        tournament.plannedMinutes ?? tournament.plannedMinimumMinutes;
    final plannedDuration = TournamentInfoSummary.duration(durationMinutes);
    final headline =
        'Voraussichtliche Dauer: $plannedDuration - '
        '$matchCount Begegnungen auf ${tournament.boardCount} Boards, '
        '${tournament.players.length} Teilnehmer';

    return Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Turnierinfos',
                      key: const ValueKey('tournament-info-dialog-title'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: AdaptiveContentList(
                maxWidth: 900,
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    '${tournament.name} · ${_dateLabel(tournament)}',
                    key: const ValueKey('tournament-info-name'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    headline,
                    key: const ValueKey('tournament-info-headline'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  for (var index = 0; index < tournament.stages.length; index++)
                    _stageCard(index + 1, tournament.stages[index], theme),
                  if (tournament.stages.isEmpty)
                    const Text(
                      'Für dieses Turnier sind keine Phasen hinterlegt.',
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                key: const ValueKey('tournament-info-dialog-close'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Schließen'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stageCard(int number, TournamentStage stage, ThemeData theme) {
    final lines = <String>[];
    if (stage.isGroupStage) {
      lines.addAll([
        TournamentInfoSummary.groupSizes(stage),
        'Zuweisungsmethode: '
            '${TournamentInfoSummary.groupAssignmentModeLabel(stage.groupAssignmentMode)}',
        TournamentInfoSummary.playType(stage),
        TournamentInfoSummary.format(stage.gameFormat),
        TournamentInfoSummary.advancement(stage),
        'Regeln bei Punktgleichheit: '
            '${TournamentInfoSummary.tieBreakers(stage.groupTieBreakers)}',
      ]);
    } else {
      final advancing = stage.knockoutParticipantCount;
      lines.addAll([
        if (advancing != null) 'Top $advancing',
        'Auslosungsmethode: '
            '${TournamentInfoSummary.knockoutSeedingModeLabel(stage.knockoutSeedingMode)}',
        TournamentInfoSummary.format(stage.gameFormat),
        if (stage.placementPlaces.contains(3))
          'Optionales Platzierungsspiel um Platz 3',
      ]);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Phase $number: ${TournamentInfoSummary.stageType(stage)}'
              '${stage.name.isEmpty ? '' : ' · ${stage.name}'}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(line, style: theme.textTheme.bodyMedium),
              ),
          ],
        ),
      ),
    );
  }
}
