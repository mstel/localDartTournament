import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../shared/persistence/app_data_directory.dart';

/// Kleine Herzschlag-Datei für den separaten Zweitmonitor-Prozess.
///
/// Die Prozess-Referenz im Hauptfenster geht verloren, wenn die Seite neu
/// erstellt oder die App neu gestartet wird. Der Monitor schreibt stattdessen
/// regelmäßig seinen aktiven Turniernamen in diesen Datei-Eintrag; das
/// Hauptfenster kann dadurch unabhängig von der Prozess-Instanz erkennen, dass
/// eine Anzeige läuft, und den Info-Toggle aktivieren.
class SecondScreenSessionRegistry {
  SecondScreenSessionRegistry._();

  static const heartbeatTimeout = Duration(seconds: 8);

  static Future<File> _file() async {
    final directory = await appDataDirectory(includeSupabaseAccount: false);
    return File(p.join(directory.path, 'second-screen-session.json'));
  }

  static Future<void> heartbeat(String tournamentId) async {
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode({
          'tournamentId': tournamentId,
          'updatedAt': DateTime.now().toIso8601String(),
        }),
      );
    } catch (_) {
      // Ein vorübergehender Schreibfehler darf die Anzeige nicht stören.
    }
  }

  static Future<bool> isActive(String tournamentId) async {
    try {
      final file = await _file();
      if (!await file.exists()) return false;
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (data['tournamentId'] != tournamentId) return false;
      final updatedAt = DateTime.tryParse(data['updatedAt'] as String? ?? '');
      if (updatedAt == null) return false;
      return DateTime.now().difference(updatedAt) < heartbeatTimeout;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clear(String tournamentId) async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (data['tournamentId'] == tournamentId) {
        await file.delete();
      }
    } catch (_) {
      // Beim Schließen ist ein Fehler unkritisch; der Herzschlag läuft ab.
    }
  }
}
