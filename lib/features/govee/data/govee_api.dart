import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/govee_device.dart';

class GoveeApi {
  GoveeApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  void close() => _client.close();

  Future<List<GoveeDevice>> devices(String apiKey) async {
    final response = await _client
        .get(
          Uri.https('openapi.api.govee.com', '/router/api/v1/user/devices'),
          headers: {'Govee-API-Key': apiKey, 'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 15));
    final body = _decode(response);
    if (response.statusCode != 200 || body['code'] != 200) {
      throw GoveeApiException(_message(body, response.statusCode));
    }
    return (body['data'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => GoveeDevice.fromJson(Map<String, dynamic>.from(item)))
        .where(
          (device) =>
              device.supportsRgb ||
              device.supportsTemperature ||
              device.rainbowScene != null,
        )
        .toList(growable: false);
  }

  Future<void> setRgb({
    required String apiKey,
    required GoveeDevice device,
    required int rgb,
  }) => _control(
    apiKey: apiKey,
    device: device,
    capability: {
      'type': 'devices.capabilities.color_setting',
      'instance': 'colorRgb',
      'value': rgb,
    },
  );

  Future<void> setTemperature({
    required String apiKey,
    required GoveeDevice device,
    required int kelvin,
  }) => _control(
    apiKey: apiKey,
    device: device,
    capability: {
      'type': 'devices.capabilities.color_setting',
      'instance': 'colorTemperatureK',
      'value': kelvin,
    },
  );

  Future<void> setScene({
    required String apiKey,
    required GoveeDevice device,
    required GoveeScene scene,
  }) => _control(
    apiKey: apiKey,
    device: device,
    capability: {
      'type': 'devices.capabilities.dynamic_scene',
      'instance': 'lightScene',
      'value': scene.sceneId,
    },
  );

  Future<void> _control({
    required String apiKey,
    required GoveeDevice device,
    required Map<String, Object> capability,
  }) async {
    final response = await _client
        .post(
          Uri.https('openapi.api.govee.com', '/router/api/v1/device/control'),
          headers: {
            'Govee-API-Key': apiKey,
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'requestId': DateTime.now().microsecondsSinceEpoch.toString(),
            'payload': {
              'sku': device.sku,
              'device': device.id,
              'capability': capability,
            },
          }),
        )
        .timeout(const Duration(seconds: 15));
    final body = _decode(response);
    if (response.statusCode != 200 || body['code'] != 200) {
      throw GoveeApiException(_message(body, response.statusCode));
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const GoveeApiException('Ungültige API-Antwort.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  String _message(Map<String, dynamic> body, int statusCode) {
    if (statusCode == 401) {
      return 'API-Key ungültig oder abgelaufen.';
    }
    if (statusCode == 429) {
      return 'Govee-Anfragelimit erreicht. Bitte kurz warten.';
    }
    return body['message'] as String? ??
        'Govee-Anfrage fehlgeschlagen ($statusCode).';
  }
}

class GoveeApiException implements Exception {
  const GoveeApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
