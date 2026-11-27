import 'package:flutter/material.dart';

import '../../../domain/engines/qualification_plan_engine.dart';
import '../../../domain/tournament_models.dart';
import '../creation/stage_setup_widgets.dart';
import 'brackets/knockout_seeding_mode_label.dart';

/// Editierbarer Entwurf der Regeloptionen einer bereits laufenden Phase.
///
/// Die Presentations-Komponenten bleiben zustandslos; dieser Entwurf hält die
/// Textfelder und die abgeleiteten Qualifikationsdaten zusammen, damit die
/// Laufseite ihn unverändert speichern kann.
class RunningRulesDraft {
  RunningRulesDraft.fromStage(
    TournamentStage stage, {
    TournamentStage? knockoutStage,
    this.knockoutStageIndex = -1,
  }) : _qualifiedParticipantCount = TextEditingController(
         text: '${stage.qualifiedParticipantCount ?? 0}',
       ),
       _knockoutAdvancingCount = TextEditingController(
         text:
             (knockoutStage ?? stage).knockoutAdvancingCount?.toString() ?? '',
       ),
       playsKnockoutFully =
           (knockoutStage ?? stage).knockoutAdvancingCount == null,
       autoAdjust = stage.qualificationAutoAdjust,
       advancementPolicy = stage.qualificationAdvancementPolicy,
       qualifiersByGroup = List<int>.from(stage.qualifiersByGroup),
       fixedQualifiersByGroup = List<int>.from(stage.fixedQualifiersByGroup),
       extraQualifierRank = stage.extraQualifierRank,
       extraQualifierCount = stage.extraQualifierCount,
       qualificationPlaceStatuses = Map<String, String>.from(
         stage.qualificationPlaceStatuses,
       ),
       knockoutSeedingMode = (knockoutStage ?? stage).knockoutSeedingMode,
       placementPlaces = List<int>.from(
         (knockoutStage ?? stage).placementPlaces,
       );

  final int knockoutStageIndex;

  final TextEditingController _qualifiedParticipantCount;
  final TextEditingController _knockoutAdvancingCount;

  bool playsKnockoutFully;
  bool autoAdjust;
  String advancementPolicy;
  List<int> qualifiersByGroup;
  List<int> fixedQualifiersByGroup;
  int? extraQualifierRank;
  int? extraQualifierCount;
  Map<String, String> qualificationPlaceStatuses;
  String knockoutSeedingMode;
  List<int> placementPlaces;

  TextEditingController get qualifiedParticipantCount =>
      _qualifiedParticipantCount;
  TextEditingController get knockoutAdvancingCount => _knockoutAdvancingCount;

  int? get parsedQualifierCount =>
      int.tryParse(_qualifiedParticipantCount.text.trim());
  int? get parsedKnockoutAdvancingCount => playsKnockoutFully
      ? null
      : int.tryParse(_knockoutAdvancingCount.text.trim());

  void dispose() {
    _qualifiedParticipantCount.dispose();
    _knockoutAdvancingCount.dispose();
  }

  QualificationPlan? planFor(List<int> groupSizes) {
    final total = parsedQualifierCount;
    if (groupSizes.isEmpty || total == null || total < 1) return null;
    return const QualificationPlanEngine().build(
      groupSizes: groupSizes,
      totalQualifiers: total,
      autoAdjust: autoAdjust,
      advancementPolicy: advancementPolicy,
      fixedByGroup: fixedQualifiersByGroup.isEmpty
          ? null
          : fixedQualifiersByGroup,
      manualExtraRank: extraQualifierRank,
      manualExtraCount: extraQualifierCount,
      selectedExtraGroups: qualifiersByGroup,
      placeStatuses: parseQualificationPlaceStatuses(
        qualificationPlaceStatuses,
      ),
    );
  }

