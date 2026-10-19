import 'package:flutter/widgets.dart';
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

    await Supabase.initialize(
      url: SupabaseAccountConfig.url,
      publishableKey: SupabaseAccountConfig.anonKey,
    );
    _isInitialized = true;
  }
}
