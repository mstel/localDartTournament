import 'package:flutter/material.dart';

import '../../tournaments/application/player_insight_preferences.dart';
import '../../tournaments/domain/player_insight.dart';

class PlayerInsightDefaultsPanel extends StatefulWidget {
  const PlayerInsightDefaultsPanel({super.key});

  @override
  State<PlayerInsightDefaultsPanel> createState() =>
      _PlayerInsightDefaultsPanelState();
}

class _PlayerInsightDefaultsPanelState
    extends State<PlayerInsightDefaultsPanel> {
  final _storage = PlayerInsightPreferencesStorage();
  var _settings = PlayerInsightPreferences.defaults();
  var _loading = true;
  final Set<PlayerInsightType> _saving = {};
  late final _thresholdControllers = {
    for (final type in PlayerInsightType.values)
      if (type.hasThreshold)
        type: TextEditingController(
          text: '${PlayerInsightPreferences.defaultThreshold(type)}',
        ),
  };
  final _thresholdForms = {
    for (final type in PlayerInsightType.values)
      if (type.hasThreshold) type: GlobalKey<FormState>(),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await _storage.load();
      if (mounted) {
        setState(() {
          _settings = settings;
          for (final entry in _thresholdControllers.entries) {
            entry.value.text = '${settings.thresholdFor(entry.key)}';
          }
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Insights-Standardwerte konnten nicht geladen werden: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setEnabled(PlayerInsightType type, bool enabled) async {
    final previous = _settings;
    final updated = previous.withEnabled(type, enabled);
    setState(() {
      _settings = updated;
      _saving.add(type);
    });
    try {
      await _storage.save(updated);
    } catch (error) {
      if (mounted) {
        setState(() {
          _settings = previous;
          _thresholdControllers[type]?.text =
              '${previous.thresholdFor(type)}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(type));
    }
  }

  Future<void> _setThreshold(PlayerInsightType type, int value) async {
    final previous = _settings;
    final updated = previous.withThreshold(type, value);
    setState(() {
      _settings = updated;
      _saving.add(type);
    });
    try {
      await _storage.save(updated);
    } catch (error) {
      if (mounted) {
        setState(() {
          _settings = previous;
          _thresholdControllers[type]?.text =
              '${previous.thresholdFor(type)}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(type));
    }
  }

  Future<void> _saveThreshold(PlayerInsightType type) async {
    final form = _thresholdForms[type]?.currentState;
    if (form == null || !form.validate()) return;
    final value = int.parse(_thresholdControllers[type]!.text.trim());
    await _setThreshold(type, value);
  }

  String? _validateThreshold(PlayerInsightType type, String? text) {
    final value = int.tryParse(text?.trim() ?? '');
    if (value == null ||
        value < type.minimumThreshold ||
        value > type.maximumThreshold) {
      return 'Zahl von ${type.minimumThreshold} bis ${type.maximumThreshold} eingeben.';
    }
    return null;
  }

  @override
  void dispose() {
    for (final controller in _thresholdControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    leading: const Icon(Icons.auto_awesome_outlined),
    title: const Text('Insights Standardwerte'),
    subtitle: const Text(
      'Legt fest, welche Spieler-Insights standardmäßig angezeigt werden.',
    ),
    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    children: [
      if (_loading) const LinearProgressIndicator(),
      for (final type in PlayerInsightType.values)
        Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(type.label),
              subtitle: Text(
                type.conditionDescription(_settings.thresholdFor(type)),
              ),
              value: _settings.isEnabled(type),
              onChanged: _loading || _saving.contains(type)
                  ? null
                  : (enabled) => _setEnabled(type, enabled),
            ),
            if (_settings.isEnabled(type) && type.hasThreshold)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Form(
                  key: _thresholdForms[type],
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final fieldWidth = constraints.maxWidth > 420
                          ? constraints.maxWidth - 64
                          : constraints.maxWidth;
                      return Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: fieldWidth,
                            child: TextFormField(
                              key: ValueKey('insight-threshold-${type.name}'),
                              controller: _thresholdControllers[type],
                              enabled: !_loading && !_saving.contains(type),
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: false,
                                signed: false,
                              ),
                              decoration: InputDecoration(
                                labelText: type.thresholdLabel,
                                suffixText: type.thresholdUnit,
                                border: const OutlineInputBorder(),
                              ),
                              validator: (value) =>
                                  _validateThreshold(type, value),
                              onFieldSubmitted: _loading ||
                                      _saving.contains(type)
                                  ? null
                                  : (_) => _saveThreshold(type),
                            ),
                          ),
                          IconButton(
                            key: ValueKey('save-insight-${type.name}'),
                            tooltip: 'Schwelle für ${type.label} speichern',
                            constraints: const BoxConstraints.tightFor(
                              width: 48,
                              height: 48,
                            ),
                            onPressed: _loading || _saving.contains(type)
                                ? null
                                : () => _saveThreshold(type),
                            icon: const Icon(Icons.save_outlined),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
    ],
  );
}
