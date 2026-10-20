import 'dart:io';

import 'package:dart_tournament_manager/features/updates/data/github_release_client.dart';
import 'package:dart_tournament_manager/features/updates/domain/android_release.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'HTTP rate-limit responses provide actionable update guidance',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = HttpStatus.tooManyRequests;
        await request.response.close();
      });

      final client = GitHubReleaseClient(
        releasesUri: Uri.http(
          '127.0.0.1:${server.port}',
          '/repos/mstel/localDartTournament/releases',
        ),
      );
      await expectLater(
        client.check(0),
        throwsA(
          isA<UpdateCheckException>().having(
            (error) => error.message,
            'message',
            contains('begrenzt die Update-Anfragen'),
          ),
        ),
      );
    },
  );

  test(
    'HTTP 404 explains the configured public repository requirement',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final client = GitHubReleaseClient(
        releasesUri: Uri.http(
          '127.0.0.1:${server.port}',
          '/repos/${AndroidRelease.repository}/releases',
        ),
      );
      await expectLater(
        client.check(0),
        throwsA(
          isA<UpdateCheckException>()
              .having(
                (error) => error.message,
                'message',
                contains(AndroidRelease.repository),
              )
              .having(
                (error) => error.message,
                'message',
                contains('öffentlich'),
              ),
        ),
      );
    },
  );
}
