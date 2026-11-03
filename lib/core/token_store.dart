import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the Sanctum personal access token and the selected workspace
/// (tenant) id in the platform secure store (Keychain / Keystore / DPAPI).
class TokenStore {
  TokenStore._();
  static final TokenStore instance = TokenStore._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _kToken = 'pulse_token';
  static const String _kTenant = 'pulse_tenant';

  Future<void> save({required String token, String? tenantId}) async {
    await _storage.write(key: _kToken, value: token);
    if (tenantId != null) {
      await _storage.write(key: _kTenant, value: tenantId);
    }
  }

  Future<String?> readToken() => _storage.read(key: _kToken);

  Future<String?> readTenant() => _storage.read(key: _kTenant);

  Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kTenant);
  }
}
