import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../shared/persistence/app_data_directory.dart';

/// Kleiner Heartbeat, damit der Hauptmonitor erkennt, ob die
/// Team-Game-Zweitmonitoransicht gerade geöffnet ist.
class TeamGameDisplaySessionRegistry {
  TeamGameDisplaySessionRegistry({
    Future<Directory> Function()? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? _defaultDirectory;

  static const fileName = 'team_game_display_session.json';
  static const heartbeatTimeout = Duration(seconds: 8);

  final Future<Directory> Function() _directoryProvider;

  static Future<Directory> _defaultDirectory() =>
      appDataDirectory(includeSupabaseAccount: false);

  Future<File> _file() async {
    final directory = await _directoryProvider();
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, fileName));
  }

  Future<void> heartbeat() async {
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode({'updatedAt': DateTime.now().toUtc().toIso8601String()}),
      );
    } catch (_) {
      // Ein Monitor-Heartbeat darf den Spielbetrieb niemals blockieren.
    }
  }

  Future<bool> isActive() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return false;
      final decoded = jsonDecode(await file.readAsString()) as Map;
      final updatedAt = DateTime.tryParse(decoded['updatedAt']?.toString() ?? '');
      if (updatedAt == null) return false;
      return DateTime.now().difference(updatedAt.toLocal()) < heartbeatTimeout;
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    try {
      final file = await _file();
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // Siehe heartbeat(): keine Fachlogik von einer Monitor-Datei abhaengig machen.
    }
  }
}
