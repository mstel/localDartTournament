import 'package:flutter/material.dart';
import '../../../../../shared/widgets/sport_settings_section.dart';
import '../../../domain/tournament_models.dart';
import 'stage_controls.dart';

/// Navigation first; timing, format and ranking details stay out of the match list.
class TournamentRunHeader extends StatelessWidget {
  const TournamentRunHeader({
    super.key,
    required this.tournament,
    required this.stageIndex,
    required this.completedStages,
    required this.mode,
    required this.onStageChanged,
    required this.onModeChanged,
    this.canLead = true,
    this.directorModeEnabled = false,
  });
  final CreatedTournament tournament;
  final int stageIndex;
  final Set<int> completedStages;
  final StageViewMode mode;
  final ValueChanged<int> onStageChanged;
  final ValueChanged<StageViewMode> onModeChanged;
  final bool canLead;
  final bool directorModeEnabled;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StageViewModeSwitch(
          selectedMode: mode,
          onModeChanged: onModeChanged,
          canLead: canLead,
          directorModeEnabled: directorModeEnabled,
        ),
        if (tournament.runStages.length > 1 && mode != StageViewMode.director)
          StageProgressBar(
            stages: tournament.runStages,
            activeStageIndex: stageIndex,
            completedStageIndexes: completedStages,
            onStageSelected: onStageChanged,
          ),
      ],
    ),
  );
}

class TournamentRunDetails extends StatelessWidget {
  const TournamentRunDetails({
    super.key,
    required this.tournament,
    required this.children,
  });
  final CreatedTournament tournament;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: SportSettingsSection(
      title: 'Turnierdetails',
      summary:
          '${tournament.players.length} Teilnehmer · ${tournament.boardCount} Boards · Uhr & Regeln',
      icon: Icons.info_outline,
      children: children,
    ),
  );
}
