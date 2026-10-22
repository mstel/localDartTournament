import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_account_session_storage.dart';

class SupabaseAccountConfig {
  const SupabaseAccountConfig._();

  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://pwqpcrzbmaxywcdotkbq.supabase.co',
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
    if (!SupabaseAccountConfig.isConfigured) {
      return;
    }

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
  }

  static Future<void> setPersistSession(bool persist) async {
    if (!_isInitialized) {
      throw StateError('Supabase wurde noch nicht initialisiert.');
    }
    await sessionStorage.setPersistSession(persist);
  }
}
