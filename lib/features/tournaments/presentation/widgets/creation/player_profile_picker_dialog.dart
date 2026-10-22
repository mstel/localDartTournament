import 'package:flutter/material.dart';

import '../../../data/app_database.dart';

class PlayerProfilePickerDialog extends StatefulWidget {
  const PlayerProfilePickerDialog({
    super.key,
    required this.profiles,
    required this.selectedProfileIds,
    this.createPlayer,
  });

  final List<PlayerProfile> profiles;
  final Set<String> selectedProfileIds;
  final Future<PlayerProfile> Function(String firstName, String lastName)?
  createPlayer;

  @override
  State<PlayerProfilePickerDialog> createState() =>
      PlayerProfilePickerDialogState();
}

class PlayerProfilePickerDialogState extends State<PlayerProfilePickerDialog> {
  late final _profiles = [...widget.profiles];
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final firstName = _firstName.text.trim();
    final lastName = _lastName.text.trim();
    if (firstName.isEmpty || firstName.length > 80 || lastName.length > 80) {
      setState(
        () => _error = 'Bitte einen Namen mit 1 bis 80 Zeichen eingeben.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profile = await widget.createPlayer!(firstName, lastName);
      if (!mounted) return;
      setState(() {
        _profiles.add(profile);
        _selectedProfileIds.add(profile.id);
        _firstName.clear();
        _lastName.clear();
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Spieler konnte nicht angelegt werden. Verbindung und Berechtigung prüfen.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  late final Set<String> _selectedProfileIds = {...widget.selectedProfileIds};

  void _toggleProfile(String profileId, bool selected) {
    setState(() {
      if (selected) {
        _selectedProfileIds.add(profileId);
      } else {
        _selectedProfileIds.remove(profileId);
      }
    });
  }

  void _submit() {
    Navigator.of(context).pop([
      for (final profile in _profiles)
        if (_selectedProfileIds.contains(profile.id)) profile,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(16),
        contentPadding: const EdgeInsets.all(16),
        title: const Text('Spieler auswählen'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.createPlayer != null) ...[
                  const Text('Neuen lokalen Spieler anlegen.'),
                  TextField(
                    controller: _firstName,
                    enabled: !_busy,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Vorname des neuen Spielers',
                    ),
                  ),
                  TextField(
                    controller: _lastName,
                    enabled: !_busy,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: 'Nachname'),
                    onSubmitted: _busy ? null : (_) => _create(),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _create,
                    icon: const Icon(Icons.person_add),
                    label: const Text('Neuen Spieler anlegen'),
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null) Text(_error!),
                  const SizedBox(height: 16),
                ],
                _profiles.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('Noch keine Spielerprofile angelegt.'),
                      )
                    : ListView.separated(
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        itemCount: _profiles.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final profile = _profiles[index];
                          final selected = _selectedProfileIds.contains(
                            profile.id,
                          );
                          final subtitle = [
                            if (profile.city.isNotEmpty) profile.city,
                            if (profile.country.isNotEmpty) profile.country,
                          ].join(', ');
                          return CheckboxListTile(
                            value: selected,
                            onChanged: _busy
                                ? null
                                : (value) => _toggleProfile(
                                    profile.id,
                                    value ?? false,
                                  ),
                            title: Text(profile.displayName),
                            subtitle: subtitle.isEmpty ? null : Text(subtitle),
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        },
                      ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: const Icon(Icons.check),
            label: Text('${_selectedProfileIds.length} übernehmen'),
          ),
        ],
      ),
    );
  }
}
