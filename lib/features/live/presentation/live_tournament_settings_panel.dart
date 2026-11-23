import 'package:flutter/material.dart';
import 'package:qr/qr.dart';
import 'package:url_launcher/url_launcher.dart';

import '../application/live_tournament_config.dart';
import '../application/live_tournament_publisher.dart';
import '../../tournaments/data/app_database.dart';
import '../../tournaments/domain/tournament_models.dart';

/// Compact, testable settings block for the public spectator channel.
class LiveTournamentSettingsPanel extends StatefulWidget {
  const LiveTournamentSettingsPanel({
    super.key,
    required this.tournament,
    required this.publisher,
    required this.onLiveVisibleChanged,
    this.profiles = const {},
    this.onOpenUrl,
  });

  final CreatedTournament tournament;
  final LiveTournamentPublisher publisher;
  final Future<void> Function(bool value) onLiveVisibleChanged;
  final Map<String, PlayerProfile> profiles;
  final Future<void> Function(String url)? onOpenUrl;

  @override
  State<LiveTournamentSettingsPanel> createState() =>
      _LiveTournamentSettingsPanelState();
}

class _LiveTournamentSettingsPanelState
    extends State<LiveTournamentSettingsPanel> {
  bool _busy = false;
  String? _status;
  String? _error;

  bool get _visible => widget.tournament.tournamentSettings.liveVisible;

  Future<void> _setVisible(bool value) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onLiveVisibleChanged(value);
      if (value) {
        final result = await widget.publisher.publish(
          widget.tournament,
          profiles: widget.profiles,
        );
        if (!mounted) return;
        setState(() {
          _status = switch (result.status) {
            LivePublishStatus.published =>
              'Veröffentlicht · ${_formatTime(result.generatedAt)}',
            LivePublishStatus.notSignedIn =>
              result.message ?? 'Nicht angemeldet.',
            LivePublishStatus.disabled => 'Nicht veröffentlicht.',
          };
        });
      } else {
        await widget.publisher.unpublish();
        if (!mounted) return;
        setState(() => _status = 'Live-Ansicht deaktiviert.');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Live-Veröffentlichung fehlgeschlagen: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publishNow() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.publisher.publish(
        widget.tournament,
        profiles: widget.profiles,
      );
      if (!mounted) return;
      setState(() {
        _status = switch (result.status) {
          LivePublishStatus.published =>
            'Aktualisiert · ${_formatTime(result.generatedAt)}',
          LivePublishStatus.notSignedIn => result.message ?? 'Nicht angemeldet.',
          LivePublishStatus.disabled => 'Nicht veröffentlicht.',
        };
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Live-Veröffentlichung fehlgeschlagen: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openUrl() async {
    final url = LiveTournamentConfig.viewerUrl;
    final handler = widget.onOpenUrl;
    if (handler != null) {
      await handler(url);
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  String _formatTime(DateTime? value) {
    if (value == null) return '–';
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}. '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const ValueKey('live-visible-switch'),
          contentPadding: EdgeInsets.zero,
          value: _visible,
          onChanged: _busy ? null : _setVisible,
          title: const Text('Turnier Live sichtbar machen?'),
          subtitle: const Text(
            'Öffentliche, anonymisierte Ansicht mit fester URL und QR-Code.',
          ),
        ),
        if (_visible) ...[
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 620;
              final qr = SizedBox(
                width: wide ? 176 : 148,
                height: wide ? 176 : 148,
                child: const _LiveQrCode(url: LiveTournamentConfig.viewerUrl),
              );
              final details = ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Zuschauer-URL', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    const SingleChildScrollView(
                      key: ValueKey('live-viewer-url-scroll'),
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(
                        LiveTournamentConfig.viewerUrl,
                        key: ValueKey('live-viewer-url'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('live-publish-now'),
                          onPressed: _busy ? null : _publishNow,
                          icon: const Icon(Icons.publish),
                          label: const Text('Jetzt veröffentlichen'),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('live-open-url'),
                          onPressed: _openUrl,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('URL öffnen'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [qr, const SizedBox(width: 20), Expanded(child: details)],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [qr, const SizedBox(height: 12), details],
                    );
            },
          ),
          if (_status != null) ...[
            const SizedBox(height: 10),
            Text(
              _status!,
              key: const ValueKey('live-status'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              key: const ValueKey('live-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Nur Tabellen, KO-Baum, Zwischenstände, Bestleistungen, Partien, '
            'Format und Uhrzeit. Namen erscheinen als Vorname + Nachnameinitial.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _LiveQrCode extends StatelessWidget {
  const _LiveQrCode({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final code = QrCode.fromData(
      data: url,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final image = QrImage(code);
    return CustomPaint(
      key: const ValueKey('live-qr-code'),
      painter: _QrPainter(image),
      size: Size.square(148),
      child: const SizedBox.expand(),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.qr);

  final QrImage qr;
  static const _quietZone = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width < size.height ? size.width : size.height;
    final moduleCount = qr.moduleCount + _quietZone * 2;
    final moduleSize = side / moduleCount;
    final offset = (size.width - side) / 2;

    canvas.drawRect(
      Offset(offset, (size.height - side) / 2) & Size(side, side),
      Paint()..color = Colors.white,
    );
    final dark = Paint()..color = Colors.black;
    for (var row = 0; row < qr.moduleCount; row++) {
      for (var column = 0; column < qr.moduleCount; column++) {
        if (!qr.isDark(row, column)) continue;
        final x = offset + (column + _quietZone) * moduleSize;
        final y = (size.height - side) / 2 + (row + _quietZone) * moduleSize;
        canvas.drawRect(Offset(x, y) & Size(moduleSize, moduleSize), dark);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) => oldDelegate.qr != qr;
}
