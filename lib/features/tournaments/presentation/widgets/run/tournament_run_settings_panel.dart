import 'package:flutter/material.dart';

import '../../../../../shared/widgets/adaptive_content.dart';
import '../../../domain/tournament_models.dart';
import '../../../domain/tournament_settings.dart';

class TournamentRunSettingsPanel extends StatefulWidget {
  const TournamentRunSettingsPanel({
    super.key,
    required this.tournament,
    required this.onChanged,
    this.showAudioSettings = true,
    this.showPrioritySettings = true,
    this.showHintAudioSettings = true,
  });

  final CreatedTournament tournament;
  final Future<void> Function() onChanged;
  final bool showAudioSettings;
  final bool showPrioritySettings;
  final bool showHintAudioSettings;

  @override
  State<TournamentRunSettingsPanel> createState() =>
      _TournamentRunSettingsPanelState();
}

class _TournamentRunSettingsPanelState
    extends State<TournamentRunSettingsPanel> {
  final _idleFormKey = GlobalKey<FormState>();
  final _priorityFormKey = GlobalKey<FormState>();
  final _announcementFormKey = GlobalKey<FormState>();
  late final _playerThreshold = TextEditingController(
    text: '${widget.tournament.tournamentSettings.playerMatchDeficitThreshold}',
  );
  late final _groupThreshold = TextEditingController(
    text: '${widget.tournament.tournamentSettings.groupMatchDeficitThreshold}',
  );
  late final _idleStartMinutes = TextEditingController(
    text: '${widget.tournament.tournamentSettings.idleBoardSoundStartMinutes}',
  );
  late final _idleRepeatMinutes = TextEditingController(
    text: '${widget.tournament.tournamentSettings.idleBoardSoundRepeatMinutes}',
  );
  late final _alternativeRecommendationCount = TextEditingController(
    text:
        '${widget.tournament.tournamentSettings.alternativeRecommendationCount}',
  );
  bool _saving = false;

  Future<void> _save(TournamentSettings updated) async {
    if (_saving || !updated.isValid) return;
    final previous = widget.tournament.tournamentSettings;
    setState(() => _saving = true);
    widget.tournament.tournamentSettings = updated;
    try {
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Turniereinstellungen gespeichert.')),
        );
      }
    } catch (error) {
      widget.tournament.tournamentSettings = previous;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Turniereinstellungen konnten nicht gespeichert werden: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateRange(
    String? text, {
    required int minimum,
    required int maximum,
  }) {
    final value = int.tryParse(text?.trim() ?? '');
    return value != null && value >= minimum && value <= maximum
        ? null
        : 'Ganze Zahl zwischen $minimum und $maximum eingeben.';
  }

  Future<void> _saveNumberSettings() async {
    final current = widget.tournament.tournamentSettings;
    if (widget.showAudioSettings &&
        current.readAlternativeRecommendations &&
        !(_announcementFormKey.currentState?.validate() ?? false)) {
      return;
    }
    if (widget.showHintAudioSettings &&
        current.idleBoardSoundEnabled &&
        !(_idleFormKey.currentState?.validate() ?? false)) {
      return;
    }
    if (widget.showPrioritySettings &&
        !(_priorityFormKey.currentState?.validate() ?? false)) {
      return;
    }
    await _save(
      current.copyWith(
        playerMatchDeficitThreshold: int.parse(_playerThreshold.text.trim()),
        groupMatchDeficitThreshold: int.parse(_groupThreshold.text.trim()),
        idleBoardSoundStartMinutes: int.parse(_idleStartMinutes.text.trim()),
        idleBoardSoundRepeatMinutes: int.parse(_idleRepeatMinutes.text.trim()),
        alternativeRecommendationCount: current.readAlternativeRecommendations
            ? int.parse(_alternativeRecommendationCount.text.trim())
            : current.alternativeRecommendationCount,
      ),
    );
  }

  @override
  void dispose() {
    _playerThreshold.dispose();
    _groupThreshold.dispose();
    _idleStartMinutes.dispose();
    _idleRepeatMinutes.dispose();
    _alternativeRecommendationCount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.tournament.tournamentSettings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showAudioSettings) ...[
          Text('Tonmodus', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sprachassistenz aktivieren'),
            subtitle: const Text(
              'Spricht nach einem eingetragenen Ergebnis die nächste Partie für dieses Board an.',
            ),
            value: settings.soundModeEnabled,
            onChanged: _saving
                ? null
                : (enabled) =>
                      _save(settings.copyWith(soundModeEnabled: enabled)),
          ),
          if (settings.soundModeEnabled) ...[
            DropdownButtonFormField<AnnouncementNameFormat>(
              key: ValueKey(settings.announcementNameFormat),
              initialValue: settings.announcementNameFormat,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Namensformat',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: AnnouncementNameFormat.fullName,
                  child: Text('Vollständigen Namen aussprechen'),
                ),
                DropdownMenuItem(
                  value: AnnouncementNameFormat.firstNameLastInitial,
                  child: Text(
                    'Vorname + ersten Buchstaben des Nachnamens aussprechen',
                  ),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) {
                        _save(settings.copyWith(announcementNameFormat: value));
                      }
                    },
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Spitzname aussprechen, wenn vorhanden'),
              value: settings.speakNicknameWhenAvailable,
              onChanged: _saving
                  ? null
                  : (enabled) => _save(
                      settings.copyWith(speakNicknameWhenAvailable: enabled),
                    ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Alternative Empfehlungen vorlesen'),
              subtitle: const Text(
                'Liest die nächsten sichtbaren Empfehlungen in ihrer angezeigten Reihenfolge als „Alternativ“ vor.',
              ),
              value: settings.readAlternativeRecommendations,
              onChanged: _saving
                  ? null
                  : (enabled) => _save(
                      settings.copyWith(
                        readAlternativeRecommendations: enabled,
                      ),
                    ),
            ),
            if (settings.readAlternativeRecommendations)
              Form(
                key: _announcementFormKey,
                child: SizedBox(
                  width: 280,
                  child: TextFormField(
                    key: const ValueKey('alternative-recommendation-count'),
                    controller: _alternativeRecommendationCount,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Anzahl alternativer Begegnungen',
                      helperText: 'Zwischen 1 und 3',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        _validateRange(value, minimum: 1, maximum: 3),
                  ),
                ),
              ),
          ],
          const Divider(height: 32),
        ],
        if (widget.showPrioritySettings) ...[
          Text(
            'Prioritätshinweise',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Zeigt offene Partien bevorzugt an, wenn Spieler oder Gruppen im Spielplan zurückliegen.',
          ),
          const SizedBox(height: 12),
          Form(
            key: _priorityFormKey,
            child: AdaptiveTileLayout(
              minTileWidth: 250,
              children: [
                TextFormField(
                  key: const ValueKey('player-match-deficit-threshold'),
                  controller: _playerThreshold,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Spielerrückstand ab',
                    suffixText: 'Partien',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => _validateRange(
                    value,
                    minimum: TournamentSettings.minimumThreshold,
                    maximum: TournamentSettings.maximumThreshold,
                  ),
                ),
                TextFormField(
                  key: const ValueKey('group-match-deficit-threshold'),
                  controller: _groupThreshold,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Gruppenrückstand ab',
                    suffixText: 'Partien',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => _validateRange(
                    value,
                    minimum: TournamentSettings.minimumThreshold,
                    maximum: TournamentSettings.maximumThreshold,
                  ),
                ),
              ],
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Gruppenfortschritt prozentual vergleichen'),
            subtitle: const Text(
              'Vergleicht den Anteil gespielter Partien und rechnet den Abstand auf die mögliche Partienzahl der größten Gruppe um.',
            ),
            value: settings.usePercentageForGroups,
            onChanged: _saving
                ? null
                : (enabled) =>
                      _save(settings.copyWith(usePercentageForGroups: enabled)),
          ),
          const SizedBox(height: 8),
        ],
        if (widget.showHintAudioSettings) ...[
          const Divider(height: 32),
          Text(
            'Akustische Hinweise',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hinweise akustisch ankündigen'),
            subtitle: const Text(
              'Spielt bei einem neu angezeigten Hinweis einen kurzen, dezenten Signalton.',
            ),
            value: settings.announceHintsAudibly,
            onChanged: _saving
                ? null
                : (enabled) =>
                      _save(settings.copyWith(announceHintsAudibly: enabled)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Bei Board-Leerstand regelmäßig ein Signal abspielen',
            ),
            subtitle: const Text(
              'Nur im Reiter „Leitung“, wenn ein Board frei ist und sofort spielbare Partien offen sind.',
            ),
            value: settings.idleBoardSoundEnabled,
            onChanged: _saving
                ? null
                : (enabled) =>
                      _save(settings.copyWith(idleBoardSoundEnabled: enabled)),
          ),
          if (settings.idleBoardSoundEnabled)
            Form(
              key: _idleFormKey,
              child: AdaptiveTileLayout(
                minTileWidth: 250,
                children: [
                  TextFormField(
                    controller: _idleStartMinutes,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Signal starten, wenn Board frei ist seit',
                      suffixText: 'Minuten',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        _validateRange(value, minimum: 1, maximum: 5),
                  ),
                  TextFormField(
                    controller: _idleRepeatMinutes,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Signal wiederholen alle',
                      suffixText: 'Minuten',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        _validateRange(value, minimum: 1, maximum: 5),
                  ),
                ],
              ),
            ),
        ],
        if (widget.showPrioritySettings ||
            widget.showAudioSettings ||
            widget.showHintAudioSettings)
          FilledButton.icon(
            onPressed: _saving ? null : _saveNumberSettings,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Zahlenwerte speichern'),
          ),
      ],
    );
  }
}
