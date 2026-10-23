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
    ]).timeout(const Duration(seconds: 60));
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
  test(
    'reads the persistent update failure marker and its log location',
    () async {
      final marker = File(p.join(temp.path, 'update-failure.txt'))
        ..writeAsStringSync(
          'Update wurde nicht aktiviert.\nLog: C:\\AppData\\restart.log',
        );

      expect(
        await DesktopUpdateLauncher.readFailureDiagnostic(base: temp),
        contains('Log: C:\\AppData\\restart.log'),
      );
      await marker.writeAsString('');
      expect(
        await DesktopUpdateLauncher.readFailureDiagnostic(base: temp),
        isNull,
      );
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

  Future<ProcessResult> runWindowsScriptFile(File script) {
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final powershell = p.join(
      systemRoot,
      'System32',
      'WindowsPowerShell',
      'v1.0',
      'powershell.exe',
    );
    return Process.run(powershell, [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      script.path,
    ]);
  }

  test(
    'Windows package ZIP accepts PowerShell backslash entry paths',
    () async {
      final windows = release(UpdatePlatform.windows);
      final manifest = utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'version': windows.version,
          'build': windows.build,
          'platform': windows.platform.manifestPlatform,
          'architecture': windows.platform.architecture,
        }),
      );
      final archive = Archive()
        ..addFile(
          ArchiveFile(r'data\update-manifest.json', manifest.length, manifest),
        )
        ..addFile(ArchiveFile(r'data\icudtl.dat', 1, [1]))
        ..addFile(ArchiveFile(r'dart_tournament_manager.exe', 1, [1]))
        ..addFile(ArchiveFile(r'flutter_windows.dll', 1, [1]));
      final source = File(p.join(temp.path, 'windows-backslash.zip'));
      await source.writeAsBytes(ZipEncoder().encode(archive));
      final destination = Directory(p.join(temp.path, 'windows-backslash'));

      await DesktopBundle.extract(source, destination, windows);

      expect(
        await File(
          p.join(destination.path, 'data', 'icudtl.dat'),
        ).readAsBytes(),
        [1],
      );
    },
  );
  test('Windows release package manifest accepts PowerShell UTF-8 BOM', () async {
    final windows = release(UpdatePlatform.windows);
    final windowsRelease = AndroidRelease(
      version: '1.1.4',
      build: 16,
      url: windows.url,
      sha256: windows.sha256,
      size: windows.size,
      notes: windows.notes,
      platform: UpdatePlatform.windows,
    );
    final manifest = utf8.encode(
      '\uFEFF${jsonEncode({'schemaVersion': 1, 'version': '1.1.4', 'build': 16, 'platform': 'windows', 'architecture': 'x64'})}',
    );
    final archive = Archive()
      ..addFile(
        ArchiveFile('data/update-manifest.json', manifest.length, manifest),
      )
      ..addFile(ArchiveFile('data/icudtl.dat', 1, [1]))
      ..addFile(ArchiveFile('dart_tournament_manager.exe', 1, [1]))
      ..addFile(ArchiveFile('flutter_windows.dll', 1, [1]));
    final source = File(p.join(temp.path, 'release-package.zip'))
      ..writeAsBytesSync(ZipEncoder().encode(archive));

    await DesktopBundle.extract(
      source,
      Directory(p.join(temp.path, 'release-package')),
      windowsRelease,
    );
  });

  test(
    'Windows v1.1.3+15 launches and acknowledges a staged release bundle',
    () async {
      if (!Platform.isWindows) return;

      const installedBuild = 15;
      const stagedBuild = 16;
      const stagedId = 'build-16-123';
      final windows = release(UpdatePlatform.windows);
      final stagedRelease = AndroidRelease(
        version: '1.1.4',
        build: stagedBuild,
        url: windows.url,
        sha256: windows.sha256,
        size: windows.size,
        notes: windows.notes,
        platform: UpdatePlatform.windows,
      );
      final manifest = utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'version': '1.1.4',
          'build': stagedBuild,
          'platform': 'windows',
          'architecture': 'x64',
        }),
      );
      final archive = Archive()
        ..addFile(
          ArchiveFile('data/update-manifest.json', manifest.length, manifest),
        )
        ..addFile(ArchiveFile('data/icudtl.dat', 1, [1]))
        ..addFile(ArchiveFile('dart_tournament_manager.exe', 1, [1]))
        ..addFile(ArchiveFile('flutter_windows.dll', 1, [1]));
      final bundleRoot = Directory(p.join(temp.path, stagedId, 'bundle'));
      await bundleRoot.parent.create(recursive: true);
      final package = File(p.join(temp.path, 'release-package.zip'))
        ..writeAsBytesSync(ZipEncoder().encode(archive));
      await DesktopBundle.extract(package, bundleRoot, stagedRelease);
      expect(stagedBuild, greaterThan(installedBuild));
      await DesktopBundle.validate(bundleRoot, stagedRelease);

      final activeFile = p.join(temp.path, 'active.json');
      final argsFile = p.join(temp.path, 'staged-args.txt');
      final fakeStagedExe = File(
        p.join(bundleRoot.path, 'simulate-staged-activation.cmd'),
      );
      await fakeStagedExe.writeAsString(
        '@echo off\r\n'
        'echo %* > "$argsFile"\r\n'
        'echo {"schemaVersion":1,"id":"$stagedId","build":$stagedBuild} > "$activeFile"\r\n',
      );
      expect(
        await DesktopUpdateLauncher.target(Directory(temp.path), stagedId),
        await File(
          p.join(bundleRoot.path, 'dart_tournament_manager.exe'),
        ).resolveSymbolicLinks(),
      );
      final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      final fallbackExe = p.join(systemRoot, 'System32', 'where.exe');
      final logFile = p.join(temp.path, 'restart.log');
      final failureFile = p.join(temp.path, 'update-failure.txt');
      await File(failureFile).writeAsString('stale failure');
      final command = DesktopUpdateLauncher.windowsScript(
        fakeStagedExe.path,
        stagedId,
        2147483647,
        activeFile: activeFile,
        logFile: logFile,
        failureFile: failureFile,
        originalExe: fallbackExe,
      );
      final restartScript = File(p.join(temp.path, 'restart script.ps1'));
      await restartScript.writeAsBytes([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(command),
      ]);

      final result = await runWindowsScriptFile(restartScript);

      expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
      expect(
        await File(argsFile).readAsString(),
        contains('--desktop-update-activate=$stagedId'),
      );
      expect(
        jsonDecode(await File(activeFile).readAsString()),
        containsPair('id', stagedId),
      );
      expect(
        await File(logFile).readAsString(),
        contains('Update wurde erfolgreich aktiviert'),
      );
      expect(
        await File(logFile).readAsString(),
        isNot(contains('Fallback gestartet')),
      );
      expect(await File(failureFile).exists(), isFalse);
    },
  );
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
      failureFile: r"C:\App Data\updates\update-failure.txt",
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
      final failureFile = p.join(temp.path, 'update-failure.txt');
      final command = DesktopUpdateLauncher.windowsScript(
        where,
        'build-12-123',
        2147483647,
        activeFile: activeFile,
        logFile: logFile,
        failureFile: failureFile,
        originalExe: where,
      );
      final result = await runWindowsScript(command);

      expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
      final log = await File(logFile).readAsString();
      expect(log, contains('Update wurde nicht aktiviert'));
      expect(log, contains('Ursprüngliche App wurde als Fallback gestartet'));
      final diagnostic = await File(failureFile).readAsString();
      expect(diagnostic, contains('Update wurde nicht aktiviert'));
      expect(diagnostic, contains('Log: $logFile'));
    },
  );

  test(
    'Windows restart observes activation before the update process exits',
    () async {
      if (!Platform.isWindows) return;

      final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      final where = p.join(systemRoot, 'System32', 'where.exe');
      final fakeUpdate = File(p.join(temp.path, 'fake update.cmd'));
      final activeFile = p.join(temp.path, 'active.json');
      final logFile = p.join(temp.path, 'restart.log');
      final failureFile = p.join(temp.path, 'update-failure.txt');
      await fakeUpdate.writeAsString(
        '@echo off\r\n'
        'timeout /t 2 /nobreak >nul\r\n'
        'echo {"schemaVersion":1,"id":"build-12-123"} > "$activeFile"\r\n'
        'timeout /t 3 /nobreak >nul\r\n'
        'exit /b 0\r\n',
      );
      final command = DesktopUpdateLauncher.windowsScript(
        fakeUpdate.path,
        'build-12-123',
        2147483647,
        activeFile: activeFile,
        logFile: logFile,
        failureFile: failureFile,
        originalExe: where,
      );

      final timer = Stopwatch()..start();
      final result = await runWindowsScript(command);
      timer.stop();
      await Future<void>.delayed(const Duration(seconds: 4));

      expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
      expect(timer.elapsed, lessThan(const Duration(seconds: 5)));
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
