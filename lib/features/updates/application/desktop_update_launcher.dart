import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Installs beside the original application. Old shortcuts forward only after
/// the new application completed bootstrap and acknowledged the new version.
class DesktopUpdateLauncher {
  static Future<Directory> root() async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'desktop_updates'),
  );
  static Future<String?> readFailureDiagnostic({Directory? base}) async {
    final updateRoot = base ?? await root();
    final file = File(p.join(updateRoot.path, 'update-failure.txt'));
    if (!await file.exists()) return null;
    final diagnostic = (await file.readAsString()).trim();
    return diagnostic.isEmpty ? null : diagnostic;
  }

  static String executableName() => Platform.isWindows
      ? 'dart_tournament_manager.exe'
      : 'dart_tournament_manager';
  static bool validId(String id) =>
      RegExp(r'^build-[0-9]+-[0-9]+$').hasMatch(id);

  static Future<String?> target(Directory base, String id) async {
    if (!validId(id)) return null;
    final exe = File(p.join(base.path, id, 'bundle', executableName()));
    if (!await exe.exists()) return null;
    final resolved = await exe.resolveSymbolicLinks();
    if (!p.isWithin(await base.resolveSymbolicLinks(), resolved)) return null;
    return resolved;
  }

  static Future<void> forward(List<String> args) async {
    if (!(Platform.isWindows || Platform.isLinux) ||
        args.contains('--desktop-update-original') ||
        args.any((arg) => arg.startsWith('--desktop-update-activate='))) {
      return;
    }
    try {
      final base = await root();
      final pointer = File(p.join(base.path, 'active.json'));
      if (!await pointer.exists()) return;
      final saved = jsonDecode(await pointer.readAsString()) as Map;
      if (saved['schemaVersion'] != 1 ||
          saved['id'] is! String ||
          saved['build'] is! int) {
        return;
      }
      final installed = int.tryParse(
        (await PackageInfo.fromPlatform()).buildNumber,
      );
      if (installed == null || saved['build'] <= installed) return;
      final exe = await target(base, saved['id'] as String);
      if (exe == null || p.equals(exe, Platform.resolvedExecutable)) return;
      if (Platform.isLinux) {
        await restart(saved['id'] as String, forwardedArgs: args);
        exit(0);
      }
      await Process.start(
        exe,
        args,
        workingDirectory: p.dirname(exe),
        mode: ProcessStartMode.detached,
      );
      exit(0);
    } catch (_) {
      // The original remains usable when an update directory is removed.
    }
  }

  static Future<void> acknowledge(List<String> args) async {
    final markers = args
        .where((arg) => arg.startsWith('--desktop-update-activate='))
        .toList();
    if (markers.length != 1 || !(Platform.isWindows || Platform.isLinux)) {
      return;
    }
    final id = markers.single.split('=').last;
    final base = await root();
    final exe = await target(base, id);
    if (exe == null ||
        !p.equals(
          exe,
          await File(Platform.resolvedExecutable).resolveSymbolicLinks(),
        )) {
      return;
    }
    final data =
        jsonDecode(
              await File(
                p.join(p.dirname(exe), 'data', 'update-manifest.json'),
              ).readAsString(),
            )
            as Map;
    final package = await PackageInfo.fromPlatform();
    if (data['schemaVersion'] != 1 ||
        data['build'] != int.tryParse(package.buildNumber) ||
        data['version'] != package.version) {
      throw const FormatException(
        'Installierte Update-Version stimmt nicht mit dem Paket überein.',
      );
    }
    final active = File(p.join(base.path, 'active.json'));
    if (await active.exists()) {
      final previous = jsonDecode(await active.readAsString()) as Map;
      if (previous['schemaVersion'] == 1 &&
          previous['build'] is int &&
          previous['build'] > data['build']) {
        return;
      }
    }
    final temporary = File(p.join(base.path, 'active.json.new'));
    await temporary.writeAsString(
      jsonEncode({'schemaVersion': 1, 'id': id, 'build': data['build']}),
      flush: true,
    );
    await temporary.rename(p.join(base.path, 'active.json'));
  }

  static String windowsScript(
    String exe,
    String id,
    int parentPid, {
    required String activeFile,
    required String logFile,
    required String failureFile,
    required String originalExe,
  }) {
    String quote(String value) => "'${value.replaceAll("'", "''")}'";
    return '''\$ErrorActionPreference = 'Stop'
\$logFile = ${quote(logFile)}
\$failureFile = ${quote(failureFile)}
function Write-UpdateLog([string]\$message) {
  try { Add-Content -LiteralPath \$logFile -Value "\$(Get-Date -Format o) \$message" -Encoding UTF8 } catch {}
}
function Write-UpdateFailure([string]\$message) {
  Write-UpdateLog \$message
  try { Add-Content -LiteralPath \$failureFile -Value "\$(Get-Date -Format o) \$message`nLog: \$logFile" -Encoding UTF8 } catch {}
}
try { Remove-Item -LiteralPath \$failureFile -Force -ErrorAction SilentlyContinue } catch {}
\$parentProcess = Get-Process -Id $parentPid -ErrorAction SilentlyContinue
if (\$null -ne \$parentProcess -and -not \$parentProcess.WaitForExit(120000)) {
  Write-UpdateFailure 'Die ursprüngliche App wurde nicht beendet; Update nicht gestartet.'
  exit 1
}
try {
  \$updatedProcess = Start-Process -FilePath ${quote(exe)} -WorkingDirectory ${quote(p.dirname(exe))} -ArgumentList '--desktop-update-activate=$id' -WindowStyle Normal -PassThru
  \$deadline = [DateTime]::UtcNow.AddSeconds(120)
  \$exitDeadline = \$null
  while ([DateTime]::UtcNow -lt \$deadline) {
    if (Test-Path -LiteralPath ${quote(activeFile)}) {
      try {
        \$active = Get-Content -LiteralPath ${quote(activeFile)} -Raw | ConvertFrom-Json
        if (\$active.schemaVersion -eq 1 -and \$active.id -eq ${quote(id)}) {
          try { Remove-Item -LiteralPath \$failureFile -Force -ErrorAction SilentlyContinue } catch {}
          Write-UpdateLog 'Update wurde erfolgreich aktiviert.'
          exit 0
        }
      } catch {}
    }
    if (\$updatedProcess.HasExited) {
      if (\$null -eq \$exitDeadline) {
        \$exitDeadline = [DateTime]::UtcNow.AddSeconds(15)
      }
      if ([DateTime]::UtcNow -ge \$exitDeadline) { break }
    }
    Start-Sleep -Milliseconds 250
  }
  if (-not \$updatedProcess.HasExited) {
    Stop-Process -Id \$updatedProcess.Id -Force
    \$updatedProcess.WaitForExit(10000) | Out-Null
  }
  Write-UpdateFailure 'Update wurde nicht aktiviert; starte die ursprüngliche App.'
} catch {
  Write-UpdateFailure "Update-Start fehlgeschlagen: \$(\$_.Exception.Message)"
}
try {
  Start-Process -FilePath ${quote(originalExe)} -WorkingDirectory ${quote(p.dirname(originalExe))} -ArgumentList '--desktop-update-original' -WindowStyle Normal | Out-Null
  Write-UpdateLog 'Ursprüngliche App wurde als Fallback gestartet.'
} catch {
  Write-UpdateFailure "Fallback-Start fehlgeschlagen: \$(\$_.Exception.Message)"
}
''';
  }

  static String linuxScript(
    String exe,
    String id,
    int parentPid, {
    List<String> forwardedArgs = const [],
  }) {
    String quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
    return '''#!/bin/sh
set -eu
attempt=0
while kill -0 $parentPid 2>/dev/null; do
  attempt=\$((attempt + 1))
  [ "\$attempt" -le 120 ] || exit 1
  sleep 1
done
cd ${quote(p.dirname(exe))}
exec ${quote(exe)} ${forwardedArgs.map(quote).join(' ')} '--desktop-update-activate=$id'
''';
  }

  static Future<void> restart(
    String id, {
    List<String> forwardedArgs = const [],
  }) async {
    final base = await root();
    final exe = await target(base, id);
    if (exe == null) throw const FileSystemException('Update-Dateien fehlen.');
    final failureFile = File(p.join(base.path, 'update-failure.txt'));
    if (await failureFile.exists()) await failureFile.delete();
    final script = File(
      p.join(base.path, id, Platform.isWindows ? 'restart.ps1' : 'restart.sh'),
    );
    final activeFile = p.join(base.path, 'active.json');
    final logFile = p.join(base.path, id, 'restart.log');
    final originalExe = Platform.resolvedExecutable;
    final scriptContents = Platform.isWindows
        ? windowsScript(
            exe,
            id,
            pid,
            activeFile: activeFile,
            logFile: logFile,
            failureFile: failureFile.path,
            originalExe: originalExe,
          )
        : linuxScript(exe, id, pid, forwardedArgs: forwardedArgs);
    final scriptBytes = utf8.encode(scriptContents);
    await script.writeAsBytes(
      Platform.isWindows ? [0xEF, 0xBB, 0xBF, ...scriptBytes] : scriptBytes,
      flush: true,
    );
    if (Platform.isWindows) {
      final shell = p.join(
        Platform.environment['SystemRoot'] ?? r'C:\Windows',
        'System32',
        'WindowsPowerShell',
        'v1.0',
        'powershell.exe',
      );
      await Process.start(
        shell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-WindowStyle',
          'Hidden',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          script.path,
        ],
        mode: ProcessStartMode.detached,
        workingDirectory: p.dirname(script.path),
      );
    } else {
      await Process.start('/bin/sh', [
        script.path,
      ], mode: ProcessStartMode.detached);
    }
  }
}
