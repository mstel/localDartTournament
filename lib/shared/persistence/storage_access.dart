import 'dart:async';
import 'package:flutter/foundation.dart';

/// One queue for every local store, including backups and restoration.
/// Nested, awaited calls share their parent's exclusive access.
class StorageAccess {
  StorageAccess._();
  static final Object _zoneKey = Object();
  static Future<void> _tail = Future<void>.value();
  static final restartRequired = ValueNotifier<bool>(false);
  static final sessionGeneration = ValueNotifier<int>(0);
  static final localDataRevision = ValueNotifier<int>(0);
  static String restartMessage = 'Bitte App neu starten.';

  static void requireRestart(String message) {
    restartMessage = message;
    restartRequired.value = true;
  }

  static void markLocalDataChanged() => localDataRevision.value++;

  /// Rebuilds the app against restored account-scoped files after the storage
  /// queue has released the restore lease.
  static void replaceSession() => sessionGeneration.value++;

  static Future<T> run<T>(Future<T> Function() action) {
    if (restartRequired.value) {
      return Future<T>.error(StateError(restartMessage));
    }
    final current = Zone.current[_zoneKey];
    if (current is _StorageLease && current.active) return action();
    final callerZone = Zone.current;
    final completion = Completer<T>();
    final queued = Zone.root.run(
      () => _tail.then((_) async {
        try {
          if (restartRequired.value) {
            throw StateError(
              'Wiederherstellung abgeschlossen. Bitte App neu starten.',
            );
          }
          final lease = _StorageLease();
          try {
            final value = await runZoned(action, zoneValues: {_zoneKey: lease});
            callerZone.run(() => completion.complete(value));
          } finally {
            lease.active = false;
          }
        } catch (error, stackTrace) {
          callerZone.run(() => completion.completeError(error, stackTrace));
        }
      }),
    );
    _tail = Zone.root.run(
      () => queued.then<void>((_) {}, onError: (Object _, StackTrace stack) {}),
    );
    return completion.future;
  }
}

class _StorageLease {
  bool active = true;
}
