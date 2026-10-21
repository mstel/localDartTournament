import 'package:flutter/material.dart';
import '../../../../../shared/widgets/adaptive_content.dart';

/// Each numbered block is one step in the board schedule; its matches are parallel.
class PlayQueueBlock extends StatelessWidget {
  const PlayQueueBlock({
    super.key,
    required this.number,
    required this.next,
    required this.parallelCount,
    required this.children,
    this.waitingForBoards = false,
  });
  final int number, parallelCount;
  final bool next, waitingForBoards;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: next ? scheme.primaryContainer : scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: next ? scheme.primary : scheme.outlineVariant,
          width: next ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                padding: const EdgeInsets.all(8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: next ? scheme.primary : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$number',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: next ? scheme.onPrimary : scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      next ? 'Als Nächstes' : 'Danach · Block $number',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      parallelCount > 1
                          ? '$parallelCount Spiele parallel auf verschiedenen Boards'
                          : 'Ein Spiel in diesem Block',
                    ),
                    if (next && waitingForBoards)
                      const Text('Start, sobald Boards und Spieler frei sind.'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (children.length == 1)
            children.single
          else
            AdaptiveTileLayout(minTileWidth: 360, children: children),
        ],
      ),
    );
  }
}

class PlayQueueMatch extends StatelessWidget {
  const PlayQueueMatch({
    super.key,
    required this.home,
    required this.away,
    required this.origin,
    required this.board,
    required this.action,
    this.isPriority = false,
  });
  final String home, away, origin;
  final int board;
  final Widget action;
  final bool isPriority;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isPriority
            ? colors.tertiaryContainer.withAlpha(48)
            : colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPriority
              ? colors.tertiary.withAlpha(100)
              : colors.outlineVariant,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pairing = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$home – $away',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(origin, style: Theme.of(context).textTheme.bodySmall),
            ],
          );
          final boardLabel = Text(
            'Board $board',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: colors.primary),
          );
          final priorityLabel = isPriority
              ? Tooltip(
                  message: 'Priorisierte Partie',
                  child: Text(
                    '!',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.tertiary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : null;
          if (constraints.maxWidth >= 640 &&
              MediaQuery.textScalerOf(context).scale(16) <= 24) {
            return Row(
              children: [
                boardLabel,
                const SizedBox(width: 20),
                Expanded(child: pairing),
                if (priorityLabel != null) ...[
                  const SizedBox(width: 8),
                  priorityLabel,
                ],
                const SizedBox(width: 12),
                action,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [boardLabel, const Spacer(), ?priorityLabel]),
              const SizedBox(height: 6),
              pairing,
              Align(alignment: Alignment.centerRight, child: action),
            ],
          );
        },
      ),
    );
  }
}
