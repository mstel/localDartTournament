import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/supabase_workspace_sync_service.dart';
import '../../accounts/data/supabase_account_config.dart';
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

  Future<void> _signIn() async {
    final result = await showDialog<OperatorSignInResult>(
      context: context,
      builder: (_) => const OperatorSignInDialog(),
    );
    if (result == null) return;
    await _run(() async {
      await SupabaseAccountBootstrap.setPersistSession(result.persistSession);
      if (result.isRegister) {
        final res = await Supabase.instance.client.auth.signUp(
          email: result.email,
          password: result.password,
        );
        if (res.session == null) {
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
    });
  }

  Future<void> _upload() => _run(() async {
    await SupabaseWorkspaceSyncService.instance.uploadLocalVersion();
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
    await SupabaseWorkspaceSyncService.instance.downloadRemoteVersion();
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
        AuthException() =>
          'Anmeldung fehlgeschlagen. Zugangsdaten und E-Mail-Bestätigung prüfen.',
        StorageException() =>
          'Cloud-Backup fehlgeschlagen. Prüfe die Supabase-Storage-Regeln und Internetverbindung.',
        StateError() => '$error',
        _ => 'Cloud-Vorgang fehlgeschlagen: $error',
      };
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                            ? 'Mit demselben Supabase-Konto kannst du deinen Datenstand zwischen Laptop und Handy übertragen. Jedes Konto hat einen eigenen Cloud-Speicher.'
                            : 'Angemeldet als ${user.email ?? 'Betreiber'}. Der Cloud-Datenstand enthält Spieler, Turniere, Bestleistungen und Ranglisten.',
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
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
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
      await Supabase.instance.client.auth.signInWithOAuth(OAuthProvider.google);
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
                const Divider(height: 24),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _signInWithGoogle,
                  icon: const Icon(Icons.g_mobiledata, size: 24),
                  label: const Text('Mit Google anmelden'),
                ),
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
