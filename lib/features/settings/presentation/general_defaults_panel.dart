import 'package:flutter/material.dart';

import '../data/general_defaults_storage.dart';

/// Erster Punkt unter «Standardwerte». Aktuell wird nur die vorbelegte Anzahl
/// Boards gepflegt; sie gilt für alle neuen Turnier- und Ligaspiel-Anlagen.
class GeneralDefaultsPanel extends StatefulWidget {
  const GeneralDefaultsPanel({super.key, this.storage});

  final GeneralDefaultsStorage? storage;

  @override
  State<GeneralDefaultsPanel> createState() => _GeneralDefaultsPanelState();
}

class _GeneralDefaultsPanelState extends State<GeneralDefaultsPanel> {
  late final GeneralDefaultsStorage _storage =
      widget.storage ?? const GeneralDefaultsStorage();
  final _form = GlobalKey<FormState>();
  final _boards = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _boards.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final defaults = await _storage.load();
      if (mounted) _boards.text = '${defaults.defaultBoardCount}';
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = 'Standardwerte konnten nicht geladen werden: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      await _storage.save(
        GeneralDefaults(defaultBoardCount: int.parse(_boards.text.trim())),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Standardwert gespeichert. Die Anzahl Boards ist beim nächsten Anlegen vorbelegt.',
          ),
        ),
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
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        key: const ValueKey('general-defaults-panel'),
        leading: const Icon(Icons.tune),
        title: const Text('Allgemein'),
        subtitle: const Text('Anzahl Boards für neue Turniere und Ligaspiele'),
        initiallyExpanded: true,
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            )
          else
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error case final error?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  TextFormField(
                    key: const ValueKey('general-default-board-count'),
                    controller: _boards,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Anzahl Boards',
                      border: OutlineInputBorder(),
                      helperText: '1–64',
                    ),
                    validator: (text) {
                      final value = int.tryParse(text?.trim() ?? '');
                      return value != null &&
                              value >= GeneralDefaults.minimumBoardCount &&
                              value <= GeneralDefaults.maximumBoardCount
                          ? null
                          : 'Ganze Zahl von 1 bis 64 eingeben.';
                    },
                    onFieldSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.icon(
                      key: const ValueKey('general-defaults-save'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Standardwert speichern'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
