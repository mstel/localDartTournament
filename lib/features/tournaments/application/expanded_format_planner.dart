import '../../../shared/utils/background_worker.dart';
import 'dart:math';
import '../domain/tournament_models.dart';
import '../domain/tournament_format_planner.dart';
import '../domain/tournament_planning_parameters.dart';
import '../domain/planning_format_progression.dart';
import 'configuration_duration_estimator.dart';

/// Bounded beam search over production stage configurations. Each structural
/// stage is simulated once; changing its format only scales its time blocks.
class ExpandedFormatPlanner {
  const ExpandedFormatPlanner({
    this.parameters = const TournamentPlanningParameters(),
  });
  final TournamentPlanningParameters parameters;

  Future<List<TournamentFormatSuggestion>> suggest(
    TournamentPlanningRequest request, {
    bool allResults = false,
    void Function(void Function())? onCancel,
  }) async {
    final worker =
        BackgroundWorker<
          (TournamentPlanningParameters, TournamentPlanningRequest, bool),
          List<TournamentFormatSuggestion>
        >(_planInBackground);
    onCancel?.call(worker.close);
    try {
      return await worker.run((parameters, request, allResults));
    } finally {
      worker.close();
    }
  }

  Future<List<TournamentFormatSuggestion>> _suggest(
    TournamentPlanningRequest request, {
    bool allResults = false,
  }) async {
    if (request.players < 2 ||
        request.boards < 1 ||
        request.maximumStages < 1 ||
        request.maximumStages > 4 ||
        request.maximumLives < 2 ||
        request.maximumLives > 10 ||
        (request.targetMinutes != null && request.targetMinutes! <= 0)) {
      return [];
    }
    final cap = request.maximumGroups ?? parameters.maximumGroups;
    if (cap < 1 || cap > 64) return [];
    final planner = TournamentFormatPlanner(parameters: parameters);
    final cache = <String, ConfigurationEstimate?>{};
    final finalists = <TournamentFormatSuggestion>[];
    var frontier = <List<TournamentStage>>[[]];
    final options = [
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
            if ((sets == 1 || legs >= 3) &&
                (!request.lockLegsFormat || legs == request.bestOfLegs) &&
                (request.lockLegsFormat ||
                    request.bestOfLegs <= 1 ||
                    legs >= (request.bestOfLegs >= 3 ? 3 : 1)))
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
    ConfigurationEstimate? estimate(TournamentStage stage) => cache.putIfAbsent(
      '${stage.type}:${stage.knockoutParticipantCount}:${stage.groupSizes}:${stage.groupPlayType}:${stage.groupMaxGamesPerPlayer}:${stage.qualifiedParticipantCount}:${stage.knockoutLives}:${stage.groupRoundRobinRepeats}:${stage.fixedQualifiersByGroup}',
      () => const ConfigurationDurationEstimator().preview(
        [stage],
        request.boards,
        parameters,
        finalQualifiers: stage.qualifiedParticipantCount,
      ),
    );
    double penalty(TournamentFormatSuggestion s) {
      final missing = max(
        0,
        request.minimumMatchesPerPlayer - s.minimumMatchesPerPlayer,
      );
      if (request.targetMinutes != null) {
        return missing * parameters.missingMatchPenalty +
            (s.estimatedMinutes - request.targetMinutes!).abs().toDouble();
      }
      return missing * parameters.missingMatchPenalty +
          (max(0, request.minimumMinutes - s.estimatedMinutes) +
                  max(0, s.estimatedMinutes - request.maximumMinutes)) *
              parameters.timeWindowPenalty +
          (s.estimatedMinutes - request.maximumMinutes).abs() *
              parameters.targetDurationPenalty.toDouble();
    }

    TournamentFormatSuggestion? evaluate(List<TournamentStage> stages) {
      final estimates = stages.map(estimate).toList();
      if (estimates.any((e) => e == null)) return null;
      TournamentFormatSuggestion? best;
      // Equal distances, one longer final stage, or one step per stage.
      for (final base in options) {
        for (var progression = 0; progression < 5; progression++) {
          if (request.lockLegsFormat && progression > 0) continue;
          if (progression == 3 &&
              (!request.allowSets ||
                  base.bestOfSets >= 5 ||
                  base.bestOfLegs.isEven)) {
            continue;
          }
          if (progression == 4 &&
              (request.x01Selection != 'variable_301_501' ||
                  base.x01Score != 301)) {
            continue;
          }
          final formats = <TournamentGameFormat>[];
          var valid = true;
          for (var i = 0; i < stages.length; i++) {
            var legs =
                base.bestOfLegs +
                (progression == 2
                    ? 2 * i
                    : progression == 1 && i == stages.length - 1 && i > 0
                    ? 2
                    : 0);
            if (legs > 101) {
              valid = false;
              break;
            }
            final elimination =
                stages[i].type != 'groups' ||
                !['round_robin', 'swiss'].contains(stages[i].groupPlayType);
            if (legs.isEven && elimination) legs++;
            final format = TournamentGameFormat(
              x01Score: progression == 4 && i > 0 && i == stages.length - 1
                  ? 501
                  : base.x01Score,
              bestOfLegs: legs,
              bestOfSets: progression == 3 && i > 0 && i == stages.length - 1
                  ? base.bestOfSets + 2
                  : base.bestOfSets,
              checkoutType: base.checkoutType,
              doubleIn: base.doubleIn,
            );
            if (formats.isNotEmpty &&
                (!isPlanningFormatProgressionAllowed(formats.last, format) ||
                    planner.estimatedMatchMinutes(format) <
                        planner.estimatedMatchMinutes(formats.last))) {
              valid = false;
              break;
            }
            formats.add(format);
          }
          if (!valid) continue;
          var minutes = 0.0;
          var hasScheduledStage = false;
          for (var i = 0; i < stages.length; i++) {
            final sample = estimates[i]!;
            if (sample.totalMatches > 0 && hasScheduledStage) {
              minutes += parameters.boardIdleMinutes;
            }
            minutes +=
                (sample.minutes - sample.waitMinutes) /
                    planner.estimatedMatchMinutes(stages[i].gameFormat) *
                    planner.estimatedMatchMinutes(formats[i]) +
                sample.waitMinutes;
            hasScheduledStage = hasScheduledStage || sample.totalMatches > 0;
          }
          final configs = [
            for (var i = 0; i < stages.length; i++)
              TournamentStage.fromJson({
                ...stages[i].toJson(),
                'gameFormat': formats[i].toJson(),
              }),
          ];
          final count = estimates.fold<int>(
            0,
            (sum, e) => sum + e!.totalMatches,
          );
          final minimum = estimates.first!.minimumMatches;
          final duration = (minutes - 1e-9).ceil();
          final fits =
              minimum >= request.minimumMatchesPerPlayer &&
              (request.targetMinutes != null ||
                  (duration >= request.minimumMinutes &&
                      duration <= request.maximumMinutes));
          final suggestion = TournamentFormatSuggestion(
            title: stages.map((s) => s.name).join(' → '),
            stages: [
              for (var i = 0; i < stages.length; i++)
                PlannedStage(
                  type: stages[i].type,
                  groupCount: stages[i].groupCount ?? 0,
                  format: formats[i],
                ),
            ],
            configurations: configs,
            stageMatchCounts: [for (final e in estimates) e!.totalMatches],
            minimumMatchesPerPlayer: minimum,
            totalMatches: count,
            variableMatches: estimates.any((e) => e!.variableMatches),
            estimatedMinutes: duration,
            effectiveBoards: estimates
                .map((e) {
                  final blocks = <int, int>{};
                  for (final end in e!.matchEndSeconds) {
                    blocks[end] = (blocks[end] ?? 0) + 1;
                  }
                  return blocks.values.fold<int>(0, max);
                })
                .fold<int>(0, max),
            participantCount: request.players,
            boardCount: request.boards,
            isClosestAlternative: !fits,
          );
          if (best == null ||
              (best.isClosestAlternative && !suggestion.isClosestAlternative) ||
              (best.isClosestAlternative == suggestion.isClosestAlternative &&
                  penalty(suggestion) < penalty(best))) {
            best = suggestion;
          }
        }
      }
      return best;
    }

    for (var depth = 0; depth < request.maximumStages; depth++) {
      final next = <(List<TournamentStage>, double)>[];
      for (final prefix in frontier) {
        final count = prefix.isEmpty
            ? request.players
            : prefix.last.qualifiedParticipantCount!;
        for (final stage in _stages(
          count,
          cap,
          request.maximumLives,
          prefix.isEmpty ? request.manualQualifiers : null,
        )) {
          final mode = stage.type == 'groups'
              ? (stage.groupRoundRobinRepeats.isNotEmpty &&
                        stage.groupRoundRobinRepeats.first == 2)
                    ? 'groups:double_round_robin'
                    : 'groups:${stage.groupMaxGamesPerPlayer.any((limit) => limit != null) ? 'limited_round_robin' : stage.groupPlayType}'
              : stage.type;
          final terminal = stage.qualifiedParticipantCount == 1;
          final isPreferredFinal =
              terminal &&
              request.preferredFinalStage != null &&
              ((request.preferredFinalStage == mode) ||
                  (request.preferredFinalStage == 'single_knockout' &&
                      stage.type == 'single_knockout') ||
                  (request.preferredFinalStage == 'double_knockout' &&
                      stage.type == 'double_knockout') ||
                  (request.preferredFinalStage == 'triple_knockout' &&
                      stage.type == 'triple_knockout') ||
                  (request.preferredFinalStage == 'kratzer' &&
                      stage.type == 'kratzer') ||
                  (request.preferredFinalStage == 'groups:round_robin' &&
                      mode == 'groups:round_robin') ||
                  (request.preferredFinalStage == 'groups:double_round_robin' &&
                      mode == 'groups:double_round_robin'));
          if (request.enabledModes != null &&
              !request.enabledModes!.contains(mode) &&
              !isPreferredFinal) {
            continue;
          }
          final path = [...prefix, stage];
          if (!terminal && depth == request.maximumStages - 1) continue;
          if (terminal &&
              request.requireGroupPhase &&
              !path.any((s) => s.type == 'groups')) {
            continue;
          }
          if (terminal &&
              request.preferredFinalStage != null &&
              !isPreferredFinal) {
            continue;
          }
          final result = evaluate(path);
          if (result == null) continue;
          if (terminal) {
            finalists.add(result);
          } else {
            next.add((path, penalty(result)));
          }
        }
        // Keep the dialog responsive while the production runtime is sampled.
        await Future<void>.delayed(Duration.zero);
      }
      next.sort((a, b) => a.$2.compareTo(b.$2));
      frontier = next.take(48).map((e) => e.$1).toList();
    }
    final fitting = finalists.where((s) => !s.isClosestAlternative).toList();
    final ranked = fitting.isEmpty ? finalists : fitting;
    ranked.sort((a, b) {
      if (request.targetMinutes != null) {
        final distance = (a.estimatedMinutes - request.targetMinutes!)
            .abs()
            .compareTo((b.estimatedMinutes - request.targetMinutes!).abs());
        if (distance != 0) return distance;
      }
      final score = penalty(a).compareTo(penalty(b));
      return score != 0 ? score : a.stages.length.compareTo(b.stages.length);
    });
    return allResults
        ? ranked
        : ranked.take(parameters.maximumSuggestions).toList();
  }

  Iterable<TournamentStage> _stages(
    int n,
    int maxGroups,
    int maxLives, [
    int? manualQualifiers,
  ]) sync* {
    var bracket = 1;
    while (bracket < n) {
      bracket *= 2;
    }
    final targets = {
      1,
      if (manualQualifiers != null &&
          manualQualifiers < n &&
          manualQualifiers >= 1)
        manualQualifiers
      else if (n >= 4)
        n ~/ 2,
    };
    for (final type in [
      'single_knockout',
      'double_knockout',
      'triple_knockout',
      'kratzer',
    ]) {
      for (final lives
          in type == 'kratzer'
              ? [for (var l = 2; l <= maxLives; l++) l]
              : [
                  type == 'single_knockout'
                      ? 1
                      : type == 'double_knockout'
                      ? 2
                      : 3,
                ]) {
        for (final target in targets) {
          yield TournamentStage(
            name: type == 'single_knockout'
                ? 'Einfaches KO'
                : type == 'double_knockout'
                ? 'Doppel-KO'
                : type == 'triple_knockout'
                ? 'Triple-KO'
                : 'Kratzer ($lives Leben)',
            type: type,
            knockoutParticipantCount: n,
            knockoutBracketSize: bracket,
            knockoutByeCount: bracket - n,
            knockoutLives: lives,
            finalEndsTournament: type != 'kratzer',
            qualifiedParticipantCount: target,
            gameFormat: const TournamentGameFormat(bestOfLegs: 1),
          );
        }
      }
    }
    for (var groups = 1; groups <= min(maxGroups, n ~/ 3); groups++) {
      final sizes = [
        for (var i = 0; i < groups; i++) n ~/ groups + (i < n % groups ? 1 : 0),
      ];
      for (final play in [
        'round_robin',
        'double_round_robin',
        if (sizes.any((size) => size > 6)) 'limited_round_robin',
        'swiss',
        'mini_knockout',
        'double_knockout',
        'triple_knockout',
      ]) {
        final List<(int, List<int>)> qualifierPlans;
        if (manualQualifiers != null) {
          if (manualQualifiers >= n || manualQualifiers < 1) {
            qualifierPlans = const [];
          } else {
            final fixed = List.generate(
              groups,
              (i) =>
                  manualQualifiers ~/ groups +
                  (i < manualQualifiers % groups ? 1 : 0),
            );
            if (fixed.first < sizes.last && fixed.last >= 1) {
              qualifierPlans = [(manualQualifiers, fixed)];
            } else {
              qualifierPlans = const [];
            }
          }
        } else {
          final qualifierOptions = <int>{
            if (groups == 1) 1,
            min(parameters.qualifiersPerGroup, sizes.last - 1),
            if (groups > 1 && sizes.last >= 4)
              min(sizes.last ~/ 2, sizes.last - 1),
          };
          qualifierPlans = [
            for (final perGroup in qualifierOptions)
              if (perGroup < sizes.last &&
                  groups * perGroup < n &&
                  groups * perGroup >= 1)
                (groups * perGroup, List.filled(groups, perGroup)),
          ];
        }
        for (final plan in qualifierPlans) {
          final target = plan.$1;
          final fixedQualifiers = plan.$2;
          final label = play == 'double_round_robin'
              ? 'Jeder gegen jeden (zweimal)'
              : play == 'limited_round_robin'
              ? 'maximal 5 Spiele pro Spieler'
              : play == 'swiss'
              ? 'Schweizer System'
              : play == 'round_robin'
              ? 'Jeder gegen jeden'
              : play == 'mini_knockout'
              ? 'Mini-KO'
              : play == 'double_knockout'
              ? 'Mini-Doppel-KO'
              : 'Mini-Triple-KO';
          final sizeDesc = sizes.first == sizes.last
              ? '${sizes.first}'
              : '${sizes.last}–${sizes.first}';
          final groupDesc = groups == 1
              ? '1 Gruppe à $sizeDesc Spieler'
              : '$groups Gruppen à $sizeDesc Spieler';
          final isRoundRobinVariant =
              play == 'limited_round_robin' || play == 'double_round_robin';
          yield TournamentStage(
            name: '$groupDesc ($label)',
            type: 'groups',
            groupCount: groups,
            groupSizes: sizes,
            groupPlayType: isRoundRobinVariant ? 'round_robin' : play,
            groupPlayTypes: List.filled(
              groups,
              isRoundRobinVariant ? 'round_robin' : play,
            ),
            groupMaxGamesPerPlayer: play == 'limited_round_robin'
                ? List.filled(groups, 5)
                : const [],
            groupRoundRobinRepeats: List.filled(
              groups,
              play == 'swiss'
                  ? min(sizes.last - 1, (log(sizes.last) / log(2)).ceil())
                  : play == 'double_round_robin'
                  ? 2
                  : 1,
            ),
            fixedQualifiersByGroup: fixedQualifiers,
            qualifiedParticipantCount: target,
            finalEndsTournament: true,
            gameFormat: const TournamentGameFormat(bestOfLegs: 1),
          );
        }
      }
    }
  }
}

Future<List<TournamentFormatSuggestion>> _planInBackground(
  (TournamentPlanningParameters, TournamentPlanningRequest, bool) input,
) => ExpandedFormatPlanner(
  parameters: input.$1,
)._suggest(input.$2, allResults: input.$3);
