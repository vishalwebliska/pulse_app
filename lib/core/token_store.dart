import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the Sanctum personal access token, the selected workspace (tenant)
/// id, the signed-in user id, and the cached workspace list in the platform
/// secure store (Keychain / Keystore / DPAPI).
class TokenStore {
  TokenStore._();
  static final TokenStore instance = TokenStore._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _kToken = 'pulse_token';
  static const String _kTenant = 'pulse_tenant';
  static const String _kUserId = 'pulse_user_id';
  static const String _kWorkspaces = 'pulse_workspaces';

  Future<void> save({required String token, String? tenantId}) async {
    await _storage.write(key: _kToken, value: token);
    if (tenantId != null) {
      await _storage.write(key: _kTenant, value: tenantId);
    }
  }

  /// Update just the active workspace (tenant) — used by the workspace switcher.
  Future<void> writeTenant(String tenantId) =>
      _storage.write(key: _kTenant, value: tenantId);

  Future<void> writeUserId(int userId) =>
      _storage.write(key: _kUserId, value: userId.toString());

  /// Cache the workspace list (JSON) so the switcher survives app restarts.
  Future<void> saveWorkspaces(String json) =>
      _storage.write(key: _kWorkspaces, value: json);

  Future<String?> readToken() => _storage.read(key: _kToken);

  Future<String?> readTenant() => _storage.read(key: _kTenant);

  Future<int?> readUserId() async {
    final raw = await _storage.read(key: _kUserId);
    return raw == null ? null : int.tryParse(raw);
  }

  Future<String?> readWorkspaces() => _storage.read(key: _kWorkspaces);

  Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kTenant);
    await _storage.delete(key: _kUserId);
    await _storage.delete(key: _kWorkspaces);
  }
}
