import 'package:flutter/material.dart';

import '../../tournaments/domain/director_schedule_modes.dart';
import '../../tournaments/domain/tournament_settings.dart';
import '../data/director_mode_defaults.dart';

/// Opens the settings dialog and persists the selected defaults on save.
Future<void> showDirectorModeDefaultsDialog(BuildContext context) async {
  final initial = await const DirectorModeDefaultsStorage().load();
  if (!context.mounted) return;
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => DirectorModeDefaultsDialog(initial: initial),
  );
  if (saved == true && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Standardwerte gespeichert.')));
  }
}

class DirectorModeDefaultsDialog extends StatefulWidget {
  const DirectorModeDefaultsDialog({super.key, required this.initial});

  final DirectorModeDefaults initial;

  @override
  State<DirectorModeDefaultsDialog> createState() =>
      _DirectorModeDefaultsDialogState();
}

class _DirectorModeDefaultsDialogState
    extends State<DirectorModeDefaultsDialog> {
  late DirectorModeDefaults _value = widget.initial;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await const DirectorModeDefaultsStorage().save(_value);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Standardwerte für Turnierleitermodus'),
    content: SizedBox(
      width: 680,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Die Werte gelten für neu erstellte Turniere und Ligaspiele. Bestehende Turniere bleiben unverändert.',
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Turniere',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Spielleiter-Modus aktivieren'),
                        subtitle: const Text('Standard: Ja'),
                        value: _value.tournamentsEnabled,
                        onChanged: _saving
                            ? null
                            : (enabled) => setState(
                                () => _value = _value.copyWith(
                                  tournamentsEnabled: enabled,
                                ),
                              ),
                      ),
                      _dropdown<String>(
                        label: 'Spielplanmodus',
                        value: _value.tournamentScheduleMode,
                        items: const [
                          ('fixed_schedule', 'Fester Spielplan'),
                          ('dynamic', 'Dynamisch'),
                        ],
                        onChanged: (mode) => setState(
                          () => _value = _value.copyWith(
                            tournamentScheduleMode: mode,
                            tournamentBoardAssignment:
                                DirectorScheduleModes.schedulingStrategy(
                                  _value.tournamentBoardAssignment,
                                  mode,
                                ),
                          ),
                        ),
                      ),
                      if (_value.tournamentScheduleMode !=
                          DirectorScheduleModes.dynamicMode)
                        _dropdown<String>(
                          label: 'Boardzuweisung',
                          value: _value.tournamentBoardAssignment,
                          items: const [
                            ('group', 'Gruppenbasiert'),
                            ('global', 'Turnierweit optimiert'),
                          ],
                          onChanged: (mode) => setState(
                            () => _value = _value.copyWith(
                              tournamentBoardAssignment: mode,
                            ),
                          ),
                        ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Player Insights anzeigen'),
                        subtitle: const Text('Standard: Aus'),
                        value: _value.tournamentPlayerInsights,
                        onChanged: _saving
                            ? null
                            : (enabled) => setState(
                                () => _value = _value.copyWith(
                                  tournamentPlayerInsights: enabled,
                                ),
                              ),
                      ),
                      const Divider(),
                      _AudioDefaultsEditor(
                        title: 'Sprachausgabe für Turniere',
                        enabled: !_saving,
                        value: _value.tournamentAudio,
                        onChanged: (audio) => setState(
                          () =>
                              _value = _value.copyWith(tournamentAudio: audio),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Liga & Freundschaft',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Spielleiter-Modus'),
                        subtitle: const Text(
                          'Für Ligaspiele immer aktiv und nicht änderbar.',
                        ),
                        value: true,
                        onChanged: null,
                      ),
                      _dropdown<String>(
                        label: 'Spielplanmodus',
                        value: _value.leagueScheduleMode,
                        items: const [
                          ('fixed_schedule', 'Fester Spielplan'),
                          ('dynamic', 'Dynamisch aus Vorschlägen'),
                        ],
                        onChanged: (mode) => setState(
                          () => _value = _value.copyWith(
                            leagueScheduleMode: mode,
                          ),
                        ),
                      ),
                      _dropdown<String>(
                        label: 'Partievorschläge',
                        value: _value.leagueSuggestionMode,
                        items: const [
                          (
                            'mirror',
                            'Flexible Boardwahl - Gespiegelte Partievorschläge',
                          ),
                          (
                            'assigned',
                            'Fest zugewiesene Partien - Keine Doppelungen',
                          ),
                        ],
                        onChanged: (mode) => setState(
                          () => _value = _value.copyWith(
                            leagueSuggestionMode: mode,
                          ),
                        ),
                      ),
                      const Divider(),
                      _AudioDefaultsEditor(
                        title: 'Sprachausgabe für Liga & Freundschaft',
                        enabled: !_saving,
                        value: _value.leagueAudio,
                        onChanged: (audio) => setState(
                          () => _value = _value.copyWith(leagueAudio: audio),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        child: const Text('Abbrechen'),
      ),
      FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: const Icon(Icons.save_outlined),
        label: Text(_saving ? 'Speichert …' : 'Speichern'),
      ),
    ],
  );

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<(T, String)> items,
    required ValueChanged<T> onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final item in items)
          DropdownMenuItem<T>(value: item.$1, child: Text(item.$2)),
      ],
      onChanged: _saving
          ? null
          : (next) {
              if (next != null) onChanged(next);
            },
    ),
  );
}

class _AudioDefaultsEditor extends StatelessWidget {
  const _AudioDefaultsEditor({
    required this.title,
    required this.enabled,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool enabled;
  final DirectorAudioDefaults value;
  final ValueChanged<DirectorAudioDefaults> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Sprachausgabe aktivieren'),
        subtitle: const Text('Standard: Aus'),
        value: value.soundModeEnabled,
        onChanged: enabled
            ? (next) => onChanged(value.copyWith(soundModeEnabled: next))
            : null,
      ),
      DropdownButtonFormField<AnnouncementNameFormat>(
        initialValue: value.nameFormat,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Namenswiedergabe',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(
            value: AnnouncementNameFormat.fullName,
            child: Text('Vollständiger Name'),
          ),
          DropdownMenuItem(
            value: AnnouncementNameFormat.firstNameLastInitial,
            child: Text('Vorname + Nachnameninitial'),
          ),
        ],
        onChanged: enabled
            ? (format) {
                if (format != null) {
                  onChanged(value.copyWith(nameFormat: format));
                }
              }
            : null,
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Spitzname bevorzugen'),
        value: value.speakNicknameWhenAvailable,
        onChanged: enabled
            ? (next) =>
                  onChanged(value.copyWith(speakNicknameWhenAvailable: next))
            : null,
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Weitere Vorschläge vorlesen'),
        value: value.readAlternativeRecommendations,
        onChanged: enabled
            ? (next) => onChanged(
                value.copyWith(readAlternativeRecommendations: next),
              )
            : null,
      ),
      if (value.readAlternativeRecommendations)
        DropdownButtonFormField<int>(
          initialValue: value.alternativeRecommendationCount.clamp(0, 3),
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Anzahl weiterer Vorschläge',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 0, child: Text('0')),
            DropdownMenuItem(value: 1, child: Text('1')),
            DropdownMenuItem(value: 2, child: Text('2')),
            DropdownMenuItem(value: 3, child: Text('3')),
          ],
          onChanged: enabled
              ? (count) {
                  if (count != null) {
                    onChanged(
                      value.copyWith(alternativeRecommendationCount: count),
                    );
                  }
                }
              : null,
        ),
    ],
  );
}
