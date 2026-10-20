import 'dart:convert';
import 'dart:io';
import 'dart:ffi';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:dart_tournament_manager/features/updates/data/desktop_bundle.dart';
import 'package:dart_tournament_manager/features/updates/application/desktop_update_launcher.dart';
import 'package:dart_tournament_manager/features/updates/domain/android_release.dart';
import 'package:dart_tournament_manager/features/updates/domain/update_platform.dart';

AndroidRelease release(UpdatePlatform platform) => AndroidRelease(
  version: '1.0.0',
  build: 12,
  url: Uri.parse(
    'https://github.com/mstel/localDartTournament/releases/download/v1.0.0%2B12/${platform.assetName}',
  ),
  sha256: 'a' * 64,
  size: 100,
  notes: '',
  platform: platform,
);

void main() {
  late Directory temp;
  setUp(
    () async =>
        temp = await Directory.systemTemp.createTemp('desktop-update-test-'),
  );
  tearDown(() async => temp.delete(recursive: true));

  Future<ProcessResult> runWindowsScript(String command) {
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final shell = p.join(
      systemRoot,
      'System32',
      'WindowsPowerShell',
      'v1.0',
      'powershell.exe',
    );
    final encoded = base64Encode([
      for (final unit in command.codeUnits) ...[unit & 255, unit >> 8],
    ]);
    return Process.run(shell, [
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-EncodedCommand',
      encoded,
    ]).timeout(const Duration(seconds: 20));
  }

  test(
    'desktop ABI selects the native package and excludes unsupported CPUs',
    () {
      expect(
        UpdatePlatform.forDesktopAbi(Abi.linuxArm64),
        UpdatePlatform.linuxArm64,
      );
      expect(UpdatePlatform.forDesktopAbi(Abi.linuxX64), UpdatePlatform.linux);
      expect(
        UpdatePlatform.forDesktopAbi(Abi.windowsX64),
        UpdatePlatform.windows,
      );
      expect(UpdatePlatform.forDesktopAbi(Abi.linuxArm), isNull);
      expect(UpdatePlatform.forDesktopAbi(Abi.windowsArm64), isNull);
    },
  );
  for (final platform in [
    UpdatePlatform.windows,
    UpdatePlatform.linux,
    UpdatePlatform.linuxArm64,
  ]) {
    Archive bundle({int build = 12, String? architecture}) {
      final archive = Archive();
      void add(String name, List<int> bytes) =>
          archive.addFile(ArchiveFile(name, bytes.length, bytes));
      add(
        'data/update-manifest.json',
        utf8.encode(
          jsonEncode({
            'schemaVersion': 1,
            'version': '1.0.0',
            'build': build,
            'platform': platform.manifestPlatform,
            'architecture': architecture ?? platform.architecture,
          }),
        ),
      );
      for (final name in [
        'data/icudtl.dat',
        platform == UpdatePlatform.windows
            ? 'dart_tournament_manager.exe'
            : 'dart_tournament_manager',
        platform == UpdatePlatform.windows
            ? 'flutter_windows.dll'
            : 'lib/libflutter_linux_gtk.so',
      ]) {
        add(name, [1, 2, 3]);
      }
      return archive;
    }

    Future<File> write(Archive archive) async {
      final bytes = platform == UpdatePlatform.windows
          ? ZipEncoder().encode(archive)
          : gzip.encode(TarEncoder().encode(archive));
      return File(p.join(temp.path, platform.assetName)).writeAsBytes(bytes);
    }

    test('${platform.name}: extracts and verifies matching bundle', () async {
      final destination = Directory(p.join(temp.path, 'bundle'));
      await DesktopBundle.extract(
        await write(bundle()),
        destination,
        release(platform),
      );
      expect(
        await File(p.join(destination.path, 'data/icudtl.dat')).readAsBytes(),
        [1, 2, 3],
      );
      await expectLater(
        DesktopBundle.extract(
          await write(bundle()),
          destination,
          release(platform),
        ),
        throwsStateError,
      );
    });
    test('${platform.name}: rejects manifest version mismatch', () async {
      await expectLater(
        DesktopBundle.extract(
          await write(bundle(build: 11)),
          Directory(p.join(temp.path, 'bundle')),
          release(platform),
        ),
        throwsFormatException,
      );
    });
    test('${platform.name}: rejects a package for a different CPU', () async {
      await expectLater(
        DesktopBundle.extract(
          await write(
            bundle(
              architecture: platform.architecture == 'x64' ? 'arm64' : 'x64',
            ),
          ),
          Directory(p.join(temp.path, 'bundle')),
          release(platform),
        ),
        throwsFormatException,
      );
    });
    test(
      '${platform.name}: rejects path traversal without writing outside bundle',
      () async {
        final archive = bundle()..addFile(ArchiveFile('../escaped', 1, [1]));
        await expectLater(
          DesktopBundle.extract(
            await write(archive),
            Directory(p.join(temp.path, 'bundle')),
            release(platform),
          ),
          throwsFormatException,
        );
        expect(await File(p.join(temp.path, 'escaped')).exists(), isFalse);
      },
    );
    test('${platform.name}: rejects incomplete and damaged archives', () async {
      final incomplete = Archive()..addFile(ArchiveFile('readme', 1, [1]));
      await expectLater(
        DesktopBundle.extract(
          await write(incomplete),
          Directory(p.join(temp.path, 'incomplete')),
          release(platform),
        ),
        throwsFormatException,
      );
      final damaged = await File(
        p.join(temp.path, 'damaged'),
      ).writeAsBytes([1, 2, 3]);
      await expectLater(
        DesktopBundle.extract(
          damaged,
          Directory(p.join(temp.path, 'damaged-out')),
          release(platform),
        ),
        throwsA(anything),
      );
    });
    test(
      '${platform.name}: chooses only platform assets, beta requires opt-in',
      () {
        Map<String, dynamic> json(
          int build,
          UpdatePlatform target, {
          bool beta = false,
        }) => {
          'draft': false,
          'prerelease': beta,
          'tag_name': 'v1.0.0+$build',
          'assets': [
            {
              'name': target.assetName,
              'state': 'uploaded',
              'size': 100,
              'digest': 'sha256:${'a' * 64}',
              'browser_download_url': release(target).url.toString(),
            },
          ],
        };
        final releases = [
          json(10, platform),
          json(12, platform, beta: true),
          json(99, UpdatePlatform.android),
          if (platform.isLinux)
            json(
              100,
              platform == UpdatePlatform.linux
                  ? UpdatePlatform.linuxArm64
                  : UpdatePlatform.linux,
            ),
        ];
        expect(
          AndroidRelease.newest(releases, 9, platform: platform)!.build,
          10,
        );
        expect(
          AndroidRelease.newest(
            releases,
            9,
            platform: platform,
            includePrereleases: true,
          )!.build,
          12,
        );
        expect(
          AndroidRelease.newest(
            releases,
            12,
            platform: platform,
            includePrereleases: true,
          ),
          isNull,
        );
      },
    );
  }
  test('rejects dangerous cross-platform paths and device names', () {
    for (final name in [
      '../file',
      r'a\..\file',
      '/tmp/file',
      r'C:\file',
      'data/NUL.txt',
      'foo:bar',
      'name.',
    ]) {
      expect(() => DesktopBundle.safePath(name), throwsFormatException);
    }
    expect(DesktopBundle.safePath('./data/icudtl.dat'), 'data/icudtl.dat');
  });
  test('launcher paths cannot escape managed directory', () async {
    expect(await DesktopUpdateLauncher.target(temp, '../other'), isNull);
    expect(await DesktopUpdateLauncher.target(temp, 'build-12-123'), isNull);
    final executable = File(
      p.join(
        temp.path,
        'build-12-123',
        'bundle',
        DesktopUpdateLauncher.executableName(),
      ),
    );
    await executable.parent.create(recursive: true);
    await executable.writeAsString('fixture');
    expect(
      await DesktopUpdateLauncher.target(temp, 'build-12-123'),
      await executable.resolveSymbolicLinks(),
    );
  });
  test('restart scripts quote spaces, apostrophes and shell expansion', () {
    final windows = DesktopUpdateLauncher.windowsScript(
      r"C:\O'Brien\$app\dart.exe",
      'build-12-123',
      4321,
      activeFile: r"C:\App Data\updates\active.json",
      logFile: r"C:\App Data\updates\restart.log",
      originalExe: r"C:\O'Brien\old\dart.exe",
    );
    expect(windows, contains(r"'C:\O''Brien\$app\dart.exe'"));
    expect(windows, contains('WaitForExit(120000)'));
    expect(windows, contains('Update wurde erfolgreich aktiviert.'));
    expect(windows, contains("'--desktop-update-original'"));
    expect(windows, contains(r"'C:\App Data\updates\active.json'"));
    final linux = DesktopUpdateLauncher.linuxScript(
      r"/home/O'Brien/$app/dart",
      'build-12-123',
      4321,
    );
    expect(linux, contains(r"'/home/O'\''Brien/$app/dart'"));
    expect(linux, contains('kill -0 4321'));
  });

  test(
    'Windows restart reports failed activation and starts the fallback',
    () async {
      if (!Platform.isWindows) return;

      final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      final where = p.join(systemRoot, 'System32', 'where.exe');
      final activeFile = p.join(temp.path, 'active.json');
      final logFile = p.join(temp.path, 'restart.log');
      final command = DesktopUpdateLauncher.windowsScript(
        where,
        'build-12-123',
        2147483647,
        activeFile: activeFile,
        logFile: logFile,
        originalExe: where,
      );
      final result = await runWindowsScript(command);

      expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
      final log = await File(logFile).readAsString();
      expect(log, contains('Update wurde nicht aktiviert'));
      expect(log, contains('Ursprüngliche App wurde als Fallback gestartet'));
    },
  );

  test(
    'Windows restart observes activation before the update process exits',
    () async {
      if (!Platform.isWindows) return;

      final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      final where = p.join(systemRoot, 'System32', 'where.exe');
      final fakeUpdate = File(p.join(temp.path, 'fake update.cmd'));
      final delayedActivation = File(p.join(temp.path, 'activate-later.ps1'));
      final activeFile = p.join(temp.path, 'active.json');
      final logFile = p.join(temp.path, 'restart.log');
      final powershell = p.join(
        systemRoot,
        'System32',
        'WindowsPowerShell',
        'v1.0',
        'powershell.exe',
      );
      await delayedActivation.writeAsString(
        "Start-Sleep -Seconds 2\r\n"
        "Set-Content -LiteralPath '${activeFile.replaceAll("'", "''")}' "
        "-Value '{\"schemaVersion\":1,\"id\":\"build-12-123\"}'\r\n",
      );
      await fakeUpdate.writeAsString(
        '@echo off\r\n'
        'start "" "$powershell" -NoProfile -NonInteractive '
        '-WindowStyle Hidden -File "${delayedActivation.path}"\r\n'
        'exit /b 0\r\n',
      );
      final command = DesktopUpdateLauncher.windowsScript(
        fakeUpdate.path,
        'build-12-123',
        2147483647,
        activeFile: activeFile,
        logFile: logFile,
        originalExe: where,
      );

      final result = await runWindowsScript(command);

      expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
      expect(
        await File(activeFile).readAsString(),
        contains('"id":"build-12-123"'),
      );
      final log = await File(logFile).readAsString();
      expect(log, contains('Update wurde erfolgreich aktiviert'));
      expect(log, isNot(contains('Fallback gestartet')));
    },
  );
}
