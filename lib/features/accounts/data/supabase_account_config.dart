import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_account_session_storage.dart';
import 'supabase_auth_diagnostics.dart';

class SupabaseAccountConfig {
  const SupabaseAccountConfig._();

  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://rbcsrqisbuutnnxpmcvp.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: '',
  );
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: publishableKey,
  );
  static const authRedirectUri = 'dartturnier://auth/callback';

  static String? get projectHost => Uri.tryParse(url)?.host;

  static String get configurationSummary {
    final issues = <String>[];
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      issues.add('SUPABASE_URL');
    }
    if (anonKey.trim().isEmpty) {
      issues.add('SUPABASE_PUBLISHABLE_KEY');
    }
    if (issues.isEmpty) {
      return 'Konfiguriert (${projectHost ?? 'Supabase'})';
    }
    return 'Fehlt: ${issues.join(', ')}';
  }

  static bool get isConfigured {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.hasScheme &&
        uri.host.isNotEmpty &&
        anonKey.isNotEmpty;
  }
}

class SupabaseAccountBootstrap {
  SupabaseAccountBootstrap._();

  static bool _isInitialized = false;
  static SupabaseAccountSessionStorage? _sessionStorage;

  static bool get isInitialized => _isInitialized;
  static SupabaseAccountSessionStorage get sessionStorage {
    final storage = _sessionStorage;
    if (storage == null) {
      throw StateError('Supabase wurde noch nicht initialisiert.');
    }
    return storage;
  }

  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    final diagnostics = SupabaseAuthDiagnostics();
    if (!SupabaseAccountConfig.isConfigured) {
      final problems = SupabaseAccountConfig.configurationSummary;
      await diagnostics.recordInitializationCheck(
        isConfigured: false,
        reason:
            'Supabase configuration is incomplete. $problems. Build the app with the project URL and the publishable key via --dart-define.',
      );
      return;
    }

    try {
      final hostPrefix = Uri.parse(
        SupabaseAccountConfig.url,
      ).host.split('.').first;
      final sessionStorage = SupabaseAccountSessionStorage(
        storage: SharedPreferencesLocalStorage(
          persistSessionKey: 'sb-$hostPrefix-auth-token',
        ),
      );
      await Supabase.initialize(
        url: SupabaseAccountConfig.url,
        publishableKey: SupabaseAccountConfig.anonKey,
        authOptions: FlutterAuthClientOptions(localStorage: sessionStorage),
      );
      _sessionStorage = sessionStorage;
      _isInitialized = true;
      await diagnostics.recordInitializationCheck(
        isConfigured: true,
        initialized: true,
        reason: 'Supabase client initialized successfully.',
      );
    } on Object catch (error, stackTrace) {
      await diagnostics.recordInitializationCheck(
        isConfigured: true,
        initialized: false,
        reason: 'Supabase initialization failed.',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  static Future<void> setPersistSession(bool persist) async {
    if (!_isInitialized) {
      throw StateError('Supabase wurde noch nicht initialisiert.');
    }
    await sessionStorage.setPersistSession(persist);
  }
}
