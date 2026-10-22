import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_account_config.dart';
import '../application/account_session_store.dart';
import '../domain/account_user.dart';

class SupabaseAccountSessionStore implements AccountSessionStore {
  SupabaseAccountSessionStore({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  String get signInLabel => 'Supabase Online-Account';

  @override
  Future<AccountUser?> loadCurrentAccount() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return null;
    }
    return _accountFromSupabaseUser(user);
  }

  @override
  Future<AccountUser> registerAccount({
    required String displayName,
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: SupabaseAccountConfig.authRedirectUri,
      data: {'display_name': displayName.trim()},
    );
    final user = response.user;
    if (user == null) {
      throw const AuthException(
        'Account wurde angelegt. Bitte bestätige deine E-Mail und melde dich danach an.',
      );
    }
    if (response.session == null) {
      throw const AuthException(
        'Account wurde angelegt. Bitte bestätige deine E-Mail und melde dich danach an.',
      );
    }

    return _accountFromSupabaseUser(user);
  }

  @override
  Future<AccountUser?> signInAccount({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final user = response.user;
    if (user == null) {
      return null;
    }

    return _accountFromSupabaseUser(user);
  }

  @override
  bool get supportsPasswordReset => true;

  @override
  Future<void> sendPasswordResetEmail({required String email}) {
    return _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: SupabaseAccountConfig.authRedirectUri,
    );
  }

  @override
  Future<void> signOutCurrentAccount() => _client.auth.signOut();

  AccountUser _accountFromSupabaseUser(User user) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final displayName =
        (metadata['display_name'] as String?) ?? user.email ?? 'Spieler';
    final createdAt =
        DateTime.tryParse(user.createdAt) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final lastLogin = user.lastSignInAt == null
        ? null
        : DateTime.tryParse(user.lastSignInAt!);

    return AccountUser(
      id: user.id,
      username: user.email?.split('@').first ?? user.id,
      displayName: displayName,
      email: user.email ?? '',
      avatarUrl: (metadata['avatar_url'] as String?),
      createdAt: createdAt,
      updatedAt: lastLogin ?? createdAt,
      lastLogin: lastLogin,
      isActive: true,
    );
  }
}
