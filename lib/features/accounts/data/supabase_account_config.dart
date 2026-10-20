import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  static bool get isConfigured {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.hasScheme &&
        uri.host.isNotEmpty &&
        anonKey.isNotEmpty;
  }

  static String sessionStorageKey(String projectUrl) {
    final projectRef = Uri.parse(projectUrl).host.split('.').first;
    return 'sb-$projectRef-auth-token';
  }

  static Future<void> clearPersistedSession({
    SharedPreferences? preferences,
  }) async {
    final store = preferences ?? await SharedPreferences.getInstance();
    await store.remove(sessionStorageKey(url));
  }

  static const authOptions = FlutterAuthClientOptions(
    localStorage: EmptyLocalStorage(),
  );
}

class SupabaseAccountBootstrap {
  SupabaseAccountBootstrap._();

  static bool _isInitialized = false;

  static bool get isInitialized => _isInitialized;

  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    if (!SupabaseAccountConfig.isConfigured) {
      return;
    }

    await SupabaseAccountConfig.clearPersistedSession();
    await Supabase.initialize(
      url: SupabaseAccountConfig.url,
      publishableKey: SupabaseAccountConfig.anonKey,
      authOptions: SupabaseAccountConfig.authOptions,
    );
    _isInitialized = true;
  }
}
