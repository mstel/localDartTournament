class GoveeDevice {
  const GoveeDevice({
    required this.sku,
    required this.id,
    required this.name,
    required this.supportsRgb,
    required this.supportsTemperature,
    this.scenes = const [],
  });

  final String sku;
  final String id;
  final String name;
  final bool supportsRgb;
  final bool supportsTemperature;
  final List<GoveeScene> scenes;

  GoveeScene? get rainbowScene => scenes.where((scene) {
    final name = scene.name.toLowerCase();
    return name.contains('rainbow') || name.contains('regenbogen');
  }).firstOrNull;

  factory GoveeDevice.fromJson(Map<String, dynamic> json) {
    final capabilities = (json['capabilities'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item));
    final capabilityList = capabilities.toList(growable: false);
    final colorInstances = capabilities
        .where((item) => item['type'] == 'devices.capabilities.color_setting')
        .map((item) => item['instance']);
    final scenes = [
      for (final capability in capabilityList)
        if (capability['type'] == 'devices.capabilities.dynamic_scene')
          ...(capability['parameters'] is Map
                  ? (capability['parameters'] as Map)['options'] as List? ??
                        const []
                  : const [])
              .whereType<Map>()
              .map((option) => Map<String, dynamic>.from(option))
              .where(
                (option) =>
                    option['name'] is String &&
                    option['value'] is int &&
                    ((option['name'] as String).toLowerCase().contains(
                          'rainbow',
                        ) ||
                        (option['name'] as String).toLowerCase().contains(
                          'regenbogen',
                        )),
              )
              .map(
                (option) => GoveeScene(
                  name: option['name'] as String,
                  sceneId: option['value'] as int,
                ),
              ),
    ];
    final sku = json['sku'] as String? ?? '';
    final id = json['device'] as String? ?? '';
    return GoveeDevice(
      sku: sku,
      id: id,
      name: json['deviceName'] as String? ?? sku,
      supportsRgb: colorInstances.contains('colorRgb'),
      supportsTemperature: colorInstances.contains('colorTemperatureK'),
      scenes: scenes,
    );
  }
}

class GoveeScene {
  const GoveeScene({required this.name, required this.sceneId});

  final String name;
  final int sceneId;
}
