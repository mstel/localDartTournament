import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../shared/persistence/app_data_directory.dart';
import '../domain/team_game_state.dart';

/// Versionierte, kleine Signaturdatei für die Kommunikation mit dem
/// Zweitmonitor. Es werden bewusst keine Turnierdaten oder Punkte gespeichert.
class TeamGameSignalRepository {
  TeamGameSignalRepository({
    Future<Directory> Function()? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? _defaultDirectory;

  static const fileName = 'team_game_session.json';

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

  Future<TeamGameState?> load() async {
    final file = await _file();
    if (!file.existsSync()) return null;
    final content = await file.readAsString();
    if (content.trim().isEmpty) return null;
    return TeamGameState.fromJsonString(content);
  }

  Future<void> save(TeamGameState state) async {
    final file = await _file();
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(state.toJsonString());
    await temporary.rename(file.path);
  }

  Future<void> clear() async {
    final file = await _file();
    if (file.existsSync()) await file.delete();
  }
}
