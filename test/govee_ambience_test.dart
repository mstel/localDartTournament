import 'dart:convert';

import 'package:dart_tournament_manager/features/govee/data/govee_api.dart';
import 'package:dart_tournament_manager/features/govee/data/govee_api_key_storage.dart';
import 'package:dart_tournament_manager/features/govee/domain/govee_device.dart';
import 'package:dart_tournament_manager/features/govee/presentation/govee_ambience_panel.dart';
import 'package:dart_tournament_manager/features/govee/presentation/govee_hub_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('device parser exposes an available rainbow scene', () {
    final device = GoveeDevice.fromJson({
      'sku': 'H61A0',
      'device': 'device-1',
      'deviceName': 'Dart board',
      'capabilities': [
        {'type': 'devices.capabilities.color_setting', 'instance': 'colorRgb'},
        {
          'type': 'devices.capabilities.dynamic_scene',
          'instance': 'lightScene',
          'parameters': {
            'options': [
              {'name': 'Rainbow', 'value': 1001},
            ],
          },
        },
      ],
    });

    expect(device.supportsRgb, isTrue);
    expect(device.rainbowScene?.name, 'Rainbow');
    expect(device.rainbowScene?.sceneId, 1001);
  });

  test('dynamic scene uses Govee lightScene capability', () async {
    http.Request? sentRequest;
    final api = GoveeApi(
      client: MockClient((request) async {
        sentRequest = request;
        return http.Response('{"code":200,"message":"success"}', 200);
      }),
    );
    addTearDown(api.close);

    await api.setScene(
      apiKey: 'api-key',
      device: const GoveeDevice(
        sku: 'H61A0',
        id: 'device-1',
        name: 'Dart board',
        supportsRgb: false,
        supportsTemperature: false,
        scenes: [GoveeScene(name: 'Rainbow', sceneId: 1001)],
      ),
      scene: const GoveeScene(name: 'Rainbow', sceneId: 1001),
    );

    expect(sentRequest!.headers['Govee-API-Key'], 'api-key');
    expect(jsonDecode(sentRequest!.body)['payload']['capability'], {
      'type': 'devices.capabilities.dynamic_scene',
      'instance': 'lightScene',
      'value': 1001,
    });
  });

  testWidgets('API key remains saved and is not shown in plain text', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: GoveeHubPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'my-private-govee-key');
    await tester.tap(find.text('API-Key speichern'));
    await tester.pumpAndSettle();

    expect(await GoveeApiKeyStorage().load(), 'my-private-govee-key');
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );
  });

  testWidgets('ambience panel lists devices and applies color swatches', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'govee_api_key': 'saved-key'});
    final sentRequests = <http.Request>[];
    final api = GoveeApi(
      client: MockClient((request) async {
        sentRequests.add(request);
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'code': 200,
              'data': [
                {
                  'sku': 'H61A0',
                  'device': 'device-1',
                  'deviceName': 'Dart board',
                  'capabilities': [
                    {
                      'type': 'devices.capabilities.color_setting',
                      'instance': 'colorRgb',
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }
        return http.Response('{"code":200}', 200);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: [GoveeAmbiencePanel(api: api)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ambiente Einstellungen'), findsOneWidget);
    await tester.tap(find.text('Ambiente Einstellungen'));
    await tester.pumpAndSettle();
    expect(find.text('Dart board'), findsOneWidget);

    await tester.tap(find.byTooltip('Rot'));
    await tester.pumpAndSettle();

    expect(sentRequests.last.method, 'POST');
    expect(
      jsonDecode(sentRequests.last.body)['payload']['capability']['value'],
      0xFF0000,
    );
    addTearDown(api.close);
  });

  test('devices with only dynamic scenes are returned by the API', () async {
    final api = GoveeApi(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 200,
            'data': [
              {
                'sku': 'H61A0',
                'device': 'device-1',
                'deviceName': 'Dart board',
                'capabilities': [
                  {
                    'type': 'devices.capabilities.dynamic_scene',
                    'instance': 'lightScene',
                    'parameters': {
                      'options': [
                        {'name': 'Regenbogen', 'value': 1001},
                      ],
                    },
                  },
                ],
              },
            ],
          }),
          200,
        ),
      ),
    );
    addTearDown(api.close);

    final devices = await api.devices('api-key');

    expect(devices, hasLength(1));
    expect(devices.single.rainbowScene?.name, 'Regenbogen');
  });
}
