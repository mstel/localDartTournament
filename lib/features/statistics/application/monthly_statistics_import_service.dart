import '../domain/monthly_player_performance.dart';
import '../../tournaments/data/app_database.dart';
import 'monthly_statistics_xlsx_parser.dart';

class MonthlyStatisticsImportResult {
  const MonthlyStatisticsImportResult({
    required this.importedRows,
    required this.replacedRows,
  });

  final int importedRows;
  final int replacedRows;
}

class MonthlyStatisticsImportService {
  const MonthlyStatisticsImportService({required this.database});

  final LocalAppDatabase database;

  static String normalizePlayerName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  Future<MonthlyStatisticsImportResult> importDocument({
    required MonthlyStatisticsImportDocument document,
    required Map<String, String> profileIdBySourceName,
  }) async {
    final records = <MonthlyPlayerPerformance>[];
    final keys = <String>{};
    for (final row in document.rows) {
      final profileId = profileIdBySourceName[row.playerName];
      if (profileId == null || profileId.isEmpty) {
        throw FormatException(
          'Kein Teilnehmerprofil für "${row.playerName}" ausgewählt.',
        );
      }
      if (!keys.add('$profileId|${row.month}')) {
        throw FormatException(
          'Mehrere Excel-Zeilen wurden demselben Teilnehmer und Monat zugeordnet '
          '(${row.playerName}, ${row.month}).',
        );
      }
      records.add(
        MonthlyPlayerPerformance(
          playerProfileId: profileId,
          sourcePlayerName: row.playerName,
          month: row.month,
          threeDartAverage: row.threeDartAverage,
          firstNineAverage: row.firstNineAverage,
          checkoutPercentage: row.checkoutPercentage,
          legs: row.legs,
          matches: row.matches,
        ),
      );
    }

    final existing = await database.loadMonthlyPlayerPerformances({
      for (final record in records) record.playerProfileId,
    });
    final existingKeys = {
      for (final record in existing)
        '${record.playerProfileId}|${record.month}',
    };
    await database.saveMonthlyPlayerPerformances(records);
    return MonthlyStatisticsImportResult(
      importedRows: records.length,
      replacedRows: records
          .where(
            (record) => existingKeys.contains(
              '${record.playerProfileId}|${record.month}',
            ),
          )
          .length,
    );
  }
}
