import 'board_match_card.dart';
import 'participant_match_picker.dart';
import 'play_queue_block.dart';
import '../../../../../shared/widgets/sport_settings_section.dart';
import '../../../../../shared/widgets/sport_menu.dart';
import 'package:flutter/material.dart';
import '../../../application/order_of_play/order_of_play_controller.dart';
import '../../../application/tournament_flow_priority.dart';
import '../../../domain/tournament_models.dart';
import '../../../../statistics/presentation/tournament_match_statistics_page.dart';

class OrderOfPlaySection extends StatelessWidget {
  const OrderOfPlaySection({
    super.key,
    required this.tournament,
    required this.activeStage,
    required this.onChange,
    required this.onResult,
  });
  final CreatedTournament tournament;
  final int activeStage;
  final Future<void> Function() onChange;
  final Future<void> Function(GroupMatch) onResult;

  @override
  Widget build(BuildContext context) {
    const controller = OrderOfPlayController();
    final schedule = controller.plan(tournament, activeStage);
    final activeStageData =
        activeStage >= 0 && activeStage < tournament.runStages.length
        ? tournament.runStages[activeStage]
        : null;
    final flowPriority = TournamentFlowPriority.forStage(activeStageData);
    final occupied = {for (final e in schedule.running) e.match.boardNumber};
    Widget title(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
    Widget row(PlayEntry entry, String detail, {Widget? action}) =>
        MatchStatisticsTapTarget(
          match: entry.match,
          tournament: tournament,
          child: BoardMatchCard(
            home: entry.stageIndex > activeStage
                ? 'Qualifikation noch offen'
                : entry.match.homePlayer?.name ?? 'Noch offen',
            away: entry.stageIndex > activeStage
                ? 'Qualifikation noch offen'
                : entry.match.awayPlayer?.name ?? 'Noch offen',
            origin: entry.origin,
            status: detail,
            running: schedule.running.contains(entry),
            action: action,
          ),
        );
    Widget plannedRow(BoardAssignment assignment, bool next) => PlayQueueMatch(
      key: ObjectKey(assignment.entry.match),
      home: assignment.entry.match.homePlayer?.name ?? 'Noch offen',
      away: assignment.entry.match.awayPlayer?.name ?? 'Noch offen',
      origin: assignment.entry.origin,
      board: assignment.board,
      isPriority: flowPriority.prioritizedMatches.contains(
        assignment.entry.match,
      ),
      action: Wrap(
        spacing: 4,
        runSpacing: 4,
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            tooltip: 'Ergebnis erfassen',
            icon: const Icon(Icons.edit_note),
            onPressed: () => onResult(assignment.entry.match),
          ),
          PopupMenuButton<int>(
            tooltip: 'Starten / vorziehen',
            enabled:
                !schedule.running.any(
                  (e) => e.players.any(assignment.entry.players.contains),
                ) &&
                occupied.length < tournament.boardCount,
            itemBuilder: (_) => [
              for (var board = 1; board <= tournament.boardCount; board++)
                if (!occupied.contains(board) &&
                    !tournament.blockedBoards.contains(board))
                  PopupMenuItem(
                    value: board,
                    child: SportMenuLabel(
                      label: 'Auf Board $board starten',
                      icon: Icons.play_arrow_outlined,
                    ),
                  ),
            ],
            onSelected: (board) async {
              if (controller.start(
                tournament,
                activeStage,
                assignment.entry.match,
                board,
              )) {
                await onChange();
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_arrow),
                  const SizedBox(width: 8),
                  Flexible(child: Text(next ? 'Starten' : 'Vorziehen')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    final firstBlock = schedule.planned.firstOrNull?.block;
    final blocks = <int, List<BoardAssignment>>{};
    for (final assignment in schedule.planned) {
      blocks.putIfAbsent(assignment.block, () => []).add(assignment);
    }
    for (final assignments in blocks.values) {
      assignments.sort((a, b) {
        final aIsPriority = flowPriority.prioritizedMatches.contains(
          a.entry.match,
        );
        final bIsPriority = flowPriority.prioritizedMatches.contains(
          b.entry.match,
        );
        if (aIsPriority == bIsPriority) return 0;
        return aIsPriority ? -1 : 1;
      });
    }
    final orderedBlocks = blocks.keys.toList()..sort();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Order of Play',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              '${schedule.running.length} laufend · ${schedule.planned.length} eingeplant · ${schedule.finished.length} erledigt',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              isExpanded: true,
              itemHeight: null,
              key: ValueKey(tournament.boardCount),
              initialValue: tournament.boardCount,
              decoration: const InputDecoration(
                labelText: 'Verfügbare Boards',
                border: OutlineInputBorder(),
              ),
              items: [
                for (var count = 1; count <= 64; count++)
                  DropdownMenuItem(
                    value: count,
                    enabled: !occupied.any(
                      (board) => board != null && board > count,
                    ),
                    child: Text(count == 1 ? '1 Board' : '$count Boards'),
                  ),
              ],
              onChanged: (value) async {
                if (value == null) return;
                tournament.boardCount = value;
                await onChange();
              },
            ),
            const SizedBox(height: 12),
            ParticipantMatchPicker(
              tournament: tournament,
              activeStage: activeStage,
              onChange: onChange,
            ),
            if (schedule.running.isNotEmpty) title('Jetzt auf den Boards'),
            for (final entry in schedule.running)
              row(
                entry,
                'Board ${entry.match.boardNumber} · läuft seit ${entry.match.startedAt!.toLocal().toString().substring(11, 16)}',
                action: PopupMenuButton<String>(
                  tooltip: 'Match verwalten',
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'result',
                      child: SportMenuLabel(
                        label: 'Ergebnis eingeben',
                        icon: Icons.arrow_forward_outlined,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'cancel',
                      child: SportMenuLabel(
                        label: 'Start zurücknehmen',
                        icon: Icons.play_arrow_outlined,
                      ),
                    ),
                  ],
                  onSelected: (value) async {
                    if (value == 'result') {
                      await onResult(entry.match);
                    } else {
                      entry.match.startedAt = null;
                      entry.match.startedPlayers = null;
                      entry.match.boardNumber = null;
                      await onChange();
                    }
                  },
                ),
              ),
            for (final notice in flowPriority.notices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.tertiaryContainer.withAlpha(48),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.tertiary.withAlpha(100),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.priority_high,
                        size: 18,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(notice)),
                    ],
                  ),
                ),
              ),
            title('Geplante Reihenfolge'),
            const Text(
              'Unverbindliche Empfehlung zur gleichmäßigen Auslastung. Spiele im selben Block sind parallel vorgesehen. Ergebnisse können jederzeit direkt ohne Startschritt erfasst werden.',
            ),
            const SizedBox(height: 12),
            if (orderedBlocks.isEmpty)
              const Text(
                'Keine weiteren spielbereiten Matches in der aktiven Etappe.',
              ),
            for (final block in orderedBlocks)
              PlayQueueBlock(
                key: ValueKey('play-block-$block'),
                number: block + 1,
                next: block == firstBlock,
                waitingForBoards: block > 0 && schedule.running.isNotEmpty,
                parallelCount: blocks[block]!.length,
                children: [
                  for (final assignment in blocks[block]!)
                    plannedRow(assignment, block == firstBlock),
                ],
              ),
            if (schedule.finished.isNotEmpty) ...[
              SportSettingsSection(
                title: 'Abgeschlossene Matches',
                summary: '${schedule.finished.length} Ergebnisse',
                icon: Icons.check_circle_outline,
                children: [
                  title('Abgeschlossen · nach Ergebniseingang'),
                  for (final entry in schedule.finished)
                    row(
                      entry,
                      entry.match.isAnnulled
                          ? 'Annulliert'
                          : !entry.match.hasPlayers
                          ? 'Freilos · kein Board nötig'
                          : '${entry.match.scoreLabel} · ${entry.match.boardNumber == null ? 'Board nicht erfasst' : 'Board ${entry.match.boardNumber}'} · ${entry.match.finishedAt?.toLocal().toString().substring(0, 16) ?? 'Reihenfolge früherer Spiele nicht erfasst'}',
                      action:
                          entry.stageIndex == activeStage &&
                              entry.match.hasPlayers
                          ? IconButton(
                              tooltip: 'Ergebnis bearbeiten',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => onResult(entry.match),
                            )
                          : null,
                    ),
                ],
              ),
            ],
            if (schedule.waiting.isNotEmpty) ...[
              SportSettingsSection(
                title: 'Weitere Paarungen',
                summary:
                    '${schedule.waiting.length} warten auf Ergebnisse oder Freigabe',
                children: [
                  title('Wartet auf Ergebnisse / Etappenfreigabe'),
                  const Text(
                    'Diese Matches bekommen ihre Board-Zuordnung, sobald die Paarungen und die Etappe freigegeben sind.',
                  ),
                  for (final entry in schedule.waiting)
                    row(entry, 'Noch nicht eingeplant'),
                ],
              ),
            ],
            const SportSettingsSection(
              title: 'Spielplan verstehen',
              summary: 'Boards, Pausen und Zeitblöcke erklärt',
              icon: Icons.info_outline,
              children: [
                Text(
                  'Gleiche Blöcke laufen parallel. Die Planung bevorzugt lange Pausen und belegte Boards; gleichmäßige Pausen sind nicht immer möglich. Starten reserviert Board und Spieler. Vorziehen ist auf jedem freien Board möglich und plant die restlichen Matches neu. Zeitblöcke sind eine Reihenfolge, keine festen Uhrzeiten.',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
