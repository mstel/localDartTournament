import '../application/tournament_duration_range.dart';
import 'group_size_rules.dart';
import 'dart:math';
import 'planning_duration.dart';
import 'planning_format_progression.dart';

import 'tournament_models.dart';
import 'planning_match_breakdown.dart';
import 'tournament_planning_parameters.dart';

class TournamentPlanningRequest {
  static const modeLabels = <String, String>{
    'single_knockout': 'Einfaches KO',
    'double_knockout': 'Doppel-KO (Verlierer-Runde)',
    'triple_knockout': 'Triple-KO (zwei Verlierer-Chancen)',
    'kratzer': 'Kratzer (Leben-System)',
    'groups:round_robin': 'Gruppen: Jeder gegen jeden (einmal)',
    'groups:double_round_robin': 'Gruppen: Jeder gegen jeden (zweimal)',
    'groups:limited_round_robin':
        'Gruppen: Rundenformat mit max. 5 Begegnungen pro Spieler',
    'groups:swiss': 'Schweizer System',
    'groups:mini_knockout': 'Gruppen: Mini-KO',
    'groups:double_knockout': 'Gruppen: Mini-Doppel-KO',
    'groups:triple_knockout': 'Gruppen: Mini-Triple-KO',
  };
  const TournamentPlanningRequest({
    required this.players,
    required this.boards,
    required this.minimumMatchesPerPlayer,
    required this.minimumMinutes,
    required this.maximumMinutes,
    required this.x01Selection,
    required this.checkoutType,
    this.maximumGroups,
    this.requireGroupPhase = false,
    this.bestOfLegs = 3,
    this.allowSets = false,
    this.allowDraws = false,
    this.targetMinutes,
    this.maximumStages = 3,
    this.maximumLives = 5,
    this.enabledModes,
    this.preferredFinalStage,
    this.lockLegsFormat = false,
    this.manualQualifiers,
    this.considerBestWorstCase = false,
  });

  final int players;
  final int boards;
  final int bestOfLegs;
  final bool lockLegsFormat;
  final int? manualQualifiers;
  final bool considerBestWorstCase;
  final bool allowSets;
  final bool allowDraws;
  final bool requireGroupPhase;
  final int maximumStages;
  final int maximumLives;

  /// Null enables all modes; an empty set deliberately allows no suggestions.
  final Set<String>? enabledModes;
  final String? preferredFinalStage;

  /// Null uses the saved planner setting; a value overrides it for this search.
  final int? maximumGroups;
  final int minimumMatchesPerPlayer;
  final int minimumMinutes;
  final int maximumMinutes;

  /// If present, replaces the time window with nearest-duration ranking.
  final int? targetMinutes;

  /// A numeric score as a string, or `variable_301_501`.
  final String x01Selection;
  final String checkoutType;
}

class TournamentFormatSuggestion {
  const TournamentFormatSuggestion({
    required this.title,
    required this.stages,
    required this.minimumMatchesPerPlayer,
    required this.totalMatches,
    required this.estimatedMinutes,
    required this.effectiveBoards,
    required this.participantCount,
    this.isClosestAlternative = false,
    this.qualifiersPerGroup = 2,
    this.duration,
    this.boardCount = 1,
    this.configurations = const [],
    this.stageMatchCounts = const [],
    this.variableMatches = false,
  });

  final String title;
  final List<PlannedStage> stages;
  final int minimumMatchesPerPlayer;
  final int totalMatches;
  final int estimatedMinutes;
  final int effectiveBoards;
  final int participantCount;
  final bool isClosestAlternative;
  final int qualifiersPerGroup;
  final PlanningDuration? duration;
  final int boardCount;
  final List<TournamentStage> configurations;
  final List<int> stageMatchCounts;
  final bool variableMatches;
  TournamentGameFormat get format => stages.first.format;
  ({int minimumMinutes, int maximumMinutes}) get durationSpan =>
      TournamentDurationRange.forEstimate(
        estimatedMinutes: estimatedMinutes,
        matches: configurations.isNotEmpty
            ? [
                for (var i = 0; i < configurations.length; i++)
                  (
                    bestOfLegs: configurations[i].gameFormat.bestOfLegs,
                    matchCount: i < stageMatchCounts.length
                        ? stageMatchCounts[i]
                        : 1,
                  ),
              ]
            : [
                for (final stage in stages)
                  (bestOfLegs: stage.format.bestOfLegs, matchCount: 1),
              ],
      );

