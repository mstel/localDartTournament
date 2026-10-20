import '../../../shared/persistence/storage_access.dart';
import 'dart:convert';
import 'dart:io';

import '../../../shared/persistence/app_data_directory.dart';

import '../../tournaments/domain/tournament_planning_parameters.dart';

class PlanningSettingsStorage {
  PlanningSettingsStorage({this.file});
  final File? file;

  Future<File> storageFile() => _file();

  Future<File> _file() async {
    if (file != null) return file!;
    final directory = await appDataDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}planning_settings.json',
    );
  }

  Future<TournamentPlanningParameters> load() async {
    return StorageAccess.run(() async {
      final target = await _file();
      if (!await target.exists()) return const TournamentPlanningParameters();
      final json = jsonDecode(await target.readAsString());
      if (json is! Map<String, dynamic> ||
          (json['schemaVersion'] != 1 &&
              json['schemaVersion'] != 2 &&
              json['schemaVersion'] != 3) ||
          json['parameters'] is! Map<String, dynamic>) {
        throw FormatException(
          'Unbekanntes Einstellungsformat '
          '(Version ${json is Map ? json['schemaVersion'] ?? 'fehlt' : 'ungültig'}). '
          'Die Originaldatei wurde nicht verändert.',
        );
      }
      // Version 1 fixed leg counts are retired; retain all other parameters.
      return TournamentPlanningParameters.fromJson(
        json['parameters'] as Map<String, dynamic>,
      );
    });
  }

  Future<void> save(TournamentPlanningParameters parameters) async {
    return StorageAccess.run(() async {
      final target = await _file();
      await target.parent.create(recursive: true);
      if (await target.exists()) {
        await load();
        await target.copy('${target.path}.bak');
      }
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({'schemaVersion': 3, 'parameters': parameters.toJson()}),
        flush: true,
      );
      await temporary.rename(target.path);
      StorageAccess.markLocalDataChanged();
    });
  }
}
