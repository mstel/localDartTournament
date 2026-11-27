import 'package:dart_tournament_manager/features/tournaments/domain/engines/qualification_plan_engine.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _engine = QualificationPlanEngine();

void main() {
  group('QualificationPlanEngine', () {
    test('larger group priority keeps one remaining place as comparison', () {
      final plan = _engine.build(
        groupSizes: const [6, 5, 5],
        totalQualifiers: 8,
        autoAdjust: true,
        advancementPolicy: 'larger_group',
      );

      expect(plan.totalQualifiers, 8);
      expect(plan.fixedByGroup, [3, 2, 2]);
      expect(plan.extraRank, 3);
      expect(plan.extraCount, 1);
      expect(plan.extraGroups, [2, 3]);
      expect(plan.statusFor(1, 3), QualificationPlaceStatus.fixed);
      expect(plan.statusFor(2, 3), QualificationPlaceStatus.comparison);
      expect(plan.statusFor(3, 3), QualificationPlaceStatus.comparison);
    });

    test('cross-group comparison gives no bonus to the larger group', () {
      final plan = _engine.build(
        groupSizes: const [6, 5, 5],
        totalQualifiers: 8,
        autoAdjust: true,
        advancementPolicy: 'best_rank',
      );

      expect(plan.fixedByGroup, [2, 2, 2]);
      expect(plan.extraRank, 3);
      expect(plan.extraCount, 2);
      expect(plan.extraGroups, [1, 2, 3]);
      expect(plan.statusFor(1, 3), QualificationPlaceStatus.comparison);
      expect(plan.statusFor(2, 3), QualificationPlaceStatus.comparison);
      expect(plan.statusFor(3, 3), QualificationPlaceStatus.comparison);
    });

    test('equal groups disable larger-group advantage and auto-adjust cleanly', () {
      expect(QualificationPlanEngine.canUseLargerGroupPolicy(const [8, 8]), isFalse);
      expect(
        QualificationPlanEngine.automaticPolicyFor(
          groupSizes: const [8, 8],
          totalQualifiers: 6,
        ),
        'best_rank',
      );

      final plan = _engine.build(
        groupSizes: const [8, 8],
        totalQualifiers: 6,
        autoAdjust: true,
        advancementPolicy: 'larger_group',
      );

      expect(plan.fixedByGroup, [3, 3]);
      expect(plan.extraCount, 0);
      expect(QualificationPlanEngine.isDistributionClear(plan), isTrue);
    });

    test('7 qualifiers in two equal groups keeps comparison automatic', () {
      final plan = _engine.build(
        groupSizes: const [8, 8],
        totalQualifiers: 7,
        autoAdjust: true,
        advancementPolicy: 'larger_group',
      );

      expect(plan.fixedByGroup, [3, 3]);
      expect(plan.extraRank, 4);
      expect(plan.extraCount, 1);
      expect(plan.extraGroups, [1, 2]);
      expect(QualificationPlanEngine.isDistributionClear(plan), isFalse);
    });

    test('8 qualifiers in two equal groups of 8 need no comparison', () {
      final plan = _engine.build(
        groupSizes: const [8, 8],
        totalQualifiers: 8,
        autoAdjust: true,
        advancementPolicy: 'larger_group',
      );

      expect(plan.fixedByGroup, [4, 4]);
      expect(plan.extraCount, 0);
      expect(QualificationPlanEngine.isDistributionClear(plan), isTrue);
    });

    test('reducing qualifiers from 8 to 6 in two 8er groups yields 3/3', () {
      final plan = _engine.build(
        groupSizes: const [8, 8],
        totalQualifiers: 6,
        autoAdjust: true,
        advancementPolicy: 'larger_group',
      );

      expect(plan.fixedByGroup, [3, 3]);
      expect(plan.extraCount, 0);
      expect(QualificationPlanEngine.isDistributionClear(plan), isTrue);
      expect(
        QualificationPlanEngine.canUseBestRankPolicy(
          groupSizes: const [8, 8],
          totalQualifiers: 6,
        ),
        isFalse,
      );
    });

    test('8 qualifiers in two 8er groups yields 4/4 with no comparison', () {
      final plan = _engine.build(
        groupSizes: const [8, 8],
        totalQualifiers: 8,
        autoAdjust: true,
        advancementPolicy: 'automatic',
      );

      expect(plan.fixedByGroup, [4, 4]);
      expect(plan.extraCount, 0);
      expect(QualificationPlanEngine.isDistributionClear(plan), isTrue);
      expect(
        QualificationPlanEngine.canUseBestRankPolicy(
          groupSizes: const [8, 8],
          totalQualifiers: 8,
        ),
        isFalse,
      );
    });

    test('7 qualifiers in two 8er groups needs comparison (3+3+1)', () {
      final plan = _engine.build(
        groupSizes: const [8, 8],
        totalQualifiers: 7,
        autoAdjust: true,
        advancementPolicy: 'automatic',
      );

      expect(plan.fixedByGroup, [3, 3]);
      expect(plan.extraRank, 4);
      expect(plan.extraCount, 1);
      expect(plan.extraGroups, [1, 2]);
      expect(
        QualificationPlanEngine.canUseBestRankPolicy(
          groupSizes: const [8, 8],
          totalQualifiers: 7,
        ),
        isTrue,
      );
      expect(
        QualificationPlanEngine.recommendedAutomaticPolicy(
          groupSizes: const [8, 8],
          totalQualifiers: 7,
        ),
        'best_rank',
      );
    });

    test('8 qualifiers in three groups uses cross-group comparison', () {
      expect(
        QualificationPlanEngine.canUseBestRankPolicy(
          groupSizes: const [6, 6, 6],
          totalQualifiers: 8,
        ),
        isTrue,
      );
      final plan = _engine.build(
        groupSizes: const [6, 6, 6],
        totalQualifiers: 8,
        autoAdjust: true,
        advancementPolicy: 'automatic',
      );
      expect(plan.totalQualifiers, 8);
      expect(plan.fixedByGroup.fold<int>(0, (s, v) => s + v) + plan.extraCount, 8);
    });

    test('manual fixed third place consumes one comparison slot, not an extra slot', () {
      final plan = _engine.build(
        groupSizes: const [6, 5, 5],
        totalQualifiers: 8,
        autoAdjust: false,
        advancementPolicy: 'larger_group',
        fixedByGroup: const [2, 2, 2],
        manualExtraRank: 3,
        manualExtraCount: 2,
        selectedExtraGroups: const [1, 2, 3],
        placeStatuses: const {
          '1:3': QualificationPlaceStatus.fixed,
          '2:3': QualificationPlaceStatus.comparison,
          '3:3': QualificationPlaceStatus.comparison,
        },
      );

      expect(plan.extraGroups, [1, 2, 3]);
      expect(plan.extraCount, 2);
      expect(plan.lockedComparisonSlots, 1);
      expect(plan.statusFor(1, 3), QualificationPlaceStatus.fixed);
      expect(plan.statusFor(2, 3), QualificationPlaceStatus.comparison);
      expect(plan.statusFor(3, 3), QualificationPlaceStatus.comparison);
      expect(_engine.validationMessages(plan), isEmpty);
    });

    test('validation still rejects genuinely too many advancing players', () {
      final plan = _engine.build(
        groupSizes: const [6, 5, 5],
        totalQualifiers: 8,
        autoAdjust: false,
        advancementPolicy: 'larger_group',
        fixedByGroup: const [3, 2, 2],
        manualExtraRank: 3,
        manualExtraCount: 2,
        selectedExtraGroups: const [2, 3],
      );

      expect(
        _engine.validationMessages(plan),
        contains(
          'Es kommen 1 Teilnehmer zu viel weiter. Reduziere feste oder Vergleichs-Plätze.',
        ),
      );
    });

    test('place statuses survive tournament stage JSON round-trip', () {
      final stage = TournamentStage(
        name: 'Gruppenphase',
        type: 'groups',
        groupSizes: const [6, 5, 5],
        qualifiedParticipantCount: 8,
        qualifiersByGroup: const [2, 3],
        fixedQualifiersByGroup: const [3, 2, 2],
        extraQualifierRank: 3,
        extraQualifierCount: 1,
        qualificationPlaceStatuses: const {
          '1:3': 'fixed',
          '2:3': 'comparison',
          '3:3': 'comparison',
        },
      );

      final restored = TournamentStage.fromJson(stage.toJson());
      expect(restored.qualificationPlaceStatuses, stage.qualificationPlaceStatuses);

      final plan = _engine.build(
        groupSizes: restored.groupSizes,
        totalQualifiers: restored.qualifiedParticipantCount!,
        autoAdjust: restored.qualificationAutoAdjust,
        advancementPolicy: restored.qualificationAdvancementPolicy,
        fixedByGroup: restored.fixedQualifiersByGroup,
        manualExtraRank: restored.extraQualifierRank,
        manualExtraCount: restored.extraQualifierCount,
        selectedExtraGroups: restored.qualifiersByGroup,
        placeStatuses: parseQualificationPlaceStatuses(
          restored.qualificationPlaceStatuses,
        ),
      );
      expect(plan.fixedByGroup, [3, 2, 2]);
      expect(plan.extraGroups, [2, 3]);
      expect(plan.statusFor(2, 3), QualificationPlaceStatus.comparison);
    });

    test('legacy stages without place statuses are derived from old fields', () {
      final json = <String, dynamic>{
        'name': 'Gruppenphase',
        'type': 'groups',
        'groupSizes': [6, 5, 5],
        'qualifiedParticipantCount': 8,
        'qualifiersByGroup': [2, 3],
        'fixedQualifiersByGroup': [3, 2, 2],
        'extraQualifierRank': 3,
        'extraQualifierCount': 1,
      };

      final stage = TournamentStage.fromJson(json);
      expect(stage.qualificationPlaceStatuses['1:3'], 'fixed');
      expect(stage.qualificationPlaceStatuses['2:3'], 'comparison');
      expect(stage.qualificationPlaceStatuses['3:3'], 'comparison');
    });
  });
}
