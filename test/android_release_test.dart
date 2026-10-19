import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/updates/domain/android_release.dart';

void main() {
  Map<String, dynamic> release(int build) => {
    'draft': false,
    'prerelease': false,
    'tag_name': 'v1.0.0+$build',
    'body': 'Änderungen',
    'assets': [
      <String, dynamic>{
        'name': 'dart-turnier-android.apk',
        'state': 'uploaded',
        'size': 1234,
        'digest': 'sha256:${'a' * 64}',
        'browser_download_url':
            'https://github.com/mstel/localDartTournament/releases/download/v1.0.0%2B$build/dart-turnier-android.apk',
      },
    ],
  };
  test('uses highest newer Android build, never downgrades', () {
    expect(
      AndroidRelease.newest([release(3), release(8), release(5)], 4)!.build,
      8,
    );
    expect(AndroidRelease.newest([release(3)], 3), isNull);
    expect(AndroidRelease.newest([release(3)], 9), isNull);
  });
  test('ignores drafts, prereleases and incomplete uploads', () {
    expect(AndroidRelease.fromGitHub(release(2)..['draft'] = true), isNull);
    expect(
      AndroidRelease.fromGitHub(release(2)..['prerelease'] = true),
      isNull,
    );
    expect(AndroidRelease.fromGitHub(release(2)..['assets'] = []), isNull);
    expect(
      AndroidRelease.fromGitHub(release(2)..['tag_name'] = 'v1.0.0'),
      isNull,
    );
  });
  test(
    'beta opt-in includes prereleases, keeps stable releases and prevents downgrades',
    () {
      final beta = release(12)..['prerelease'] = true;
      expect(AndroidRelease.newest([release(10), beta], 9)!.build, 10);
      final selected = AndroidRelease.newest(
        [release(10), beta],
        9,
        includePrereleases: true,
      )!;
      expect(selected.build, 12);
      expect(selected.isPrerelease, isTrue);
      expect(
        AndroidRelease.newest(
          [beta, release(13)],
          9,
          includePrereleases: true,
        )!.isPrerelease,
        isFalse,
      );
      expect(
        AndroidRelease.newest(
          [beta, release(10)],
          12,
          includePrereleases: true,
        ),
        isNull,
      );
      expect(AndroidRelease.newest([beta, release(10)], 12), isNull);
      expect(
        AndroidRelease.fromGitHub(
          release(14)
            ..['prerelease'] = true
            ..['draft'] = true,
          includePrereleases: true,
        ),
        isNull,
      );
      final incomplete = release(15)..['prerelease'] = true;
      (incomplete['assets'][0] as Map)['digest'] = null;
      expect(
        AndroidRelease.fromGitHub(incomplete, includePrereleases: true),
        isNull,
      );
    },
  );
  test('requires digest, trusted repository and bounded APK size', () {
    for (final change in [
      {'digest': null},
      {'size': 0},
      {'size': 400 * 1024 * 1024},
      {'browser_download_url': 'https://example.org/app.apk'},
      {
        'browser_download_url':
            'https://github.com/other/repo/releases/download/x/app.apk',
      },
      {
        'browser_download_url':
            'http://github.com/mstel/localDartTournament/releases/download/x/app.apk',
      },
    ]) {
      final json = release(2);
      (json['assets'][0] as Map).addAll(change);
      expect(AndroidRelease.fromGitHub(json), isNull);
    }
  });
}
