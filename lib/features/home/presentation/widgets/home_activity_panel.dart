import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/home_overview_service.dart';

class HomeActivityPanel extends StatefulWidget {
  const HomeActivityPanel({
    super.key,
    this.service,
    required this.onOpenTournament,
  });

  final HomeOverviewService? service;
  final ValueChanged<String> onOpenTournament;

  @override
  State<HomeActivityPanel> createState() => _HomeActivityPanelState();
}

class _HomeActivityPanelState extends State<HomeActivityPanel> {
  late Future<HomeOverviewSnapshot> _snapshot;
  Timer? _rotationTimer;
  int _cardIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HomeActivityPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) _load();
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    super.dispose();
  }

  void _load() {
    _snapshot =
        (widget.service ?? HomeOverviewService(LocalHomeOverviewDataSource()))
            .load();
  }

  void _retry() {
    setState(_load);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<HomeOverviewSnapshot>(
    future: _snapshot,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _PanelCard(
          child: Row(
            children: [
              const Icon(Icons.error_outline),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Die Startseiten-Übersicht konnte nicht geladen werden: '
                  '${snapshot.error}',
                ),
              ),
              IconButton(
                onPressed: _retry,
                tooltip: 'Übersicht erneut laden',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        );
      }
      if (!snapshot.hasData) {
        return const _PanelCard(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          ),
        );
      }
      final overview = snapshot.data!;
      final active = overview.activeTournament;
      final latest = overview.latestTournament;
      final carouselCards = overview.cards
          .where((card) => card != latest)
          .toList();
      if (carouselCards.isEmpty && active == null && latest == null) {
        return const SizedBox.shrink();
      }
      if (carouselCards.length > 1) {
        _rotationTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
          if (!mounted) return;
          setState(() => _cardIndex++);
        });
      } else {
        _rotationTimer?.cancel();
        _rotationTimer = null;
      }
      final carousel = carouselCards.isEmpty
          ? null
          : _rotatingCard(
              context,
              carouselCards[_cardIndex % carouselCards.length],
              _cardIndex % carouselCards.length,
              carouselCards.length,
            );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (active != null) _activeCard(context, active),
          if (active == null && latest != null)
            _rotatingCard(context, latest, -1, 0),
          if (carousel != null) ...[
            if (active != null || latest != null) const SizedBox(height: 12),
            carousel,
          ],
        ],
      );
    },
  );

  Widget _activeCard(
    BuildContext context,
    HomeOverviewActiveTournament tournament,
  ) {
    final theme = Theme.of(context);
    return _PanelCard(
      onTap: () => widget.onOpenTournament(tournament.id),
      borderColor: theme.colorScheme.primary,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'AKTUELLES TURNIER',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  _StatusChip(label: 'Läuft', color: theme.colorScheme.primary),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                tournament.name,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: compact ? 20 : 40,
                runSpacing: 12,
                children: [
                  _Metric(
                    label: 'Teilnehmende',
                    value: '${tournament.participantCount}',
                  ),
                  _Metric(
                    label: 'Begegnungen',
                    value:
                        '${tournament.playedMatches} / ${tournament.totalMatches}',
                  ),
                  _Metric(
                    label: 'Noch offen',
                    value: '${tournament.openMatches}',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Semantics(
                  label:
                      'Turnierfortschritt: ${tournament.playedMatches} von ${tournament.totalMatches} Begegnungen',
                  child: LinearProgressIndicator(
                    value: tournament.progress.clamp(0, 1),
                    minHeight: 8,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Turnier öffnen',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _rotatingCard(
    BuildContext context,
    HomeOverviewCard card,
    int displayedIndex,
    int cardCount,
  ) {
    final theme = Theme.of(context);
    return _PanelCard(
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  _iconFor(card.icon),
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                Text(
                  card.title.toUpperCase(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Column(
                key: ValueKey(displayedIndex),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in card.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        line,
                        style: constraints.maxWidth < 420
                            ? theme.textTheme.bodyMedium
                            : theme.textTheme.titleMedium,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 5,
              children: [
                for (var index = 0; index < cardCount; index++)
                  Icon(
                    index == displayedIndex
                        ? Icons.circle
                        : Icons.circle_outlined,
                    size: 10,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String name) => switch (name) {
    'sports' => Icons.sports,
    'emoji_events' => Icons.emoji_events_outlined,
    'leaderboard' => Icons.leaderboard_outlined,
    'swap_vert' => Icons.swap_vert,
    'military_tech' => Icons.military_tech,
    'local_fire_department' => Icons.local_fire_department,
    'workspace_premium' => Icons.workspace_premium_outlined,
    _ => Icons.insights_outlined,
  };
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child, this.onTap, this.borderColor});

  final Widget child;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(
        color: borderColor ?? Theme.of(context).colorScheme.outlineVariant,
      ),
    ),
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 2),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
