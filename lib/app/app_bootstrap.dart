import 'dart:io';
import 'performance_diagnostics.dart';
import '../features/notifications/data/linux_notification_service.dart';
import 'package:flutter/widgets.dart';
import '../features/accounts/data/supabase_account_config.dart';
import '../features/backups/data/backup_service.dart';
import '../features/tournaments/data/tournament_storage.dart';
import '../shared/persistence/app_instance_lock.dart';
import '../features/updates/application/desktop_update_launcher.dart';

class AppBootstrap {
  AppBootstrap._();
  static AppInstanceLock? _instance;

  static Future<String?> initialize({List<String> args = const []}) async {
    WidgetsFlutterBinding.ensureInitialized();
    PerformanceDiagnostics.start();
    if (_instance != null) return null;
    await SupabaseAccountBootstrap.initialize();
    await DesktopUpdateLauncher.forward(args);
    try {
      final store = await TournamentStorage().storageFile();
      _instance = await AppInstanceLock.acquire(
        File('${store.parent.path}/app.lock'),
      );
    } catch (_) {
      return 'Die App ist bereits geöffnet oder der Datenordner ist nicht zugänglich. '
          'Schließe weitere Instanzen und starte die App erneut.';
    }
    BackupService? backupService;
    try {
      backupService = await BackupService.create();
      await backupService.recoverInterruptedRestore();
    } catch (error) {
      final transactionPath = backupService?.restoreTransactionDirectory.path;
      return formatRestoreRecoveryFailure(
        error,
        transactionPath: transactionPath,
      );
    }
    if (Platform.isLinux) LinuxNotificationService.startAccountGuard();
    try {
      await DesktopUpdateLauncher.acknowledge(args);
    } catch (_) {
      return 'Desktop-Update konnte nicht aktiviert werden. Starte die ursprüngliche App mit --desktop-update-original.';
    }
    return null;
  }

  static String formatRestoreRecoveryFailure(
    Object error, {
    String? transactionPath,
  }) {
    final details = switch (error) {
      FormatException failure => 'FormatException: ${failure.message}',
      FileSystemException failure => 'FileSystemException: ${failure.message}',
      _ => '${error.runtimeType}: $error',
    };
    return 'Eine unterbrochene Wiederherstellung konnte nicht abgeschlossen werden. '
        'Die App wurde zum Schutz der Daten nicht gestartet. '
        'Bitte den Datenordner und die Sicherungen im Unterordner backups prüfen.\n\n'
        'Ursache: $details'
        '${transactionPath == null ? '' : '\nWiederherstellungsordner: $transactionPath'}';
  }

  static Future<void> initializeSecondScreen({
    List<String> args = const [],
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    PerformanceDiagnostics.start();
    await SupabaseAccountBootstrap.initialize();
  }
}
