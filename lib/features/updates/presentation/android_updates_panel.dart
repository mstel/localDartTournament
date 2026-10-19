import 'package:dart_tournament_manager/shared/widgets/adaptive_content.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import '../application/app_update_service.dart';
import '../data/desktop_update_service.dart';
import '../../backups/presentation/backup_file_dialogs.dart';
import '../../backups/data/backup_service.dart';
import '../../backups/presentation/android_backup_export.dart';
import '../data/android_update_service.dart';
import '../domain/android_release.dart';
import '../data/update_channel_preferences.dart';
import 'manual_update_card.dart';

class AndroidUpdatesPanel extends StatefulWidget {
  const AndroidUpdatesPanel({super.key, this.service, this.preferences});
  final AppUpdateService? service;
  final UpdateChannelPreferences? preferences;
  @override
  State<AndroidUpdatesPanel> createState() => _AndroidUpdatesPanelState();
}

class _AndroidUpdatesPanelState extends State<AndroidUpdatesPanel> {
  late final AppUpdateService _service =
      widget.service ??
      ((Platform.isWindows || Platform.isLinux)
          ? DesktopUpdateService()
          : AndroidUpdateService());
  late final _preferences = widget.preferences ?? UpdateChannelPreferences();
  bool _includePrereleases = false;
  bool _loadingPreferences = true;
  bool _busy = false;
  bool _downloaded = false;
  double? _progress;
  String _status = 'Updates aus mstel/localDartTournament.';
  String? _installed;
  String? _backupStatus;
  AndroidRelease? _release;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final value = await _preferences.load();
      if (mounted) setState(() => _includePrereleases = value);
    } catch (_) {
      if (mounted) {
        setState(
          () => _status =
              'Update-Kanal konnte nicht geladen werden. Es werden nur stabile Versionen gesucht.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingPreferences = false);
    }
  }

  Future<void> _changeChannel(bool value) => _run(() async {
    await _preferences.save(value);
    if (!mounted) return;
    setState(() {
      _includePrereleases = value;
      _release = null;
      _downloaded = false;
      _status = 'Update-Kanal geändert. Bitte erneut nach Updates suchen.';
    });
  });

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _status = 'Update fehlgeschlagen: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _check() => _run(() async {
    final installed = await _service.installed();
    final release = await _service.check(
      installed.build,
      includePrereleases: _includePrereleases,
    );
    if (!mounted) return;
    setState(() {
      _installed = '${installed.version} (${installed.build})';
      _release = release;
      _downloaded = false;
      _status = release == null
          ? (_includePrereleases
                ? 'Kein neueres ${_service.platformLabel}-Update einschließlich Beta veröffentlicht.'
                : 'Kein neueres stabiles ${_service.platformLabel}-Update veröffentlicht.')
          : 'Verfügbar: ${release.version} (${release.build})${release.isPrerelease ? ' · Beta / Vorabversion' : ' · Stabil'}';
    });
  });

  Future<void> _exportBackup() => _run(() async {
    try {
      final saved = _service.isDesktop
          ? await const BackupFileDialogs().export(await BackupService.create())
          : await exportAndroidBackup();
      if (!mounted) return;
      setState(
        () => _backupStatus = saved
            ? 'Backup am gewählten Speicherort gespeichert.'
            : 'Speichern abgebrochen. Es wurde kein Backup exportiert.',
      );
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _backupStatus = 'Backup konnte nicht gespeichert werden: $error',
        );
      }
    }
  });
  Future<void> _install() => _run(() async {
    if (!_downloaded) {
      await _service.download(_release!, (value) {
        if (mounted) setState(() => _progress = value);
      });
      _downloaded = true;
    }
    if (!mounted) return;
    final started = await _service.install();
    if (mounted) {
      setState(
        () => _status = started
            ? (_service.isDesktop
                  ? 'Desktop-Update wird gestartet.'
                  : 'Android-Installation geöffnet.')
            : 'Bitte die Installation aus dieser Quelle erlauben, zurückkehren und erneut auf Installieren tippen.',
      );
    }
  });

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AdaptiveContentList(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Updates', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const ManualUpdateCard(),
        const SizedBox(height: 12),
        if (!_service.supported)
          const Text(
            'In-App-Updates unterstützen Android, Windows x64 sowie Linux x64 und ARM64.',
          )
        else ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Beta-Updates einschließen'),
            subtitle: const Text(
              'Sucht auch veröffentlichte GitHub-Vorabversionen. Stabile Versionen bleiben enthalten.',
            ),
            value: _includePrereleases,
            onChanged: _busy || _loadingPreferences ? null : _changeChannel,
          ),
          if (_includePrereleases)
            const Text(
              'Beta-Versionen können noch Fehler enthalten. Auch nach dem Ausschalten werden nur höhere Build-Nummern installiert; ein Downgrade erfolgt nicht.',
            ),
          if (_installed != null) Text('Installiert: $_installed'),
          Text(_status),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy || _loadingPreferences ? null : _check,
            child: const Text('Nach Updates suchen'),
          ),
          if (_release != null) ...[
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Empfohlen: Daten vor dem Update sichern',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Speichere deine Turniere, Ergebnisse und Einstellungen '
                      'vor der Aktualisierung als Backup-Datei außerhalb der App. '
                      'Du kannst den Speicherort selbst wählen. '
                      'Die Datei ist nicht verschlüsselt; bewahre sie sicher auf.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _busy ? null : _exportBackup,
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Daten sichern'),
                    ),
                    if (_backupStatus != null) ...[
                      const SizedBox(height: 8),
                      Text(_backupStatus!),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 16),
            Text(
              _release!.notes.isEmpty
                  ? 'Keine Versionshinweise.'
                  : _release!.notes,
            ),
            const SizedBox(height: 12),
            Text(
              _service.isDesktop
                  ? 'Vor dem Update wird eine interne Datensicherung erstellt. Die neue Version wird separat installiert und die App neu gestartet. Die ursprüngliche Installation bleibt erhalten.'
                  : 'Vor der Installation wird zusätzlich automatisch eine interne Sicherung erstellt. Android fragt nach deiner Bestätigung. Bitte die bestehende App nicht deinstallieren.',
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : _install,
              child: Text(
                _downloaded
                    ? 'Installieren'
                    : (_service.isDesktop
                          ? 'Update installieren und neu starten'
                          : 'Update herunterladen und installieren'),
              ),
            ),
          ],
          if (_busy)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(value: _progress),
            ),
        ],
      ],
    ),
  );
}
