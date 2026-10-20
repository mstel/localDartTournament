import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../accounts/data/supabase_account_config.dart';
import '../../../shared/platform/linux_commands.dart';
import 'app_push_repository.dart';

class LinuxNotificationService {
  LinuxNotificationService(this.repository);
  final AppPushRepository repository;
  static const unit = 'dart-turnier-notifications.service';
  static StreamSubscription<dynamic>? _auth;
  static Future<void> _queue = Future.value();
  static Future<void> _serial(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  static void startAccountGuard() {
    if (_auth != null) return;
    final service = LinuxNotificationService(AppPushRepository());
    void check() {
      unawaited(
        _serial(() async {
          final data = await service.configuration();
          if (data != null && data['owner'] != service.repository.userId) {
            await service._disable();
          }
        }).catchError((Object _) {
          /* Local stop runs before network revocation. */
        }),
      );
    }

    _auth = service.repository.authChanges?.listen((_) => check());
    check();
  }

  Future<Directory> _directory() async => Directory(
    p.join(
      (await getApplicationSupportDirectory()).path,
      'linux_notifications',
    ),
  );

  static String systemdQuote(String value) =>
      '"${value.replaceAll('%', '%%').replaceAll(r'$', r'$$').replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n').replaceAll('\r', '\\r')}"';

  Future<Map<String, dynamic>?> configuration() async {
    final file = File(p.join((await _directory()).path, 'device.json'));
    if (!await file.exists()) return null;
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (data['schemaVersion'] != 1) {
      throw const FormatException('Unbekannte Linux-Push-Konfiguration.');
    }
    return data;
  }

  Future<bool> active() async {
    final result = await Process.run('systemctl', [
      '--user',
      'is-active',
      '--quiet',
      unit,
    ]);
    return result.exitCode == 0;
  }

  Future<void> enable(String name) => _serial(() => _enable(name));
  Future<void> _enable(String name) async {
    final owner = repository.userId;
    if (owner == null) throw StateError('Bitte online anmelden.');
    var existing = await configuration();
    if (existing != null && existing['owner'] != owner) {
      await _disable();
      existing = null;
    }
    // Detect required commands before creating a server-side registration.
    await linuxCommand('python3', ['--version']);
    await linuxCommand('notify-send', ['--version']);
    await linuxCommand('systemctl', [
      '--user',
      'list-unit-files',
      unit,
      '--no-legend',
    ]);
    final directory = await _directory();
    await directory.create(recursive: true);
    await linuxCommand('chmod', ['700', directory.path]);
    final secret =
        existing?['secret'] as String? ??
        List.generate(
          32,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    // Save the capability before registration so failures can always be revoked.
    final config = File(p.join(directory.path, 'device.json'));
    await config.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'owner': owner,
        'secret': secret,
        'name': name,
        'url': SupabaseAccountConfig.url,
        'key': SupabaseAccountConfig.anonKey,
      }),
      flush: true,
    );
    await linuxCommand('chmod', ['600', config.path]);
    await repository.client!.rpc(
      'register_linux_notification_device',
      params: {'p_secret': secret, 'p_name': name},
    );
    if (repository.userId != owner) {
      await _disable();
      throw StateError('Konto wurde gewechselt.');
    }
    final worker = File(p.join(directory.path, 'notification_worker.py'));
    await worker.writeAsString(
      await rootBundle.loadString('assets/linux/notification_worker.py'),
      flush: true,
    );
    final home = Platform.environment['HOME'];
    if (home == null) throw StateError('HOME fehlt.');
    final configHome = Platform.environment['XDG_CONFIG_HOME'];
    final units = Directory(
      p.join(
        configHome == null || configHome.isEmpty
            ? p.join(home, '.config')
            : configHome,
        'systemd',
        'user',
      ),
    );
    await units.create(recursive: true);
    await File(p.join(units.path, unit)).writeAsString('''[Unit]
Description=DartTournamentPro-Benachrichtigungen
[Service]
Type=simple
ExecStart=/usr/bin/python3 ${systemdQuote(worker.path)} ${systemdQuote(config.path)}
Restart=on-failure
RestartSec=30
UMask=0077
NoNewPrivileges=true
[Install]
WantedBy=default.target
''', flush: true);
    await linuxCommand('systemctl', ['--user', 'daemon-reload']);
    await linuxCommand('systemctl', ['--user', 'enable', '--now', unit]);
    await linuxCommand('systemctl', ['--user', 'restart', unit]);
    if (!await active()) {
      throw StateError('Linux-Benachrichtigungsdienst konnte nicht starten.');
    }
  }

  Future<void> disable() => _serial(_disable);
  Future<void> _disable() async {
    // Stop locally even when the backend is offline. Keep the capability until
    // revocation succeeds so logout/retry cannot strand a live device registration.
    final result = await Process.run('systemctl', [
      '--user',
      'disable',
      '--now',
      unit,
    ]);
    if (result.exitCode != 0 && await active()) {
      throw StateError('Hintergrunddienst konnte nicht beendet werden.');
    }
    final data = await configuration();
    if (data == null) return;
    try {
      await repository.client!.rpc(
        'poll_linux_notifications',
        params: {'p_secret': data['secret'], 'p_disable': true},
      );
    } catch (error) {
      // A revoked capability is already disabled; other failures retain it.
      if (!error.toString().contains('Device revoked')) rethrow;
    }
    final directory = await _directory();
    await File(p.join(directory.path, 'device.json')).delete();
    final delivered = File(p.join(directory.path, 'device.delivered.json'));
    if (await delivered.exists()) await delivered.delete();
  }
}
