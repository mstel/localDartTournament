import 'dart:math';

import '../tournament_models.dart';

/// Zentrale, testbare Berechnung der Qualifikationsregeln.
///
/// [fixedByGroup] enthält nur feste Plätze außerhalb des Vergleichsrangs.
/// Ein auf dem Vergleichsrang fixierter Platz gehört dagegen zu [extraCount]
/// und wird über [placeStatuses] als [QualificationPlaceStatus.fixed] markiert.
class QualificationPlanEngine {
  const QualificationPlanEngine();

  QualificationPlan build({
    required List<int> groupSizes,
    required int totalQualifiers,
    required bool autoAdjust,
    required String advancementPolicy,
    List<int>? fixedByGroup,
    int? manualExtraRank,
    int? manualExtraCount,
    List<int>? selectedExtraGroups,
    Map<String, QualificationPlaceStatus>? placeStatuses,
  }) {
    final groupCount = groupSizes.length;
    final maximumQualifiers = groupSizes.fold<int>(
      0,
      (sum, size) => sum + max(0, size),
    );
    final cappedTotal = min(max(0, totalQualifiers), maximumQualifiers);
    if (groupCount == 0) {
      return QualificationPlan(
        totalQualifiers: 0,
        fixedPerGroup: 0,
        extraCount: 0,
        extraRank: 1,
        eligibleGroupSize: null,
        extraGroups: const [],
        fixedByGroup: const [],
      );
    }

    final baseFixedPerGroup = cappedTotal ~/ groupCount;
    final baseFixed = [
      for (final size in groupSizes) min(baseFixedPerGroup, max(0, size)),
    ];
    final resolvedPolicy = resolveAdvancementPolicy(
      groupSizes: groupSizes,
      advancementPolicy: advancementPolicy,
    );

    if (autoAdjust) {
      final fixed = resolvedPolicy == 'larger_group'
          ? _allocateLargerGroupBonus(
              groupSizes: groupSizes,
              baseFixed: baseFixed,
              totalQualifiers: cappedTotal,
            )
          : List<int>.from(baseFixed);
      var remaining =
          cappedTotal - fixed.fold<int>(0, (sum, value) => sum + value);
      remaining = _reduceExtraSlotsWhenNecessary(
        groupSizes: groupSizes,
        fixed: fixed,
        remaining: remaining,
        baseFixedPerGroup: baseFixedPerGroup,
      );
      final extraRank = _effectiveExtraRank(
        groupSizes: groupSizes,
        fixed: fixed,
        baseFixedPerGroup: baseFixedPerGroup,
        neededSlots: remaining,
      );
      final derivedGroups = _eligibleGroups(
        groupSizes: groupSizes,
        fixed: fixed,
        extraRank: extraRank,
      );
      final extraGroups = _applyExplicitExtraGroups(
        groupSizes: groupSizes,
        fixed: fixed,
        extraRank: extraRank,
        derivedGroups: derivedGroups,
        explicit: placeStatuses,
      );
      final extraCount = min(remaining, extraGroups.length);
      final statuses = _statusesFor(
        groupSizes: groupSizes,
        fixed: fixed,
        extraRank: extraRank,
        extraGroups: extraGroups,
        explicit: placeStatuses,
      );
      final eligibleGroupSize = extraGroups.isEmpty
          ? null
          : extraGroups
              .map((groupNumber) => groupSizes[groupNumber - 1])
              .reduce(max);

      return QualificationPlan(
        totalQualifiers: cappedTotal,
        fixedPerGroup: baseFixedPerGroup,
        extraCount: extraCount,
        extraRank: extraRank,
        eligibleGroupSize: eligibleGroupSize,
        extraGroups: extraGroups,
        fixedByGroup: fixed,
        placeStatuses: statuses,
      );
    }

    final manualFixed = fixedByGroup == null || fixedByGroup.length != groupCount
        ? List<int>.from(baseFixed)
        : [
            for (var index = 0; index < groupCount; index++)
              min(max(0, fixedByGroup[index]), max(0, groupSizes[index])),
          ];
    final extraRank = manualExtraRank ?? (baseFixedPerGroup + 1);
    final remaining =
        cappedTotal - manualFixed.fold<int>(0, (sum, value) => sum + value);
    final extraCount = min(
      max(0, manualExtraCount ?? remaining),
      groupCount,
    );
    final selected = selectedExtraGroups?.toSet() ?? <int>{};
    final extraGroups = <int>[];
    for (var groupNumber = 1; groupNumber <= groupCount; groupNumber++) {
      final explicit =
          placeStatuses?[qualificationPlaceKey(groupNumber, extraRank)];
      final isCandidate = explicit == QualificationPlaceStatus.fixed ||
          explicit == QualificationPlaceStatus.comparison ||
          (explicit == null && selected.contains(groupNumber));
      if (isCandidate &&
          groupSizes[groupNumber - 1] >= extraRank &&
          manualFixed[groupNumber - 1] < extraRank) {
        extraGroups.add(groupNumber);
      }
    }
    final statuses = _statusesFor(
      groupSizes: groupSizes,
      fixed: manualFixed,
      extraRank: extraRank,
      extraGroups: extraGroups,
      explicit: placeStatuses,
    );
    final eligibleGroupSize = extraGroups.isEmpty
        ? null
        : extraGroups
            .map((groupNumber) => groupSizes[groupNumber - 1])
            .reduce(max);

    return QualificationPlan(
      totalQualifiers: cappedTotal,
      fixedPerGroup: baseFixedPerGroup,
      extraCount: extraCount,
      extraRank: extraRank,
      eligibleGroupSize: eligibleGroupSize,
      extraGroups: extraGroups,
      fixedByGroup: manualFixed,
      placeStatuses: statuses,
    );
  }

