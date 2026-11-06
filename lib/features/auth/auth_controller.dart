import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/push.dart';
import '../../core/token_store.dart';
import 'workspace.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState {
  const AuthState(this.status,
      {this.tenantId, this.userId, this.workspaces = const []});

  final AuthStatus status;
  final String? tenantId;
  final int? userId;
  final List<Workspace> workspaces;

  /// The workspace matching the active tenant, if known.
  Workspace? get currentWorkspace {
    for (final w in workspaces) {
      if (w.id == tenantId) return w;
    }
    return null;
  }

  AuthState copyWith({
    AuthStatus? status,
    String? tenantId,
    int? userId,
    List<Workspace>? workspaces,
  }) =>
      AuthState(
        status ?? this.status,
        tenantId: tenantId ?? this.tenantId,
        userId: userId ?? this.userId,
        workspaces: workspaces ?? this.workspaces,
      );
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
    final userId = await TokenStore.instance.readUserId();
    final workspaces = await _readStoredWorkspaces();
    state = AuthState(
      token != null ? AuthStatus.signedIn : AuthStatus.signedOut,
      tenantId: tenant,
      userId: userId,
      workspaces: workspaces,
    );
    // Backfill the workspace list for sessions saved before this existed.
    if (token != null && workspaces.isEmpty) {
      await refreshWorkspaces();
    }
    // Already-signed-in launch: (re)register this device for push.
    if (token != null) unawaited(PushService.registerForUser());
  }

  /// Signs in against POST /api/v1/auth/mobile/login and stores the token +
  /// workspace list. Returns null on success, or a user-facing error message.
  Future<String?> login(String email, String password) async {
    try {
      final res = await ApiClient.instance.dio.post(
        '/auth/mobile/login',
        data: {'email': email, 'password': password, 'device_name': 'Pulse Flutter'},
      );
      final data = (res.data as Map).cast<String, dynamic>();
      return (await _applyAuthResponse(data))
          ? null
          : 'Sign-in failed. Please try again.';
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

  /// Creates an account against POST /api/v1/auth/mobile/register — which also
  /// provisions a personal, Pulse-ready workspace — and signs straight in.
  /// Returns null on success, or a user-facing error message.
  Future<String?> register(String name, String email, String password) async {
    try {
      final res = await ApiClient.instance.dio.post(
        '/auth/mobile/register',
        data: {
          'name': name,
          'email': email,
          'password': password,
          'device_name': 'Pulse Flutter',
        },
      );
      final data = (res.data as Map).cast<String, dynamic>();
      return (await _applyAuthResponse(data))
          ? null
          : 'Sign-up failed. Please try again.';
    } on DioException catch (e) {
      final body = e.response?.data;
      switch (e.response?.statusCode) {
        case 409:
          if (body is Map && body['account_exists'] == true) {
            return 'You already have an account with this email — please sign in.';
          }
          return 'This account needs to be finished on the web for now.';
        case 422:
          return _firstError(body) ?? 'Please check your details and try again.';
        default:
          return 'Could not create your account. Check your connection and try again.';
      }
    }
  }

  /// Persist a login/signup response (token + tenant + workspaces) and flip the
  /// auth state to signed-in. Returns false if the response carried no token.
  Future<bool> _applyAuthResponse(Map<String, dynamic> data) async {
    final token = data['token'] as String?;
    if (token == null) return false;
    final tenantId = data['tenant_id']?.toString();
    final user = data['user'];
    final userId = (user is Map) ? user['id'] as int? : null;
    final workspaces = _parseWorkspaces(data['workspaces']);
    await TokenStore.instance.save(token: token, tenantId: tenantId);
    if (userId != null) await TokenStore.instance.writeUserId(userId);
    await _storeWorkspaces(workspaces);
    state = AuthState(AuthStatus.signedIn,
        tenantId: tenantId, userId: userId, workspaces: workspaces);
    // Register this device for push (Android/iOS/web only; no-op elsewhere).
    unawaited(PushService.registerForUser());
    return true;
  }

  /// First Laravel validation message (or the top-level message) in an error body.
  String? _firstError(dynamic body) {
    if (body is Map) {
      final errors = body['errors'];
      if (errors is Map) {
        for (final v in errors.values) {
          if (v is List && v.isNotEmpty) return v.first.toString();
        }
      }
      if (body['message'] is String) return body['message'] as String;
    }
    return null;
  }

  Future<void> signInWithToken(String token, {String? tenantId}) async {
    await TokenStore.instance.save(token: token, tenantId: tenantId);
    state = AuthState(AuthStatus.signedIn,
        tenantId: tenantId, workspaces: state.workspaces);
    unawaited(PushService.registerForUser());
    await refreshWorkspaces();
  }

  /// Switch the active workspace (tenant). Persists it and updates state; the
  /// API client sends X-Tenant-ID per request, so subsequent calls are scoped
  /// to the new workspace.
  Future<void> switchWorkspace(String tenantId) async {
    if (tenantId == state.tenantId) return;
    await TokenStore.instance.writeTenant(tenantId);
    state = state.copyWith(tenantId: tenantId);
  }

  /// Refresh the workspace list from the server (GET /auth/mobile/workspaces).
  Future<void> refreshWorkspaces() async {
    try {
      final res = await ApiClient.instance.dio.get('/auth/mobile/workspaces');
      final ws = _parseWorkspaces((res.data as Map)['workspaces']);
      if (ws.isEmpty) return;
      await _storeWorkspaces(ws);
      // Keep the current tenant if still valid; otherwise default to the first.
      final stillValid = ws.any((w) => w.id == state.tenantId);
      final tenant = stillValid ? state.tenantId : ws.first.id;
      if (tenant != null && tenant != state.tenantId) {
        await TokenStore.instance.writeTenant(tenant);
      }
      state = state.copyWith(tenantId: tenant, workspaces: ws);
    } on DioException {
      // Keep whatever we already have.
    }
  }

  Future<void> signOut() async {
    await TokenStore.instance.clear();
    state = const AuthState(AuthStatus.signedOut);
  }

  // ---- helpers ----

  List<Workspace> _parseWorkspaces(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Workspace.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<List<Workspace>> _readStoredWorkspaces() async {
    final raw = await TokenStore.instance.readWorkspaces();
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => Workspace.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _storeWorkspaces(List<Workspace> ws) =>
      TokenStore.instance.saveWorkspaces(
          jsonEncode(ws.map((w) => w.toJson()).toList()));
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
