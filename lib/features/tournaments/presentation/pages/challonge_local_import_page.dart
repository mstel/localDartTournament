import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../challonge/data/challonge_public_reader.dart';
import '../../../challonge/data/challonge_client.dart';
import '../../../challonge/domain/challonge_tournament.dart';
import '../../../challonge/presentation/challonge_browser_page.dart';
import '../../../rankings/domain/local_ranking.dart';
import '../../data/app_database.dart';
import '../../data/tournament_storage.dart';

class ChallongeLocalImportPage extends StatefulWidget {
  const ChallongeLocalImportPage({super.key});

  @override
  State<ChallongeLocalImportPage> createState() => _ChallongeLocalImportPageState();
}

class _ChallongeLocalImportPageState extends State<ChallongeLocalImportPage> {
  final _url = TextEditingController();
  final _apiKey = TextEditingController();
  final _database = LocalAppDatabase();
  final _storage = TournamentStorage();
  late final _client = ChallongeClient(publicReader: ChallongePublicReader(readDocument: (uri) async {
    final source = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => ChallongeBrowserPage(uri: uri)));
    if (source == null) throw const FormatException('Öffentlicher Abruf abgebrochen.');
    return source;
  }));
  List<ChallongeTournament> _sources = [];
  List<PlayerProfile> _players = [];
  List<LocalRanking> _rankings = [];
  final Map<String, String?> _assignments = {};
  final Set<String> _remember = {};
  final Set<String> _selectedRankings = {};
  bool _countsForRanking = false;
  bool _busy = false;
  String? _message;

  Future<void> _loadFile() async {
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(label: 'Challonge-Export', extensions: ['json', 'html', 'htm']),
    ]);
    if (file == null || !mounted) return;
    setState(() { _busy = true; _message = null; });
    try {
      await _prepare(ChallongePublicReader.decodeDocument(await file.readAsString()));
    } catch (error) {
      if (mounted) setState(() => _message = 'Importdatei konnte nicht gelesen werden: $error');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _loadUrl() async {
    setState(() { _busy = true; _message = null; });
    try {
      var identifier = _url.text.trim();
      if (_apiKey.text.trim().isNotEmpty) {
        final uri = Uri.tryParse(identifier);
        if (uri != null && uri.hasScheme) {
          final parts = uri.pathSegments.where((part) => !['de', 'en', 'fr', 'es', 'pt', 'ja'].contains(part)).toList();
          if (parts.isEmpty) throw const FormatException('Turnierkennung fehlt.');
          identifier = uri.host == 'challonge.com' ? parts.first : '${uri.host.split('.').first}-${parts.first}';
        }
      }
      await _prepare([await _client.tournament(_apiKey.text, identifier)]);
    } catch (error) {
      if (mounted) setState(() => _message = 'Challonge-Turnier konnte nicht geladen werden: $error');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _prepare(List<ChallongeTournament> decoded) async {
    final existing = (await _storage.loadTournaments()).map((t) => t.id).toSet();
    final sources = decoded.where((t) => !existing.contains(t.tournamentId)).toList();
    final players = await _database.loadPlayerProfiles();
    final rankings = await _database.loadLocalRankings();
    final aliases = await _database.loadChallongePlayerLinks();
    final byName = {for (final row in aliases) '${row['challongeName']}'.trim().toLowerCase(): '${row['playerProfileId']}'};
    _assignments.clear();
    for (final tournament in sources) {
      for (final participant in tournament.participants) {
        final name = ChallongeTournament.name(participant);
        _assignments[_key(tournament, participant)] = byName[name.trim().toLowerCase()];
      }
    }
    _remember.clear();
    _sources = sources;
    _players = players;
    _rankings = rankings;
    if (mounted) {
      if (decoded.isNotEmpty && sources.isEmpty) {
        setState(() => _message = 'Alle enthaltenen Turniere wurden bereits importiert.');
      } else if (sources.length < decoded.length) {
        setState(() => _message = '${sources.length} neue Turniere geladen (${decoded.length - sources.length} bereits importiert).');
      } else {
        setState(() => _message = '${sources.length} abgeschlossene Turniere geladen.');
      }
    }
  }

  @override
  void dispose() { _url.dispose(); _apiKey.dispose(); super.dispose(); }

  String _key(ChallongeTournament t, Map<String, dynamic> p) => '${t.id}:${p['id']}';

  Future<void> _import() async {
    setState(() { _busy = true; _message = null; });
    try {
      if (_countsForRanking && _selectedRankings.isEmpty) {
        throw const FormatException('Bitte mindestens eine Rangliste auswählen.');
      }
      if (_sources.isEmpty) {
        throw const FormatException('Keine neuen Turniere zum Übernehmen vorhanden.');
      }
      var imported = 0;
      for (final source in _sources) {
        final profiles = <String, String>{};
        for (final participant in source.participants) {
          final selected = _assignments[_key(source, participant)];
          if (selected != null) profiles['${participant['id']}'] = selected;
          if (selected != null && _remember.contains(_key(source, participant))) {
            await _database.saveChallongePlayerLink(ChallongeTournament.name(participant), selected);
          }
        }
        final tournament = source.convert(
          profiles,
          countsForRanking: _countsForRanking,
          rankingIds: _selectedRankings.toList(),
          allowUnlinkedPlayers: true,
        );
        await _storage.saveTournament(tournament);
        imported++;
      }
      if (mounted) {
        setState(() { _sources = []; _message = '$imported Turniere erfolgreich lokal importiert.'; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$imported Turniere erfolgreich lokal importiert.')),
        );
      }
    } catch (error) {
      if (mounted) {
        final message = switch (error) {
          FormatException() => error.message,
          ArgumentError() => error.message?.toString() ?? '$error',
          _ => 'Import fehlgeschlagen: $error',
        };
        setState(() => _message = message);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _export() async {
    setState(() { _busy = true; _message = null; });
    try {
      final tournaments = await _storage.loadTournaments();
      final jsonString = const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'tournaments': tournaments.map((t) => t.toJson()).toList(),
      });
      final bytes = utf8.encode(jsonString);
      const fileName = 'dart-turniere.json';

      if (kIsWeb) {
        final uri = Uri.dataFromBytes(bytes, mimeType: 'application/json');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      } else if (Platform.isAndroid) {
        try {
          final saved = await const MethodChannel('dartturnier/backups').invokeMethod<bool>('export', {
            'bytes': bytes,
            'fileName': fileName,
            'mimeType': 'application/json',
          });
          if (saved == false) return;
        } catch (_) {
          final tempDir = await getTemporaryDirectory();
          final file = File('${tempDir.path}/$fileName');
          await file.writeAsBytes(bytes, flush: true);
          final uri = Uri.file(file.path);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          }
        }
      } else {
        final location = await getSaveLocation(
          suggestedName: fileName,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'JSON', extensions: ['json']),
          ],
        );
        if (location == null) return;
        await File(location.path).writeAsBytes(bytes, flush: true);
      }
      if (mounted) {
        setState(() => _message = '${tournaments.length} Turniere exportiert.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tournaments.length} Turniere erfolgreich exportiert.')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'Export fehlgeschlagen: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Challonge-Import und Export')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Text('Abgeschlossene Challonge-Turniere aus einem JSON- oder HTML-Export übernehmen.', style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 8, children: [
        FilledButton.icon(onPressed: _busy ? null : _loadFile, icon: const Icon(Icons.file_open), label: const Text('Challonge-Datei importieren')),
        OutlinedButton.icon(onPressed: _busy ? null : _export, icon: const Icon(Icons.download), label: const Text('Turniere exportieren')),
      ]),
      const SizedBox(height: 10),
      TextField(controller: _url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Öffentlicher Challonge-Turnierlink', hintText: 'https://challonge.com/turniername')),
      TextField(controller: _apiKey, obscureText: true, decoration: const InputDecoration(labelText: 'API-Schlüssel für private Turniere (optional)')),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _busy ? null : _loadUrl, icon: const Icon(Icons.download), label: const Text('Link laden'))),
      if (_busy) const LinearProgressIndicator(),
      if (_message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_message!)),
      if (_sources.isNotEmpty) ...[
        const Divider(height: 28),
        SwitchListTile(title: const Text('Für Rangliste/n berücksichtigen'), value: _countsForRanking, onChanged: (value) => setState(() => _countsForRanking = value)),
        if (_countsForRanking) ...[
          for (final ranking in _rankings) CheckboxListTile(title: Text(ranking.name), value: _selectedRankings.contains(ranking.id), onChanged: (value) => setState(() { value == true ? _selectedRankings.add(ranking.id) : _selectedRankings.remove(ranking.id); })),
        ],
        for (final tournament in _sources) ...[
          Padding(padding: const EdgeInsets.only(top: 12, bottom: 6), child: Text(tournament.title, style: Theme.of(context).textTheme.titleMedium)),
          for (final participant in tournament.participants)
            Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ChallongeTournament.name(participant), style: Theme.of(context).textTheme.titleSmall),
              DropdownButtonFormField<String?>(
                initialValue: _assignments[_key(tournament, participant)],
                decoration: const InputDecoration(labelText: 'Lokalen Spieler zuweisen', isDense: true),
                items: [const DropdownMenuItem<String?>(value: null, child: Text('Nicht verknüpfen')), ..._players.map((p) => DropdownMenuItem<String?>(value: p.id, child: Text(p.displayName)))],
                onChanged: (value) => setState(() => _assignments[_key(tournament, participant)] = value),
              ),
              CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Zuordnung für künftige Importe merken'), value: _remember.contains(_key(tournament, participant)), onChanged: _assignments[_key(tournament, participant)] == null ? null : (value) => setState(() { value == true ? _remember.add(_key(tournament, participant)) : _remember.remove(_key(tournament, participant)); })),
            ]))),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _busy ? null : _import, icon: const Icon(Icons.move_to_inbox), label: const Text('Ausgewählte Turniere lokal übernehmen')),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              _message!,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: _message!.startsWith('Import fehlgeschlagen') || _message!.startsWith('Bitte')
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
      ],
    ]),
  );
}
