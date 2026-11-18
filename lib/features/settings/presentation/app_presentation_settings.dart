import 'package:flutter/material.dart';

import '../data/app_presentation_preferences.dart';

class DynamicDashboardSettings extends StatefulWidget {
  const DynamicDashboardSettings({super.key});

  @override
  State<DynamicDashboardSettings> createState() =>
      _DynamicDashboardSettingsState();
}

class _DynamicDashboardSettingsState extends State<DynamicDashboardSettings> {
  final _preferences = AppPresentationPreferences.load();
  final _intervalController = TextEditingController();
  AppPresentationPreferences? _value;

  @override
  void dispose() {
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _save({bool? dashboardEnabled, int? interval}) async {
    await AppPresentationPreferences.load().then(
      (current) => current.save(
        dynamicDashboardEnabled: dashboardEnabled,
        dashboardIntervalSeconds: interval,
      ),
    );
    final updated = await AppPresentationPreferences.load();
    if (!mounted) return;
    _intervalController.text = '${updated.dashboardIntervalSeconds}';
    setState(() => _value = updated);
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<AppPresentationPreferences>(
        future: _preferences,
        builder: (context, snapshot) {
          final value = _value ?? snapshot.data;
          if (value == null) {
            return const Card(child: LinearProgressIndicator());
          }
          if (_intervalController.text.isEmpty) {
            _intervalController.text = '${value.dashboardIntervalSeconds}';
          }
          return Card(
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  title: const Text('Dynamisches Info Dashboard aktivieren'),
                  subtitle: const Text(
                    'Zeigt wechselnde Infokarten auf der Startseite. Das aktuelle Turnier bleibt immer sichtbar.',
                  ),
                  value: value.dynamicDashboardEnabled,
                  onChanged: (enabled) => _save(dashboardEnabled: enabled),
                ),
                if (value.dynamicDashboardEnabled)
                  ListTile(
                    title: const Text('Wechselintervall der Infokarten'),
                    trailing: SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _intervalController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          suffixText: 'Sek.',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (raw) {
                          final seconds = int.tryParse(raw);
                          if (seconds != null) {
                            _save(interval: seconds.clamp(1, 300));
                          }
                        },
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
}

class AppPresentationSettings extends StatefulWidget {
  const AppPresentationSettings({super.key});

  @override
  State<AppPresentationSettings> createState() =>
      _AppPresentationSettingsState();
}

class _AppPresentationSettingsState extends State<AppPresentationSettings> {
  final _preferences = AppPresentationPreferences.load();
  AppPresentationPreferences? _value;

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<AppPresentationPreferences>(
        future: _preferences,
        builder: (context, snapshot) {
          final value = _value ?? snapshot.data;
          if (value == null) {
            return const Card(child: LinearProgressIndicator());
          }
          return Card(
            child: ExpansionTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF-Export-Einstellungen'),
              children: [
                _switch('Datum', value.pdfShowDate, (v) => _save(date: v)),
                _switch(
                  'Unterschriften Heim-/Gastmannschaft',
                  value.pdfShowSignatures,
                  (v) => _save(signatures: v),
                ),
                _switch(
                  'Info: Übertrag in die nächste Etappe',
                  value.pdfShowAdvancement,
                  (v) => _save(advancement: v),
                ),
                _switch(
                  'Querformat (aus = Hochformat)',
                  value.pdfLandscape,
                  (v) => _save(landscape: v),
                ),
                _switch(
                  'Notizenfeld',
                  value.pdfShowNotes,
                  (v) => _save(notes: v),
                ),
                _switch(
                  'Feld für Bestleistungen',
                  value.pdfShowBestPerformances,
                  (v) => _save(performances: v),
                ),
              ],
            ),
          );
        },
      );

  Future<void> _save({
    bool? date,
    bool? signatures,
    bool? advancement,
    bool? landscape,
    bool? notes,
    bool? performances,
  }) async {
    await AppPresentationPreferences.load().then(
      (current) => current.save(
        pdfShowDate: date,
        pdfShowSignatures: signatures,
        pdfShowAdvancement: advancement,
        pdfLandscape: landscape,
        pdfShowNotes: notes,
        pdfShowBestPerformances: performances,
      ),
    );
    final updated = await AppPresentationPreferences.load();
    if (!mounted) return;
    setState(() => _value = updated);
  }

  Widget _switch(String title, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile.adaptive(
        title: Text(title),
        value: value,
        onChanged: onChanged,
      );
}
