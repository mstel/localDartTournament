import 'package:flutter/material.dart';

import '../data/govee_api_key_storage.dart';

class GoveeHubPage extends StatefulWidget {
  const GoveeHubPage({super.key, this.storage});

  final GoveeApiKeyStorage? storage;

  @override
  State<GoveeHubPage> createState() => _GoveeHubPageState();
}

class _GoveeHubPageState extends State<GoveeHubPage> {
  final _keyController = TextEditingController();
  late final GoveeApiKeyStorage _storage =
      widget.storage ?? GoveeApiKeyStorage();
  bool _loading = true;
  bool _saving = false;
  bool _hasSavedKey = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyController.clear();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final key = await _storage.load();
      if (!mounted) return;
      _keyController.text = key ?? '';
      setState(() {
        _hasSavedKey = key?.isNotEmpty == true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'API-Key konnte nicht geladen werden: $error';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Bitte einen Govee API-Key eingeben.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _storage.save(key);
      if (!mounted) return;
      setState(() => _hasSavedKey = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Govee API-Key auf diesem Gerät gespeichert.'),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Speichern fehlgeschlagen: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Govee API-Key')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Speichere hier den API-Key für die Govee-Geräte dieses Geräts. '
                'Die Geräteauswahl und Lichtfarben findest du in den Einstellungen '
                'eines geöffneten Turniers unter „Ambiente Einstellungen“.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _keyController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: 'Govee API-Key',
                  border: const OutlineInputBorder(),
                  helperText: _hasSavedKey
                      ? 'Ein API-Key ist auf diesem Gerät gespeichert.'
                      : 'Der API-Key bleibt nach dem Neustart verfügbar.',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Speichert …' : 'API-Key speichern'),
                ),
              ),
            ],
          ),
  );
}
