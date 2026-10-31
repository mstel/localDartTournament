import 'package:flutter/material.dart';

import '../../../shared/widgets/adaptive_content.dart';
import '../../tournaments/application/tournament_flow_priority_preferences.dart';
import '../../tournaments/domain/tournament_flow_priority_settings.dart';

class PriorityNoticeSettingsPanel extends StatefulWidget {
  const PriorityNoticeSettingsPanel({super.key});

  @override
  State<PriorityNoticeSettingsPanel> createState() =>
      _PriorityNoticeSettingsPanelState();
}

class _PriorityNoticeSettingsPanelState
    extends State<PriorityNoticeSettingsPanel> {
  final _preferences = TournamentFlowPriorityPreferences();
  final _form = GlobalKey<FormState>();
  final _playerThreshold = TextEditingController(
    text:
        '${const TournamentFlowPrioritySettings().playerMatchDeficitThreshold}',
  );
  final _groupThreshold = TextEditingController(
    text:
        '${const TournamentFlowPrioritySettings().groupMatchDeficitThreshold}',
  );
  bool _usePercentage =
      const TournamentFlowPrioritySettings().usePercentageForGroups;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await _preferences.load();
      if (!mounted) return;
      _playerThreshold.text = '${settings.playerMatchDeficitThreshold}';
      _groupThreshold.text = '${settings.groupMatchDeficitThreshold}';
      setState(() => _usePercentage = settings.usePercentageForGroups);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Hinweiseinstellungen konnten nicht geladen werden: $error',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _preferences.save(
        TournamentFlowPrioritySettings(
          playerMatchDeficitThreshold: int.parse(_playerThreshold.text.trim()),
          groupMatchDeficitThreshold: int.parse(_groupThreshold.text.trim()),
          usePercentageForGroups: _usePercentage,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hinweiseinstellungen gespeichert.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _playerThreshold.dispose();
    _groupThreshold.dispose();
    super.dispose();
  }

  String? _validateThreshold(String? text) {
    final value = int.tryParse(text?.trim() ?? '');
    return value != null &&
            value >= TournamentFlowPrioritySettings.minimumThreshold
        ? null
        : 'Positive ganze Zahl eingeben.';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Form(
      key: _form,
      child: AdaptiveContentList(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Hinweiseinstellungen',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Die Werte gelten für Prioritätshinweise in allen Turnieren.',
          ),
          const SizedBox(height: 16),
          AdaptiveTileLayout(
            minTileWidth: 280,
            children: [
              TextFormField(
                controller: _playerThreshold,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Prioritätshinweis pro Spieler ab Verzug von',
                  suffixText: 'Partien',
                  border: OutlineInputBorder(),
                ),
                validator: _validateThreshold,
              ),
              TextFormField(
                controller: _groupThreshold,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Prioritätshinweis pro Gruppe ab Verzug von',
                  suffixText: 'Partien',
                  border: OutlineInputBorder(),
                ),
                validator: _validateThreshold,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Prozentuale Berechnung verwenden'),
            subtitle: const Text(
              'Vergleicht den Fortschritt der Gruppen im Verhältnis zu ihren möglichen Begegnungen.',
            ),
            value: _usePercentage,
            onChanged: _saving
                ? null
                : (value) => setState(() => _usePercentage = value),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Speichert …' : 'Speichern'),
          ),
        ],
      ),
    );
  }
}
