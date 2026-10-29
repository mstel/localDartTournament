import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/supabase_workspace_sync_service.dart';
import '../../accounts/data/supabase_account_config.dart';
import '../../accounts/data/supabase_auth_diagnostics.dart';
import '../data/backup_service.dart';
import '../data/supabase_backup_repository.dart';

typedef OperatorSignInResult = ({
  String email,
  String password,
  bool isRegister,
  bool persistSession,
});

class CloudBackupPanel extends StatefulWidget {
  const CloudBackupPanel({super.key});

  @override
  State<CloudBackupPanel> createState() => _CloudBackupPanelState();
}

class _CloudBackupPanelState extends State<CloudBackupPanel> {
  bool _busy = false;
  String? _status;
  bool _error = false;
  final _diagnostics = SupabaseAuthDiagnostics();
  String? _diagnosticsWarning;

  Future<void> _signIn() async {
    final result = await showDialog<OperatorSignInResult>(
      context: context,
      builder: (_) => const OperatorSignInDialog(),
    );
    if (result == null) return;
    _diagnosticsWarning = null;
    await _run(() async {
      await SupabaseAccountBootstrap.setPersistSession(result.persistSession);
      final timer = Stopwatch()..start();
      try {
        await _diagnostics.recordSignInStarted();
      } on Object catch (error) {
        _diagnosticsWarning =
            'Diagnoseprotokoll konnte nicht gestartet werden: $error';
      }
      try {
        if (result.isRegister) {
          final response = await Supabase.instance.client.auth.signUp(
            email: result.email,
            password: result.password,
            emailRedirectTo: SupabaseAccountConfig.authRedirectUri,
          );
          if (response.session == null) {
            _status =
                'Konto erstellt! Bitte bestätige die Bestätigungs-E-Mail und melde dich an.';
          } else {
            _status = 'Betreiberkonto registriert und angemeldet.';
          }
        } else {
          await Supabase.instance.client.auth.signInWithPassword(
            email: result.email,
            password: result.password,
          );
          _status = 'Betreiberkonto verbunden.';
        }
        try {
          await _diagnostics.recordSignInSucceeded(timer.elapsed);
        } on Object catch (error) {
          _diagnosticsWarning =
              'Anmeldung erfolgreich, aber das Diagnoseprotokoll konnte nicht aktualisiert werden: $error';
        }
      } on Object catch (error, stackTrace) {
        try {
          await _diagnostics.recordSignInFailed(
            error,
            duration: timer.elapsed,
            stackTrace: stackTrace,
          );
        } on Object catch (logError) {
          _diagnosticsWarning =
              'Fehler konnte nicht protokolliert werden: $logError';
        }
        rethrow;
      }
    });
  }

