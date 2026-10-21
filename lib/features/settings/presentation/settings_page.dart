import '../../../shared/widgets/sport_settings_section.dart';
import 'package:dart_tournament_manager/shared/widgets/adaptive_content.dart';
import '../../backups/presentation/backup_panel.dart';
import '../../backups/application/local_app_reset_service.dart';
import '../../updates/presentation/android_updates_panel.dart';
import 'package:flutter/material.dart';
import '../data/planning_settings_storage.dart';
import '../../notifications/presentation/push_sender_menu.dart';
import '../../notifications/presentation/push_device_menu.dart';
import '../../dev_tools/presentation/dev_tools_page.dart';
import '../../govee/presentation/govee_hub_page.dart';

import '../../tournaments/domain/tournament_planning_parameters.dart';
import 'appearance_panel.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _selected = 0;

  static const _sections = [
    'Daten',
    'Updates',
    'Darstellung',
    'Werkzeuge & Verwaltung',
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Einstellungen')),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var i = 0; i < _sections.length; i++)
                  ChoiceChip(
                    label: Text(_sections[i]),
                    avatar: Icon(
                      [
                        Icons.storage,
                        Icons.system_update_outlined,
                        Icons.palette,
                        Icons.settings_outlined,
                      ][i],
                    ),
                    selected: _selected == i,
                    onSelected: (_) => setState(() => _selected = i),
                  ),
              ],
            ),
          ),
          Expanded(
            child: switch (_selected) {
              0 => _DataPanel(onReset: () => _resetLocalData(context)),
              1 => const AndroidUpdatesPanel(),
              2 => const AppearancePanel(),
              _ => const _AdministrationPanel(),
            },
          ),
        ],
      ),
    ),
  );
}

class _DataPanel extends StatelessWidget {
  const _DataPanel({required this.onReset});
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => BackupPanel(
    trailing: Card(
      child: ListTile(
        leading: const Icon(Icons.restart_alt),
        title: const Text('Lokale App-Daten zurücksetzen'),
        subtitle: const Text(
          'Sichert lokale Dateien bytegetreu; Cloud und andere Geräte bleiben unberührt.',
        ),
        onTap: onReset,
      ),
    ),
  );
}

class _AdministrationPanel extends StatelessWidget {
  const _AdministrationPanel();

  @override
  Widget build(BuildContext context) => AdaptiveContentList(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Werkzeuge & Verwaltung',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      const PushSenderMenu(),
      const PushDeviceMenu(),
      Card(
        child: ListTile(
          leading: const Icon(Icons.lightbulb_outline),
          title: const Text('Govee Licht-Hub'),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const GoveeHubPage())),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.science_outlined),
          title: const Text('Dev Tools'),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const DevToolsPage())),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text('Passende Turnierform'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const PlanningParametersPage(),
            ),
          ),
        ),
      ),
    ],
  );
}

class PlanningParametersPage extends StatelessWidget {
  const PlanningParametersPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Passende Turnierform')),
    body: const SafeArea(child: _PlanningParametersPanel()),
  );
}

Future<void> _resetLocalData(BuildContext context) async {
  final controller = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Lokale App-Daten zurücksetzen?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Die aktiven lokalen Turniere, Spieler, Ergebnisse, Ranglisten, Statistiken und Planungseinstellungen dieses Geräts werden nach einer bytegetreuen Sicherung entfernt. Deine Anmeldung und übrigen App-Einstellungen bleiben erhalten. Cloud-Daten und andere Geräte bleiben unberührt. Die Synchronisierung wird pausiert, damit keine alten Cloud-Daten zurückgeladen oder neue lokale Daten automatisch hochgeladen werden. Ein neuer Stand bleibt lokal, bis du ihn ausdrücklich als Cloud-Stand freigibst.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Zum Bestätigen ZURÜCKSETZEN eingeben',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            dialogContext,
            controller.text.trim() == 'ZURÜCKSETZEN',
          ),
          child: const Text('Daten zurücksetzen'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (confirmed != true || !context.mounted) return;
  try {
    await const LocalAppResetService().reset();
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Zurücksetzen fehlgeschlagen: $error')),
    );
  }
}

