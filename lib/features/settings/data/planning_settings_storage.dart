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
      final version = json is Map<String, dynamic>
          ? json['schemaVersion']
          : null;
      if (json is! Map<String, dynamic> ||
          (version != 1 && version != 2 && version != 3) ||
          json['parameters'] is! Map<String, dynamic>) {
        throw const FormatException('Unbekanntes Einstellungsformat');
      }
      final parameters = Map<String, dynamic>.from(
        json['parameters'] as Map<String, dynamic>,
      );
      if (version != 3) {
        _migrateDefault(parameters, 'minutes301DoubleOut', 8, 3);
        _migrateDefault(parameters, 'minutes501DoubleOut', 10, 5);
        _migrateDefault(parameters, 'minutes301SingleOut', 5, 2);
        _migrateDefault(parameters, 'minutes501SingleOut', 7, 4);
      }
      return TournamentPlanningParameters.fromJson(parameters);
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

  void _migrateDefault(
    Map<String, dynamic> parameters,
    String key,
    int previousDefault,
    int currentDefault,
  ) {
    if (parameters[key] == previousDefault) {
      parameters[key] = currentDefault;
    }
  }
}
