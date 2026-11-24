import 'package:flutter/material.dart';

import 'package:dart_tournament_manager/tournament_workspace.dart'
    show KnockoutBracketView;

import '../../../../shared/widgets/adaptive_content.dart';
import '../../application/tournament_phase_views.dart';
import '../../domain/tournament_models.dart';
import '../widgets/run/brackets/knockout_seeding_mode_label.dart'
    show knockoutSeedingModeLabelForStage;
import '../widgets/run/standings_table.dart';

/// Read-only detail view over every derived phase of a finished tournament.
class TournamentPhaseResultsPage extends StatelessWidget {
  const TournamentPhaseResultsPage({
    super.key,
    required this.tournament,
    this.initialPhaseIndex = 0,
  });

  final CreatedTournament tournament;
  final int initialPhaseIndex;

  @override
  Widget build(BuildContext context) {
    final phases = const TournamentPhaseViews().derive(tournament);
    if (phases.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Turnierphasen')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Für dieses Turnier sind keine Turnierphasen vorhanden.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final initialIndex = initialPhaseIndex.clamp(0, phases.length - 1);
    return DefaultTabController(
      length: phases.length,
      initialIndex: initialIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Turnierphasen'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final phase in phases)
                Tab(
                  key: ValueKey('phase-tab-${phase.index}'),
                  text: phase.name,
                ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final phase in phases)
              _TournamentPhaseSection(tournament: tournament, phase: phase),
          ],
        ),
      ),
    );
  }
}

class _TournamentPhaseSection extends StatelessWidget {
  const _TournamentPhaseSection({
    required this.tournament,
    required this.phase,
  });

  final CreatedTournament tournament;
  final TournamentPhaseView phase;

  @override
  Widget build(BuildContext context) {
    return AdaptiveContentList(
      key: PageStorageKey('tournament-phase-${phase.index}'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          phase.name,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(switch (phase.type) {
          TournamentPhaseViewType.table => 'Tabelle und Begegnungen',
          TournamentPhaseViewType.knockout => 'K.-o.-Baum',
          TournamentPhaseViewType.kratzer => 'Kratzer mit verbleibenden Leben',
        }, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        switch (phase.type) {
          TournamentPhaseViewType.table => _TablePhaseBody(phase: phase),
          TournamentPhaseViewType.knockout => _KnockoutPhaseBody(
            tournament: tournament,
            phase: phase,
          ),
          TournamentPhaseViewType.kratzer => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LivesCard(livesRemaining: phase.livesRemaining),
              const SizedBox(height: 16),
              _KnockoutPhaseBody(tournament: tournament, phase: phase),
            ],
          ),
        },
        const SizedBox(height: 24),
      ],
    );
  }
}

class _TablePhaseBody extends StatelessWidget {
  const _TablePhaseBody({required this.phase});

  final TournamentPhaseView phase;

  @override
  Widget build(BuildContext context) {
    final stage = phase.stage;
    if (stage is! GroupTournamentRunStage || phase.groups.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Für diese Phase liegen keine Tabellen vor.'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final groupView in phase.groups)
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Gruppe ${groupView.groupNumber} · ${groupView.group.name}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final table = StandingsTable(
                        standings: groupView.standings,
                        group: groupView.group,
                        groupNumber: groupView.groupNumber,
                        qualificationPlan: stage.qualificationPlan,
                        tieBreakers: stage.tieBreakers,
                      );
                      final matches = _PhaseMatchList(
                        matches: [
                          ...groupView.group.matches,
                          ...groupView.group.knockoutRounds.expand(
                            (round) => round,
                          ),
                          ...groupView.group.placementMatches,
                        ],
                      );
                      if (constraints.maxWidth >= 900) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: table),
                            const SizedBox(width: 16),
                            Expanded(flex: 2, child: matches),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [table, const SizedBox(height: 16), matches],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PhaseMatchList extends StatelessWidget {
  const _PhaseMatchList({required this.matches});

  final List<GroupMatch> matches;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Begegnungen',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        if (matches.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Keine Begegnungen vorhanden.'),
          ),
        for (final match in matches)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(
              match.isKratzer
                  ? match.participantLabel
                  : '${match.homePlayer?.name ?? 'Offen'} – '
                        '${match.awayPlayer?.name ?? 'Offen'}',
            ),
            subtitle: match.label == null ? null : Text(match.label!),
            trailing: Text(
              match.isAnnulled
                  ? 'Annulliert'
                  : match.hasResult
                  ? match.scoreLabel
                  : 'Offen',
            ),
          ),
      ],
    );
  }
}

class _KnockoutPhaseBody extends StatelessWidget {
  const _KnockoutPhaseBody({required this.tournament, required this.phase});

  final CreatedTournament tournament;
  final TournamentPhaseView phase;

  @override
  Widget build(BuildContext context) {
    final knockoutStage = phase.knockoutStage;
    if (knockoutStage == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Für diese Phase liegt kein Turnierbaum vor.'),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: KnockoutBracketView(
                  stage: knockoutStage,
                  placementMatches: knockoutStage.placementMatches,
                  qualifyingRank: _qualifyingRankFor(tournament, phase.index),
                  onEditResult: (_) {},
                  canEditResults: false,
                  isEditMode: false,
                  onSwapSlot: (_, _) {},
                  drawMethodLabel: knockoutSeedingModeLabelForStage(
                    tournament,
                    knockoutStage,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _PhaseMatchList(matches: knockoutStage.matches),
            if (constraints.maxWidth < 600) const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class _LivesCard extends StatelessWidget {
  const _LivesCard({required this.livesRemaining});

  final Map<String, int> livesRemaining;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Verbleibende Leben',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (livesRemaining.isEmpty)
              const Text('Es sind keine Leben erfasst.')
            else
              for (final entry in livesRemaining.entries)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Icon(
                    entry.value == 0
                        ? Icons.person_off_outlined
                        : Icons.favorite_outlined,
                  ),
                  title: Text(entry.key),
                  trailing: Text('${entry.value} Leben'),
                ),
          ],
        ),
      ),
    );
  }
}

int _qualifyingRankFor(CreatedTournament tournament, int stageIndex) {
  if (stageIndex >= tournament.stages.length - 1) return 1;
  final runStage = tournament.runStages[stageIndex];
  final availablePlayers = switch (runStage) {
    GroupTournamentRunStage() => runStage.groups.fold<int>(
      0,
      (sum, group) => sum + group.players.length,
    ),
    KnockoutTournamentRunStage() when runStage.isKratzer =>
      runStage.participants.length,
    KnockoutTournamentRunStage() =>
      runStage.rounds.isEmpty
          ? 0
          : runStage.rounds.first.fold<int>(
              0,
              (sum, match) =>
                  sum +
                  (match.homePlayer == null ? 0 : 1) +
                  (match.awayPlayer == null ? 0 : 1),
            ),
    _ => 0,
  };
  if (availablePlayers <= 0) return 1;

  final nextStage = tournament.stages[stageIndex + 1];
  final requiredPlayers = nextStage.isGroupStage
      ? nextStage.groupSizes.fold<int>(0, (sum, size) => sum + size)
      : nextStage.knockoutParticipantCount ?? availablePlayers;
  return requiredPlayers.clamp(1, availablePlayers).toInt();
}
