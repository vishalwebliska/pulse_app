import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/token_store.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState {
  const AuthState(this.status, {this.tenantId});
  final AuthStatus status;
  final String? tenantId;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    _bootstrap();
    return const AuthState(AuthStatus.unknown);
  }

  Future<void> _bootstrap() async {
    final token = await TokenStore.instance.readToken();
    final tenant = await TokenStore.instance.readTenant();
    state = AuthState(
      token != null ? AuthStatus.signedIn : AuthStatus.signedOut,
      tenantId: tenant,
    );
  }

  /// Signs in against POST /api/v1/auth/mobile/login and stores the token.
  /// Returns null on success, or a user-facing error message.
  Future<String?> login(String email, String password) async {
    try {
      final res = await ApiClient.instance.dio.post(
        '/auth/mobile/login',
        data: {'email': email, 'password': password, 'device_name': 'Pulse Flutter'},
      );
      final data = (res.data as Map).cast<String, dynamic>();
      final token = data['token'] as String?;
      if (token == null) return 'Sign-in failed. Please try again.';
      final tenantId = data['tenant_id'] as String?;
      await TokenStore.instance.save(token: token, tenantId: tenantId);
      state = AuthState(AuthStatus.signedIn, tenantId: tenantId);
      return null;
    } on DioException catch (e) {
      switch (e.response?.statusCode) {
        case 401:
          return 'Invalid email or password.';
        case 409:
          return 'This account uses two-factor authentication — sign in on the web for now.';
        default:
          return 'Could not sign in. Check your connection and try again.';
      }
    }
  }

  Future<void> signInWithToken(String token, {String? tenantId}) async {
    await TokenStore.instance.save(token: token, tenantId: tenantId);
    state = AuthState(AuthStatus.signedIn, tenantId: tenantId);
  }

  Future<void> signOut() async {
    await TokenStore.instance.clear();
    state = const AuthState(AuthStatus.signedOut);
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
