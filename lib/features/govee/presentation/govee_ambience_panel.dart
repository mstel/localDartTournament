import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/govee_api.dart';
import '../data/govee_api_key_storage.dart';
import '../domain/govee_device.dart';

class GoveeAmbiencePanel extends StatefulWidget {
  const GoveeAmbiencePanel({super.key, this.api, this.keyStorage});

  final GoveeApi? api;
  final GoveeApiKeyStorage? keyStorage;

  @override
  State<GoveeAmbiencePanel> createState() => _GoveeAmbiencePanelState();
}

class _GoveeAmbiencePanelState extends State<GoveeAmbiencePanel> {
  late final GoveeApiKeyStorage _keyStorage =
      widget.keyStorage ?? GoveeApiKeyStorage();
  late final GoveeApi _api = widget.api ?? GoveeApi(client: http.Client());
  String? _apiKey;
  String? _error;
  List<GoveeDevice> _devices = const [];
  final Set<String> _busyDevices = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final apiKey = await _keyStorage.load();
      if (apiKey == null || apiKey.trim().isEmpty) {
        if (mounted) {
          setState(() {
            _apiKey = null;
            _devices = const [];
            _loading = false;
          });
        }
        return;
      }
      final devices = await _api.devices(apiKey);
      if (!mounted) return;
      setState(() {
        _apiKey = apiKey;
        _devices = devices;
        _loading = false;
        if (devices.isEmpty) {
          _error = 'Keine farbsteuerbaren Govee-Geräte gefunden.';
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Govee-Geräte konnten nicht geladen werden: $error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _apply(GoveeDevice device, _AmbienceColor color) async {
    final apiKey = _apiKey;
    if (apiKey == null || _busyDevices.contains(device.id)) return;
    setState(() {
      _busyDevices.add(device.id);
      _error = null;
    });
    try {
      switch (color) {
        case _AmbienceColor.coldWhite:
          if (device.supportsTemperature) {
            await _api.setTemperature(
              apiKey: apiKey,
              device: device,
              kelvin: 6500,
            );
          } else {
            await _api.setRgb(apiKey: apiKey, device: device, rgb: color.rgb);
          }
          return;
        case _AmbienceColor.rainbow:
          final scene = device.rainbowScene;
          if (scene == null) {
            throw const GoveeApiException(
              'Dieses Gerät bietet keine Regenbogen-Szene an.',
            );
          }
          await _api.setScene(apiKey: apiKey, device: device, scene: scene);
          return;
        case _:
          await _api.setRgb(apiKey: apiKey, device: device, rgb: color.rgb);
          return;
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busyDevices.remove(device.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_apiKey == null) return const SizedBox.shrink();
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.light_mode_outlined),
        title: const Text('Ambiente Einstellungen'),
        subtitle: Text(
          _error ?? '${_devices.length} Govee-Geräte',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Govee-Geräte erneut laden',
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          if (_devices.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                final tileWidth = constraints.maxWidth < 540
                    ? constraints.maxWidth
                    : 250.0;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final device in _devices)
                      SizedBox(
                        width: tileWidth,
                        child: _deviceControls(device),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _deviceControls(GoveeDevice device) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            device.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final color in _AmbienceColor.values)
                _colorButton(device, color),
            ],
          ),
          if (_busyDevices.contains(device.id))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    ),
  );

  Widget _colorButton(GoveeDevice device, _AmbienceColor color) {
    final supported = switch (color) {
      _AmbienceColor.coldWhite =>
        device.supportsTemperature || device.supportsRgb,
      _AmbienceColor.rainbow => device.rainbowScene != null,
      _ => device.supportsRgb,
    };
    return Tooltip(
      message: color.label,
      child: Semantics(
        button: true,
        label: color.label,
        child: InkWell(
          onTap: !supported || _busyDevices.contains(device.id)
              ? null
              : () => _apply(device, color),
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.swatch,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: color == _AmbienceColor.coldWhite
                    ? Theme.of(context).colorScheme.outline
                    : Colors.black.withValues(alpha: 0.2),
              ),
            ),
            child: !supported
                ? Icon(
                    Icons.block,
                    size: 18,
                    color: Colors.black.withValues(alpha: 0.55),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

enum _AmbienceColor {
  coldWhite('Kaltweiß', Color(0xFFF4F8FF), 0xFFF4F8FF),
  red('Rot', Color(0xFFFF0000), 0xFF0000),
  green('Grün', Color(0xFF00D000), 0x00FF00),
  yellow('Gelb', Color(0xFFFFFF00), 0xFFFF00),
  turquoise('Türkis', Color(0xFF40E0D0), 0x40E0D0),
  rainbow('Regenbogen', Color(0xFF9B59B6), 0);

  const _AmbienceColor(this.label, this.swatch, this.rgb);

  final String label;
  final Color swatch;
  final int rgb;
}