  List<String> validationMessages(QualificationPlan plan) {
    final fixedTotal = plan.fixedByGroup.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    final advancingCount = fixedTotal + plan.extraCount;
    if (fixedTotal > plan.totalQualifiers) {
      return [
        'Es sind ${fixedTotal - plan.totalQualifiers} feste Plätze zu viel markiert.',
      ];
    }
    if (plan.extraGroups.length < plan.extraCount) {
      return [
        'Es fehlen ${plan.extraCount - plan.extraGroups.length} Gruppen für den Beste-${plan.extraCount}-Vergleich.',
      ];
    }
    if (plan.lockedComparisonSlots > plan.extraCount) {
      return [
        'Es sind ${plan.lockedComparisonSlots - plan.extraCount} fixierte Vergleichsplätze zu viel markiert. Reduziere "Beste-N Weiter" oder entferne einen fixierten Vergleichsplatz.',
      ];
    }
    if (advancingCount == plan.totalQualifiers) return const [];
    if (advancingCount < plan.totalQualifiers) {
      return [
        'Es kommen noch ${plan.totalQualifiers - advancingCount} Teilnehmer zu wenig weiter. Erhöhe "Beste-N Weiter" oder markiere feste Plätze.',
      ];
    }
    return [
      'Es kommen ${advancingCount - plan.totalQualifiers} Teilnehmer zu viel weiter. Reduziere "Beste-N Weiter" oder feste Plätze.',
    ];
  }

  static bool hasEqualGroupSizes(List<int> groupSizes) {
    final nonEmpty = groupSizes.where((size) => size > 0).toList();
    return nonEmpty.isEmpty || nonEmpty.toSet().length == 1;
  }

  static String resolveAdvancementPolicy({
    required List<int> groupSizes,
    required String advancementPolicy,
  }) {
    if (hasEqualGroupSizes(groupSizes)) return 'best_rank';
    return advancementPolicy == 'best_rank' ? 'best_rank' : 'larger_group';
  }

  static bool canUseLargerGroupPolicy(List<int> groupSizes) =>
      !hasEqualGroupSizes(groupSizes);

  static bool isDistributionClear(QualificationPlan plan) {
    if (plan.totalQualifiers <= 0) return true;
    if (plan.extraCount <= 0) return true;
    return plan.extraCount == plan.extraGroups.length &&
        plan.lockedComparisonSlots == 0;
  }

