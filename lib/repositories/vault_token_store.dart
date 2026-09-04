import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The mcp-vault bearer token, held in platform secure storage.
///
/// Deliberately not a Hive field: a Hive box is plaintext on disk, and this is a
/// credential. iOS/macOS use the Keychain, Android EncryptedSharedPreferences,
/// Windows the credential locker, Linux libsecret.
class VaultTokenStore {
  static const String _key = 'vault_bearer_token';

  final FlutterSecureStorage _storage;

  VaultTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<String?> read() async {
    try {
      final token = await _storage.read(key: _key);
      return (token == null || token.isEmpty) ? null : token;
    } catch (_) {
      // A locked or unavailable keystore reads as "no token configured" rather
      // than crashing the app on startup.
      return null;
    }
  }

  Future<void> write(String token) async {
    if (token.isEmpty) {
      await delete();
      return;
    }
    await _storage.write(key: _key, value: token);
  }

  Future<void> delete() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Nothing useful to do if the keystore refuses; the token stays put.
    }
  }
}
