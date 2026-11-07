import 'package:flutter/material.dart';

import '../domain/achievement_catalog.dart';
import '../domain/achievement_definition.dart';

class AchievementTargetValues {
  const AchievementTargetValues({
    required this.primary,
    required this.parameters,
    required this.alternative,
  });

  final Map<String, double> primary;
  final Map<String, double> parameters;
  final Map<String, double> alternative;
}

class AchievementTargetDialog extends StatefulWidget {
  const AchievementTargetDialog({
    super.key,
    required this.targets,
    this.parameters = const {},
    this.alternativeTargets = const {},
  });

  final Map<String, double> targets;
  final Map<String, double> parameters;
  final Map<String, double> alternativeTargets;

  @override
  State<AchievementTargetDialog> createState() =>
      _AchievementTargetDialogState();
}

class _AchievementTargetDialogState extends State<AchievementTargetDialog> {
  final _formKey = GlobalKey<FormState>();
  late final List<AchievementDefinition> _definitions;
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, TextEditingController> _alternativeControllers;
  late final Map<String, TextEditingController> _parameterControllers;

  @override
  void initState() {
    super.initState();
    _definitions = AchievementCatalog.definitions
        .where((definition) => !definition.isCategoryCompletion)
        .toList();
    _controllers = {
      for (final definition in _definitions)
        definition.id: TextEditingController(
          text: _format(widget.targets[definition.id] ?? definition.target),
        ),
    };
    _alternativeControllers = {
      for (final definition in _definitions)
        if (definition.alternativeTarget != null)
          definition.id: TextEditingController(
            text: _format(
              widget.alternativeTargets[definition.id] ??
                  definition.alternativeTarget!,
            ),
          ),
    };
    _parameterControllers = {
      for (final definition in _definitions)
        if (definition.parameterTarget != null)
          definition.id: TextEditingController(
            text: _format(
              widget.parameters[definition.id] ?? definition.parameterTarget!,
            ),
          ),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final controller in _alternativeControllers.values) {
      controller.dispose();
    }
    for (final controller in _parameterControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _format(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  double? _value(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      AchievementTargetValues(
        primary: {
          for (final definition in _definitions)
            if (_value(_controllers[definition.id]!.text) != definition.target)
              definition.id: _value(_controllers[definition.id]!.text)!,
        },
        parameters: {
          for (final definition in _definitions)
            if (definition.parameterTarget != null &&
                _value(_parameterControllers[definition.id]!.text) !=
                    definition.parameterTarget)
              definition.id: _value(
                _parameterControllers[definition.id]!.text,
              )!,
        },
        alternative: {
          for (final definition in _definitions)
            if (definition.alternativeTarget != null &&
                _value(_alternativeControllers[definition.id]!.text) !=
                    definition.alternativeTarget)
              definition.id: _value(
                _alternativeControllers[definition.id]!.text,
              )!,
        },
      ),
    );
  }

  Future<void> _restoreDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Standardwerte wiederherstellen?'),
        content: const Text(
          'Alle angepassten Achievement-Zielwerte dieser Rangliste werden auf die Standardwerte zurückgesetzt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Wiederherstellen'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(
        const AchievementTargetValues(
          primary: {},
          parameters: {},
          alternative: {},
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: const Text('Achievement-Werte anpassen'),
      content: SizedBox(
        width: size.width > 700 ? 620 : size.width - 80,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: size.height * 0.68),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Die Änderungen gelten nur für diese Rangliste und werden '
                    'mit den Ranglisteneinstellungen gespeichert.',
                  ),
                  for (final category in AchievementCategory.values)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(category.label),
                      children: [
                        for (final definition in _definitions.where(
                          (item) => item.category == category,
                        )) ...[
                          if (definition.parameterTarget == null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TextFormField(
                                key: ValueKey(
                                  'achievement-target-${definition.id}',
                                ),
                                controller: _controllers[definition.id],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: definition.name,
                                  helperText: definition
                                      .copyWith(
                                        target:
                                            _value(
                                              _controllers[definition.id]!.text,
                                            ) ??
                                            (widget.targets[definition.id] ??
                                                definition.target),
                                      )
                                      .description,
                                  border: const OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() {}),
                                validator: (text) {
                                  final value = _value(text ?? '');
                                  return value == null ||
                                          !value.isFinite ||
                                          value <= 0
                                      ? 'Bitte einen Wert größer als 0 eingeben.'
                                      : null;
                                },
                              ),
                            ),
                          if (definition.parameterTarget != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TextFormField(
                                key: ValueKey(
                                  'achievement-parameter-${definition.id}',
                                ),
                                controller:
                                    _parameterControllers[definition.id],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: definition.parameterLabel,
                                  helperText: definition
                                      .copyWith(
                                        parameterTarget:
                                            _value(
                                              _parameterControllers[definition
                                                      .id]!
                                                  .text,
                                            ) ??
                                            (widget.parameters[definition.id] ??
                                                definition.parameterTarget),
                                      )
                                      .description,
                                  border: const OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() {}),
                                validator: (text) {
                                  final value = _value(text ?? '');
                                  return value == null ||
                                          !value.isFinite ||
                                          value <= 0
                                      ? 'Bitte einen Wert größer als 0 eingeben.'
                                      : null;
                                },
                              ),
                            ),
                          if (definition.alternativeTarget != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TextFormField(
                                key: ValueKey(
                                  'achievement-alternative-target-${definition.id}',
                                ),
                                controller:
                                    _alternativeControllers[definition.id],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: '${definition.name} · Alternative',
                                  helperText: definition.alternativeDescription,
                                  border: const OutlineInputBorder(),
                                ),
                                onChanged: (_) => setState(() {}),
                                validator: (text) {
                                  final value = _value(text ?? '');
                                  return value == null ||
                                          !value.isFinite ||
                                          value <= 0
                                      ? 'Bitte einen Wert größer als 0 eingeben.'
                                      : null;
                                },
                              ),
                            ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _restoreDefaults,
          child: const Text('Standard wiederherstellen'),
        ),
        FilledButton(onPressed: _save, child: const Text('Speichern')),
      ],
    );
  }
}