  static String automaticPolicyFor({
    required List<int> groupSizes,
    required int totalQualifiers,
  }) {
    if (groupSizes.isEmpty) return 'best_rank';
    final groupCount = groupSizes.length;
    final cappedTotal = min(
      max(0, totalQualifiers),
      groupSizes.fold<int>(0, (sum, size) => sum + max(0, size)),
    );
    final baseFixedPerGroup = cappedTotal ~/ groupCount;
    final baseFixed = [
      for (final size in groupSizes) min(baseFixedPerGroup, max(0, size)),
    ];
    final remaining =
        cappedTotal - baseFixed.fold<int>(0, (sum, value) => sum + value);
    if (remaining <= 0) return 'best_rank';
    if (hasEqualGroupSizes(groupSizes)) return 'best_rank';
    final largerFixed = _allocateLargerGroupBonusStatic(
      groupSizes: groupSizes,
      baseFixed: baseFixed,
      totalQualifiers: cappedTotal,
    );
    final largerRemaining =
        cappedTotal - largerFixed.fold<int>(0, (sum, value) => sum + value);
    final largerRank = _effectiveExtraRankStatic(
      groupSizes: groupSizes,
      fixed: largerFixed,
      baseFixedPerGroup: baseFixedPerGroup,
      neededSlots: largerRemaining,
    );
    final largerEligible = _eligibleGroupsStatic(
      groupSizes: groupSizes,
      fixed: largerFixed,
      extraRank: largerRank,
    );
    if (largerRemaining > 0 && largerRemaining == largerEligible.length) {
      return 'best_rank';
    }
    return 'larger_group';
  }

  static List<int> _allocateLargerGroupBonusStatic({
    required List<int> groupSizes,
    required List<int> baseFixed,
    required int totalQualifiers,
  }) {
    const engine = QualificationPlanEngine();
    return engine._allocateLargerGroupBonus(
      groupSizes: groupSizes,
      baseFixed: baseFixed,
      totalQualifiers: totalQualifiers,
    );
  }

  static int _effectiveExtraRankStatic({
    required List<int> groupSizes,
    required List<int> fixed,
    required int baseFixedPerGroup,
    required int neededSlots,
  }) {
    const engine = QualificationPlanEngine();
    return engine._effectiveExtraRank(
      groupSizes: groupSizes,
      fixed: fixed,
      baseFixedPerGroup: baseFixedPerGroup,
      neededSlots: neededSlots,
    );
  }

  static List<int> _eligibleGroupsStatic({
    required List<int> groupSizes,
    required List<int> fixed,
    required int extraRank,
  }) {
    const engine = QualificationPlanEngine();
    return engine._eligibleGroups(
      groupSizes: groupSizes,
      fixed: fixed,
      extraRank: extraRank,
    );
  }

  /// Größere Gruppen erhalten vorrang einen festen Platz. Kann eine
  /// Größenstufe nicht vollständig bedient werden, bleibt der Restplatz als
  /// Vergleich zwischen den nächstbestehenden Gruppen erhalten.
  List<int> _allocateLargerGroupBonus({
    required List<int> groupSizes,
    required List<int> baseFixed,
    required int totalQualifiers,
  }) {
    final fixed = List<int>.from(baseFixed);
    var remaining =
        totalQualifiers - fixed.fold<int>(0, (sum, value) => sum + value);
    if (remaining <= 0) return fixed;

    final indexes = List<int>.generate(groupSizes.length, (index) => index)
      ..sort((a, b) {
        final sizeCompare = groupSizes[b].compareTo(groupSizes[a]);
        return sizeCompare != 0 ? sizeCompare : a.compareTo(b);
      });
    var cursor = 0;
    while (cursor < indexes.length && remaining > 0) {
      final tierSize = groupSizes[indexes[cursor]];
      final tier = <int>[];
      while (cursor < indexes.length &&
          groupSizes[indexes[cursor]] == tierSize) {
        tier.add(indexes[cursor]);
        cursor++;
      }
      if (tier.length > remaining ||
          tier.any((index) => fixed[index] >= groupSizes[index])) {
        continue;
      }
      for (final index in tier) {
        fixed[index]++;
      }
      remaining -= tier.length;
    }
    return fixed;
  }

