import 'package:flutter/material.dart';

import 'app/app_bootstrap.dart';
import 'app/storage_session_root.dart';

import 'app/second_screen_standalone_app.dart';
import 'app/team_game_standalone_app.dart';

export 'app/dart_tournament_app.dart';
export 'features/tournaments/application/tournament_creation_controller.dart';
export 'features/tournaments/application/tournament_run_controller.dart';
export 'features/tournaments/data/tournament_storage.dart';
export 'features/tournaments/domain/engines/tournament_engine.dart';
export 'features/tournaments/domain/tournament_models.dart'
    hide defaultGroupTieBreakers, groupLabel;
export 'tournament_workspace.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--team-game-display')) {
    await AppBootstrap.initializeSecondaryDisplay(args: args);
    runApp(const TeamGameStandaloneApp());
    return;
  }

  final secondScreenIndex = args.indexOf('--second-screen');
  if (secondScreenIndex != -1) {
    String? tournamentId;
    if (secondScreenIndex + 1 < args.length &&
        !args[secondScreenIndex + 1].startsWith('--')) {
      tournamentId = args[secondScreenIndex + 1];
    }
    await AppBootstrap.initializeSecondaryDisplay(args: args);
    runApp(SecondScreenStandaloneApp(tournamentId: tournamentId));
    return;
  }

  final startupError = await AppBootstrap.initialize(args: args);
  runApp(StorageSessionRoot(startupError: startupError));
}

