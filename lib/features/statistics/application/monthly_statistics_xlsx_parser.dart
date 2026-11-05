import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

class MonthlyStatisticsImportRow {
  const MonthlyStatisticsImportRow({
    required this.sourceRow,
    required this.playerName,
    required this.month,
    required this.threeDartAverage,
    required this.firstNineAverage,
    required this.legs,
    required this.matches,
    this.checkoutPercentage,
  });

  final int sourceRow;
  final String playerName;
  final String month;
  final double threeDartAverage;
  final double firstNineAverage;
  final double? checkoutPercentage;
  final int legs;
  final int matches;
}

class MonthlyStatisticsImportDocument {
  const MonthlyStatisticsImportDocument({required this.rows});

  final List<MonthlyStatisticsImportRow> rows;

  List<String> get playerNames =>
      rows.map((row) => row.playerName).toSet().toList()..sort(
        (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
      );
}

class MonthlyStatisticsXlsxParser {
  const MonthlyStatisticsXlsxParser();

  static const maximumBytes = 20 * 1024 * 1024;
  static const _spreadsheetNs =
      'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  static const _officeRelNs =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  static const _packageRelNs =
      'http://schemas.openxmlformats.org/package/2006/relationships';
  static const _maximumRows = 10000;

  MonthlyStatisticsImportDocument parse(List<int> bytes) {
    if (bytes.length > maximumBytes) {
      throw const FormatException('Die Excel-Datei ist größer als 20 MB.');
    }

    try {
      final archive = ZipDecoder().decodeBytes(Uint8List.fromList(bytes));
      final uncompressedBytes = archive.files.fold<int>(
        0,
        (sum, file) => sum + file.size,
      );
      if (uncompressedBytes > maximumBytes * 8) {
        throw const FormatException(
          'Der entpackte Inhalt der Excel-Datei ist zu groß.',
        );
      }

      final workbook = _xml(archive, 'xl/workbook.xml');
      final workbookRels = _xml(archive, 'xl/_rels/workbook.xml.rels');
      final sheet = workbook
          .findAllElements('sheet', namespaceUri: _spreadsheetNs)
          .firstOrNull;
      final relationshipId = sheet?.getAttribute(
        'id',
        namespaceUri: _officeRelNs,
      );
      if (relationshipId == null) {
        throw const FormatException(
          'Die Excel-Datei enthält kein Tabellenblatt.',
        );
      }

      String? target;
      for (final relation in workbookRels.findAllElements(
        'Relationship',
        namespaceUri: _packageRelNs,
      )) {
        if (relation.getAttribute('Id') == relationshipId) {
          target = relation.getAttribute('Target');
          break;
        }
      }
      if (target == null || target.isEmpty) {
        throw const FormatException(
          'Das erste Tabellenblatt konnte nicht gefunden werden.',
        );
      }

      final sheetPath = target.startsWith('/')
          ? target.substring(1)
          : path.posix.normalize(path.posix.join('xl', target));
      final worksheet = _xml(archive, sheetPath);
      final sharedStrings = _sharedStrings(archive);
      final rows = worksheet
          .findAllElements('row', namespaceUri: _spreadsheetNs)
          .toList();
      if (rows.isEmpty) {
        throw const FormatException('Das Tabellenblatt ist leer.');
      }

      final header = _readCells(rows.first, sharedStrings);
      final columns = _headerColumns(header);
      if (rows.length - 1 > _maximumRows) {
        throw const FormatException(
          'Das Tabellenblatt enthält mehr als 10.000 Datenzeilen.',
        );
      }

      final parsedRows = <MonthlyStatisticsImportRow>[];
      final seen = <String>{};
      for (final row in rows.skip(1)) {
        final rowNumber = int.tryParse(row.getAttribute('r') ?? '') ?? 0;
        final cells = _readCells(row, sharedStrings);
        if (cells.values.every((value) => value.trim().isEmpty)) continue;

        final playerName = _value(cells, columns.player).trim();
        if (playerName.isEmpty || playerName.length > 200) {
          throw FormatException(
            'Zeile $rowNumber: Spielername fehlt oder ist zu lang.',
          );
        }
        final month = _parseMonth(_value(cells, columns.month), rowNumber);
        final key = '${_normalizeName(playerName)}|$month';
        if (!seen.add(key)) {
          throw FormatException(
            'Zeile $rowNumber: Spieler und Monat kommen mehrfach vor ($playerName, $month).',
          );
        }

        parsedRows.add(
          MonthlyStatisticsImportRow(
            sourceRow: rowNumber,
            playerName: playerName,
            month: month,
            threeDartAverage: _number(
              _value(cells, columns.threeDartAverage),
              '3-Dart Average',
              rowNumber,
            ),
            firstNineAverage: _number(
              _value(cells, columns.firstNineAverage),
              'First 9',
              rowNumber,
            ),
            checkoutPercentage: columns.checkoutPercentage == null
                ? null
                : _optionalNumber(
                    _value(cells, columns.checkoutPercentage!),
                    'Checkout Quote %',
                    rowNumber,
                    maximum: 100,
                  ),
            legs: _count(_value(cells, columns.legs), 'Anzahl Legs', rowNumber),
            matches: _count(
              _value(cells, columns.matches),
              'Anzahl Partien',
              rowNumber,
            ),
          ),
        );
      }
      if (parsedRows.isEmpty) {
        throw const FormatException('Es wurden keine Monatsdaten gefunden.');
      }
      return MonthlyStatisticsImportDocument(
        rows: List.unmodifiable(parsedRows),
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Excel-Datei konnte nicht gelesen werden: $error');
    }
  }

  XmlDocument _xml(Archive archive, String name) {
    final entry = archive.files.where((file) => file.name == name).firstOrNull;
    if (entry == null || !entry.isFile || entry.size > maximumBytes) {
      throw FormatException('Excel-Datei enthält keine gültige Datei "$name".');
    }
    final content = entry.readBytes();
    if (content == null) {
      throw FormatException('Excel-Datei "$name" konnte nicht gelesen werden.');
    }
    return XmlDocument.parse(utf8.decode(content, allowMalformed: false));
  }

  List<String> _sharedStrings(Archive archive) {
    if (!archive.files.any((file) => file.name == 'xl/sharedStrings.xml')) {
      return const [];
    }
    final document = _xml(archive, 'xl/sharedStrings.xml');
    return [
      for (final item in document.findAllElements(
        'si',
        namespaceUri: _spreadsheetNs,
      ))
        item
            .findAllElements('t', namespaceUri: _spreadsheetNs)
            .map((text) => text.innerText)
            .join(),
    ];
  }

  Map<String, String> _readCells(XmlElement row, List<String> sharedStrings) {
    final values = <String, String>{};
    for (final cell in row.findElements('c', namespaceUri: _spreadsheetNs)) {
      final reference = cell.getAttribute('r') ?? '';
      final match = RegExp(r'^([A-Z]+)').firstMatch(reference);
      if (match == null) continue;

      final type = cell.getAttribute('t');
      if (type == 'inlineStr') {
        values[match.group(1)!] = cell
            .findAllElements('t', namespaceUri: _spreadsheetNs)
            .map((text) => text.innerText)
            .join();
        continue;
      }

      final valueElement = cell
          .findElements('v', namespaceUri: _spreadsheetNs)
          .firstOrNull;
      var value = valueElement?.innerText ?? '';
      if (type == 's' && value.isNotEmpty) {
        final index = int.tryParse(value);
        if (index == null || index < 0 || index >= sharedStrings.length) {
          throw FormatException(
            'Ungültiger gemeinsamer Textwert in $reference.',
          );
        }
        value = sharedStrings[index];
      }
      values[match.group(1)!] = value;
    }
    return values;
  }

  _MonthlyColumns _headerColumns(Map<String, String> values) {
    final indexes = <String, String>{
      for (final entry in values.entries)
        entry.value.trim().toLowerCase(): entry.key,
    };
    String required(String name) {
      final column = indexes[name.toLowerCase()];
      if (column == null) {
        throw FormatException('Erforderliche Excel-Spalte fehlt: "$name".');
      }
      return column;
    }

    return _MonthlyColumns(
      player: required('Spieler'),
      month: required('Monat'),
      threeDartAverage: required('3-Dart Average'),
      firstNineAverage: required('First 9'),
      checkoutPercentage: indexes['checkout quote %'],
      legs: required('Anzahl Legs'),
      matches: required('Anzahl Partien'),
    );
  }

  String _value(Map<String, String> values, String column) =>
      values[column] ?? '';

  String _parseMonth(String value, int row) {
    final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(value.trim());
    if (match == null) {
      throw FormatException('Zeile $row: Monat muss im Format JJJJ-MM stehen.');
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    if (year < 1900 || month < 1 || month > 12) {
      throw FormatException('Zeile $row: ungültiger Monat "${value.trim()}".');
    }
    return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
  }

  double _number(String value, String label, int row) {
    final number = _optionalNumber(value, label, row);
    if (number == null) {
      throw FormatException('Zeile $row: "$label" darf nicht leer sein.');
    }
    return number;
  }

  double? _optionalNumber(
    String value,
    String label,
    int row, {
    double? maximum,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final number = double.tryParse(trimmed.replaceAll(',', '.'));
    if (number == null ||
        !number.isFinite ||
        number < 0 ||
        (maximum != null && number > maximum)) {
      throw FormatException('Zeile $row: ungültiger Wert für "$label".');
    }
    return number;
  }

  int _count(String value, String label, int row) {
    final number = _optionalNumber(value, label, row);
    if (number == null || number != number.truncateToDouble()) {
      throw FormatException('Zeile $row: "$label" muss eine ganze Zahl sein.');
    }
    return number.toInt();
  }

  String _normalizeName(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

class _MonthlyColumns {
  const _MonthlyColumns({
    required this.player,
    required this.month,
    required this.threeDartAverage,
    required this.firstNineAverage,
    required this.checkoutPercentage,
    required this.legs,
    required this.matches,
  });

  final String player;
  final String month;
  final String threeDartAverage;
  final String firstNineAverage;
  final String? checkoutPercentage;
  final String legs;
  final String matches;
}
