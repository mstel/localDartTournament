import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/android_release.dart';

/// Recovery remains available without reading local storage or the release API.
class ManualUpdateCard extends StatefulWidget {
  const ManualUpdateCard({super.key, this.openReleases});

  static final releasesUri = Uri.https(
    'github.com',
    '/${AndroidRelease.repository}/releases',
  );
  final Future<bool> Function(Uri)? openReleases;

  @override
  State<ManualUpdateCard> createState() => _ManualUpdateCardState();
}

class _ManualUpdateCardState extends State<ManualUpdateCard> {
  String? _message;

  Future<void> _open() async {
    try {
      final opened =
          await (widget.openReleases?.call(ManualUpdateCard.releasesUri) ??
              launchUrl(
                ManualUpdateCard.releasesUri,
                mode: LaunchMode.externalApplication,
              ));
      if (!opened) throw StateError('Browser unavailable');
      if (mounted) setState(() => _message = null);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Der Browser konnte nicht geöffnet werden. Kopiere den Link oder öffne ihn manuell.',
        );
      }
    }
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(
        ClipboardData(text: ManualUpdateCard.releasesUri.toString()),
      );
      if (mounted) setState(() => _message = 'Link kopiert.');
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Kopieren nicht möglich. Du kannst den Link unten markieren.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Plan B: manuell aktualisieren',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Falls das In-App-Update fehlschlägt, lade auf GitHub eine neuere '
            'Version für dein Gerät unter „Assets“ herunter. Vorabversionen '
            'sind dort als „Pre-release“ gekennzeichnet.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Android: APK über die bestehende App installieren, nicht vorher '
            'deinstallieren. Windows/Linux: das vollständige passende Archiv '
            'in einen neuen Ordner entpacken und die neue App starten. '
            'Vorhandene App-Daten behalten; wenn möglich vorher ein Backup exportieren.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _open,
                icon: const Icon(Icons.open_in_new),
                label: const Text('GitHub-Releases öffnen'),
              ),
              TextButton.icon(
                onPressed: _copy,
                icon: const Icon(Icons.copy),
                label: const Text('Link kopieren'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(ManualUpdateCard.releasesUri.toString()),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(_message!, semanticsLabel: _message),
          ],
        ],
      ),
    ),
  );
}
