import 'package:flutter/material.dart';

import '../domain/achievement_catalog.dart';
import '../domain/achievement_definition.dart';

class AchievementTargetDialog extends StatefulWidget {
  const AchievementTargetDialog({super.key, required this.targets});

  final Map<String, double> targets;

  @override
  State<AchievementTargetDialog> createState() =>
      _AchievementTargetDialogState();
}

class _AchievementTargetDialogState extends State<AchievementTargetDialog> {
  final _formKey = GlobalKey<FormState>();
  late final List<AchievementDefinition> _definitions;
  late final Map<String, TextEditingController> _controllers;

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
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
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
    Navigator.of(context).pop({
      for (final definition in _definitions)
        if (_value(_controllers[definition.id]!.text) != definition.target)
          definition.id: _value(_controllers[definition.id]!.text)!,
    });
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
      Navigator.of(context).pop(const <String, double>{});
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
                        ))
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
