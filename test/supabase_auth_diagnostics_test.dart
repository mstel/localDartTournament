import 'dart:convert';
import 'dart:io';

import 'package:dart_tournament_manager/features/accounts/data/supabase_auth_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'records safe auth failure and runtime context without credentials',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'supabase_auth_diagnostics_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      PackageInfo.setMockInitialValues(
        appName: 'Dart Tournament Manager',
        packageName: 'test',
        version: '2.1.1',
        buildNumber: '35',
        buildSignature: '',
      );
      const token = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.signature';
      const password = 'never-write-this-password';
      final diagnostics = SupabaseAuthDiagnostics(directory: directory);

      await diagnostics.recordSignInStarted();
      await diagnostics.recordSignInFailed(
        const AuthException(
          'Invalid login credentials; token $token; password $password; '
          'user@example.com',
          statusCode: '400',
          code: 'invalid_credentials',
        ),
        duration: const Duration(milliseconds: 1250),
        stackTrace: StackTrace.current,
        probeConnectivity: false,
      );

      final file = await diagnostics.logFile;
      final records = (await file.readAsLines())
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
      expect(records, hasLength(2));
      expect(records.last['event'], 'sign_in_failed');
      expect(records.last['appVersion'], '2.1.1');
      expect(records.last['appBuild'], '35');
      expect(records.last['durationMs'], 1250);
      final content = await file.readAsString();
      expect(content, isNot(contains(token)));
      expect(content, isNot(contains(password)));
      expect(content, isNot(contains('user@example.com')));
      expect(content, contains('[REDACTED_TOKEN]'));
    },
  );
}
