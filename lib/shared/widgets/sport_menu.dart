import 'package:flutter/material.dart';

import '../../app/app_theme.dart';

class SportMenuAction {
  const SportMenuAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.description,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final String? description;
}

/// A single quiet surface instead of a separate card for every command.
class SportMenuGroup extends StatelessWidget {
  const SportMenuGroup({
    super.key,
    required this.title,
    required this.actions,
    this.collapsible = false,
    this.icon = Icons.tune,
  });
  final String title;
  final List<SportMenuAction> actions;
  final bool collapsible;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = <Widget>[
      for (var i = 0; i < actions.length; i++) ...[
        if (i > 0)
          Divider(
            height: 1,
            indent: 68,
            endIndent: 16,
            color: scheme.outlineVariant,
          ),
        ListTile(
          enabled: actions[i].onTap != null,
          minVerticalPadding: 12,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(actions[i].icon, size: 22),
          ),
          title: Text(
            actions[i].label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: actions[i].description == null
              ? null
              : Text(actions[i].description!),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: actions[i].onTap,
        ),
      ],
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!collapsible)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: collapsible
                ? ExpansionTile(
                    key: PageStorageKey('sport-menu-$title'),
                    maintainState: true,
                    leading: Icon(icon),
                    title: Text(title),
                    children: entries,
                  )
                : Column(children: entries),
          ),
        ],
      ),
    );
  }
}

/// Overflow actions stay labelled and keyboard accessible.
class SportActionsMenu extends StatelessWidget {
  const SportActionsMenu({
    super.key,
    required this.actions,
    this.label = 'Weitere Aktionen',
  });
  final List<SportMenuAction> actions;
  final String label;
  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    tooltip: label,
    onSelected: (index) => actions[index].onTap?.call(),
    itemBuilder: (_) => [
      for (var i = 0; i < actions.length; i++)
        PopupMenuItem(
          value: i,
          enabled: actions[i].onTap != null,
          child: Row(
            children: [
              Icon(actions[i].icon),
              const SizedBox(width: 12),
              Expanded(child: Text(actions[i].label)),
            ],
          ),
        ),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.more_horiz),
          const SizedBox(width: 8),
          Flexible(child: Text(label)),
        ],
      ),
    ),
  );
}

/// Shared presentation for all context-menu entries.
class SportMenuLabel extends StatelessWidget {
  const SportMenuLabel({super.key, required this.label, required this.icon});
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: appAccentColor(context)),
      const SizedBox(width: 12),
      Expanded(child: Text(label)),
    ],
  );
}
