import 'package:dart_tournament_manager/features/personal_profile/domain/dart_setup.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dart_tournament_manager/features/personal_profile/data/personal_profile_repository.dart';
import 'package:dart_tournament_manager/features/personal_profile/domain/personal_profile.dart';

void main() {
  test('older profiles migrate to empty setup without losing fields', () {
    final old = const PersonalProfile(name: 'Anna').toJson()
      ..remove('dartSetup');
    final restored = PersonalProfile.fromJson(old);
    expect(restored.name, 'Anna');
    expect(restored.dartSetup.isEmpty, isTrue);
    expect(restored.toJson()['dartSetup']['version'], 1);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('online profile including image loads on another device', () async {
    Map<String, dynamic>? remote;
    PersonalProfileRepository device() => PersonalProfileRepository(
      currentUserId: () => 'a',
      upload: (row) async => remote = row,
      download: (_) async => remote,
    );
    const profile = PersonalProfile(
      name: 'Anna',
      picture: 'AQID',
      nationality: 'Deutschland',
      song: 'Song',
      spotify: 'https://open.spotify.com/track/123',
      favoritePlayer: 'Teilnehmer',
      favoriteDouble: 'D20',
      dartSetup: DartSetup(
        barrel: 'Target',
        weight: '23 g',
        shaft: 'Short',
        flights: 'No. 2',
        points: 'Steel 35 mm',
        notes: 'Ringe',
      ),
    );
    final first = device();
    await first.save('a', profile);
    expect(first.status, 'Profil online gespeichert');
    SharedPreferences.setMockInitialValues({});
    expect((await device().load('a', 'Default')).toJson(), profile.toJson());
  });
  test('offline change survives restart and uploads before download', () async {
    Map<String, dynamic>? remote = {
      'owner_user_id': 'a',
      'payload': const PersonalProfile(name: 'Old').toJson(),
    };
    final offline = PersonalProfileRepository(
      currentUserId: () => 'a',
      upload: (_) async => throw StateError('offline'),
      download: (_) async => remote,
    );
    await offline.save('a', const PersonalProfile(name: 'New'));
    expect(offline.status, contains('fehlgeschlagen'));
    final online = PersonalProfileRepository(
      currentUserId: () => 'a',
      upload: (row) async => remote = row,
      download: (_) async => remote,
    );
    expect((await online.load('a', 'Default')).name, 'New');
    expect(remote!['payload']['name'], 'New');
  });
  test('legacy local profile migrates and uploads', () async {
    SharedPreferences.setMockInitialValues({
      'personal_profile_v1_a': jsonEncode(
        const PersonalProfile(name: 'Legacy').toJson(),
      ),
    });
    Map<String, dynamic>? remote;
    final repository = PersonalProfileRepository(
      currentUserId: () => 'a',
      upload: (row) async => remote = row,
      download: (_) async => remote,
    );
    expect((await repository.load('a', 'Default')).name, 'Legacy');
    expect(remote!['payload']['name'], 'Legacy');
  });
  test('wrong account never reads or writes online', () async {
    final repository = PersonalProfileRepository(
      currentUserId: () => 'b',
      upload: (_) async => fail('wrong account upload'),
      download: (_) async {
        fail('wrong account download');
      },
    );
    await repository.save('a', const PersonalProfile(name: 'Local'));
    expect((await repository.load('a', 'Default')).name, 'Local');
  });
  test('account switch during download does not cache foreign data', () async {
    String user = 'a';
    final repository = PersonalProfileRepository(
      currentUserId: () => user,
      download: (_) async {
        user = 'b';
        return {
          'owner_user_id': 'a',
          'payload': const PersonalProfile(name: 'Remote').toJson(),
        };
      },
    );
    expect((await repository.load('a', 'Default')).name, 'Default');
  });
}