  PlanningMatchBreakdown get matchBreakdown {
    final groups = stages.first.groupCount;
    return PlanningMatchBreakdown(
      groupSizes: List.generate(
        groups,
        (index) =>
            participantCount ~/ groups +
            (index < participantCount % groups ? 1 : 0),
      ),
      qualifiersPerGroup: qualifiersPerGroup,
      directKnockoutParticipants: groups == 0 ? participantCount : null,
    );
  }
}

class PlannedStage {
  const PlannedStage({
    required this.type,
    required this.groupCount,
    required this.format,
  });
  final String type;
  final int groupCount;
  final TournamentGameFormat format;
  String get label => type == 'groups'
      ? '$groupCount Gruppen (Jeder gegen jeden)'
      : 'K.-o.-Finalrunde';
}

/// Estimates dependencies per round. This prevents unrealistically counting
/// four boards for a 3-player group or a later knockout round.
class TournamentFormatPlanner {
  const TournamentFormatPlanner({
    this.parameters = const TournamentPlanningParameters(),
  });
  final TournamentPlanningParameters parameters;

  /// Formats are searched independently for each stage. Board scheduling is
  /// computed once per layout; only the duration of its blocks varies.
  List<TournamentFormatSuggestion> suggestFormats(
    TournamentPlanningRequest request,
  ) => _suggest(request, automatic: true);

  List<TournamentFormatSuggestion> suggest(TournamentPlanningRequest request) =>
      _suggest(request, automatic: false);