  /// Schreibt die aus der neuen Weiterkommenszahl abgeleitete Verteilung
  /// zurück in den Entwurf, damit „Weiterkommen im Detail“ nach dem
  /// Übernehmen nicht mehr die alte Aufteilung zeigt.
  void syncQualificationDistribution(List<int> groupSizes) {
    final plan = planFor(groupSizes);
    if (plan == null) return;
    fixedQualifiersByGroup = List<int>.from(plan.fixedByGroup);
    qualifiersByGroup = List<int>.from(plan.extraGroups);
    extraQualifierRank = plan.extraRank;
    extraQualifierCount = plan.extraCount;
    qualificationPlaceStatuses = Map<String, String>.from(
      plan.placeStatuses.map((key, value) => MapEntry(key, value.jsonValue)),
    );

  }

  void setQualifierCount(String value, List<int> groupSizes) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < 0) return;
    _qualifiedParticipantCount.text = '$parsed';
    fixedQualifiersByGroup = const [];
    qualifiersByGroup = const [];
    extraQualifierRank = null;
    extraQualifierCount = null;
    qualificationPlaceStatuses = const {};
    if (autoAdjust) {
      advancementPolicy = QualificationPlanEngine.recommendedAutomaticPolicy(
        groupSizes: groupSizes,
        totalQualifiers: parsed,
      );
    }
    syncQualificationDistribution(groupSizes);
  }

  void setKnockoutAdvancingCount(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < 0) return;
    _knockoutAdvancingCount.text = '$parsed';
  }

  void setPlaysKnockoutFully(bool enabled, int participants) {
    playsKnockoutFully = enabled;
    if (enabled) {
      _knockoutAdvancingCount.clear();
      return;
    }
    final suggested = participants >= 5 ? participants ~/ 2 : 4;
    final bounded = suggested < 4 ? 4 : suggested;
    _knockoutAdvancingCount.text =
        '${bounded >= participants ? participants - 1 : bounded}';
  }

  void setAutoAdjust(bool enabled, List<int> groupSizes) {
    final previous = planFor(groupSizes);
    autoAdjust = enabled;
    if (!enabled && previous != null) {
      fixedQualifiersByGroup = List<int>.from(previous.fixedByGroup);
      qualifiersByGroup = List<int>.from(previous.extraGroups);
      extraQualifierRank = previous.extraRank;
      extraQualifierCount = previous.extraCount;
      qualificationPlaceStatuses = Map<String, String>.from(
        previous.placeStatuses.map(
          (key, value) => MapEntry(key, value.jsonValue),
        ),
      );
    }
    if (enabled) {
      extraQualifierRank = null;
      extraQualifierCount = null;
      qualificationPlaceStatuses = const {};
      fixedQualifiersByGroup = const [];
      qualifiersByGroup = const [];
      advancementPolicy = QualificationPlanEngine.recommendedAutomaticPolicy(
        groupSizes: groupSizes,
        totalQualifiers:
            previous?.totalQualifiers ?? (parsedQualifierCount ?? 0),
      );
    }
    syncQualificationDistribution(groupSizes);
  }

  /// In auto mode: change policy but stay automatic. In manual mode: ignored.
  void setAdvancementPolicy(String value, List<int> groupSizes) {
    if (!autoAdjust) return;
    advancementPolicy = value;
    fixedQualifiersByGroup = const [];
    qualifiersByGroup = const [];
    extraQualifierRank = null;
    extraQualifierCount = null;
    qualificationPlaceStatuses = const {};
    syncQualificationDistribution(groupSizes);
  }

  /// True when user has made manual place/distribution edits (manual mode).
  bool get isManualMode => !autoAdjust;



  void setExtraGroup(
    int groupNumber,
    bool selected,
    List<int> currentGroups,
    QualificationPlan? plan,
    List<int> groupSizes,
  ) {
    autoAdjust = false;
    final groups = <int>{
      ...(qualifiersByGroup.isEmpty ? currentGroups : qualifiersByGroup),
    };
    if (selected) {
      groups.add(groupNumber);
    } else {
      groups.remove(groupNumber);
    }
    qualifiersByGroup = groups.toList()..sort();
    if (plan != null) {
      qualificationPlaceStatuses = {
        ...qualificationPlaceStatuses,
        qualificationPlaceKey(groupNumber, plan.extraRank): selected
            ? QualificationPlaceStatus.comparison.jsonValue
            : QualificationPlaceStatus.eliminated.jsonValue,
      };
    }
  }

  void cycleQualificationPlace(
    int groupNumber,
    int place,
    List<int> groupSizes,
  ) {
    autoAdjust = false;
    final plan = planFor(groupSizes);
    if (plan == null ||
        groupNumber < 1 ||
        groupNumber > groupSizes.length ||
        place < 1 ||
        place > groupSizes[groupNumber - 1]) {
      return;
    }
    final fixed = List<int>.from(plan.fixedByGroup);
    final groupIndex = groupNumber - 1;
    final status = plan.statusFor(groupNumber, place);
    final key = qualificationPlaceKey(groupNumber, place);
    switch (status) {
      case QualificationPlaceStatus.comparison:
        qualifiersByGroup = {...qualifiersByGroup, groupNumber}.toList()
          ..sort();
        qualificationPlaceStatuses = {
          ...qualificationPlaceStatuses,
          key: QualificationPlaceStatus.fixed.jsonValue,
        };
      case QualificationPlaceStatus.fixed:
        if (place <= fixed[groupIndex]) {
          fixed[groupIndex] = place - 1;
        }
        qualifiersByGroup = qualifiersByGroup
            .where((group) => group != groupNumber)
            .toList();
        qualificationPlaceStatuses = {
          ...qualificationPlaceStatuses,
          key: QualificationPlaceStatus.eliminated.jsonValue,
        };
      case QualificationPlaceStatus.eliminated:
        extraQualifierRank = place;
        qualifiersByGroup = {...qualifiersByGroup, groupNumber}.toList()
          ..sort();
        qualificationPlaceStatuses = {
          ...qualificationPlaceStatuses,
          key: QualificationPlaceStatus.comparison.jsonValue,
        };
    }
    fixedQualifiersByGroup = fixed;
    final updated = planFor(groupSizes);
    if (updated != null) {
      qualificationPlaceStatuses = Map<String, String>.from(
        updated.placeStatuses.map(
          (key, value) => MapEntry(key, value.jsonValue),
        ),
      );
    }
  }

  void togglePlacementPlace(int place) {
    placementPlaces =
        placementPlaces.contains(place)
              ? placementPlaces.where((value) => value != place).toList()
              : [...placementPlaces, place]
          ..sort();
  }

  bool hasChanges(TournamentStage stage, {TournamentStage? knockoutStage}) {
    final plan = planFor(stage.groupSizes);
    final messages = autoAdjust || plan == null
        ? const <String>[]
        : const QualificationPlanEngine().validationMessages(plan);
    final knockout = knockoutStage ?? stage;
    final samePlaces = _sameStrings(
      Map<String, String>.from(qualificationPlaceStatuses),
      Map<String, String>.from(stage.qualificationPlaceStatuses),
    );
    return parsedQualifierCount != stage.qualifiedParticipantCount ||
        autoAdjust != stage.qualificationAutoAdjust ||
        advancementPolicy != stage.qualificationAdvancementPolicy ||
        extraQualifierRank != stage.extraQualifierRank ||
        extraQualifierCount != stage.extraQualifierCount ||
        !_sameInts(qualifiersByGroup, stage.qualifiersByGroup) ||
        !_sameInts(fixedQualifiersByGroup, stage.fixedQualifiersByGroup) ||
        !samePlaces ||
        playsKnockoutFully != (knockout.knockoutAdvancingCount == null) ||
        parsedKnockoutAdvancingCount != knockout.knockoutAdvancingCount ||
        knockoutSeedingMode != knockout.knockoutSeedingMode ||
        !_sameInts(placementPlaces, knockout.placementPlaces) ||
        messages.isNotEmpty;
  }

  TournamentStage applyToKnockoutStage(TournamentStage stage) =>
      stage.withKnockoutRunningRules(
        advancingCount: parsedKnockoutAdvancingCount,
        seedingMode: knockoutSeedingMode,
        placementPlaces: List<int>.from(placementPlaces),
      );

  TournamentStage applyTo(TournamentStage stage) {
    if (stage.isGroupStage) {
      return stage.withRunningRules(
        qualifiedParticipantCount: parsedQualifierCount,
        qualificationAutoAdjust: autoAdjust,
        qualificationAdvancementPolicy: advancementPolicy,
        qualifiersByGroup: List<int>.from(qualifiersByGroup),
        fixedQualifiersByGroup: List<int>.from(fixedQualifiersByGroup),
        extraQualifierRank: extraQualifierRank,
        extraQualifierCount: extraQualifierCount,
        qualificationPlaceStatuses: Map<String, String>.from(
          qualificationPlaceStatuses,
        ),
        knockoutAdvancingCount: stage.knockoutAdvancingCount,
        knockoutSeedingMode: stage.knockoutSeedingMode,
        placementPlaces: List<int>.from(stage.placementPlaces),
      );
    }
    return stage.withRunningRules(
      qualifiedParticipantCount: stage.qualifiedParticipantCount,
      qualificationAutoAdjust: stage.qualificationAutoAdjust,
      qualificationAdvancementPolicy: stage.qualificationAdvancementPolicy,
      qualifiersByGroup: List<int>.from(stage.qualifiersByGroup),
      fixedQualifiersByGroup: List<int>.from(stage.fixedQualifiersByGroup),
      extraQualifierRank: stage.extraQualifierRank,
      extraQualifierCount: stage.extraQualifierCount,
      qualificationPlaceStatuses: Map<String, String>.from(
        stage.qualificationPlaceStatuses,
      ),
      knockoutAdvancingCount: parsedKnockoutAdvancingCount,
      knockoutSeedingMode: knockoutSeedingMode,
      placementPlaces: List<int>.from(placementPlaces),
    );
  }

  static bool _sameInts(List<int> left, List<int> right) =>
      left.length == right.length &&
      List.generate(
        left.length,
        (index) => index,
      ).every((index) => left[index] == right[index]);

  static bool _sameStrings(
    Map<String, String> left,
    Map<String, String> right,
  ) =>
      left.length == right.length &&
      left.entries.every((entry) => right[entry.key] == entry.value);
}