  Future<void> _exportDiagnostics() async {
    try {
      final file = await _diagnostics.logFile;
      if (!await file.exists()) {
        setState(() {
          _status = 'Noch keine Anmeldeversuche protokolliert.';
          _error = false;
        });
        return;
      }
      final location = await getSaveLocation(
        suggestedName: 'supabase-auth-diagnostics.log',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Protokolldatei', extensions: ['log']),
        ],
        confirmButtonText: 'Diagnosedatei speichern',
      );
      if (location == null) return;
      await File(
        location.path,
      ).writeAsBytes(await file.readAsBytes(), flush: true);
      if (!mounted) return;
      setState(() {
        _status = 'Diagnosedatei exportiert: ${location.path}';
        _error = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Diagnosedatei konnte nicht exportiert werden: $error';
        _error = true;
      });
    }
  }

  Future<void> _upload() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cloud-Datenstand ersetzen?'),
        content: const Text(
          'Der lokale Datenstand dieses Geräts wird zum Cloud-Datenstand dieses Kontos. Andere Geräte werden nicht direkt gelöscht, können diesen Stand aber beim nächsten Abgleich übernehmen. Nur fortfahren, wenn dieser PC der gewünschte kanonische Stand ist.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cloud-Stand ersetzen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await SupabaseWorkspaceSyncService.instance.uploadLocalVersion();
      _status = SupabaseWorkspaceSyncService.status.value;
    });
  }

  Future<void> _synchronize() => _run(() async {
    await SupabaseWorkspaceSyncService.instance.synchronize();
    _status = SupabaseWorkspaceSyncService.status.value;
  });

  Future<void> _restore() => _run(() async {
    final backups = await BackupService.create();
    final repository = SupabaseBackupRepository();
    final preview = await repository.download(backups);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cloud-Backup wiederherstellen?'),
        content: Text(
          'Backup vom ${preview.createdAt.toLocal()} mit ${preview.tournaments} Turnieren laden? '
          'Der aktuelle lokale Stand wird ersetzt; vorher legt die App eine Sicherung an.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Wiederherstellen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SupabaseWorkspaceSyncService.instance.downloadRemoteVersion(
      preview: preview,
    );
    _status = 'Cloud-Datenstand übernommen. Die Oberfläche lädt neu.';
  });

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _status = null;
      _error = false;
    });
    try {
      await action();
    } catch (error) {
      _error = true;
      _status = switch (error) {
        AuthException() => _authFailureMessage(error),
        StorageException() =>
          'Cloud-Backup fehlgeschlagen. Prüfe die Supabase-Storage-Regeln und Internetverbindung.',
        StateError() => '$error',
        _ => 'Cloud-Vorgang fehlgeschlagen: $error',
      };
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authFailureMessage(AuthException error) {
    final projectHost = Uri.tryParse(SupabaseAccountConfig.url)?.host;
    final diagnostics = [
      if (error.statusCode != null) 'HTTP ${error.statusCode}',
      if (error.code != null) 'Code ${error.code}',
    ];
    final context = [?projectHost, ...diagnostics].join(' · ');
    return 'Supabase-Anmeldung fehlgeschlagen'
        '${context.isEmpty ? '' : ' ($context)'}: ${error.message}';
  }

  @override
  Widget build(BuildContext context) {
    final configured =
        SupabaseAccountConfig.isConfigured &&
        SupabaseAccountBootstrap.isInitialized;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Supabase-Backup & Synchronisierung',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (!configured)
              const Text(
                'Für Cloud-Sicherung SUPABASE_PUBLISHABLE_KEY beim App-Build setzen.',
              )
            else
              StreamBuilder<AuthState>(
                stream: Supabase.instance.client.auth.onAuthStateChange,
                builder: (context, snapshot) {
                  final user = snapshot.hasData
                      ? snapshot.data!.session?.user
                      : Supabase.instance.client.auth.currentUser;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user == null
                            ? 'Mit demselben Supabase-Konto kannst du deinen Datenstand zwischen Laptop und Handy übertragen. Jedes Konto hat einen eigenen Cloud-Speicher. Der Abgleich erfolgt nur manuell.'
                            : 'Angemeldet als ${user.email ?? 'Betreiber'}. Spieler, Turniere, Bestleistungen und Ranglisten bleiben lokal, bis du den Cloud-Abgleich manuell startest.',
                      ),
                      const SizedBox(height: 8),
                      if (user == null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _signIn,
                            icon: const Icon(Icons.login),
                            label: const Text('Als Betreiber anmelden'),
                          ),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: _busy ? null : _synchronize,
                              icon: const Icon(Icons.sync),
                              label: const Text('Jetzt abgleichen'),
                            ),
                            FilledButton.icon(
                              onPressed: _busy ? null : _upload,
                              icon: const Icon(Icons.cloud_upload_outlined),
                              label: const Text('Lokalen Stand hochladen'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _restore,
                              icon: const Icon(Icons.cloud_download_outlined),
                              label: const Text('Cloud-Datenstand laden'),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _run(() async {
                                      await Supabase.instance.client.auth
                                          .signOut();
                                      _status = 'Abgemeldet.';
                                    }),
                              child: const Text('Abmelden'),
                            ),
                          ],
                        ),
                    ],
                  );
                },
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            ValueListenableBuilder<String>(
              valueListenable: SupabaseWorkspaceSyncService.status,
              builder: (context, status, _) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(status),
              ),
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText(
                  _status!,
                  style: TextStyle(
                    color: _error ? Theme.of(context).colorScheme.error : null,
                  ),
                ),
              ),
            if (_diagnosticsWarning != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText(
                  _diagnosticsWarning!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FutureBuilder<File>(
              future: _diagnostics.logFile,
              builder: (context, snapshot) {
                if (!configured || !snapshot.hasData) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Lokales Supabase-Anmeldeprotokoll:'),
                      SelectableText(snapshot.data!.path),
                      OutlinedButton.icon(
                        onPressed: _exportDiagnostics,
                        icon: const Icon(Icons.save_alt),
                        label: const Text('Diagnosedatei exportieren'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class OperatorSignInDialog extends StatefulWidget {
  const OperatorSignInDialog({super.key});
  @override
  State<OperatorSignInDialog> createState() => _OperatorSignInDialogState();
}

class _OperatorSignInDialogState extends State<OperatorSignInDialog> {
  static const _showSelfServiceAuthOptions = false;

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _isRegisterMode = false;
  bool _isResetMode = false;
  bool _persistSession = true;
  bool _busy = false;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _sendPasswordReset() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(
        () => _errorMessage = 'Bitte eine gültige E-Mail-Adresse eingeben.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: SupabaseAccountConfig.authRedirectUri,
      );
      setState(() {
        _infoMessage =
            'Ein Link zum Zurücksetzen des Passworts wurde an $email gesendet.';
      });
    } catch (e) {
      setState(() => _errorMessage = 'Fehler beim Senden des Links: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await SupabaseAccountBootstrap.setPersistSession(_persistSession);
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: SupabaseAccountConfig.authRedirectUri,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _errorMessage = 'Google-Anmeldung fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submit() {
    final email = _email.text.trim();
    final pass = _password.text;
    if (email.isEmpty || !email.contains('@')) {
      setState(
        () => _errorMessage = 'Bitte eine gültige E-Mail-Adresse angeben.',
      );
      return;
    }
    if (pass.length < 6) {
      setState(
        () =>
            _errorMessage = 'Das Passwort muss mindestens 6 Zeichen lang sein.',
      );
      return;
    }
    if (_isRegisterMode) {
      if (pass != _confirmPassword.text) {
        setState(() => _errorMessage = 'Die Passwörter stimmen nicht überein.');
        return;
      }
    }
    Navigator.pop(context, (
      email: email,
      password: pass,
      isRegister: _isRegisterMode,
      persistSession: _persistSession,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final title = _isResetMode
        ? 'Passwort zurücksetzen'
        : _isRegisterMode
        ? 'Neues Betreiberkonto erstellen'
        : 'Betreiberkonto anmelden';

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              if (_infoMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _infoMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 13,
                    ),
                  ),
                ),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                decoration: const InputDecoration(
                  labelText: 'E-Mail',
                  border: OutlineInputBorder(),
                ),
              ),
              if (!_isResetMode) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(
                    labelText: 'Passwort',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (!_isRegisterMode) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: const Text('Anmelden'),
                  ),
                ],
                if (_isRegisterMode) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmPassword,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Passwort bestätigen',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _persistSession,
                  title: const Text('Angemeldet bleiben'),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _persistSession = value ?? false;
                        }),
                ),
              ],
              if (_isResetMode)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _isResetMode = false;
                            _errorMessage = null;
                            _infoMessage = null;
                          }),
                    child: const Text('Zurück zur Anmeldung'),
                  ),
                ),
              if (!_isResetMode && !_isRegisterMode) ...[
                if (_showSelfServiceAuthOptions) ...[
                  const Divider(height: 24),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _signInWithGoogle,
                    icon: const Icon(Icons.g_mobiledata, size: 24),
                    label: const Text('Mit Google anmelden'),
                  ),
                ],
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _isResetMode = true;
                          _errorMessage = null;
                          _infoMessage = null;
                        }),
                  child: const Text('Passwort vergessen?'),
                ),
                if (_showSelfServiceAuthOptions)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _isRegisterMode = true;
                            _errorMessage = null;
                            _infoMessage = null;
                          }),
                    child: const Text('Registrieren'),
                  ),
              ],
              if (_isRegisterMode)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _isRegisterMode = false;
                          _errorMessage = null;
                          _infoMessage = null;
                        }),
                  child: const Text('Bereits ein Konto? Jetzt anmelden'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        if (_isResetMode)
          FilledButton(
            onPressed: _busy ? null : _sendPasswordReset,
            child: Text(_busy ? 'Wird gesendet…' : 'Reset-Link senden'),
          )
        else if (_isRegisterMode)
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: const Text('Registrieren'),
          ),
      ],
    );
  }
}
