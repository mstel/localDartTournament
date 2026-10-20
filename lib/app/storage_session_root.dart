import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../shared/persistence/storage_access.dart';
import 'dart_tournament_app.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/accounts/data/supabase_account_config.dart';
import '../features/backups/application/supabase_workspace_sync_service.dart';

/// Replaces and disposes the entire live application after a restore.
class StorageSessionRoot extends StatefulWidget {
  const StorageSessionRoot({super.key, this.startupError});
  final String? startupError;

  @override
  State<StorageSessionRoot> createState() => _StorageSessionRootState();
}

class _StorageSessionRootState extends State<StorageSessionRoot> {
  StreamSubscription<dynamic>? _authSubscription;
  String? _accountId;

  @override
  void initState() {
    super.initState();
    if (!SupabaseAccountBootstrap.isInitialized) return;
    _accountId = _currentAccountId();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      _,
    ) async {
      final next = _currentAccountId();
      if (next == _accountId) return;
      try {
        await SupabaseWorkspaceSyncService.instance.activateAccount(next);
      } catch (error) {
        SupabaseWorkspaceSyncService.status.value =
            'Konto-Daten konnten noch nicht vorbereitet werden: $error';
      }
      if (!mounted) return;
      setState(() => _accountId = next);
      unawaited(SupabaseWorkspaceSyncService.instance.synchronize());
    });
  }

  String? _currentAccountId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      StorageAccess.restartRequired,
      StorageAccess.sessionGeneration,
    ]),
    builder: (context, _) {
      if (widget.startupError == null && !StorageAccess.restartRequired.value) {
        return DartTournamentApp(
          key: ValueKey('$_accountId:${StorageAccess.sessionGeneration.value}'),
        );
      }
      return MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('DartTournamentPro')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelectableText(
                      widget.startupError ?? StorageAccess.restartMessage,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () {
                        if (Platform.isWindows ||
                            Platform.isLinux ||
                            Platform.isMacOS) {
                          exit(0);
                        }
                        SystemNavigator.pop();
                      },
                      child: const Text('App schließen'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