class _PlanningParametersPanel extends StatefulWidget {
  const _PlanningParametersPanel();

  @override
  State<_PlanningParametersPanel> createState() =>
      _PlanningParametersPanelState();
}

class _PlanningParametersPanelState extends State<_PlanningParametersPanel> {
  final _storage = PlanningSettingsStorage();
  final _form = GlobalKey<FormState>();
  final _sections = {
    for (final category
        in PlanningParameter.values.map((p) => p.category).toSet())
      category: GlobalKey<SportSettingsSectionState>(),
  };
  final _controllers = {
    for (final parameter in PlanningParameter.values)
      parameter: TextEditingController(text: '${parameter.defaultValue}'),
  };
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final parameters = await _storage.load();
      if (!mounted) return;
      for (final entry in _controllers.entries) {
        entry.value.text = '${parameters.value(entry.key)}';
      }
    } catch (_) {
      if (!mounted) return;
      _error = 'Einstellungen konnten nicht geladen werden.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      for (final section in _sections.values) {
        section.currentState?.expand();
      }
      return;
    }
    setState(() => _saving = true);
    try {
      await _storage.save(
        TournamentPlanningParameters.fromValues({
          for (final entry in _controllers.entries)
            entry.key: int.parse(entry.value.text.trim()),
        }),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Einstellungen gespeichert. Sie gelten für die nächste Turniersuche.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speichern fehlgeschlagen. Bitte erneut versuchen.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!),
              TextButton(onPressed: _load, child: const Text('Erneut laden')),
            ],
          ),
        ),
      );
    }
    return Form(
      key: _form,
      child: AdaptiveContentList(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Passende Turnierform',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Die Parameter gelten nach dem Speichern für neue Berechnungen. Bereits erstellte Turniere bleiben unverändert.',
          ),
          const SizedBox(height: 16),
          for (final category
              in PlanningParameter.values.map((p) => p.category).toSet())
            SportSettingsSection(
              key: _sections[category],
              title: category,
              summary:
                  '${PlanningParameter.values.where((p) => p.category == category).length} Einstellungen · bei Bedarf anpassen',
              initiallyExpanded:
                  category == PlanningParameter.values.first.category,
              children: [
                AdaptiveTileLayout(
                  minTileWidth: 320,
                  children: [
                    for (final parameter in PlanningParameter.values.where(
                      (p) => p.category == category,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(parameter.label),
                            const SizedBox(height: 6),
                            TextFormField(
                              key: ValueKey(parameter.name),
                              controller: _controllers[parameter],
                              enabled: !_saving,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                helperText:
                                    '${parameter.minimum}–${parameter.maximum}',
                                errorMaxLines: 3,
                              ),
                              validator: (text) {
                                final value = int.tryParse(text?.trim() ?? '');
                                return value != null && parameter.accepts(value)
                                    ? null
                                    : 'Ganze Zahl von ${parameter.minimum} bis ${parameter.maximum} eingeben.';
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 12),
          const SportSettingsSection(
            title: 'So wird gerechnet',
            summary: 'Leg-Dauern und Bewertung erklärt',
            icon: Icons.info_outline,
            children: [
              Text(
                'Leg-Dauern sind Schätzwerte. Pro Match gilt der Mittelwert aus minimaler und maximaler Leg-Zahl: Bo3 = 2,5; Bo5 = 4; Bo101 = 76; Bo1 = 1 Leg. Bei Sets wird zusätzlich mit der mittleren Set-Zahl gerechnet. Double In verwendet die Double-Out-Dauer. Weniger Strafpunkte bedeuten eine bessere Platzierung. Spielerzahl, Boards, Zeitfenster, Punktzahl und Checkout werden weiterhin je Turniersuche festgelegt.',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Speichert …' : 'Speichern'),
              ),
              OutlinedButton(
                onPressed: _saving
                    ? null
                    : () {
                        for (final entry in _controllers.entries) {
                          entry.value.text = '${entry.key.defaultValue}';
                        }
                        _form.currentState?.validate();
                      },
                child: const Text('Standardwerte einsetzen'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
