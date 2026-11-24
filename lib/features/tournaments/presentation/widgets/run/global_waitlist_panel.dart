import 'package:flutter/material.dart';

import '../../../application/tournament_director_snapshot.dart';
import '../../../domain/engines/board_scheduling_engine.dart';
import '../../../domain/engines/global_waitlist_engine.dart';
import '../../../domain/tournament_models.dart';

/// Shared presentation of the tournament-wide waiting list.
///
/// The same widget is used by the tournament director and by the standalone
/// second monitor, so both views always show the same fixed preview and the
/// same optimised remainder.
class GlobalWaitlistPanel extends StatelessWidget {
  const GlobalWaitlistPanel({
    super.key,
    required this.snapshot,
    this.onFixedCountChanged,
    this.dense = false,
  });

  final TournamentDirectorSnapshot snapshot;
  final ValueChanged<int>? onFixedCountChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final plan = snapshot.globalWaitlist;
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final surface = theme.colorScheme.surfaceContainerHighest;
    final spacing = dense ? 6.0 : 10.0;

    return Semantics(
      label: 'Gemeinsame Warteliste',
      child: Container(
        key: const ValueKey('global-waitlist-panel'),
        padding: EdgeInsets.all(dense ? 10 : 14),
        decoration: BoxDecoration(
          color: surface.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.list_alt, color: accent),
                    const SizedBox(width: 8),
                    Text(
                      'Gemeinsame Warteliste',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ],
                ),
                if (onFixedCountChanged != null)
                  SizedBox(
                    width: 190,
                    child: DropdownButtonFormField<int>(
                      initialValue: plan.fixedCount,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Fixierte Begegnungen',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final count in const [2, 4, 6, 8, 10, 12])
                          DropdownMenuItem(
                            value: count,
                            child: Text('$count Begegnungen'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) onFixedCountChanged!(value);
                      },
                    ),
                  ),
              ],
            ),
            SizedBox(height: spacing),
            Text(
              'Die nächste Begegnung kommt an das nächste freie Board.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if ([
              ...plan.fixed,
              ...plan.dynamic,
              ...plan.skipped,
            ].any(plan.isSkipped))
              Padding(
                padding: EdgeInsets.only(top: spacing / 2),
                child: Text(
                  'Einige Begegnungen sind vorläufig übersprungen, weil ihre Spieler noch spielen.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (plan.groupProgress.isNotEmpty) ...[
              SizedBox(height: spacing),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final group in plan.groupProgress)
                    _GroupProgressChip(group: group, dense: dense),
                ],
              ),
            ],
            SizedBox(height: spacing + 2),
            _sectionHeading(
              context,
              key: const ValueKey('global-waitlist-fixed-heading'),
              icon: Icons.lock_outline,
              label: 'Fest eingeplant',
              detail: 'Nächste ${plan.fixedCount} Begegnungen: FIX',
              color: accent,
            ),
            if (plan.fixed.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: spacing, bottom: spacing),
                child: Text(
                  'Derzeit sind keine spielbaren Begegnungen verfügbar.',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              for (var index = 0; index < plan.fixed.length; index++)
                _MatchRow(
                  key: ValueKey('global-waitlist-fixed-$index'),
                  number: index + 1,
                  entry: plan.fixed[index],
                  fixed: true,
                  skipped: plan.isSkipped(plan.fixed[index]),
                  dense: dense,
                ),
            if (plan.fixed.length < plan.fixedCount)
              Padding(
                padding: EdgeInsets.only(top: spacing),
                child: Text(
                  'Nur ${plan.fixed.length} spielbare Begegnungen verfügbar.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: spacing + 2),
              child: Divider(color: accent.withValues(alpha: 0.4)),
            ),
            _sectionHeading(
              context,
              key: const ValueKey('global-waitlist-dynamic-heading'),
              icon: Icons.autorenew,
              label: 'Dynamisch optimiert',
              detail: 'Wird nach jedem Aufruf neu berechnet',
              color: theme.colorScheme.tertiary,
            ),
            if (plan.dynamic.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: spacing),
                child: Text(
                  'Keine weiteren offenen Begegnungen.',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              for (var index = 0; index < plan.dynamic.length; index++)
                _MatchRow(
                  key: ValueKey('global-waitlist-dynamic-$index'),
                  number: plan.fixed.length + index + 1,
                  entry: plan.dynamic[index],
                  fixed: false,
                  skipped: plan.isSkipped(plan.dynamic[index]),
                  dense: dense,
                ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeading(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required String detail,
    required Color color,
  }) {
    return Row(
      key: key,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            detail,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupProgressChip extends StatelessWidget {
  const _GroupProgressChip({required this.group, required this.dense});

  final GlobalWaitlistGroupProgress group;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (group.displayedRatio * 100).round();
    return Container(
      constraints: BoxConstraints(minWidth: dense ? 150 : 180, maxWidth: 240),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${group.label} · ${group.total} Spieler',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (group.needsCatchUp)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Aufholbedarf',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${group.completed} von ${group.total} Partien · $percent %',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: group.displayedRatio.clamp(0.0, 1.0),
            minHeight: 5,
          ),
        ],
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({
    super.key,
    required this.number,
    required this.entry,
    required this.fixed,
    required this.skipped,
    required this.dense,
  });

  final int number;
  final PlayEntry entry;
  final bool fixed;
  final bool skipped;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final GroupMatch match = entry.match;
    final group = _groupShortLabel(entry.groupKey);
    final color = fixed
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.only(top: dense ? 3 : 4),
      child: Row(
        children: [
          Container(
            width: dense ? 24 : 28,
            height: dense ? 24 : 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fixed
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$number',
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(width: dense ? 6 : 8),
          Expanded(
            child: Text(
              match.participantShortLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: fixed ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (group.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              '· $group',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (skipped)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '· übersprungen',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (fixed)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(
                Icons.lock_outline,
                size: 14,
                color: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }

  String _groupShortLabel(String? key) {
    if (key == null || key.isEmpty) return '';
    final separator = key.indexOf(':');
    var name = separator >= 0 ? key.substring(separator + 1) : key;
    name = name.replaceFirst(RegExp(r'^Gruppe\s+'), '');
    return name;
  }
}