  List<TournamentFormatSuggestion> _suggest(
    TournamentPlanningRequest request, {
    required bool automatic,
  }) {
    if ((request.targetMinutes != null && request.targetMinutes! <= 0) ||
        request.players < 2 ||
        request.boards < 1 ||
        request.bestOfLegs < 1 ||
        (request.bestOfLegs.isEven && !request.allowDraws)) {
      return const [];
    }
    final limit = request.maximumGroups ?? parameters.maximumGroups;
    if (!PlanningParameter.maximumGroups.accepts(limit)) return const [];
    final candidates = <TournamentFormatSuggestion>[];
    final options = <TournamentGameFormat>[
      for (final score
          in request.x01Selection == 'variable_301_501'
              ? [301, 501]
              : [int.parse(request.x01Selection)])
        for (final sets in request.allowSets ? [1, 3, 5] : [1])
          for (final legs in [
            ...TournamentGameFormat.supportedBestOfLegs,
            if (request.allowDraws && sets == 1)
              ...TournamentGameFormat.supportedDrawLegs,
          ])
            if (sets == 1 || legs >= 3)
              TournamentGameFormat(
                x01Score: score,
                bestOfLegs: legs,
                bestOfSets: sets,
                checkoutType: request.checkoutType == 'double_in_out'
                    ? 'double_out'
                    : request.checkoutType,
                doubleIn: request.checkoutType == 'double_in_out',
              ),
    ];
    for (
      var groups = 1;
      groups <= min(request.players ~/ minimumPlayersPerGroup, limit);
      groups++
    ) {
      final sizes = _balancedSizes(request.players, groups);
      final minimumGames = sizes.map((size) => size - 1).reduce(min);
      final effectiveBoards = min(
        request.boards,
        sizes.fold<int>(0, (total, size) => total + size ~/ 2),
      );
      final breakdown = PlanningMatchBreakdown(
        groupSizes: sizes,
        qualifiersPerGroup: parameters.qualifiersPerGroup,
      );
      final qualifiers = groups == 1
          ? 0
          : sizes.fold<int>(
              0,
              (sum, size) => sum + min(parameters.qualifiersPerGroup, size),
            );
      final slots = PlanningDuration.calculate(
        groupSizes: sizes,
        qualifiers: qualifiers,
        boards: request.boards,
        matchMinutes: 1,
      );
      final formats = automatic
          ? options
          : [_formatFor(request, sizes, qualifiers)];
      final finalFormats = !automatic && formats.single.allowsDraws
          ? [
              TournamentGameFormat(
                x01Score: formats.single.x01Score,
                bestOfLegs: formats.single.bestOfLegs + 1,
                checkoutType: formats.single.checkoutType,
                doubleIn: formats.single.doubleIn,
              ),
            ]
          : formats;
      for (final groupFormat in formats) {
        for (final finalFormat
            in qualifiers > 1 ? finalFormats : [groupFormat]) {
          if (qualifiers > 1 && finalFormat.allowsDraws) continue;
          if (!isPlanningFormatProgressionAllowed(groupFormat, finalFormat)) {
            continue;
          }
          final groupMatchMinutes = _matchMinutes(groupFormat);
          final finalMatchMinutes = _matchMinutes(finalFormat);
          // Later stages may be longer, while keeping early matches affordable.
          if (automatic && finalMatchMinutes < groupMatchMinutes) continue;
          final duration = PlanningDuration(
            groupSlots: slots.groupSlots,
            knockoutSlots: slots.knockoutSlots,
            matchMinutes: groupMatchMinutes,
            knockoutMatchMinutes: finalMatchMinutes,
            boardIdleMinutes: parameters.boardIdleMinutes,
          );
          final fits =
              minimumGames >= request.minimumMatchesPerPlayer &&
              (request.targetMinutes != null ||
                  (duration.totalMinutes >= request.minimumMinutes &&
                      duration.totalMinutes <= request.maximumMinutes));
          candidates.add(
            TournamentFormatSuggestion(
              title: (() {
                // Build descriptive title with group size range and mode label
                final sizeDesc = sizes.first == sizes.last
                    ? '${sizes.first}'
                    : '${sizes.last}–${sizes.first}';
                final groupDesc = groups == 1
                    ? '1 Gruppe à $sizeDesc Spieler'
                    : '$groups Gruppen à $sizeDesc Spieler';
                // Determine mode key for lookup (double round robin or regular)
                final modeKey = 'groups:round_robin';
                final modeLabel =
                    TournamentPlanningRequest.modeLabels[modeKey] ?? '';
                return '$groupDesc ($modeLabel)';
              })(),
              stages: [
                PlannedStage(
                  type: 'groups',
                  groupCount: groups,
                  format: groupFormat,
                ),
                if (qualifiers > 1)
                  PlannedStage(
                    type: 'single_knockout',
                    groupCount: 0,
                    format: finalFormat,
                  ),
              ],
              minimumMatchesPerPlayer: minimumGames,
              totalMatches: breakdown.total,
              estimatedMinutes: duration.totalMinutes,
              duration: duration,
              effectiveBoards: effectiveBoards,
              boardCount: request.boards,
              participantCount: request.players,
              qualifiersPerGroup: parameters.qualifiersPerGroup,
              isClosestAlternative: !fits,
            ),
          );
        }
      }
    }
    if (!request.requireGroupPhase) {
      final formats = automatic
          ? options
          : [_formatFor(request, const [], request.players)];
      for (final format in formats.where((f) => !f.allowsDraws)) {
        final duration = PlanningDuration.calculate(
          groupSizes: const [],
          qualifiers: request.players,
          boards: request.boards,
          matchMinutes: _matchMinutes(format),
          boardIdleMinutes: parameters.boardIdleMinutes,
        );
        final fits =
            request.minimumMatchesPerPlayer <= 1 &&
            (request.targetMinutes != null ||
                (duration.totalMinutes >= request.minimumMinutes &&
                    duration.totalMinutes <= request.maximumMinutes));
        candidates.add(
          TournamentFormatSuggestion(
            title: 'Einfaches K.-o.',
            stages: [
              PlannedStage(
                type: 'single_knockout',
                groupCount: 0,
                format: format,
              ),
            ],
            minimumMatchesPerPlayer: 1,
            totalMatches: request.players - 1,
            estimatedMinutes: duration.totalMinutes,
            duration: duration,
            effectiveBoards: min(request.boards, request.players ~/ 2),
            boardCount: request.boards,
            participantCount: request.players,
            isClosestAlternative: !fits,
          ),
        );
      }
    }
    final fitting = candidates.where((c) => _fits(c, request)).toList();
    final ranked = fitting.isEmpty ? candidates : fitting;
    ranked.sort((a, b) {
      if (request.targetMinutes case final target?) {
        final distance = (a.estimatedMinutes - target).abs().compareTo(
          (b.estimatedMinutes - target).abs(),
        );
        if (distance != 0) return distance;
      }
      final penalty = _penalty(a, request).compareTo(_penalty(b, request));
      if (penalty != 0) return penalty;
      final groups = a.stages.first.groupCount.compareTo(
        b.stages.first.groupCount,
      );
      if (groups != 0) return groups;
      final length = _matchMinutes(b.format).compareTo(_matchMinutes(a.format));
      if (length != 0) return length;
      // Prefer the simpler leg-only format when the time estimate is identical.
      return a.format.bestOfSets.compareTo(b.format.bestOfSets);
    });
    return ranked.take(parameters.maximumSuggestions).toList();
  }

