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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await _storage.load();
      if (mounted) setState(() => _settings = settings);
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
        setState(() => _settings = previous);
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
        setState(() => _settings = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(type));
    }
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
              value: _settings.isEnabled(type),
              onChanged: _loading || _saving.contains(type)
                  ? null
                  : (enabled) => _setEnabled(type, enabled),
            ),
            if (_settings.isEnabled(type))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DropdownButtonFormField<int>(
                  initialValue: _settings.thresholdFor(type).clamp(1, 5),
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Schwelle für ${type.label}',
                    border: const OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1')),
                    DropdownMenuItem(value: 2, child: Text('2')),
                    DropdownMenuItem(value: 3, child: Text('3')),
                    DropdownMenuItem(value: 4, child: Text('4')),
                    DropdownMenuItem(value: 5, child: Text('5')),
                  ],
                  onChanged: _loading || _saving.contains(type)
                      ? null
                      : (value) {
                          if (value != null) _setThreshold(type, value);
                        },
                ),
              ),
          ],
        ),
    ],
  );
}