  /// Ein Restplatz muss durch mindestens eine Vergleichsgruppe abgedeckt sein.
  /// Falls nicht, wandert er so lange in einen festen Platz der größten
  /// Gruppe, bis die Vergleichsgruppen wieder ausreichen.
  int _reduceExtraSlotsWhenNecessary({
    required List<int> groupSizes,
    required List<int> fixed,
    required int remaining,
    required int baseFixedPerGroup,
  }) {
    var result = remaining;
    for (var iteration = 0;
        iteration < groupSizes.length * groupSizes.length + 8 && result > 0;
        iteration++) {
      final rank = _effectiveExtraRank(
        groupSizes: groupSizes,
        fixed: fixed,
        baseFixedPerGroup: baseFixedPerGroup,
        neededSlots: result,
      );
      final eligible = _eligibleGroups(
        groupSizes: groupSizes,
        fixed: fixed,
        extraRank: rank,
      );
      if (result <= eligible.length) break;
      final candidates = List<int>.generate(groupSizes.length, (index) => index)
        ..removeWhere((index) => fixed[index] >= groupSizes[index])
        ..sort((a, b) {
          final sizeCompare = groupSizes[b].compareTo(groupSizes[a]);
          return sizeCompare != 0 ? sizeCompare : a.compareTo(b);
        });
      if (candidates.isEmpty) break;
      fixed[candidates.first]++;
      result--;
    }
    return result;
  }

  /// Der Vergleichsrang beginnt bei einem Platz über der Grundqualifikation.
  /// Reichen die Gruppen auf diesem Rang nicht aus, rutscht er nach unten in
  /// der Tabelle weiter, bis genug Vergleichskandidaten vorhanden sind.
  int _effectiveExtraRank({
    required List<int> groupSizes,
    required List<int> fixed,
    required int baseFixedPerGroup,
    required int neededSlots,
  }) {
    final maximumRank = groupSizes.isEmpty
        ? 1
        : groupSizes.reduce(max) + 1;
    for (var rank = max(1, baseFixedPerGroup + 1);
        rank <= maximumRank;
        rank++) {
      if (_eligibleGroups(
            groupSizes: groupSizes,
            fixed: fixed,
            extraRank: rank,
          ).length >=
          neededSlots) {
        return rank;
      }
    }
    return maximumRank;
  }

  List<int> _eligibleGroups({
    required List<int> groupSizes,
    required List<int> fixed,
    required int extraRank,
  }) {
    return [
      for (var index = 0; index < groupSizes.length; index++)
        if (groupSizes[index] >= extraRank && fixed[index] < extraRank)
          index + 1,
    ];
  }

  List<int> _applyExplicitExtraGroups({
    required List<int> groupSizes,
    required List<int> fixed,
    required int extraRank,
    required List<int> derivedGroups,
    Map<String, QualificationPlaceStatus>? explicit,
  }) {
    if (explicit == null || explicit.isEmpty) return derivedGroups;
    final groups = <int>{};
    for (final groupNumber in derivedGroups) {
      final index = groupNumber - 1;
      final key = qualificationPlaceKey(groupNumber, extraRank);
      final status = explicit[key] ?? QualificationPlaceStatus.comparison;
      if (groupSizes[index] >= extraRank &&
          fixed[index] < extraRank &&
          status != QualificationPlaceStatus.eliminated) {
        groups.add(groupNumber);
      }
    }
    return groups.toList()..sort();
  }

  Map<String, QualificationPlaceStatus> _statusesFor({
    required List<int> groupSizes,
    required List<int> fixed,
    required int extraRank,
    required List<int> extraGroups,
    Map<String, QualificationPlaceStatus>? explicit,
  }) {
    final result = <String, QualificationPlaceStatus>{};
    for (var groupIndex = 0; groupIndex < groupSizes.length; groupIndex++) {
      final groupNumber = groupIndex + 1;
      final fixedForGroup = fixed[groupIndex];
      for (var place = 1; place <= groupSizes[groupIndex]; place++) {
        final key = qualificationPlaceKey(groupNumber, place);
        final status = place <= fixedForGroup
            ? QualificationPlaceStatus.fixed
            : explicit?[key] ??
                (place == extraRank && extraGroups.contains(groupNumber)
                    ? QualificationPlaceStatus.comparison
                    : QualificationPlaceStatus.eliminated);
        result[key] = status;
      }
    }
    return Map.unmodifiable(result);
  }
}
