import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/adaptive_content.dart';
import '../../tournaments/data/app_database.dart';
import '../application/monthly_statistics_import_service.dart';
import '../application/monthly_statistics_xlsx_parser.dart';

class MonthlyStatisticsImportPage extends StatefulWidget {
  const MonthlyStatisticsImportPage({super.key});

  @override
  State<MonthlyStatisticsImportPage> createState() =>
      _MonthlyStatisticsImportPageState();
}

class _MonthlyStatisticsImportPageState
    extends State<MonthlyStatisticsImportPage> {
  final _database = LocalAppDatabase();
  final _parser = const MonthlyStatisticsXlsxParser();
  MonthlyStatisticsImportDocument? _document;
  List<PlayerProfile> _profiles = const [];
  final Map<String, String> _profileIdBySourceName = {};
  bool _loading = false;
  bool _saving = false;
  String? _message;
  bool _failed = false;

  Future<void> _selectWorkbook() async {
    final selected = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Excel-Arbeitsmappe',
          extensions: ['xlsx'],
          uniformTypeIdentifiers: ['org.openxmlformats.spreadsheetml.sheet'],
        ),
      ],
      confirmButtonText: 'Excel-Datei prüfen',
    );
    if (selected == null || !mounted) return;

    setState(() {
      _loading = true;
      _message = null;
      _failed = false;
    });
    try {
      if (await selected.length() > MonthlyStatisticsXlsxParser.maximumBytes) {
        throw const FormatException('Die Excel-Datei ist größer als 20 MB.');
      }
      final document = _parser.parse(await selected.readAsBytes());
      final profiles = await _database.loadPlayerProfiles();
      if (!mounted) return;
      _profileIdBySourceName.clear();
      for (final name in document.playerNames) {
        final matches = profiles
            .where(
              (profile) =>
                  MonthlyStatisticsImportService.normalizePlayerName(
                    profile.displayName,
                  ) ==
                  MonthlyStatisticsImportService.normalizePlayerName(name),
            )
            .toList();
        if (matches.length == 1) {
          _profileIdBySourceName[name] = matches.single.id;
        }
      }
      setState(() {
        _document = document;
        _profiles = profiles;
        _message = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _document = null;
        _message = error is FormatException
            ? error.message
            : 'Die Excel-Datei konnte nicht geprüft werden: $error';
        _failed = true;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Set<String> get _duplicateTargetKeys {
    final document = _document;
    if (document == null) return const {};
    final counts = <String, int>{};
    for (final row in document.rows) {
      final profileId = _profileIdBySourceName[row.playerName];
      if (profileId == null) continue;
      final key = '$profileId|${row.month}';
      counts.update(key, (count) => count + 1, ifAbsent: () => 1);
    }
    return {
      for (final entry in counts.entries)
        if (entry.value > 1) entry.key,
    };
  }

  bool get _hasCompleteMappings =>
      _document != null &&
      _document!.playerNames.every(
        (name) => _profileIdBySourceName[name] != null,
      ) &&
      _duplicateTargetKeys.isEmpty;

  Future<void> _import() async {
    final document = _document;
    if (document == null || !_hasCompleteMappings || _saving) return;
    final existing = await _database.loadMonthlyPlayerPerformances({
      ..._profileIdBySourceName.values,
    });
    final existingKeys = {
      for (final row in existing) '${row.playerProfileId}|${row.month}',
    };
    final replacedRows = document.rows.where((row) {
      final profileId = _profileIdBySourceName[row.playerName]!;
      return existingKeys.contains('$profileId|${row.month}');
    }).length;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Monatswerte importieren?'),
        content: Text(
          '${document.rows.length} Monatszeilen für '
          '${document.playerNames.length} Teilnehmer werden gespeichert. '
          '$replacedRows vorhandene Teilnehmer-Monate werden ersetzt; alle '
          'anderen gespeicherten Monate bleiben erhalten. Die Werte werden '
          'als Monatsdurchschnitte gespeichert, nicht als rekonstruierte '
          'Einzelspiele. Checkout bleibt leer, sofern die Excel-Zelle leer ist.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Importieren'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _message = null;
      _failed = false;
    });
    try {
      final result = await MonthlyStatisticsImportService(database: _database)
          .importDocument(
            document: document,
            profileIdBySourceName: Map.unmodifiable(_profileIdBySourceName),
          );
      if (!mounted) return;
      setState(() {
        _message =
            '${result.importedRows} Monatszeilen gespeichert. '
            '${result.replacedRows} vorhandene Monatszeilen aktualisiert. '
            'Die Werte sind jetzt lokal in der App und werden in den '
            'Teilnehmerstatistiken angezeigt. Für Supabase gehe zurück zu '
            'Einstellungen > Daten und nutze „Lokalen Stand hochladen“. '
            'Dabei wird nach Bestätigung das Cloud-Backup ersetzt.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Import fehlgeschlagen: $error';
        _failed = true;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Monatsstatistiken importieren')),
    body: AdaptiveContentList(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Importiert pro Teilnehmer und Monat 3-Dart Average, First 9, Partien '
          'und Legs. Die Monatswerte werden getrennt von Einzelspielen '
          'gespeichert; leere Checkout-Werte bleiben leer.',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _loading || _saving ? null : _selectWorkbook,
          icon: const Icon(Icons.upload_file_outlined),
          label: Text(_loading ? 'Prüfe Excel …' : 'Excel-Datei auswählen'),
        ),
        if (_loading || _saving) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_document case final document?) ...[
          const SizedBox(height: 20),
          Text(
            'Vorschau: ${document.rows.length} Monatszeilen · '
            '${document.playerNames.length} Teilnehmer',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Zeitraum: ${document.rows.map((row) => row.month).reduce((a, b) => a.compareTo(b) < 0 ? a : b)}'
            ' bis ${document.rows.map((row) => row.month).reduce((a, b) => a.compareTo(b) > 0 ? a : b)}',
          ),
          const SizedBox(height: 8),
          const Text(
            'Vorschau der ersten 10 Zeilen (Tabelle horizontal scrollbar):',
          ),
          _ImportPreviewTable(rows: document.rows.take(10).toList()),
          const SizedBox(height: 12),
          for (final sourceName in document.playerNames)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                initialValue: _profileIdBySourceName[sourceName],
                isExpanded: true,
                menuMaxHeight: 420,
                decoration: InputDecoration(
                  labelText: 'Excel: $sourceName',
                  border: const OutlineInputBorder(),
                  helperText: _profileIdBySourceName[sourceName] == null
                      ? 'Teilnehmerprofil zuordnen'
                      : null,
                ),
                items: [
                  for (final profile in _profiles)
                    DropdownMenuItem(
                      value: profile.id,
                      child: Text(profile.displayName),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (profileId) => setState(() {
                        if (profileId == null) {
                          _profileIdBySourceName.remove(sourceName);
                        } else {
                          _profileIdBySourceName[sourceName] = profileId;
                        }
                      }),
              ),
            ),
          if (_duplicateTargetKeys.isNotEmpty)
            Text(
              'Mehrere Excel-Namen sind demselben Teilnehmer und Monat '
              'zugeordnet. Bitte ändere die Zuordnung vor dem Import.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving || !_hasCompleteMappings ? null : _import,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Monatswerte übernehmen'),
          ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 16),
          SelectableText(
            _message!,
            style: TextStyle(
              color: _failed ? Theme.of(context).colorScheme.error : null,
            ),
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          'Der Import schreibt nichts direkt in Supabase. Die Einträge sind '
          'Teil der lokalen App-Datenbank und des App-Backups; erst ein '
          'bewusster Upload über „Lokalen Stand hochladen“ überträgt den '
          'neuen Stand in dein Supabase-Backup und ersetzt dort den bisherigen '
          'Cloud-Datenstand.',
        ),
      ],
    ),
  );
}

class _ImportPreviewTable extends StatelessWidget {
  const _ImportPreviewTable({required this.rows});

  final List<MonthlyStatisticsImportRow> rows;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      columns: const [
        DataColumn(label: Text('Teilnehmer')),
        DataColumn(label: Text('Monat')),
        DataColumn(label: Text('3-Dart Ø'), numeric: true),
        DataColumn(label: Text('First 9'), numeric: true),
        DataColumn(label: Text('Checkout'), numeric: true),
        DataColumn(label: Text('Legs'), numeric: true),
        DataColumn(label: Text('Partien'), numeric: true),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(Text(row.playerName)),
              DataCell(Text(row.month)),
              DataCell(Text(row.threeDartAverage.toStringAsFixed(2))),
              DataCell(Text(row.firstNineAverage.toStringAsFixed(2))),
              DataCell(
                Text(
                  row.checkoutPercentage == null
                      ? '–'
                      : '${row.checkoutPercentage!.toStringAsFixed(1)} %',
                ),
              ),
              DataCell(Text('${row.legs}')),
              DataCell(Text('${row.matches}')),
            ],
          ),
      ],
    ),
  );
}
