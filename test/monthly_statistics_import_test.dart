import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dart_tournament_manager/features/statistics/application/monthly_statistics_import_service.dart';
import 'package:dart_tournament_manager/features/statistics/application/monthly_statistics_xlsx_parser.dart';
import 'package:dart_tournament_manager/features/statistics/domain/local_statistics.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _xlsx({
  String rows =
      '<row r="2"><c r="A2" t="inlineStr"><is><t>Alex Spieler</t></is></c>'
      '<c r="B2" t="inlineStr"><is><t>2026-07</t></is></c>'
      '<c r="C2"><v>36.92</v></c><c r="D2"><v>42.76</v></c>'
      '<c r="E2"></c><c r="F2"><v>26</v></c><c r="G2"><v>13</v></c></row>',
}) {
  final archive = Archive()
    ..add(
      ArchiveFile.string(
        'xl/workbook.xml',
        '''<?xml version="1.0" encoding="UTF-8"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets><sheet name="Monat" sheetId="1" r:id="rId1"/></sheets>
        </workbook>''',
      ),
    )
    ..add(
      ArchiveFile.string(
        'xl/_rels/workbook.xml.rels',
        '''<?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/>
        </Relationships>''',
      ),
    )
    ..add(
      ArchiveFile.string(
        'xl/worksheets/sheet1.xml',
        '''<?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
            <row r="1">
              <c r="A1" t="inlineStr"><is><t>Spieler</t></is></c>
              <c r="B1" t="inlineStr"><is><t>Monat</t></is></c>
              <c r="C1" t="inlineStr"><is><t>3-Dart Average</t></is></c>
              <c r="D1" t="inlineStr"><is><t>First 9</t></is></c>
              <c r="E1" t="inlineStr"><is><t>Checkout Quote %</t></is></c>
              <c r="F1" t="inlineStr"><is><t>Anzahl Legs</t></is></c>
              <c r="G1" t="inlineStr"><is><t>Anzahl Partien</t></is></c>
            </row>
            $rows
          </sheetData>
        </worksheet>''',
      ),
    );
  return ZipEncoder().encode(archive);
}

void main() {
  test('reads monthly averages and leaves empty checkout values null', () {
    final document = const MonthlyStatisticsXlsxParser().parse(_xlsx());

    expect(document.rows, hasLength(1));
    final row = document.rows.single;
    expect(row.sourceRow, 2);
    expect(row.playerName, 'Alex Spieler');
    expect(row.month, '2026-07');
    expect(row.threeDartAverage, 36.92);
    expect(row.firstNineAverage, 42.76);
    expect(row.checkoutPercentage, isNull);
    expect(row.legs, 26);
    expect(row.matches, 13);
  });

  test('rejects duplicate player-month rows before any import', () {
    final bytes = _xlsx(
      rows:
          '<row r="2"><c r="A2" t="inlineStr"><is><t>Alex Spieler</t></is></c>'
          '<c r="B2" t="inlineStr"><is><t>2026-07</t></is></c>'
          '<c r="C2"><v>36.92</v></c><c r="D2"><v>42.76</v></c>'
          '<c r="E2"></c><c r="F2"><v>26</v></c><c r="G2"><v>13</v></c></row>'
          '<row r="3"><c r="A3" t="inlineStr"><is><t>Alex Spieler</t></is></c>'
          '<c r="B3" t="inlineStr"><is><t>2026-07</t></is></c>'
          '<c r="C3"><v>38</v></c><c r="D3"><v>44</v></c>'
          '<c r="E3"></c><c r="F3"><v>8</v></c><c r="G3"><v>4</v></c></row>',
    );

    expect(
      () => const MonthlyStatisticsXlsxParser().parse(bytes),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('mehrfach'),
        ),
      ),
    );
  });

  test('maps rows to player profiles and reimport updates same month', () async {
    final directory = await Directory.systemTemp.createTemp(
      'monthly_statistics_import_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = LocalAppDatabase(baseDirectory: directory);
    final profile = await database.createPlayerProfile(
      displayName: 'Alex Spieler',
    );
    final document = const MonthlyStatisticsXlsxParser().parse(_xlsx());
    final first = await MonthlyStatisticsImportService(database: database)
        .importDocument(
          document: document,
          profileIdBySourceName: {'Alex Spieler': profile.id},
        );
    expect(first.importedRows, 1);
    expect(first.replacedRows, 0);

    final secondDocument = const MonthlyStatisticsXlsxParser().parse(
      _xlsx(
        rows:
            '<row r="2"><c r="A2" t="inlineStr"><is><t>Alex Spieler</t></is></c>'
            '<c r="B2" t="inlineStr"><is><t>2026-07</t></is></c>'
            '<c r="C2"><v>40</v></c><c r="D2"><v>47</v></c>'
            '<c r="E2"></c><c r="F2"><v>30</v></c><c r="G2"><v>15</v></c></row>',
      ),
    );
    final second = await MonthlyStatisticsImportService(database: database)
        .importDocument(
          document: secondDocument,
          profileIdBySourceName: {'Alex Spieler': profile.id},
        );

    expect(second.importedRows, 1);
    expect(second.replacedRows, 1);
    final stored = await database.loadMonthlyPlayerPerformances({
      profile.id,
    }, year: 2026);
    expect(stored, hasLength(1));
    expect(stored.single.threeDartAverage, 40);
    expect(stored.single.firstNineAverage, 47);
    expect(stored.single.checkoutPercentage, isNull);
    expect(stored.single.legs, 30);
    expect(stored.single.matches, 15);
    final statistics = await LocalStatisticsService(
      database: database,
    ).forPlayersFromTournaments({profile.id}, const []);
    expect(statistics.monthlyPerformances, hasLength(1));
    expect(statistics.matches, 0);
  });

  test(
    'rolls back the entire import if any profile mapping is invalid',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'monthly_statistics_import_rollback_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final database = LocalAppDatabase(baseDirectory: directory);
      final profile = await database.createPlayerProfile(
        displayName: 'Alex Spieler',
      );
      final document = const MonthlyStatisticsXlsxParser().parse(_xlsx());

      await expectLater(
        MonthlyStatisticsImportService(database: database).importDocument(
          document: document,
          profileIdBySourceName: {'Alex Spieler': 'missing-profile'},
        ),
        throwsStateError,
      );
      expect(
        await database.loadMonthlyPlayerPerformances({profile.id}),
        isEmpty,
      );
    },
  );
}
