import 'package:flutter/material.dart';

import '../../tournaments/application/audio_announcement_preferences.dart';

class AudioAnnouncementDefaultsPanel extends StatefulWidget {
  const AudioAnnouncementDefaultsPanel({super.key});

  @override
  State<AudioAnnouncementDefaultsPanel> createState() =>
      _AudioAnnouncementDefaultsPanelState();
}

class _AudioAnnouncementDefaultsPanelState
    extends State<AudioAnnouncementDefaultsPanel> {
  final _storage = AudioAnnouncementPreferencesStorage();
  var _settings = const AudioAnnouncementPreferences();
  var _loading = true;
  var _saving = false;

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
              'Ton-Modus-Einstellungen konnten nicht geladen werden: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(AudioAnnouncementPreferences updated) async {
    final previous = _settings;
    setState(() {
      _settings = updated;
      _saving = true;
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
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    leading: const Icon(Icons.record_voice_over_outlined),
    title: const Text('Ton Modus Einstellungen'),
    subtitle: const Text('Legt fest, wie Spielernamen angesagt werden.'),
    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    children: [
      if (_loading) const LinearProgressIndicator(),
      DropdownButtonFormField<AnnouncementNameFormat>(
        key: ValueKey(_settings.nameFormat),
        initialValue: _settings.nameFormat,
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
        onChanged: _loading || _saving
            ? null
            : (format) {
                if (format != null) {
                  _save(_settings.copyWith(nameFormat: format));
                }
              },
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Spitzname aussprechen, wenn vorhanden'),
        subtitle: const Text(
          'Ein vorhandener Spitzname hat Vorrang vor dem Namensformat.',
        ),
        value: _settings.speakNicknameWhenAvailable,
        onChanged: _loading || _saving
            ? null
            : (enabled) {
                if (enabled != null) {
                  _save(
                    _settings.copyWith(speakNicknameWhenAvailable: enabled),
                  );
                }
              },
      ),
    ],
  );
}