  double _matchMinutes(TournamentGameFormat format) =>
      _legMinutes(format) * PlanningDuration.estimatedMatchLegs(format);

  double estimatedMatchMinutes(TournamentGameFormat format) =>
      _matchMinutes(format);

  bool _fits(
    TournamentFormatSuggestion suggestion,
    TournamentPlanningRequest request,
  ) =>
      suggestion.minimumMatchesPerPlayer >= request.minimumMatchesPerPlayer &&
      (request.targetMinutes != null ||
          (suggestion.estimatedMinutes >= request.minimumMinutes &&
              suggestion.estimatedMinutes <= request.maximumMinutes));

  int _penalty(
    TournamentFormatSuggestion suggestion,
    TournamentPlanningRequest request,
  ) {
    final missingGames = max(
      0,
      request.minimumMatchesPerPlayer - suggestion.minimumMatchesPerPlayer,
    );
    if (request.targetMinutes != null) {
      return missingGames * parameters.missingMatchPenalty;
    }
    final tooShort = max(
      0,
      request.minimumMinutes - suggestion.estimatedMinutes,
    );
    final tooLong = max(
      0,
      suggestion.estimatedMinutes - request.maximumMinutes,
    );
    return missingGames * parameters.missingMatchPenalty +
        (tooShort + tooLong) * parameters.timeWindowPenalty +
        (suggestion.estimatedMinutes - request.maximumMinutes).abs() *
            parameters.targetDurationPenalty;
  }

  TournamentGameFormat _formatFor(
    TournamentPlanningRequest request,
    List<int> sizes,
    int qualifiers,
  ) {
    if (request.x01Selection != 'variable_301_501') {
      return TournamentGameFormat(
        x01Score: int.parse(request.x01Selection),
        bestOfLegs: request.bestOfLegs,
        checkoutType: request.checkoutType == 'double_in_out'
            ? 'double_out'
            : request.checkoutType,
        doubleIn: request.checkoutType == 'double_in_out',
      );
    }
    final format501 = TournamentGameFormat(
      x01Score: 501,
      bestOfLegs: request.bestOfLegs,
      checkoutType: request.checkoutType == 'double_in_out'
          ? 'double_out'
          : request.checkoutType,
      doubleIn: request.checkoutType == 'double_in_out',
    );
    final estimated501 = PlanningDuration.calculate(
      groupSizes: sizes,
      qualifiers: qualifiers,
      boards: request.boards,
      matchMinutes:
          _legMinutes(format501) *
          PlanningDuration.estimatedLegs(format501.bestOfLegs),
      boardIdleMinutes: parameters.boardIdleMinutes,
    ).totalMinutes;
    return estimated501 > (request.targetMinutes ?? request.maximumMinutes)
        ? TournamentGameFormat(
            x01Score: 301,
            bestOfLegs: request.bestOfLegs,
            checkoutType: format501.checkoutType,
            doubleIn: format501.doubleIn,
          )
        : format501;
  }

  int _legMinutes(TournamentGameFormat format) {
    if (format.x01Score == 301 && format.checkoutType == 'double_out') {
      return parameters.minutes301DoubleOut;
    }
    if (format.x01Score == 501 && format.checkoutType == 'double_out') {
      return parameters.minutes501DoubleOut;
    }
    if (format.x01Score == 301 && format.checkoutType == 'single_out') {
      return parameters.minutes301SingleOut;
    }
    if (format.x01Score == 501 && format.checkoutType == 'single_out') {
      return parameters.minutes501SingleOut;
    }
    return format.checkoutType == 'single_out'
        ? parameters.fallbackSingleOutMinutes
        : parameters.fallbackOtherMinutes;
  }

  List<int> _balancedSizes(int players, int groups) => List.generate(
    groups,
    (index) => players ~/ groups + (index < players % groups ? 1 : 0),
  );
}
