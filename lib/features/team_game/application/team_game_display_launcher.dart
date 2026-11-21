import 'dart:async';
import 'dart:io' show Platform, Process, pid;

/// Abstraktion, damit Setup-Tests keinen echten Zweitmonitor-Prozess starten.
abstract class TeamGameDisplayLauncher {
  const TeamGameDisplayLauncher();

  bool get supportsSeparateWindow =>
      !Platform.isAndroid && !Platform.isIOS;

  /// Öffnet die Anzeige. Liefert `false`, wenn ein Fullscreen-Fallback
  /// innerhalb der App erforderlich ist.
  Future<bool> open();

  Future<void> close() async {}
}

class ProcessTeamGameDisplayLauncher extends TeamGameDisplayLauncher {
  Process? _process;

  @override
  Future<bool> open() async {
    if (!supportsSeparateWindow) return false;
    try {
      _process = await Process.start(
        Platform.resolvedExecutable,
        <String>['--team-game-display', '--parent-pid=$pid'],
      );
      unawaited(_process!.stdout.drain<void>());
      unawaited(_process!.stderr.drain<void>());
      unawaited(_process!.exitCode.then((_) => _process = null));
      return true;
    } catch (_) {
      _process = null;
      return false;
    }
  }

  @override
  Future<void> close() async {
    final process = _process;
    _process = null;
    if (process == null) return;
    try {
      if (process.kill()) await process.exitCode;
    } catch (_) {
      // Der Prozess ist möglicherweise bereits beendet.
    }
  }
}
