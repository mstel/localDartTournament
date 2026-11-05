import 'package:flutter/material.dart';

import 'monthly_statistics_import_page.dart';

class MonthlyStatisticsImportPanel extends StatelessWidget {
  const MonthlyStatisticsImportPanel({super.key});

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.table_view_outlined),
      title: const Text('Monatsstatistiken aus Excel importieren'),
      subtitle: const Text(
        'Spieler und Monat zuordnen, Werte prüfen und sicher übernehmen.',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const MonthlyStatisticsImportPage(),
        ),
      ),
    ),
  );
}