class RunningTournamentRulesPanel extends StatefulWidget {
  const RunningTournamentRulesPanel({
    super.key,
    required this.stage,
    required this.draft,
    required this.enabled,
    required this.saving,
    required this.onSave,
    required this.onChanged,
    this.followUpKnockoutStage,
    this.followUpKnockoutStageIndex = -1,
    this.disabledReason,
  });

  final TournamentStage stage;
  final RunningRulesDraft draft;
  final TournamentStage? followUpKnockoutStage;
  final int followUpKnockoutStageIndex;
  final bool enabled;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onChanged;
  final String? disabledReason;

  @override
  State<RunningTournamentRulesPanel> createState() =>
      _RunningTournamentRulesPanelState();
}

class _RunningTournamentRulesPanelState
    extends State<RunningTournamentRulesPanel> {
  static const _title = Text(
    'Weiterkommensregeln, Auslosungsmethode & Optionale Platzierungsspiele',
  );

  void _changed() {
    setState(widget.onChanged);
  }

  Widget _groupSection() {
    final groupSizes = widget.stage.groupSizes;
    final plan = widget.draft.planFor(groupSizes);
    final messages = widget.draft.autoAdjust || plan == null
        ? const <String>[]
        : const QualificationPlanEngine().validationMessages(plan);
    final manualMode = widget.draft.isManualMode;
    final canUseLargerGroup = QualificationPlanEngine.canUseLargerGroupPolicy(
      groupSizes,
    );
    final totalQualifiers = widget.draft.parsedQualifierCount ?? 0;
    final canUseBestRank = QualificationPlanEngine.canUseBestRankPolicy(
      groupSizes: groupSizes,
      totalQualifiers: totalQualifiers,
    );
    final effectiveAutoValue = widget.draft.advancementPolicy == 'automatic'
        ? QualificationPlanEngine.recommendedAutomaticPolicy(
            groupSizes: groupSizes,
            totalQualifiers: totalQualifiers,
          )
        : QualificationPlanEngine.resolveAutomaticDistributionPolicy(
            groupSizes: groupSizes,
            totalQualifiers: totalQualifiers,
            advancementPolicy: widget.draft.advancementPolicy,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Weiterkommende', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        TextField(
          key: const ValueKey('group-qualifier-count-field'),
          controller: widget.draft.qualifiedParticipantCount,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onChanged: (value) {
            widget.draft.setQualifierCount(value, groupSizes);
            _changed();
          },
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          key: const ValueKey('running-rules-qualification-details'),
          initiallyExpanded: false,
          title: const Text('Weiterkommen im Detail'),
          childrenPadding: const EdgeInsets.only(bottom: 12),
          children: [
            if (manualMode)
              DropdownButtonFormField<String>(
                key: const ValueKey('running-qualification-manual-mode'),
                initialValue: 'manual',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Weiterkommensregel',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'manual',
                    child: Text('Manuelle weiterkommensregelung'),
                  ),
                ],
                onChanged: null,
              )
            else
              DropdownButtonFormField<String>(
                key: const ValueKey('running-qualification-auto-mode'),
                initialValue: effectiveAutoValue,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Weiterkommensregel',
                  border: OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<String>(
                    value: 'larger_group',
                    enabled: canUseLargerGroup,
                    child: Text(
                      canUseLargerGroup
                          ? 'Größere Gruppe hat Vorrang'
                          : 'Größere Gruppe hat Vorrang (bei gleich großen Gruppen nicht nötig)',
                    ),
                  ),
                  DropdownMenuItem<String>(
                    value: 'best_rank',
                    enabled: canUseBestRank,
                    child: Text(
                      canUseBestRank
                          ? 'Beste X Plätze gruppenübergreifend vergleichen'
                          : 'Beste X Plätze gruppenübergreifend vergleichen (bei klarer Verteilung nicht nötig)',
                    ),
                  ),
                  const DropdownMenuItem<String>(
                    value: 'automatic',
                    child: Text('Automatisch'),
                  ),
                ],
                onChanged: widget.enabled
                    ? (value) {
                        if (value == null) return;
                        if (value == 'automatic') {
                          widget.draft.advancementPolicy = 'automatic';
                          widget.draft.syncQualificationDistribution(
                            groupSizes,
                          );
                        } else {
                          widget.draft.setAdvancementPolicy(value, groupSizes);
                        }
                        _changed();
                      }
                    : null,
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const ValueKey('running-auto-adjust-true'),
                  avatar: const Icon(Icons.auto_fix_high_outlined, size: 18),
                  label: const Text('Automatik'),
                  selected: !manualMode,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  onSelected: widget.enabled
                      ? (_) {
                          widget.draft.setAutoAdjust(true, groupSizes);
                          _changed();
                        }
                      : null,
                ),
                ChoiceChip(
                  key: const ValueKey('running-auto-adjust-false'),
                  avatar: const Icon(Icons.tune_outlined, size: 18),
                  label: const Text('Manuell'),
                  selected: manualMode,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  onSelected: widget.enabled
                      ? (_) {
                          if (!manualMode) {
                            widget.draft.setAutoAdjust(false, groupSizes);
                            _changed();
                          }
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            QualificationRuleSummary(qualificationPlan: plan),
            if (plan != null) ...[

            ],
            for (final message in messages) ...[
              const SizedBox(height: 8),
              QualificationErrorBanner(message: message),
            ],
            const SizedBox(height: 12),
            QualificationGroupPreview(
              groupSizes: groupSizes,
              qualificationPlan: plan,
              onCyclePlace: widget.enabled
                  ? (groupNumber, place) {
                      widget.draft.cycleQualificationPlace(
                        groupNumber,
                        place,
                        groupSizes,
                      );
                      _changed();
                    }
                  : (_, _) {},
            ),
            if (plan != null && plan.extraCount > 0) ...[
              const SizedBox(height: 12),
              Text(
                'Gruppen im Beste-${plan.extraCount}-Vergleich',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < groupSizes.length; index++)
                    FilterChip(
                      key: ValueKey('extra-group-chip-${index + 1}'),
                      label: Text(groupLabel(index + 1)),
                      selected: plan.extraGroups.contains(index + 1),
                      onSelected:
                          !widget.enabled || groupSizes[index] < plan.extraRank
                          ? null
                          : (selected) {
                              widget.draft.setExtraGroup(
                                index + 1,
                                selected,
                                plan.extraGroups,
                                plan,
                                groupSizes,
                              );
                              _changed();
                            },
                    ),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _knockoutSection({
    required TournamentStage stage,
    String? heading,
    int? participantCountOverride,
    bool allowPlayFully = true,
    bool hideAdvancingControls = false,
  }) {
    final participants =
        participantCountOverride ?? stage.knockoutParticipantCount ?? 0;
    final canPlayFully = allowPlayFully && participants >= 5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (heading != null) ...[
          Text(heading, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
        ],
        if (!hideAdvancingControls) ...[
          if (canPlayFully)
            SwitchListTile(
              key: const ValueKey('running-knockout-play-fully'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Turnierform vollständig ausspielen'),
              value: widget.draft.playsKnockoutFully,
              onChanged: widget.enabled
                  ? (value) {
                      widget.draft.setPlaysKnockoutFully(value, participants);
                      _changed();
                    }
                  : null,
            ),
          if ((!widget.draft.playsKnockoutFully || !canPlayFully) &&
              participants > 1) ...[
            Text('Weiterkommende', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            TextField(
              key: const ValueKey('knockout-advancing-count-field'),
              controller: widget.draft.knockoutAdvancingCount,
              enabled: widget.enabled,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                helperText: '4 bis ${participants - 1}',
              ),
              onChanged: (value) {
                widget.draft.setKnockoutAdvancingCount(value);
                _changed();
              },
            ),
          ],
        ],
        const SizedBox(height: 12),
        Text(
          'Auslosungsmethode',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          key: const ValueKey('running-knockout-seeding-mode'),
          initialValue: widget.draft.knockoutSeedingMode,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: [
            for (final mode in [
              'cross',
              'random_cross',
              'elo',
              'manual',
              'random',
            ])
              DropdownMenuItem(
                value: mode,
                child: Text(knockoutSeedingModeLabel(mode)),
              ),
          ],
          onChanged: widget.enabled
              ? (value) {
                  if (value != null) {
                    widget.draft.knockoutSeedingMode = value;
                    _changed();
                  }
                }
              : null,
        ),
        const SizedBox(height: 12),
        Text(
          'Optionale Platzierungsspiele',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (participants < 4)
          const Text('Ab 4 Teilnehmern verfügbar.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var place = 3; place < participants; place += 2)
                FilterChip(
                  key: ValueKey('running-placement-place-$place'),
                  label: Text('Platz $place'),
                  selected: widget.draft.placementPlaces.contains(place),
                  onSelected: widget.enabled
                      ? (_) {
                          widget.draft.togglePlacementPlace(place);
                          _changed();
                        }
                      : null,
                ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGroup = widget.stage.isGroupStage;
    final followUp = widget.followUpKnockoutStage;
    final hasChanges = widget.draft.hasChanges(
      widget.stage,
      knockoutStage: followUp,
    );
    return Card(
      key: const ValueKey('running-tournament-rules-panel'),
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const Icon(Icons.rule_outlined),
        title: _title,
        subtitle: Text(
          widget.enabled
              ? 'Regeln der Phase „${widget.stage.name}“ anpassen'
              : widget.disabledReason ??
                    'Diese Phase kann nicht mehr geändert werden.',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (isGroup) ...[
            _groupSection(),
            if (followUp != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              _knockoutSection(
                stage: followUp,
                heading: 'Folgephase: ${followUp.name}',
                participantCountOverride:
                    widget.draft.parsedQualifierCount ??
                    widget.stage.qualifiedParticipantCount ??
                    followUp.knockoutParticipantCount ??
                    0,
                allowPlayFully: false,
                hideAdvancingControls: true,
              ),
            ],
          ] else
            _knockoutSection(stage: widget.stage, allowPlayFully: false),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const ValueKey('running-rules-save'),
              onPressed: widget.enabled && hasChanges && !widget.saving
                  ? widget.onSave
                  : null,
              icon: widget.saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Übernehmen'),
            ),
          ),
        ],
      ),
    );
  }
}
