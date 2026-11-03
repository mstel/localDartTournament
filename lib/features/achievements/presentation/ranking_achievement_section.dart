import 'package:flutter/material.dart';

import '../../rankings/domain/local_ranking.dart';
import '../domain/achievement_definition.dart';
import '../domain/achievement_engine.dart';

class RankingAchievementView {
  const RankingAchievementView({
    required this.ranking,
    required this.playerProfileId,
    required this.evaluation,
  });

  final LocalRanking ranking;
  final String playerProfileId;
  final AchievementEvaluation evaluation;
}

class RankingAchievementSection extends StatelessWidget {
  const RankingAchievementSection({super.key, required this.achievements});

  final List<RankingAchievementView> achievements;

  @override
  Widget build(BuildContext context) {
    if (achievements.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text('Errungenschaften', style: Theme.of(context).textTheme.titleLarge),
        for (final view in achievements) _RankingAchievements(view: view),
      ],
    );
  }
}

class _RankingAchievements extends StatelessWidget {
  const _RankingAchievements({required this.view});

  final RankingAchievementView view;

  @override
  Widget build(BuildContext context) {
    final evaluation = view.evaluation;
    final unlocked = evaluation.progress.values
        .where((item) => item.isCompleted)
        .length;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = constraints.maxWidth >= 600
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  view.ranking.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: itemWidth,
                      child: _AchievementSummaryTile(
                        icon: Icons.emoji_events_outlined,
                        title: 'Errungenschaften',
                        value: '$unlocked/${evaluation.progress.length}',
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _AchievementSummaryTile(
                        icon: Icons.stars_outlined,
                        title: 'Errungenschaften-Level',
                        value: 'Level ${evaluation.level}',
                        detail: evaluation.experiencePointsToNextLevel == null
                            ? '${evaluation.totalExperiencePoints} XP insgesamt'
                            : '${evaluation.experiencePointsToNextLevel} XP bis zum nächsten Level',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: evaluation.levelProgress),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _AchievementDetailsDialog(view: view),
                    ),
                    icon: const Icon(Icons.list_alt),
                    label: const Text('Errungenschaften anzeigen'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AchievementSummaryTile extends StatelessWidget {
  const _AchievementSummaryTile({
    required this.icon,
    required this.title,
    required this.value,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleLarge),
                if (detail != null) Text(detail!),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _AchievementDetailsDialog extends StatefulWidget {
  const _AchievementDetailsDialog({required this.view});

  final RankingAchievementView view;

  @override
  State<_AchievementDetailsDialog> createState() =>
      _AchievementDetailsDialogState();
}

class _AchievementDetailsDialogState extends State<_AchievementDetailsDialog> {
  AchievementCategory? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final categories = _selectedCategory == null
        ? AchievementCategory.values
        : [_selectedCategory!];
    final visibleProgress = widget.view.evaluation.progress.values.where(
      (item) =>
          _selectedCategory == null ||
          item.definition.category == _selectedCategory,
    );
    final grouped = {
      for (final category in categories)
        category: visibleProgress
            .where((item) => item.definition.category == category)
            .toList(),
    };
    final recentUnlocks =
        visibleProgress
            .where((item) => item.isCompleted && item.unlockedAt != null)
            .toList()
          ..sort(
            (left, right) => right.unlockedAt!.compareTo(left.unlockedAt!),
          );
    return AlertDialog(
      title: Text('Errungenschaften · ${widget.view.ranking.name}'),
      content: SizedBox(
        width: 680,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<AchievementCategory?>(
                  initialValue: _selectedCategory,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Kategorie filtern',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<AchievementCategory?>(
                      value: null,
                      child: Text('Alle Kategorien'),
                    ),
                    for (final category in AchievementCategory.values)
                      DropdownMenuItem<AchievementCategory?>(
                        value: category,
                        child: Text(category.label),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedCategory = value),
                ),
                const SizedBox(height: 8),
                for (final category in categories)
                  Builder(
                    builder: (context) {
                      final categoryItems = grouped[category]!;
                      final completedCount = categoryItems
                          .where((item) => item.isCompleted)
                          .length;
                      final countLabel =
                          category == AchievementCategory.rankingAwards
                          ? '${completedCount == 0 ? 0 : 1} / 1 abgeschlossen'
                          : '$completedCount / ${categoryItems.length} abgeschlossen';
                      return ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(category.label),
                        subtitle: Text(countLabel),
                        children: [
                          for (final progress in categoryItems)
                            _AchievementProgressTile(progress: progress),
                        ],
                      );
                    },
                  ),
                if (recentUnlocks.isNotEmpty) ...[
                  const Divider(),
                  Text(
                    _selectedCategory == null
                        ? 'Zuletzt freigeschaltet'
                        : 'Zuletzt freigeschaltet · '
                              '${_selectedCategory!.label}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final progress in recentUnlocks.take(5))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.check_circle_outline),
                      title: Text(progress.definition.name),
                      subtitle: Text(
                        MaterialLocalizations.of(
                          context,
                        ).formatMediumDate(progress.unlockedAt!.toLocal()),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}

class _AchievementProgressTile extends StatelessWidget {
  const _AchievementProgressTile({required this.progress});

  final AchievementProgress progress;

  String _format(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = switch (progress.status) {
      AchievementStatus.locked => 'Gesperrt',
      AchievementStatus.inProgress => 'In Bearbeitung',
      AchievementStatus.completed => 'Abgeschlossen',
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        progress.isCompleted
            ? Icons.check_circle
            : progress.status == AchievementStatus.inProgress
            ? Icons.timelapse
            : Icons.lock_outline,
        color: progress.isCompleted ? theme.colorScheme.primary : null,
      ),
      title: Text(progress.definition.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(progress.definition.description),
          const SizedBox(height: 4),
          Text(
            '$status · ${_format(progress.currentValue)} / '
            '${_format(progress.definition.target)}',
          ),
          LinearProgressIndicator(value: progress.fraction),
          if (progress.unlockedAt != null)
            Text(
              'Freigeschaltet am '
              '${MaterialLocalizations.of(context).formatMediumDate(progress.unlockedAt!.toLocal())}',
            ),
        ],
      ),
      trailing: Text('${progress.definition.experiencePoints} XP'),
    );
  }
}
